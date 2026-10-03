import Foundation

/// Lit le fichier `Bookmarks` d'un navigateur Chromium (JSON).
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

    static func read(from url: URL) throws -> [Bookmark] {
        try parse(Data(contentsOf: url))
    }

    /// Séparé de `read` pour pouvoir tester sans fichier sur le disque.
    static func parse(_ data: Data) throws -> [Bookmark] {
        let file = try JSONDecoder().decode(File.self, from: data)
        var result = flatten(file.roots.bookmark_bar, parents: []) + flatten(file.roots.other, parents: [])
        if let synced = file.roots.synced {
            result += flatten(synced, parents: [])
        }
        return result
    }

    /// `parents` : noms des dossiers traversés pour arriver jusqu'à ce nœud.
    private static func flatten(_ node: Node, parents: [String]) -> [Bookmark] {
        var result: [Bookmark] = []
        if node.type == "url", let url = node.url {
            result.append(Bookmark(name: node.name,
                                   url: url,
                                   folder: parents.joined(separator: " / "),
                                   nodeID: node.id ?? ""))
        }
        let path = parents + [node.name]
        for child in node.children ?? [] {
            result += flatten(child, parents: path)
        }
        return result
    }
}
