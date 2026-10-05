import Foundation

/// Orchestre les trois étapes : analyser → télécharger → écrire.
/// Un `actor` : tout le travail se fait hors du thread principal.
actor FaviconSyncEngine {
    static let maxConcurrentHosts = 16
    static let retryConcurrentHosts = 6
    static let retryDelaySeconds = 5

    let profile: ChromiumProfile
    private let fetcher = FaviconFetcher()

    init(profile: ChromiumProfile) {
        self.profile = profile
    }

    // MARK: 1. Analyse (lecture seule : le navigateur peut rester ouvert)

    func analyze() async throws -> SyncAnalysis {
        let all = try BookmarksReader.readAll(for: profile)

        // On ne traite que les liens web (pas vivaldi://, file://, etc.).
        let web = all.filter {
            let scheme = URL(string: $0.url)?.scheme?.lowercased() ?? ""
            return scheme == "http" || scheme == "https"
        }

        let database = try FaviconDatabase(url: profile.faviconsURL, writable: false)
        let known = try await database.urlsWithFavicon()

        // Comparaison sur l'URL EXACTE (pas le domaine : github.com a une favicon
        // pour certaines pages, pas pour toutes).
        let missing = web.filter { !known.contains($0.url) }
        return SyncAnalysis(totalBookmarks: all.count, webBookmarks: web.count, missing: missing)
    }

    // MARK: 2. Téléchargement (aucune écriture)

    func fetchMissing(_ analysis: SyncAnalysis,
                      onEvent: @escaping @Sendable (SyncEvent) -> Void) async -> SyncFetchResult {

        // Dédoublonnage par origine : une résolution par origine, partagée par tous ses favoris.
        var origins: [Origin] = []
        var urlsByKey: [String: [URL]] = [:]
        for bookmark in analysis.missing {
            guard let url = URL(string: bookmark.url), let origin = Origin.from(url) else { continue }
            if urlsByKey[origin.key] == nil {
                origins.append(origin)
                urlsByKey[origin.key] = []
            }
            if let pageURL = bookmarkPageURL(url, origin: origin),
               !(urlsByKey[origin.key] ?? []).contains(pageURL) {
                urlsByKey[origin.key]?.append(pageURL)
            }
        }

        let allOrigins = origins
        let allURLs = urlsByKey

        var results = await fetcher.resolveAll(
            origins: allOrigins, urlsByKey: allURLs, maxConcurrent: Self.maxConcurrentHosts
        ) { origin, result, done in
            onEvent(.resolved(pass: 1, done: done, total: allOrigins.count,
                              origin: origin.label, status: .init(result)))
        }

        // Seconde passe automatique sur les échecs transitoires.
        let retryOrigins = allOrigins.filter { results[$0.key]?.isRetryable == true }
        if !retryOrigins.isEmpty {
            onEvent(.retrying(count: retryOrigins.count, delaySeconds: Self.retryDelaySeconds))
            try? await Task.sleep(for: .seconds(Self.retryDelaySeconds))

            let secondPass = await fetcher.resolveAll(
                origins: retryOrigins, urlsByKey: allURLs, maxConcurrent: Self.retryConcurrentHosts
            ) { origin, result, done in
                onEvent(.resolved(pass: 2, done: done, total: retryOrigins.count,
                                  origin: origin.label, status: .init(result)))
            }
            results.merge(secondPass) { _, new in new }
        }

        // Répartition des favoris selon le résultat de leur origine.
        var fetched: [FetchedFavicon] = []
        var confirmedNone: [BookmarkIssue] = []
        var failures: [BookmarkIssue] = []

        for bookmark in analysis.missing {
            guard let url = URL(string: bookmark.url),
                  let origin = Origin.from(url),
                  let result = results[origin.key] else {
                failures.append(BookmarkIssue(bookmark: bookmark, reason: "URL invalide"))
                continue
            }
            switch result {
            case .found(let data):
                fetched.append(FetchedFavicon(bookmark: bookmark, iconData: data, origin: origin))
            case .confirmedNone(let reason):
                confirmedNone.append(BookmarkIssue(bookmark: bookmark, reason: reason))
            case .failed(let reason, _):
                failures.append(BookmarkIssue(bookmark: bookmark, reason: reason))
            }
        }
        return SyncFetchResult(fetched: fetched, confirmedNone: confirmedNone, failures: failures)
    }

    // MARK: 3. Écriture (navigateur fermé obligatoire, sauvegarde automatique)

    func write(_ result: SyncFetchResult) async throws -> WriteSummary {
        guard !result.fetched.isEmpty else {
            return WriteSummary(success: 0, failure: 0, uniqueIcons: 0, backupURL: nil)
        }
        if profile.isBrowserRunning {
            throw SyncError.browserRunning(profile.browserName)
        }

        let backupURL = try FaviconBackup.create(from: profile.faviconsURL, label: profile.id)

        let database = try FaviconDatabase(url: profile.faviconsURL, writable: true)
        try await database.begin()

        // Une seule icône par clé : www.x.fr et x.fr la partagent, deux services locaux jamais.
        var iconIDByKey: [String: Int64] = [:]
        var success = 0
        var failure = 0

        for item in result.fetched {
            let iconID: Int64
            if let existing = iconIDByKey[item.origin.iconKey] {
                iconID = existing
            } else {
                let bitmaps = FaviconImage.bitmaps(from: item.iconData)
                guard !bitmaps.isEmpty,
                      let newID = try? await database.insertIcon(sourceURL: item.origin.iconSourceURL,
                                                                 bitmaps: bitmaps) else {
                    failure += 1
                    continue
                }
                iconIDByKey[item.origin.iconKey] = newID
                iconID = newID
            }

            do {
                try await database.insertMapping(pageURL: item.bookmark.url, iconID: iconID)
                success += 1
            } catch {
                failure += 1
            }
        }

        do {
            try await database.commit()
        } catch {
            await database.rollback()
            throw error
        }

        return WriteSummary(success: success, failure: failure,
                            uniqueIcons: iconIDByKey.count, backupURL: backupURL)
    }
}
