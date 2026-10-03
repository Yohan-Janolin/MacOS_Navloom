import Testing
import Foundation
@testable import Navloom

struct SyncReportTests {

    @Test func regroupeLesFavorisParRaison() {
        let issues = [
            BookmarkIssue(bookmark: Bookmark(name: "A", url: "https://a.fr"), reason: "délai dépassé"),
            BookmarkIssue(bookmark: Bookmark(name: "B", url: "https://b.fr"), reason: "délai dépassé"),
            BookmarkIssue(bookmark: Bookmark(name: "C", url: "https://c.fr"), reason: "HTTP 403"),
        ]
        let report = SyncReport.text(
            browserName: "Vivaldi",
            profileName: "Default",
            analysis: SyncAnalysis(totalBookmarks: 10, webBookmarks: 9, missing: []),
            fetchResult: SyncFetchResult(fetched: [], confirmedNone: [], failures: issues),
            summary: nil
        )

        #expect(report.contains("[délai dépassé]"))
        #expect(report.contains("[HTTP 403]"))
        #expect(report.contains("- A (https://a.fr)"))
        #expect(report.contains("Échecs indéterminés, à traiter à la main : 3"))
    }
}
