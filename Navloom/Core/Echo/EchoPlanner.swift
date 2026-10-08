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
