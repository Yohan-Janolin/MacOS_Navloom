import Testing
import Foundation
@testable import Navloom

// MARK: - Assemblage des listes renvoyées par AppleScript (aucun navigateur)

struct TabSnapshotTests {

    private func sample(modes: [String?]? = ["normal", "incognito"]) -> [OpenWindow] {
        TabSnapshot.windows(
            browserID: "vivaldi",
            windowIDs: [11, 22],
            modes: modes,
            urls: [["https://a.fr/", "http://192.168.1.45:3456/containers"], ["https://b.fr/x"]],
            titles: [["Page A", nil], ["Page B"]],
            activeIndexes: [2, 1]
        )
    }

    @Test func lesFenetresEtOngletsSontAlignes() {
        let windows = sample()
        #expect(windows.count == 2)
        #expect(windows[0].windowID == 11)
        #expect(windows[0].position == 1)
        #expect(windows[0].tabs.map(\.url) == ["https://a.fr/", "http://192.168.1.45:3456/containers"])
        #expect(windows[1].tabs.map(\.title) == ["Page B"])
    }

    @Test func lOngletActifEstRepere() {
        let windows = sample()
        #expect(windows[0].tabs.map(\.isActive) == [false, true])
        #expect(windows[0].activeTab?.index == 2)
        #expect(windows[1].activeTab?.title == "Page B")
    }

    @Test func laNavigationPriveeEstDetectee() {
        let windows = sample()
        #expect(windows[0].isPrivate == false)
        #expect(windows[1].isPrivate == true)
    }

    @Test func sansModeAucuneFenetreNEstPrivee() {
        #expect(sample(modes: nil).allSatisfy { !$0.isPrivate })
    }

    @Test func lesIdentifiantsSontUniques() {
        let ids = sample().flatMap { $0.tabs.map(\.id) }
        #expect(Set(ids).count == ids.count)
        #expect(ids.first == "vivaldi/11#1")
    }

    @Test func desListesTropCourtesNePlantentPas() {
        let windows = TabSnapshot.windows(browserID: "opera", windowIDs: [1, 2],
                                          modes: [], urls: [["https://a.fr/"]],
                                          titles: [], activeIndexes: [])
        #expect(windows.count == 2)
        #expect(windows[0].tabs.first?.title == "")
        #expect(windows[1].tabs.isEmpty)
        #expect(windows[0].isPrivate == false)
    }
}

// MARK: - Onglet

struct OpenTabTests {

    private func tab(_ title: String, _ url: String) -> OpenTab {
        OpenTab(id: "x", index: 1, title: title, url: url, isActive: false)
    }

    @Test func titreVideRemplaceParLHote() {
        #expect(tab("", "http://192.168.1.45:3456/containers").displayTitle == "192.168.1.45")
        #expect(tab("  ", "https://github.com/x").displayTitle == "github.com")
        #expect(tab("Accueil", "https://a.fr/").displayTitle == "Accueil")
    }

    @Test func rechercheDansTitreEtURLSansCasse() {
        let t = tab("Home Assistant", "https://ha.example.org/dashboard")
        #expect(t.matches("assistant"))
        #expect(t.matches("DASHBOARD"))
        #expect(t.matches(""))
        #expect(!t.matches("vivaldi"))
    }
}

// MARK: - Rapport texte

struct TabReportTests {

    private let browser = ChromiumBrowser.known.first { $0.id == "vivaldi" }!

    private var tabs: BrowserTabs {
        BrowserTabs(browser: browser, result: .success(TabSnapshot.windows(
            browserID: "vivaldi", windowIDs: [1, 2], modes: ["normal", "incognito"],
            urls: [["https://a.fr/"], ["https://secret.fr/"]],
            titles: [["Page A"], ["Secret"]], activeIndexes: [1, 1])))
    }

    @Test func laNavigationPriveeEstExclueParDefaut() {
        let text = TabSnapshot.report([tabs], includePrivate: false)
        #expect(text.contains("Vivaldi — 1 fenêtre, 1 onglet"))
        #expect(text.contains("https://a.fr/"))
        #expect(!text.contains("secret.fr"))
    }

    @Test func laNavigationPriveePeutEtreIncluse() {
        let text = TabSnapshot.report([tabs], includePrivate: true)
        #expect(text.contains("2 fenêtres, 2 onglets"))
        #expect(text.contains("Fenêtre 2 · privée"))
        #expect(text.contains("https://secret.fr/"))
    }

    @Test func uneErreurApparaitDansLeRapport() {
        let failed = BrowserTabs(browser: browser, result: .failure(.permissionDenied))
        let text = TabSnapshot.report([failed], includePrivate: false)
        #expect(text.contains("Vivaldi — non lu"))
    }

    @Test func pluriel() {
        #expect(TabSnapshot.plural(0, "onglet") == "0 onglet")
        #expect(TabSnapshot.plural(1, "onglet") == "1 onglet")
        #expect(TabSnapshot.plural(3, "onglet") == "3 onglets")
    }
}

// MARK: - Codes d'erreur AppleScript et icônes

@MainActor
struct TabReaderErrorTests {

    @Test func codesDAutorisation() {
        #expect(TabReader.error(code: -1743, message: "") == .permissionDenied)
        #expect(TabReader.error(code: -1744, message: "") == .permissionDenied)
    }

    @Test func navigateurFerme() {
        #expect(TabReader.error(code: -600, message: "") == .notRunning)
        #expect(TabReader.error(code: -609, message: "") == .notRunning)
    }

    @Test func autreErreur() {
        #expect(TabReader.error(code: -1712, message: "délai") == .script(code: -1712, message: "délai"))
    }

    @Test func leScriptCibleLeBundleID() {
        let source = TabReader.source(bundleID: "com.vivaldi.Vivaldi", withModes: true)
        #expect(source.contains(#"tell application id "com.vivaldi.Vivaldi""#))
        #expect(source.contains("mode of every window"))
        #expect(!TabReader.source(bundleID: "x", withModes: false).contains("mode of every window"))
    }
}

struct TabFaviconTests {

    @Test func prefixeDuSite() {
        #expect(TabFaviconLoader.sitePrefix(of: "https://github.com/Yohan/x?y=1") == "https://github.com/")
        #expect(TabFaviconLoader.sitePrefix(of: "http://192.168.1.45:3456/containers") == "http://192.168.1.45:3456/")
        #expect(TabFaviconLoader.sitePrefix(of: "chrome://settings") == "chrome://settings/")
        #expect(TabFaviconLoader.sitePrefix(of: "pas une url") == nil)
    }

    @Test func jokersDeLikeNeutralises() {
        #expect(FaviconDatabase.escapedForLike("https://a_b.fr/100%") == #"https://a\_b.fr/100\%"#)
    }

    @Test func meilleurBitmap() {
        let bitmaps = [16, 32, 128].map { FaviconBitmap(size: $0, png: Data([UInt8($0 % 256)])) }
        #expect(FaviconDatabase.bestBitmap(bitmaps)?.size == 32)
        #expect(FaviconDatabase.bestBitmap([FaviconBitmap(size: 128, png: Data())])?.size == 128)
        #expect(FaviconDatabase.bestBitmap([]) == nil)
    }
}
