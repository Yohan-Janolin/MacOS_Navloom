//
//  DuplicateFinder.swift
//  Navloom
//

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
}
