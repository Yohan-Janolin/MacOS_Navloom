import Foundation

/// Ce que sauvegarde un fichier : la base Favicons (FaviconSync) ou le fichier Bookmarks (Twins, Ghosts).
nonisolated enum BackupCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case favicons, bookmarks

    var id: String { rawValue }

    /// Ce que contient le fichier (l'outil qui l'a créé est un autre critère : voir `BackupTool`).
    var title: String {
        switch self {
        case .favicons: "Favicons"
        case .bookmarks: "Favoris"
        }
    }

    var fileExtension: String {
        switch self {
        case .favicons: "sqlite"
        case .bookmarks: "json"
        }
    }

    /// Partie fixe du nom de fichier : <profil>-Favicons-<date> ou <profil>-Bookmarks-<date>
    var separator: String {
        switch self {
        case .favicons: "-Favicons-"
        case .bookmarks: "-Bookmarks-"
        }
    }

    /// Ce que contient une sauvegarde, pour l'affichage (« 120 favicons », « 340 favoris »).
    var itemName: String {
        switch self {
        case .favicons: "favicons"
        case .bookmarks: "favoris"
        }
    }
}

/// L'outil de Navloom qui a écrit dans le navigateur (et donc créé la sauvegarde).
/// Il est noté dans le nom du fichier : <profil>-Bookmarks-<date>-<outil>.json
nonisolated enum BackupTool: String, CaseIterable, Identifiable, Hashable, Sendable {
    case faviconSync = "faviconsync"
    case twins
    case ghosts
    case echo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .faviconSync: "FaviconSync"
        case .twins: "Twins"
        case .ghosts: "Ghosts"
        case .echo: "Echo"
        }
    }
}

/// Une sauvegarde, décrite par son nom de fichier.
nonisolated struct BackupEntry: Identifiable, Hashable, Sendable {
    nonisolated enum Kind: Hashable, Sendable {
        case beforeWrite      // créée automatiquement avant une écriture
        case beforeRestore    // créée automatiquement avant une restauration
    }

    let url: URL
    /// Profil concerné, avec "/" remplacé par "-" (ex. "vivaldi-Default")
    let label: String
    let date: Date
    let kind: Kind
    let category: BackupCategory
    /// Outil noté dans le nom du fichier ; nil pour les sauvegardes d'avant cette étiquette.
    let tool: BackupTool?
    let sizeBytes: Int64

    var id: URL { url }

    /// L'outil, y compris pour les anciennes sauvegardes quand on peut le déduire : avant Echo, seul
    /// FaviconSync écrivait dans la base de favicons. Les anciennes sauvegardes de favoris viennent de
    /// Twins ou de Ghosts, sans moyen de savoir lequel : nil.
    var effectiveTool: BackupTool? {
        tool ?? (category == .favicons ? .faviconSync : nil)
    }
}

