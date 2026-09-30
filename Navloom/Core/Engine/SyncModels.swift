import Foundation

/// Résultat de l'analyse : combien de favoris n'ont pas d'icône.
nonisolated struct SyncAnalysis: Sendable {
    let totalBookmarks: Int
    let webBookmarks: Int
    let missing: [Bookmark]

    var ignoredCount: Int { totalBookmarks - webBookmarks }
    var withFaviconCount: Int { webBookmarks - missing.count }
}

nonisolated struct FetchedFavicon: Sendable {
    let bookmark: Bookmark
    let iconData: Data
    let origin: Origin
}

nonisolated struct BookmarkIssue: Sendable {
    let bookmark: Bookmark
    let reason: String
}

/// Résultat du téléchargement, avant toute écriture.
nonisolated struct SyncFetchResult: Sendable {
    let fetched: [FetchedFavicon]
    let confirmedNone: [BookmarkIssue]
    let failures: [BookmarkIssue]
}

nonisolated struct WriteSummary: Sendable {
    let success: Int
    let failure: Int
    let uniqueIcons: Int
    let backupURL: URL?
}

/// Évènements de progression, destinés à l'interface.
nonisolated enum SyncEvent: Sendable {
    case resolved(pass: Int, done: Int, total: Int, origin: String, status: Status)
    case retrying(count: Int, delaySeconds: Int)

    enum Status: Sendable {
        case found(bytes: Int)
        case confirmedNone(String)
        case failed(String)

        init(_ result: HostResult) {
            switch result {
            case .found(let data): self = .found(bytes: data.count)
            case .confirmedNone(let reason): self = .confirmedNone(reason)
            case .failed(let reason, _): self = .failed(reason)
            }
        }
    }
}

nonisolated enum SyncError: LocalizedError {
    case browserRunning(String)

    var errorDescription: String? {
        switch self {
        case .browserRunning(let name):
            "\(name) est ouvert. Ferme-le complètement (Cmd + Q) avant d'écrire dans sa base."
        }
    }
}
