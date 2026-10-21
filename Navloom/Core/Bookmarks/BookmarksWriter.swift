import Foundation

nonisolated enum BookmarksWriteError: LocalizedError {
    case invalidFormat
    case nothingToRemove
    case fileChanged(expected: Int, found: Int)
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            String(localized: "The Bookmarks file doesn't have the expected format: nothing was changed.")
        case .nothingToRemove:
            String(localized: "No bookmark checked.")
        case .fileChanged(let expected, let found):
            String(localized: "The Bookmarks file changed since the analysis (\(found) of \(expected) bookmarks found). Run the analysis again: nothing was changed.")
        case .verificationFailed:
            String(localized: "Checking the result failed: nothing was changed.")
        }
    }
}

nonisolated struct BookmarksWriteSummary: Sendable {
    let removed: Int
    let backupURL: URL
}

/// Supprime des favoris dans le fichier `Bookmarks` d'un navigateur Chromium.
///
/// Le fichier est modifié comme un JSON générique (et non via les structures Codable de
/// `BookmarksReader`) : tout ce que l'on ne comprend pas — champs propres à Vivaldi, métadonnées
/// de synchronisation, etc. — est réécrit tel quel.
nonisolated enum BookmarksWriter {

    // MARK: Transformation pure (testable sans fichier)

    /// Retire les favoris (type "url") dont l'identifiant est dans `ids`. Les dossiers ne sont
    /// jamais supprimés. Retourne le nouveau contenu et le nombre de favoris réellement retirés.
    static func removing(ids: Set<String>, from data: Data) throws -> (data: Data, removed: Int) {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var roots = root["roots"] as? [String: Any] else {
            throw BookmarksWriteError.invalidFormat
        }

        var removed = 0
        for (key, value) in roots {
            // "sync_transaction_version" et autres valeurs qui ne sont pas des dossiers : ignorées.
            guard let node = value as? [String: Any] else { continue }
            roots[key] = prune(node, ids: ids, removed: &removed)
        }
        root["roots"] = roots

        // Chromium recalcule ce total de contrôle à la prochaine sauvegarde du fichier ; un total
        // périmé serait pire qu'une absence de total.
        root.removeValue(forKey: "checksum")

        let output = try JSONSerialization.data(withJSONObject: root,
                                                options: [.prettyPrinted, .withoutEscapingSlashes])
        return (output, removed)
    }

    private static func prune(_ node: [String: Any], ids: Set<String>, removed: inout Int) -> [String: Any] {
        guard let children = node["children"] as? [[String: Any]] else { return node }

        var kept: [[String: Any]] = []
        for child in children {
            if child["type"] as? String == "url",
               let id = child["id"] as? String,
               ids.contains(id) {
                removed += 1
                continue
            }
            kept.append(prune(child, ids: ids, removed: &removed))
        }

        var result = node
        result["children"] = kept
        return result
    }

    // MARK: Écriture sur le disque

    /// Sauvegarde le fichier, puis le remplace par une version sans les favoris indiqués.
    /// Tout est vérifié en mémoire AVANT la moindre écriture.
    @discardableResult
    static func removeBookmarks(ids: Set<String>,
                                in file: URL,
                                label: String,
                                tool: BackupTool? = nil,
                                backupDirectory: URL = FaviconBackup.directory) throws -> BookmarksWriteSummary {
        guard !ids.isEmpty else { throw BookmarksWriteError.nothingToRemove }

        let original = try Data(contentsOf: file)
        let countBefore = try BookmarksReader.parse(original).count
        let (output, removed) = try removing(ids: ids, from: original)

        // Chaque identifiant demandé doit avoir été retrouvé (sinon le fichier a changé).
        guard removed == ids.count else {
            throw BookmarksWriteError.fileChanged(expected: ids.count, found: removed)
        }
        // Le nouveau fichier doit se relire, avec exactement les favoris en moins.
        guard try BookmarksReader.parse(output).count == countBefore - removed else {
            throw BookmarksWriteError.verificationFailed
        }

        let backup = try backupFile(file, label: label, tool: tool, in: backupDirectory)

        let permissions = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.posixPermissions]
        try output.write(to: file, options: .atomic)
        if let permissions {
            try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.path)
        }

        return BookmarksWriteSummary(removed: removed, backupURL: backup)
    }

    /// Copie le fichier Bookmarks dans le dossier des sauvegardes de Navloom.
    /// Nom : <profil>-Bookmarks-<date locale ISO>-<outil>.json (voir `FaviconBackup`).
    static func backupFile(_ source: URL, label: String, tool: BackupTool? = nil, in directory: URL) throws -> URL {
        try FaviconBackup.create(from: source, label: label, category: .bookmarks, tool: tool, in: directory)
    }
}
