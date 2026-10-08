import Foundation

nonisolated struct EchoMergeResult: Sendable {
    let data: Data
    let added: Int
    let createdFolders: Int
}

/// Ajoute des favoris dans le contenu d'un fichier `Bookmarks` Chromium (mode « fusion » : on n'enlève rien).
///
/// Comme `BookmarksWriter`, le fichier est manipulé comme un JSON générique : tout ce que l'on ne comprend
/// pas (champs propres à Vivaldi ou Opera, métadonnées) est réécrit tel quel. Rien n'est écrit sur le
/// disque ici : c'est `EchoEngine.apply` qui sauvegarde puis écrit.
nonisolated enum EchoWriter {

    /// Ajoute chaque favori à la fin de son dossier (créé s'il n'existe pas), et retourne le nouveau contenu.
    ///
    /// - Un dossier existant est reconnu à son nom (le premier de ce nom, comme `EchoReader`).
    /// - Si la destination n'a pas la racine du favori (typiquement « Favoris mobiles »), il va dans « Autres favoris ».
    static func merging(_ bookmarks: [EchoBookmark], into data: Data, now: Date = Date()) throws -> EchoMergeResult {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var roots = root["roots"] as? [String: Any] else {
            throw EchoError.invalidFormat
        }
        // On lâche l'ancien arbre : sans ça, chaque ajout copierait des listes entières.
        root.removeValue(forKey: "roots")

        var nextID = maxNodeID(in: roots) + 1
        var created = 0
        let stamp = chromiumTimestamp(now)

        for bookmark in bookmarks {
            let rootKey = roots[bookmark.rootKey] is [String: Any] ? bookmark.rootKey : "other"
            guard var node = roots.removeValue(forKey: rootKey) as? [String: Any] else {
                throw EchoError.invalidFormat
            }
            insert(bookmark, path: bookmark.folderPath[...], into: &node,
                   nextID: &nextID, created: &created, stamp: stamp)
            roots[rootKey] = node
        }
        root["roots"] = roots

        // Chromium recalcule ce total de contrôle à la prochaine sauvegarde du fichier ; un total
        // périmé serait pire qu'une absence de total.
        root.removeValue(forKey: "checksum")

        let output = try JSONSerialization.data(withJSONObject: root,
                                                options: [.prettyPrinted, .withoutEscapingSlashes])
        return EchoMergeResult(data: output, added: bookmarks.count, createdFolders: created)
    }

    // MARK: - Arbre

    private static func insert(_ bookmark: EchoBookmark,
                               path: ArraySlice<String>,
                               into node: inout [String: Any],
                               nextID: inout Int,
                               created: inout Int,
                               stamp: String) {
        var children = (node.removeValue(forKey: "children") as? [[String: Any]]) ?? []

        if let name = path.first {
            let existing = children.firstIndex {
                $0["type"] as? String == "folder" && $0["name"] as? String == name
            }
            if let index = existing {
                var folder = children[index]
                children[index] = [:]
                insert(bookmark, path: path.dropFirst(), into: &folder,
                       nextID: &nextID, created: &created, stamp: stamp)
                children[index] = folder
            } else {
                var folder = newNode(type: "folder", name: name, id: &nextID, stamp: stamp)
                created += 1
                insert(bookmark, path: path.dropFirst(), into: &folder,
                       nextID: &nextID, created: &created, stamp: stamp)
                children.append(folder)
            }
        } else {
            var item = newNode(type: "url", name: bookmark.name, id: &nextID, stamp: stamp)
            item["url"] = bookmark.url
            children.append(item)
        }

        node["children"] = children
        node["date_modified"] = stamp
    }

    /// Un nœud tel que Chromium l'écrit : identifiant numérique unique (sous forme de texte), guid, dates.
    private static func newNode(type: String, name: String, id: inout Int, stamp: String) -> [String: Any] {
        var node: [String: Any] = [
            "id": String(id),
            "guid": UUID().uuidString.lowercased(),
            "name": name,
            "type": type,
            "date_added": stamp,
        ]
        id += 1

        if type == "folder" {
            node["children"] = [[String: Any]]()
            node["date_modified"] = stamp
        } else {
            node["date_last_used"] = "0"
        }
        return node
    }

    /// Plus grand identifiant de nœud du fichier : les nouveaux démarrent juste après, sans collision.
    private static func maxNodeID(in value: Any) -> Int {
        var best = 0
        if let dictionary = value as? [String: Any] {
            if let id = dictionary["id"] as? String, let number = Int(id) { best = number }
            for child in dictionary.values { best = max(best, maxNodeID(in: child)) }
        } else if let array = value as? [Any] {
            for child in array { best = max(best, maxNodeID(in: child)) }
        }
        return best
    }

    /// Le format de date de Chromium : microsecondes depuis le 1er janvier 1601, écrites en texte.
    private static func chromiumTimestamp(_ date: Date) -> String {
        let epochOffset: Int64 = 11_644_473_600_000_000
        return String(Int64(date.timeIntervalSince1970 * 1_000_000) + epochOffset)
    }
}
