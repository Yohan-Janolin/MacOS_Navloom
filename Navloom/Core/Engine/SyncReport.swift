import Foundation

/// Construit le rapport texte d'une synchronisation.
nonisolated enum SyncReport {

    static func text(browserName: String,
                     profileName: String,
                     analysis: SyncAnalysis,
                     fetchResult: SyncFetchResult,
                     summary: WriteSummary?,
                     date: Date = Date()) -> String {

        var report = "Rapport FaviconSync — \(date.formatted(date: .long, time: .shortened))\n\n"
        report += "Navigateur : \(browserName) (profil \(profileName))\n"
        report += "Favoris web analysés : \(analysis.webBookmarks)\n"
        report += "Favoris sans favicon au départ : \(analysis.missing.count)\n"

        if let summary {
            report += "Favicons récupérées et écrites : \(summary.success)\n"
            if let backup = summary.backupURL {
                report += "Sauvegarde de la base : \(backup.path)\n"
            }
        } else {
            report += "Favicons récupérées (pas encore écrites) : \(fetchResult.fetched.count)\n"
        }

        report += "\nSites confirmés sans favicon disponible : \(fetchResult.confirmedNone.count)\n"
        report += grouped(fetchResult.confirmedNone)

        report += "\nÉchecs indéterminés, à traiter à la main : \(fetchResult.failures.count)\n"
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