/// Sauvegardes de la base Favicons et du fichier Bookmarks.
/// Nom de fichier : <profil>-Favicons-<date ISO>[-<outil>][-avant-restauration].sqlite
///              ou  <profil>-Bookmarks-<date ISO>[-<outil>][-avant-restauration].json
nonisolated enum FaviconBackup {
    private static let restoreSuffix = "-avant-restauration"

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Navloom/Backups", directoryHint: .isDirectory)
    }

    /// Dossier des sauvegardes : celui choisi dans les Paramètres, sinon le dossier par défaut.
    static var directory: URL {
        if let path = UserDefaults.standard.string(forKey: SettingsKey.backupDirectory), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return defaultDirectory
    }

    static func safeLabel(_ label: String) -> String {
        label.replacingOccurrences(of: "/", with: "-")
    }

    /// Horodatage pour un nom de fichier, en heure locale avec son décalage :
    /// "2026-10-03T18-39-53+02-00" (les ":" sont remplacés, ils posent problème dans un nom de fichier).
    static func fileStamp(_ date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        return formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
    }

    // MARK: Création

    @discardableResult
    static func create(from source: URL,
                       label: String,
                       category: BackupCategory = .favicons,
                       tool: BackupTool? = nil,
                       kind: BackupEntry.Kind = .beforeWrite,
                       in directory: URL = FaviconBackup.directory) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let stamp = fileStamp()
        let toolSuffix = tool.map { "-\($0.rawValue)" } ?? ""
        let suffix = toolSuffix + (kind == .beforeRestore ? restoreSuffix : "")
        let destination = directory.appending(
            path: "\(safeLabel(label))\(category.separator)\(stamp)\(suffix).\(category.fileExtension)")

        try fm.copyItem(at: source, to: destination)

        // Nettoyage automatique des anciennes sauvegardes, s'il est activé dans les Paramètres.
        if let retention = BackupRetention.current {
            prune(label: label, retention: retention, in: directory)
        }
        return destination
    }

    // MARK: Lecture

    /// Sauvegardes disponibles, les plus récentes d'abord. `label` filtre sur un profil.
    static func list(label: String? = nil, in directory: URL = FaviconBackup.directory) -> [BackupEntry] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []

        return urls
            .compactMap { entry(for: $0) }
            .filter { label == nil || $0.label == label }
            .sorted { $0.date > $1.date }
    }

    /// Décode le nom d'un fichier de sauvegarde. Retourne nil si ce n'en est pas une.
    static func entry(for url: URL) -> BackupEntry? {
        guard let category = BackupCategory.allCases.first(where: { $0.fileExtension == url.pathExtension }) else {
            return nil
        }

        var base = url.deletingPathExtension().lastPathComponent
        var kind = BackupEntry.Kind.beforeWrite
        if base.hasSuffix(restoreSuffix) {
            kind = .beforeRestore
            base.removeLast(restoreSuffix.count)
        }

        // L'outil vient juste après la date (qui se termine par un chiffre ou « Z », jamais par un nom d'outil).
        var tool: BackupTool?
        if let found = BackupTool.allCases.first(where: { base.hasSuffix("-\($0.rawValue)") }) {
            tool = found
            base.removeLast(found.rawValue.count + 1)
        }

        guard let range = base.range(of: category.separator, options: .backwards) else { return nil }
        let label = String(base[..<range.lowerBound])
        let stamp = String(base[range.upperBound...])
        guard !label.isEmpty, let date = parseStamp(stamp) else { return nil }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
        return BackupEntry(url: url, label: label, date: date, kind: kind, category: category,
                           tool: tool, sizeBytes: size)
    }

    /// Relit un horodatage de nom de fichier, ancien ("2026-09-30T12-15-00Z", en UTC) ou
    /// récent ("2026-09-30T14-15-00+02-00", en heure locale). Les ":" avaient été remplacés par des "-".
    static func parseStamp(_ stamp: String) -> Date? {
        let parts = stamp.split(separator: "T", maxSplits: 1)
        guard parts.count == 2, parts[1].count >= 8 else { return nil }

        let time = parts[1].prefix(8).replacingOccurrences(of: "-", with: ":")

        // Décalage horaire : "Z", ou un signe suivi de "hh-mm" (le signe peut être un "-").
        let tail = parts[1].dropFirst(8)
        var zone = String(tail)
        if let sign = tail.first, sign == "+" || sign == "-" {
            zone = String(sign) + tail.dropFirst().replacingOccurrences(of: "-", with: ":")
        }

        return ISO8601DateFormatter().date(from: "\(parts[0])T\(time)\(zone)")
    }

    /// Nombre d'éléments d'une sauvegarde (pages associées à une favicon, ou favoris),
    /// ou nil si le fichier est illisible.
    static func itemCount(of entry: BackupEntry) async -> Int? {
        switch entry.category {
        case .favicons:
            guard let database = try? FaviconDatabase(url: entry.url, writable: false) else { return nil }
            return try? await database.mappingCount()
        case .bookmarks:
            return (try? BookmarksReader.read(from: entry.url))?.count
        }
    }

    /// Vrai si le fichier s'ouvre comme une base Favicons ou un fichier Bookmarks valide.
    static func isReadable(_ entry: BackupEntry) async -> Bool {
        await itemCount(of: entry) != nil
    }

    // MARK: Restauration

    /// Remplace `destination` par la sauvegarde. L'état actuel est sauvegardé d'abord :
    /// on retourne l'emplacement de cette copie (nil s'il n'y avait rien à sauvegarder).
    @discardableResult
    static func restore(_ entry: BackupEntry,
                        to destination: URL,
                        label: String,
                        in directory: URL = FaviconBackup.directory) throws -> URL? {
        let fm = FileManager.default

        var safety: URL?
        if fm.fileExists(atPath: destination.path) {
            safety = try create(from: destination, label: label, category: entry.category,
                                tool: entry.tool, kind: .beforeRestore, in: directory)
        }

        // On copie d'abord à côté de la destination, puis on remplace d'un coup :
        // le fichier n'est jamais dans un état à moitié écrit.
        let temporary = destination.deletingLastPathComponent().appending(path: ".navloom-restore-tmp")
        try? fm.removeItem(at: temporary)
        try fm.copyItem(at: entry.url, to: temporary)

        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fm.moveItem(at: temporary, to: destination)
        }

        // Fichiers annexes SQLite de l'ancienne base : ils ne correspondent plus à la nouvelle.
        if entry.category == .favicons {
            for suffix in ["-journal", "-wal", "-shm"] {
                try? fm.removeItem(at: URL(fileURLWithPath: destination.path + suffix))
            }
        }
        return safety
    }

    // MARK: Suppression et nettoyage

    /// Mise à la corbeille (récupérable), pas de suppression définitive.
    static func delete(_ entry: BackupEntry) throws {
        try FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)
    }

    /// Un lot de sauvegardes comptées ensemble par le nettoyage : même fichier sauvegardé, même outil.
    private nonisolated struct PruneGroup: Hashable {
        let category: BackupCategory
        let tool: BackupTool?
    }

    /// Ne garde que les plus récentes sauvegardes d'un profil, séparément pour chaque catégorie, chaque
    /// outil et chaque type (« avant écriture », « avant restauration »). Les sauvegardes d'Echo ne
    /// font donc pas disparaître celles de Twins. Retourne le nombre de sauvegardes retirées.
    /// `remover` : corbeille par défaut.
    @discardableResult
    static func prune(label: String,
                      retention: BackupRetention,
                      in directory: URL = FaviconBackup.directory,
                      remover: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> Int {
        let entries = list(label: safeLabel(label), in: directory)   // les plus récentes d'abord
        let limits: [(BackupEntry.Kind, Int)] = [
            (.beforeWrite, retention.keepBeforeWrite),
            (.beforeRestore, retention.keepBeforeRestore),
        ]

        let groups = Dictionary(grouping: entries) { PruneGroup(category: $0.category, tool: $0.effectiveTool) }

        var removed = 0
        for group in groups.values {
            for (kind, keep) in limits {
                // On garde toujours au moins une sauvegarde de chaque type.
                let old = group.filter { $0.kind == kind }   // les plus récentes d'abord
                for entry in old.dropFirst(max(keep, 1)) {
                    if (try? remover(entry.url)) != nil { removed += 1 }
                }
            }
        }
        return removed
    }

    /// Nettoyage de tous les profils d'un coup (bouton « Nettoyer maintenant »).
    @discardableResult
    static func pruneAll(retention: BackupRetention, in directory: URL = FaviconBackup.directory) -> Int {
        let labels = Set(list(in: directory).map(\.label))
        return labels.reduce(0) { $0 + prune(label: $1, retention: retention, in: directory) }
    }

    // MARK: Changement de dossier

    /// Déplace toutes les sauvegardes d'un dossier vers un autre. Retourne le nombre de fichiers déplacés.
    @discardableResult
    static func moveAll(from source: URL, to destination: URL) throws -> Int {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        var moved = 0
        for entry in list(in: source) {
            let target = destination.appending(path: entry.url.lastPathComponent)
            guard !fm.fileExists(atPath: target.path) else { continue }
            try fm.moveItem(at: entry.url, to: target)
            moved += 1
        }
        return moved
    }
}
