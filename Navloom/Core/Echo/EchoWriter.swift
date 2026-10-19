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

    // MARK: - Copie complète

    /// Réécrit les racines de la cible pour qu'elles soient l'image de celles de la source :
    /// mêmes dossiers, même ordre, mêmes noms. Ce qui n'est pas dans la source disparaît.
    ///
    /// - Les nœuds de la cible identiques à ceux de la source (même dossier de même nom, même favori
    ///   de même nom et URL) sont gardés tels quels, avec leurs dates et leurs champs propres au navigateur.
    /// - Les dossiers gérés par le navigateur (Speed Dial et Corbeille de Vivaldi) ne sont pas touchés.
    /// - Une racine de la source absente de la cible est ajoutée à la fin de « Autres favoris ».
    static func mirroring(source sourceData: Data, into data: Data, now: Date = Date()) throws -> Data {
        guard let sourceRoot = try JSONSerialization.jsonObject(with: sourceData) as? [String: Any],
              let sourceRoots = sourceRoot["roots"] as? [String: Any],
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var roots = root["roots"] as? [String: Any],
              roots["other"] is [String: Any] else {
            throw EchoError.invalidFormat
        }
        root.removeValue(forKey: "roots")

        var nextID = maxNodeID(in: roots) + 1
        let stamp = chromiumTimestamp(now)
        var leftovers: [[String: Any]] = []

        for key in EchoReader.rootKeys {
            let wanted = filteredChildren((sourceRoots[key] as? [String: Any])?["children"] as? [[String: Any]] ?? [])
            guard var node = roots.removeValue(forKey: key) as? [String: Any] else {
                // La cible n'a pas cette racine : son contenu va dans « Autres favoris ».
                if !wanted.isEmpty {
                    leftovers += rebuild(wanted, reusing: [], nextID: &nextID, stamp: stamp)
                }
                continue
            }
            var current = (node.removeValue(forKey: "children") as? [[String: Any]]) ?? []
            let managed = extractBrowserManaged(from: &current)
            node["children"] = managed + rebuild(wanted, reusing: current, nextID: &nextID, stamp: stamp)
            node["date_modified"] = stamp
            roots[key] = node
        }

        if !leftovers.isEmpty, var other = roots.removeValue(forKey: "other") as? [String: Any] {
            other["children"] = ((other["children"] as? [[String: Any]]) ?? []) + leftovers
            roots["other"] = other
        }
        root["roots"] = roots
        root.removeValue(forKey: "checksum")

        return try JSONSerialization.data(withJSONObject: root,
                                          options: [.prettyPrinted, .withoutEscapingSlashes])
    }

    /// Ce que la source donne à copier : favoris web et dossiers, sans les dossiers gérés par le navigateur.
    private static func filteredChildren(_ children: [[String: Any]]) -> [[String: Any]] {
        children.compactMap { child in
            if EchoReader.isWebURL(child) { return child }
            guard child["type"] as? String == "folder", !EchoReader.isBrowserManaged(child) else { return nil }
            var folder = child
            folder["children"] = filteredChildren(child["children"] as? [[String: Any]] ?? [])
            return folder
        }
    }

    /// Retire de la cible (à n'importe quelle profondeur) les dossiers gérés par le navigateur et les rend.
    private static func extractBrowserManaged(from children: inout [[String: Any]]) -> [[String: Any]] {
        var managed: [[String: Any]] = []
        var kept: [[String: Any]] = []
        for var child in children {
            if EchoReader.isBrowserManaged(child) {
                managed.append(child)
            } else if child["type"] as? String == "folder", var inner = child["children"] as? [[String: Any]] {
                child["children"] = [[String: Any]]()
                managed += extractBrowserManaged(from: &inner)
                child["children"] = inner
                kept.append(child)
            } else {
                kept.append(child)
            }
        }
        children = kept
        return managed
    }

    /// Construit la liste d'enfants voulue. Un nœud existant identique est gardé, sinon un nouveau est créé.
    private static func rebuild(_ wanted: [[String: Any]],
                                reusing existing: [[String: Any]],
                                nextID: inout Int,
                                stamp: String) -> [[String: Any]] {
        var pool = existing
        var result: [[String: Any]] = []

        for item in wanted {
            let name = item["name"] as? String ?? ""
            let isFolder = item["type"] as? String == "folder"
            let url = item["url"] as? String

            let match = pool.firstIndex { candidate in
                guard candidate["name"] as? String == name else { return false }
                if isFolder { return candidate["type"] as? String == "folder" }
                return candidate["type"] as? String == "url" && candidate["url"] as? String == url
            }
            var node: [String: Any]
            var previous: [[String: Any]] = []
            if let match {
                node = pool.remove(at: match)
                previous = (node.removeValue(forKey: "children") as? [[String: Any]]) ?? []
            } else {
                node = newNode(type: isFolder ? "folder" : "url", name: name, id: &nextID, stamp: stamp)
                if !isFolder { node["url"] = url ?? "" }
            }

            if isFolder {
                node["children"] = rebuild(item["children"] as? [[String: Any]] ?? [],
                                           reusing: previous, nextID: &nextID, stamp: stamp)
            }
            result.append(node)
        }
        return result
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
