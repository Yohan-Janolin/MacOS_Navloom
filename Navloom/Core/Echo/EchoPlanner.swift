import Foundation

/// Décide quoi ajouter à la destination (mode « fusion » : on ajoute, on ne supprime jamais).
nonisolated enum EchoPlanner {

    static func plan(source: EchoSnapshot,
                     destination: EchoSnapshot,
                     mode: EchoMatchMode,
                     options: EchoURLOptions = EchoURLOptions()) -> EchoPlan {
        let destinationKeys = Set(destination.bookmarks.map { key(for: $0, mode: mode, options: options) })

        var added = Set<String>()
        var toAdd: [EchoBookmark] = []
        var alreadyPresent = 0
        var skippedDuplicates = 0

        for bookmark in source.bookmarks {
            let k = key(for: bookmark, mode: mode, options: options)
            if destinationKeys.contains(k) {
                alreadyPresent += 1
            } else if !added.insert(k).inserted {
                // Deux favoris de la source identiques : une seule copie part dans la destination.
                skippedDuplicates += 1
            } else {
                toAdd.append(bookmark)
            }
        }

        // Dossiers à créer : ceux du chemin de chaque favori ajouté qui n'existent pas encore.
        var missingFolders = Set<EchoFolder>()
        for bookmark in toAdd {
            var prefix: [String] = []
            for name in bookmark.folderPath {
                prefix.append(name)
                let folder = EchoFolder(rootKey: bookmark.rootKey, path: prefix)
                if !destination.folders.contains(folder) { missingFolders.insert(folder) }
            }
        }

        return EchoPlan(toAdd: toAdd,
                        alreadyPresent: alreadyPresent,
                        skippedSourceDuplicates: skippedDuplicates,
                        newFolders: missingFolders.count)
    }

    /// Copie complète : ce qu'il faudrait ajouter et supprimer pour que la cible soit l'image de la source.
    /// Les favoris sont comparés exactement (racine, dossiers, nom, URL) ; les options d'URL ne servent pas ici.
    static func mirrorPlan(source: EchoSnapshot, destination: EchoSnapshot) -> EchoMirrorPlan {
        // Une racine que la cible n'a pas (« Favoris mobiles ») est copiée dans « Autres favoris ».
        func moved(_ bookmark: EchoBookmark) -> EchoBookmark {
            guard !destination.rootKeys.contains(bookmark.rootKey) else { return bookmark }
            return EchoBookmark(rootKey: "other", folderPath: bookmark.folderPath,
                                name: bookmark.name, url: bookmark.url)
        }

        let expected = source.bookmarks.map(moved)
        var targetLeft: [String: Int] = [:]
        for bookmark in destination.bookmarks { targetLeft[EchoReader.exactKey(bookmark), default: 0] += 1 }
        var sourceLeft: [String: Int] = [:]
        for bookmark in expected { sourceLeft[EchoReader.exactKey(bookmark), default: 0] += 1 }

        var toAdd: [EchoBookmark] = []
        var unchanged = 0
        for bookmark in expected {
            let k = EchoReader.exactKey(bookmark)
            if let left = targetLeft[k], left > 0 {
                targetLeft[k] = left - 1
                unchanged += 1
            } else {
                toAdd.append(bookmark)
            }
        }

        var toRemove: [EchoBookmark] = []
        for bookmark in destination.bookmarks {
            let k = EchoReader.exactKey(bookmark)
            if let left = sourceLeft[k], left > 0 {
                sourceLeft[k] = left - 1
            } else {
                toRemove.append(bookmark)
            }
        }

        let sourceFolders = Set(source.folders.map { folder in
            destination.rootKeys.contains(folder.rootKey) ? folder : EchoFolder(rootKey: "other", path: folder.path)
        })

        // Déjà identiques : mêmes dossiers, mêmes favoris, même ordre, rien de non web à retirer.
        let usedRoots = Set(source.bookmarks.map(\.rootKey)).union(source.folders.map(\.rootKey))
        let sameRoots = usedRoots.isSubset(of: destination.rootKeys)
        let identical = sameRoots && source.layout == destination.layout && destination.ignoredCount == 0

        return EchoMirrorPlan(toAdd: toAdd,
                              toRemove: toRemove,
                              nonWebToRemove: destination.ignoredCount,
                              unchanged: unchanged,
                              foldersToAdd: sourceFolders.subtracting(destination.folders).count,
                              foldersToRemove: destination.folders.subtracting(sourceFolders).count,
                              expected: expected,
                              isIdentical: identical)
    }

    /// Forme comparable d'une URL : schéma et nom de domaine en minuscules, « / » final ignoré,
    /// plus les variantes choisies dans `options`. Le reste (chemin, ancre…) compte comme une différence.
    static func normalized(_ url: String, options: EchoURLOptions = EchoURLOptions()) -> String {
        guard var components = URLComponents(string: url) else { return url }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()

        if options.ignoreScheme, components.scheme == "http" {
            components.scheme = "https"
        }
        if options.ignoreWWW, let host = components.host, host.hasPrefix("www."), host.count > 4 {
            components.host = String(host.dropFirst(4))
        }
        if options.ignoreQuery {
            components.query = nil
        }

        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        components.path = path

        return components.string ?? url
    }

    private static func key(for bookmark: EchoBookmark, mode: EchoMatchMode, options: EchoURLOptions) -> String {
        let url = normalized(bookmark.url, options: options)
        switch mode {
        case .anywhere:
            return url
        case .sameFolder:
            let folder = ([bookmark.rootKey] + bookmark.folderPath).joined(separator: "\u{1E}")
            return folder + "\u{1F}" + url
        }
    }
}
