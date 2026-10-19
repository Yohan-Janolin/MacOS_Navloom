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
        var layout: [String] = []
        var present = Set<String>()
        var ignored = 0

        for key in rootKeys {
            guard let node = roots[key] as? [String: Any] else { continue }
            present.insert(key)
            collect(children: node["children"] as? [[String: Any]] ?? [],
                    rootKey: key, path: [],
                    bookmarks: &bookmarks, folders: &folders, layout: &layout, ignored: &ignored)
        }
        return EchoSnapshot(bookmarks: bookmarks, folders: folders, ignoredCount: ignored,
                            rootKeys: present, layout: layout)
    }

    /// Dossiers gérés par le navigateur lui-même (Vivaldi : Speed Dial et Corbeille). Echo ne les copie
    /// ni ne les compte, et une copie complète n'y touche pas.
    static func isBrowserManaged(_ node: [String: Any]) -> Bool {
        guard node["type"] as? String == "folder",
              let meta = node["meta_info"] as? [String: Any] else { return false }
        return ["Speeddial", "Trash"].contains { key in
            (meta[key] as? String)?.lowercased() == "true"
        }
    }

    static func isWebURL(_ node: [String: Any]) -> Bool {
        guard node["type"] as? String == "url", let url = node["url"] as? String else { return false }
        let scheme = URL(string: url)?.scheme?.lowercased() ?? ""
        return scheme == "http" || scheme == "https"
    }

    /// Clé exacte d'un favori (racine, dossiers, nom, URL) : sert à comparer deux profils sans aucune tolérance.
    static func exactKey(_ bookmark: EchoBookmark) -> String {
        (["B", bookmark.rootKey, bookmark.folderPath.joined(separator: "\u{1E}"), bookmark.name, bookmark.url])
            .joined(separator: "\u{1F}")
    }

    private static func collect(children: [[String: Any]],
                                rootKey: String,
                                path: [String],
                                bookmarks: inout [EchoBookmark],
                                folders: inout Set<EchoFolder>,
                                layout: inout [String],
                                ignored: inout Int) {
        for child in children {
            let type = child["type"] as? String
            let name = child["name"] as? String ?? ""

            if type == "url", let url = child["url"] as? String {
                if isWebURL(child) {
                    let bookmark = EchoBookmark(rootKey: rootKey, folderPath: path, name: name, url: url)
                    bookmarks.append(bookmark)
                    layout.append(exactKey(bookmark))
                } else {
                    ignored += 1
                }
            } else if type == "folder" {
                if isBrowserManaged(child) { continue }
                let subPath = path + [name]
                folders.insert(EchoFolder(rootKey: rootKey, path: subPath))
                layout.append((["F", rootKey] + subPath).joined(separator: "\u{1F}"))
                collect(children: child["children"] as? [[String: Any]] ?? [],
                        rootKey: rootKey, path: subPath,
                        bookmarks: &bookmarks, folders: &folders, layout: &layout, ignored: &ignored)
            }
        }
    }
}
