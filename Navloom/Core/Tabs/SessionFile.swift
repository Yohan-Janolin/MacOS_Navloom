import Foundation

/// Un onglet tel que le fichier de session le décrit, après avoir rejoué toutes les commandes.
nonisolated struct SessionTab: Equatable, Sendable {
    let id: Int
    var windowID: Int?
    /// Position dans la fenêtre (à partir de 0). Chez Opera, comptée à l'intérieur de chaque espace.
    var index: Int = 0
    var url: String = ""
    var title: String = ""
    var isPinned = false
    /// Données ajoutées par le navigateur (clé → valeur brute), comme `workspaces_state` chez Opera.
    var extraData: [String: Data] = [:]
}

nonisolated struct SessionWindow: Equatable, Sendable {
    let id: Int
    /// Position de l'onglet sélectionné (commande SetSelectedTabInIndex).
    var selectedTabIndex: Int?
    var extraData: [String: Data] = [:]
    /// Onglets ouverts, triés par position.
    var tabs: [SessionTab] = []
}

/// Lecture d'un fichier de session Chromium (format « SNSS »), en lecture seule.
///
/// Le fichier est un journal : une en-tête (`SNSS` + version), puis une suite de commandes
/// (taille sur 2 octets, identifiant sur 1 octet, données). Le navigateur y ajoute chaque
/// changement à la suite ; l'état actuel s'obtient en rejouant tout le fichier, comme le fait
/// le navigateur à son lancement. Les fenêtres de navigation privée n'y sont jamais écrites.
///
/// Les identifiants de fenêtres sont les mêmes qu'en AppleScript : c'est ce qui permet de
/// fusionner les deux sources dans Ferry.
nonisolated enum SessionFile {

    /// Identifiants des commandes utilisées (session_service_commands.cc de Chromium).
    enum Command: UInt8 {
        case setTabWindow = 0
        case setTabIndexInWindow = 2
        case updateTabNavigation = 6
        case setSelectedNavigationIndex = 7
        case setSelectedTabInIndex = 8
        case setPinnedState = 12
        /// Chromium : date de dernière activité (ignorée). Vivaldi : bloc JSON propre à l'onglet
        /// (espace de travail, pile d'onglets…). Les deux se distinguent par leur contenu.
        case lastActiveTimeOrVivaldiExtData = 21
        case tabClosed = 16
        case windowClosed = 17
        /// Données ajoutées à une fenêtre / un onglet (observé chez Opera).
        case addWindowExtraData = 254
        case addTabExtraData = 255
    }

    // MARK: - Fichiers

    /// Fichier de session en cours d'un profil : `Sessions/Session_<horodatage>` le plus récent.
    static func latestSessionFile(inProfile directory: URL) -> URL? {
        let folder = directory.appending(path: "Sessions")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        let latest = names
            .filter { $0.hasPrefix("Session_") }
            .max { timestamp(of: $0) < timestamp(of: $1) }
        return latest.map { folder.appending(path: $0) }
    }

    /// « Session_13436884803716912 » → 13436884803716912 (date de création du fichier).
    static func timestamp(of name: String) -> UInt64 {
        UInt64(name.dropFirst("Session_".count)) ?? 0
    }

    // MARK: - Lecture

    /// Fenêtres ouvertes, triées par identifiant, avec leurs onglets triés par position.
    static func parse(_ data: Data) -> [SessionWindow] {
        let bytes = [UInt8](data)
        guard bytes.count >= 8, bytes[0..<4].elementsEqual("SNSS".utf8) else { return [] }

        var tabs: [Int: SessionTab] = [:]
        var windows: [Int: SessionWindow] = [:]
        var navigations: [Int: [Int: (url: String, title: String)]] = [:]
        var selectedNavigation: [Int: Int] = [:]
        var closedTabs = Set<Int>()
        var closedWindows = Set<Int>()

        func tab(_ id: Int) -> SessionTab { tabs[id] ?? SessionTab(id: id) }
        func window(_ id: Int) -> SessionWindow { windows[id] ?? SessionWindow(id: id) }

        var position = 8
        while position + 2 <= bytes.count {
            let size = Int(bytes[position]) | Int(bytes[position + 1]) << 8
            position += 2
            // Une commande tronquée (fichier en cours d'écriture) arrête la lecture.
            guard size > 0, position + size <= bytes.count else { break }
            let commandID = bytes[position]
            let payload = Array(bytes[(position + 1)..<(position + size)])
            position += size

            guard let command = Command(rawValue: commandID) else { continue }
            let raw = RawReader(payload)

            switch command {
            case .setTabWindow:
                guard let windowID = raw.int32(at: 0), let tabID = raw.int32(at: 4) else { continue }
                var value = tab(tabID)
                value.windowID = windowID
                tabs[tabID] = value
                if windows[windowID] == nil { windows[windowID] = window(windowID) }
            case .setTabIndexInWindow:
                guard let tabID = raw.int32(at: 0), let index = raw.int32(at: 4) else { continue }
                var value = tab(tabID)
                value.index = index
                tabs[tabID] = value
            case .updateTabNavigation:
                var pickle = PickleReader(payload)
                guard let tabID = pickle.int32(), let index = pickle.int32(),
                      let url = pickle.string(), let title = pickle.string16() else { continue }
                navigations[tabID, default: [:]][index] = (url, title)
            case .setSelectedNavigationIndex:
                guard let tabID = raw.int32(at: 0), let index = raw.int32(at: 4) else { continue }
                selectedNavigation[tabID] = index
            case .setSelectedTabInIndex:
                guard let windowID = raw.int32(at: 0), let index = raw.int32(at: 4) else { continue }
                var value = window(windowID)
                value.selectedTabIndex = index
                windows[windowID] = value
            case .setPinnedState:
                guard let tabID = raw.int32(at: 0), payload.count >= 5 else { continue }
                var value = tab(tabID)
                value.isPinned = payload[4] != 0
                tabs[tabID] = value
            case .lastActiveTimeOrVivaldiExtData:
                // Vivaldi : numéro d'onglet puis texte JSON. Une date Chromium ne commence pas par « { ».
                var pickle = PickleReader(payload)
                guard let tabID = pickle.int32(), let json = pickle.bytes(),
                      json.first == UInt8(ascii: "{") else { continue }
                var value = tab(tabID)
                value.extraData[BrowserWorkspaces.vivaldiExtDataKey] = Data(json)
                tabs[tabID] = value
            case .tabClosed:
                guard let tabID = raw.int32(at: 0) else { continue }
                closedTabs.insert(tabID)
            case .windowClosed:
                guard let windowID = raw.int32(at: 0) else { continue }
                closedWindows.insert(windowID)
            case .addTabExtraData, .addWindowExtraData:
                var pickle = PickleReader(payload)
                guard let ownerID = pickle.int32(), let key = pickle.string(),
                      let value = pickle.bytes() else { continue }
                if command == .addTabExtraData {
                    var updated = tab(ownerID)
                    updated.extraData[key] = Data(value)
                    tabs[ownerID] = updated
                } else {
                    var updated = window(ownerID)
                    updated.extraData[key] = Data(value)
                    windows[ownerID] = updated
                }
            }
        }

        // Dernière page affichée de chaque onglet.
        for (tabID, entries) in navigations {
            guard var value = tabs[tabID], let lastIndex = entries.keys.max() else { continue }
            let chosen = selectedNavigation[tabID].flatMap { entries[$0] } ?? entries[lastIndex]!
            value.url = chosen.url
            value.title = chosen.title
            tabs[tabID] = value
        }

        // Rangement des onglets encore ouverts dans leurs fenêtres encore ouvertes.
        for value in tabs.values where !closedTabs.contains(value.id) && !value.url.isEmpty {
            guard let windowID = value.windowID, !closedWindows.contains(windowID) else { continue }
            windows[windowID, default: SessionWindow(id: windowID)].tabs.append(value)
        }

        return windows.values
            .filter { !closedWindows.contains($0.id) && !$0.tabs.isEmpty }
            .map { window in
                var sorted = window
                sorted.tabs.sort { ($0.index, $0.id) < ($1.index, $1.id) }
                return sorted
            }
            .sorted { $0.id < $1.id }
    }

    /// Valeur texte d'une donnée ajoutée (« 1 » pour `workspaces_state`).
    static func text(_ data: Data?) -> String? {
        guard let data, let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Lecture binaire

/// Entiers lus à une position fixe (commandes à structure simple, sans pickle).
private nonisolated struct RawReader {
    let bytes: [UInt8]
    init(_ bytes: [UInt8]) { self.bytes = bytes }

    func int32(at offset: Int) -> Int? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        let value = UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
        return Int(Int32(bitPattern: value))
    }
}

/// Lecture d'un base::Pickle de Chromium : taille sur 4 octets, puis champs alignés sur 4 octets.
private nonisolated struct PickleReader {
    private let raw: RawReader
    private var position = 4

    init(_ bytes: [UInt8]) { raw = RawReader(bytes) }

    private mutating func align() {
        position = (position + 3) & ~3
    }

    mutating func int32() -> Int? {
        guard let value = raw.int32(at: position) else { return nil }
        position += 4
        return value
    }

    /// Chaîne d'octets : longueur puis contenu.
    mutating func bytes() -> [UInt8]? {
        guard let length = int32(), length >= 0, position + length <= raw.bytes.count else { return nil }
        let value = Array(raw.bytes[position..<(position + length)])
        position += length
        align()
        return value
    }

    mutating func string() -> String? {
        bytes().map { String(decoding: $0, as: UTF8.self) }
    }

    /// Chaîne UTF-16 : nombre de caractères puis 2 octets par caractère.
    mutating func string16() -> String? {
        guard let length = int32(), length >= 0, position + 2 * length <= raw.bytes.count else { return nil }
        let units = (0..<length).map { i -> UInt16 in
            UInt16(raw.bytes[position + 2 * i]) | UInt16(raw.bytes[position + 2 * i + 1]) << 8
        }
        position += 2 * length
        align()
        return String(decoding: units, as: UTF16.self)
    }
}
