import Foundation

/// Lit le fichier `Bookmarks` d'un navigateur Chromium (JSON).
/// `AccountBookmarks` (favoris du compte Google dans Chrome) a le même format.
nonisolated enum BookmarksReader {

    // Un nœud est soit un dossier, soit un favori (champs optionnels selon le type).
    private nonisolated struct Node: Decodable {
        let id: String?
        let name: String
        let type: String
        let url: String?
        let children: [Node]?
    }

    private nonisolated struct Roots: Decodable {
        let bookmark_bar: Node
        let other: Node
        let synced: Node?
    }

    private nonisolated struct File: Decodable {
        let roots: Roots
    }

    static func read(from url: URL, source: BookmarkSource = .local) throws -> [Bookmark] {
        try parse(Data(contentsOf: url), source: source)
    }

    /// Les favoris d'un profil : ceux du fichier `Bookmarks`, puis ceux de `AccountBookmarks` s'il existe
    /// et si Chrome les affiche encore (voir `AccountBookmarksStatus`).
    /// Un fichier du compte illisible est ignoré (ce format n'est pas documenté par Chrome) ;
    /// si aucun des deux fichiers n'est lisible, l'erreur de `Bookmarks` est remontée.
    static func readAll(for profile: ChromiumProfile) throws -> [Bookmark] {
        let fm = FileManager.default
        var result: [Bookmark] = []
        var found = false
        var accountHidden = false

        if fm.fileExists(atPath: profile.bookmarksURL.path) {
            result += try read(from: profile.bookmarksURL)
            found = true
        }
        if fm.fileExists(atPath: profile.accountBookmarksURL.path) {
            if AccountBookmarksStatus.detect(for: profile) == .disabled {
                // Option désactivée : le fichier reste sur le disque, mais Chrome ne montre plus ces favoris.
                accountHidden = true
            } else if let account = try? read(from: profile.accountBookmarksURL, source: .account) {
                result += account
                found = true
            }
        }
        if !found {
            // Seuls des favoris du compte masqués : il n'y a rien à analyser, ce n'est pas une erreur.
            if accountHidden { return [] }
            return try read(from: profile.bookmarksURL)
        }
        return result
    }

    /// Séparé de `read` pour pouvoir tester sans fichier sur le disque.
    static func parse(_ data: Data, source: BookmarkSource = .local) throws -> [Bookmark] {
        let file = try JSONDecoder().decode(File.self, from: data)
        var result = flatten(file.roots.bookmark_bar, parents: [], source: source)
            + flatten(file.roots.other, parents: [], source: source)
        if let synced = file.roots.synced {
            result += flatten(synced, parents: [], source: source)
        }
        return result
    }

    /// `parents` : noms des dossiers traversés pour arriver jusqu'à ce nœud.
    private static func flatten(_ node: Node, parents: [String], source: BookmarkSource) -> [Bookmark] {
        var result: [Bookmark] = []
        if node.type == "url", let url = node.url {
            result.append(Bookmark(name: node.name,
                                   url: url,
                                   folder: parents.joined(separator: " / "),
                                   nodeID: node.id ?? "",
                                   source: source))
        }
        let path = parents + [node.name]
        for child in node.children ?? [] {
            result += flatten(child, parents: path, source: source)
        }
        return result
    }
}
