import Foundation

/// Façon dont un navigateur range ses espaces de travail.
nonisolated enum WorkspaceStyle: Sendable, Equatable {
    /// Opera : `ui.workspaces.config` dans Preferences ; chaque onglet du fichier de session porte
    /// la donnée `workspaces_state` (identifiant de son espace, en texte), et chaque fenêtre la même
    /// donnée pour l'espace affiché. AppleScript ne voit que les onglets du premier espace.
    case opera
    /// Vivaldi : `vivaldi.workspaces.list` dans Preferences ; chaque onglet du fichier de session
    /// porte un bloc JSON dont `workspaceId` désigne son espace (absent : espace par défaut).
    /// AppleScript voit les onglets de tous les espaces.
    case vivaldi
}

/// Espaces de travail d'un profil : leur style et leur liste, dans l'ordre du navigateur.
nonisolated struct ProfileWorkspaces: Sendable, Equatable {
    let style: WorkspaceStyle
    let list: [TabWorkspace]
}

nonisolated enum BrowserWorkspaces {

    /// Clé des données ajoutées par Opera dans le fichier de session.
    static let sessionKey = "workspaces_state"
    /// Clé sous laquelle `SessionFile` range le bloc JSON de Vivaldi.
    static let vivaldiExtDataKey = "vivExtData"
    /// Espace des onglets Vivaldi sans `workspaceId`.
    static let vivaldiDefaultID = "vivaldi-default"

    // MARK: - Préférences

    static func load(inProfile directory: URL) -> ProfileWorkspaces? {
        guard let data = try? Data(contentsOf: directory.appending(path: "Preferences")) else { return nil }
        return parse(preferences: data)
    }

    /// Espaces trouvés dans `Preferences`, quel que soit le navigateur (nil s'il n'y en a pas).
    static func parse(preferences data: Data) -> ProfileWorkspaces? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let opera = parseOpera(root)
        if !opera.isEmpty { return ProfileWorkspaces(style: .opera, list: opera) }
        let vivaldi = parseVivaldi(root)
        if !vivaldi.isEmpty { return ProfileWorkspaces(style: .vivaldi, list: vivaldi) }
        return nil
    }

    private static func dictionary(_ root: [String: Any], _ path: String...) -> [String: Any]? {
        var current: [String: Any]? = root
        for key in path { current = current?[key] as? [String: Any] }
        return current
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    /// Opera : `ui.workspaces.config` (ordre, noms, icônes, émojis), identifiants « 0 », « 1 »…
    private static func parseOpera(_ root: [String: Any]) -> [TabWorkspace] {
        guard let config = dictionary(root, "ui", "workspaces", "config"),
              let names = config["names"] as? [String: String], !names.isEmpty else { return [] }
        let icons = config["icons"] as? [String: String] ?? [:]
        let emojis = config["emoji_icons"] as? [String: String] ?? [:]

        // Ordre explicite, puis les espaces qu'il aurait oubliés (triés par identifiant).
        let ordered = (config["order"] as? [String] ?? []).filter { names[$0] != nil }
        let remaining = names.keys
            .filter { !ordered.contains($0) }
            .sorted { (Int($0) ?? .max, $0) < (Int($1) ?? .max, $1) }

        return (ordered + remaining).map { id in
            TabWorkspace(id: id,
                         name: nonEmpty(names[id]) ?? "Espace \((Int(id) ?? 0) + 1)",
                         icon: icons[id],
                         emoji: nonEmpty(emojis[id]))
        }
    }

    /// Vivaldi : `vivaldi.workspaces.list`, identifiants numériques (horodatages en millisecondes).
    /// L'espace par défaut (onglets sans espace) est ajouté en tête.
    private static func parseVivaldi(_ root: [String: Any]) -> [TabWorkspace] {
        guard let list = dictionary(root, "vivaldi", "workspaces")?["list"] as? [[String: Any]] else { return [] }

        let spaces = list.enumerated().compactMap { offset, item -> TabWorkspace? in
            guard let id = workspaceKey(item["id"]) else { return nil }
            return TabWorkspace(id: id,
                                name: nonEmpty(item["name"]) ?? nonEmpty(item["title"]) ?? "Espace \(offset + 1)",
                                icon: nil,
                                emoji: nonEmpty(item["emoji"]))
        }
        guard !spaces.isEmpty else { return [] }
        return [TabWorkspace(id: vivaldiDefaultID, name: "Espace par défaut")] + spaces
    }

    /// Identifiant numérique (écrit « 1791027980791 » ou « 1.791027980791e+12 ») → texte entier.
    static func workspaceKey(_ value: Any?) -> String? {
        if let number = value as? NSNumber {
            let double = number.doubleValue
            guard double.isFinite else { return nil }
            return String(Int64(double.rounded()))
        }
        if let text = value as? String, let double = Double(text), double.isFinite {
            return String(Int64(double.rounded()))
        }
        return nil
    }

    // MARK: - Fichier de session

    /// Espace d'un onglet du fichier de session.
    static func workspaceID(of tab: SessionTab, style: WorkspaceStyle) -> String? {
        switch style {
        case .opera:
            return SessionFile.text(tab.extraData[sessionKey])
        case .vivaldi:
            guard let data = tab.extraData[vivaldiExtDataKey],
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let key = workspaceKey(json["workspaceId"]) else { return vivaldiDefaultID }
            return key
        }
    }

    // MARK: - Icônes

    /// Symbole SF approchant l'icône choisie dans Opera (repli : une pile).
    static func symbol(for icon: String?) -> String {
        guard let icon = icon?.lowercased() else { return "square.stack.fill" }
        let table: [(String, String)] = [
            ("home", "house.fill"),
            ("doc", "doc.fill"),
            ("day", "sun.max.fill"),
            ("night", "moon.fill"),
            ("work", "briefcase.fill"),
            ("star", "star.fill"),
            ("heart", "heart.fill"),
            ("music", "music.note"),
            ("game", "gamecontroller.fill"),
            ("shop", "cart.fill"),
            ("cart", "cart.fill"),
            ("travel", "airplane"),
            ("code", "chevron.left.forwardslash.chevron.right"),
            ("chat", "bubble.left.fill"),
            ("mail", "envelope.fill"),
            ("news", "newspaper.fill"),
        ]
        return table.first { icon.contains($0.0) }?.1 ?? "square.stack.fill"
    }
}
