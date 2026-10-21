import Foundation

/// Construit le rapport texte d'une synchronisation.
nonisolated enum SyncReport {

    static func text(browserName: String,
                     profileName: String,
                     analysis: SyncAnalysis,
                     fetchResult: SyncFetchResult,
                     summary: WriteSummary?,
                     date: Date = Date()) -> String {

        let when = date.formatted(date: .long, time: .shortened)
        var report = String(localized: "FaviconSync report — \(when)") + "\n\n"
        report += String(localized: "Browser: \(browserName) (profile \(profileName))") + "\n"
        report += String(localized: "Web bookmarks analyzed: \(analysis.webBookmarks)") + "\n"
        report += String(localized: "Bookmarks without a favicon at the start: \(analysis.missing.count)") + "\n"

        if let summary {
            report += String(localized: "Favicons fetched and written: \(summary.success)") + "\n"
            if let backup = summary.backupURL {
                report += String(localized: "Database backup: \(backup.path)") + "\n"
            }
        } else {
            report += String(localized: "Favicons fetched (not written yet): \(fetchResult.fetched.count)") + "\n"
        }

        report += "\n" + String(localized: "Sites confirmed to have no favicon: \(fetchResult.confirmedNone.count)") + "\n"
        report += grouped(fetchResult.confirmedNone)

        report += "\n" + String(localized: "Undetermined failures, to handle by hand: \(fetchResult.failures.count)") + "\n"
        report += grouped(fetchResult.failures)

        return report
    }

    /// Regroupe les favoris par raison, dans l'ordre alphabétique des raisons.
    private static func grouped(_ issues: [BookmarkIssue]) -> String {
        let groups = Dictionary(grouping: issues, by: \.reason)
        var text = ""
        for reason in groups.keys.sorted() {
            text += "\n  [\(reason)]\n"
            for issue in groups[reason] ?? [] {
                text += "    - \(issue.bookmark.name) (\(issue.bookmark.url))\n"
            }
        }
        return text
    }
}
