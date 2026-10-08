import Foundation

/// Lit un fichier `Bookmarks` pour la comparaison d'Echo.
///
/// Comme `BookmarksWriter`, on passe par un JSON générique : on ne s'occupe que de ce qui sert
/// à comparer (racine, dossiers, nom, URL) et on ignore le reste.
nonisolated enum EchoReader {

    /// Les racines d'un fichier Bookmarks Chromium. Les autres clés (« sync_transaction_version »…) ne sont pas des dossiers.
    static let rootKeys = ["bookmark_bar", "other", "synced"]

    static func read(from url: URL) throws -> EchoSnapshot {
        try parse(Data(contentsOf: url))
    }

    /// Séparé de `read` pour pouvoir tester sans fichier sur le disque.
    static func parse(_ data: Data) throws -> EchoSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = root["roots"] as? [String: Any] else {
            throw EchoError.invalidFormat
        }

        var bookmarks: [EchoBookmark] = []
        var folders = Set<EchoFolder>()
        var ignored = 0

        for key in rootKeys {
            guard let node = roots[key] as? [String: Any] else { continue }
            collect(children: node["children"] as? [[String: Any]] ?? [],
                    rootKey: key, path: [],
                    bookmarks: &bookmarks, folders: &folders, ignored: &ignored)
        }
        return EchoSnapshot(bookmarks: bookmarks, folders: folders, ignoredCount: ignored)
    }

    private static func collect(children: [[String: Any]],
                                rootKey: String,
                                path: [String],
                                bookmarks: inout [EchoBookmark],
                                folders: inout Set<EchoFolder>,
                                ignored: inout Int) {
        for child in children {
            let type = child["type"] as? String
            let name = child["name"] as? String ?? ""

            if type == "url", let url = child["url"] as? String {
                let scheme = URL(string: url)?.scheme?.lowercased() ?? ""
                if scheme == "http" || scheme == "https" {
                    bookmarks.append(EchoBookmark(rootKey: rootKey, folderPath: path, name: name, url: url))
                } else {
                    ignored += 1
                }
            } else if type == "folder" {
                let subPath = path + [name]
                folders.insert(EchoFolder(rootKey: rootKey, path: subPath))
                collect(children: child["children"] as? [[String: Any]] ?? [],
                        rootKey: rootKey, path: subPath,
                        bookmarks: &bookmarks, folders: &folders, ignored: &ignored)
            }
        }
    }
}
