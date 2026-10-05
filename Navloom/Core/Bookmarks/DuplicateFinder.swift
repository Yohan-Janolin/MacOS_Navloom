import Foundation

/// Des favoris qui pointent exactement sur la même URL.
nonisolated struct DuplicateGroup: Identifiable, Sendable {
    let url: String
    let bookmarks: [Bookmark]

    var id: String { url }
}

nonisolated enum DuplicateFinder {

    /// Regroupe les favoris par URL EXACTE (aucune normalisation : `/` final, `www.`, http/https
    /// et paramètres comptent comme des différences). Seuls les groupes d'au moins deux favoris
    /// sont retournés, les plus gros d'abord, puis par ordre alphabétique.
    static func groups(in bookmarks: [Bookmark]) -> [DuplicateGroup] {
        Dictionary(grouping: bookmarks, by: \.url)
            .filter { $0.value.count > 1 }
            .map { DuplicateGroup(url: $0.key, bookmarks: $0.value) }
            .sorted { ($0.bookmarks.count, $1.url) > ($1.bookmarks.count, $0.url) }
    }

    /// Favoris à cocher pour « Garder le premier de chaque groupe » (identifiants de nœud, favoris
    /// locaux uniquement : ceux du compte ne se suppriment pas d'ici). S'il existe une copie dans
    /// le compte, c'est elle qu'on garde et toutes les copies locales sont cochées ; sinon on garde
    /// la première copie locale.
    static func removableKeepingFirst(in groups: [DuplicateGroup]) -> Set<String> {
        var ids = Set<String>()
        for group in groups {
            let hasAccountCopy = group.bookmarks.contains { $0.source == .account }
            let locals = group.bookmarks.filter { $0.source == .local }
            let toRemove = hasAccountCopy ? locals : Array(locals.dropFirst())
            ids.formUnion(toRemove.map(\.nodeID))
        }
        return ids
    }
}
