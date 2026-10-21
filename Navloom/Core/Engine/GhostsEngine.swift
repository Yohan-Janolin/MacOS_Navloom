import Foundation

/// Résultat d'une recherche de liens morts, par favori.
nonisolated struct GhostsReport: Sendable {
    let webBookmarks: Int
    let aliveCount: Int
    let dead: [BookmarkIssue]
    let uncertain: [BookmarkIssue]
    let moved: [BookmarkIssue]

    func text(browserName: String, profileName: String, date: Date = Date()) -> String {
        let when = date.formatted(date: .long, time: .shortened)
        var report = String(localized: "Ghosts report — \(when)") + "\n\n"
        report += String(localized: "Browser: \(browserName) (profile \(profileName))") + "\n"
        report += String(localized: "Web bookmarks analyzed: \(webBookmarks)") + "\n"
        report += String(localized: "Reachable: \(aliveCount)") + "\n"
        report += "\n" + String(localized: "Dead links: \(dead.count)") + "\n" + Self.grouped(dead)
        report += "\n" + String(localized: "To check by hand: \(uncertain.count)") + "\n" + Self.grouped(uncertain)
        report += "\n" + String(localized: "Redirected: \(moved.count)") + "\n" + Self.grouped(moved)
        return report
    }

    /// « Dossier : Barre / Dev », avec la mention du compte Google si besoin.
    static func folderLine(_ folder: String, isAccount: Bool) -> String {
        isAccount
            ? String(localized: "Folder: \(folder) (Google Account bookmark, delete it by hand)")
            : String(localized: "Folder: \(folder)")
    }

    private static func grouped(_ issues: [BookmarkIssue]) -> String {
        let groups = Dictionary(grouping: issues, by: \.reason)
        var text = ""
        for reason in groups.keys.sorted() {
            text += "\n  [\(reason)]\n"
            for issue in groups[reason] ?? [] {
                let folder = issue.bookmark.folder.isEmpty ? String(localized: "Root") : issue.bookmark.folder
                text += "    - \(issue.bookmark.name) (\(issue.bookmark.url))\n"
                text += "      " + folderLine(folder, isAccount: issue.bookmark.source == .account) + "\n"
            }
        }
        return text
    }
}

nonisolated enum GhostsEvent: Sendable {
    case checked(pass: Int, done: Int, total: Int, url: String)
    case retrying(count: Int, delaySeconds: Int)
}

/// Lecture seule : ne touche ni au fichier Bookmarks ni à la base Favicons.
/// Le navigateur peut rester ouvert.
actor GhostsEngine {
    static let maxConcurrent = 16
    static let retryConcurrent = 6
    static let retryDelaySeconds = 5

    let profile: ChromiumProfile
    private let checker: any LinkChecking
    private let retryDelay: Int

    /// `checker` et `retryDelaySeconds` ne changent que dans les tests.
    init(profile: ChromiumProfile,
         checker: any LinkChecking = LinkChecker(),
         retryDelaySeconds: Int = GhostsEngine.retryDelaySeconds) {
        self.profile = profile
        self.checker = checker
        self.retryDelay = retryDelaySeconds
    }

    func scan(onEvent: @escaping @Sendable (GhostsEvent) -> Void) async throws -> GhostsReport {
        let all = try BookmarksReader.readAll(for: profile)
        let web = all.filter {
            let scheme = URL(string: $0.url)?.scheme?.lowercased() ?? ""
            return scheme == "http" || scheme == "https"
        }

        // Une vérification par URL exacte, partagée par tous les favoris qui la contiennent.
        var bookmarksByURL: [String: [Bookmark]] = [:]
        var urls: [URL] = []
        var invalid: [BookmarkIssue] = []
        for bookmark in web {
            guard let url = URL(string: bookmark.url) else {
                invalid.append(BookmarkIssue(bookmark: bookmark, reason: String(localized: "Invalid URL")))
                continue
            }
            if bookmarksByURL[bookmark.url] == nil { urls.append(url) }
            bookmarksByURL[bookmark.url, default: []].append(bookmark)
        }

        let checker = self.checker
        var results = await Self.runAll(urls, checker: checker,
                                        concurrency: Self.maxConcurrent, pass: 1, onEvent: onEvent)

        // Seconde passe sur les échecs transitoires (délai, 5xx, DNS…).
        let retryURLs = urls.filter { results[$0.absoluteString]?.isRetryable == true }
        if !retryURLs.isEmpty {
            onEvent(.retrying(count: retryURLs.count, delaySeconds: retryDelay))
            try? await Task.sleep(for: .seconds(retryDelay))
            let second = await Self.runAll(retryURLs, checker: checker,
                                           concurrency: Self.retryConcurrent, pass: 2, onEvent: onEvent)
            results.merge(second) { _, new in new }
        }

        // Répartition par favori.
        var alive = 0
        var dead = invalid
        var uncertain: [BookmarkIssue] = []
        var moved: [BookmarkIssue] = []

        for (key, bookmarks) in bookmarksByURL {
            let result = results[key] ?? .uncertain(String(localized: "not checked"), retryable: false)
            for bookmark in bookmarks {
                switch result {
                case .alive:
                    alive += 1
                case .moved(let note):
                    moved.append(BookmarkIssue(bookmark: bookmark, reason: note))
                case .dead(let reason):
                    dead.append(BookmarkIssue(bookmark: bookmark, reason: reason))
                case .unresolved(let reason):
                    // Toujours introuvable au second passage : on le range parmi les morts.
                    dead.append(BookmarkIssue(bookmark: bookmark, reason: reason))
                case .uncertain(let reason, _):
                    uncertain.append(BookmarkIssue(bookmark: bookmark, reason: reason))
                }
            }
        }

        func sorted(_ issues: [BookmarkIssue]) -> [BookmarkIssue] {
            issues.sorted { $0.bookmark.url.localizedCaseInsensitiveCompare($1.bookmark.url) == .orderedAscending }
        }

        return GhostsReport(webBookmarks: web.count, aliveCount: alive,
                            dead: sorted(dead), uncertain: sorted(uncertain), moved: sorted(moved))
    }

    /// Vérifie une liste d'URLs avec un nombre borné de requêtes simultanées.
    private static func runAll(_ urls: [URL],
                               checker: any LinkChecking,
                               concurrency: Int,
                               pass: Int,
                               onEvent: @escaping @Sendable (GhostsEvent) -> Void) async -> [String: LinkCheckResult] {
        var results: [String: LinkCheckResult] = [:]
        var next = 0
        var done = 0
        let total = urls.count

        await withTaskGroup(of: (URL, LinkCheckResult).self) { group in
            while next < min(concurrency, total) {
                let url = urls[next]
                next += 1
                group.addTask { (url, await checker.check(url)) }
            }
            for await (url, result) in group {
                results[url.absoluteString] = result
                done += 1
                onEvent(.checked(pass: pass, done: done, total: total, url: url.absoluteString))

                if next < total {
                    let following = urls[next]
                    next += 1
                    group.addTask { (following, await checker.check(following)) }
                }
            }
        }
        return results
    }
}
