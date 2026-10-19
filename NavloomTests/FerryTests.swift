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

// MARK: - Fichier de session (SNSS fabriqué à la main)

/// Construit un fichier SNSS minimal, au même format que Chromium.
private struct SNSSBuilder {
    private(set) var data = Data("SNSS".utf8) + SNSSBuilder.le(3)

    static func le(_ value: Int32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func padded(_ data: Data) -> Data {
        data + Data(repeating: 0, count: (4 - data.count % 4) % 4)
    }

    private static func string(_ text: String) -> Data {
        let bytes = Data(text.utf8)
        return padded(le(Int32(bytes.count)) + bytes)
    }

    private static func bytes(_ raw: Data) -> Data {
        padded(le(Int32(raw.count)) + raw)
    }

    private static func string16(_ text: String) -> Data {
        let units = Array(text.utf16)
        var raw = Data()
        for unit in units { raw += withUnsafeBytes(of: unit.littleEndian) { Data($0) } }
        return padded(le(Int32(units.count)) + raw)
    }

    private static func pickle(_ body: Data) -> Data {
        withUnsafeBytes(of: UInt32(body.count).littleEndian) { Data($0) } + body
    }

    private mutating func record(_ id: UInt8, _ payload: Data) {
        let size = UInt16(payload.count + 1)
        data += withUnsafeBytes(of: size.littleEndian) { Data($0) }
        data.append(id)
        data += payload
    }

    mutating func tab(_ tab: Int32, window: Int32, index: Int32, url: String, title: String) {
        record(0, Self.le(window) + Self.le(tab))
        record(2, Self.le(tab) + Self.le(index))
        record(6, Self.pickle(Self.le(tab) + Self.le(0) + Self.string(url) + Self.string16(title)))
    }

    mutating func navigate(_ tab: Int32, navIndex: Int32, url: String, title: String) {
        record(6, Self.pickle(Self.le(tab) + Self.le(navIndex) + Self.string(url) + Self.string16(title)))
        record(7, Self.le(tab) + Self.le(navIndex))
    }

    mutating func selectTab(window: Int32, index: Int32) {
        record(8, Self.le(window) + Self.le(index))
    }

    mutating func close(tab: Int32) {
        record(16, Self.le(tab) + Data(repeating: 0, count: 8))
    }

    mutating func tabExtra(_ tab: Int32, _ key: String, _ value: String) {
        record(255, Self.pickle(Self.le(tab) + Self.string(key) + Self.bytes(Data(value.utf8))))
    }

    mutating func windowExtra(_ window: Int32, _ key: String, _ value: String) {
        record(254, Self.pickle(Self.le(window) + Self.string(key) + Self.bytes(Data(value.utf8))))
    }

    /// Vivaldi : bloc JSON de l'onglet (commande 21).
    mutating func vivaldiExt(_ tab: Int32, _ json: String) {
        record(21, Self.pickle(Self.le(tab) + Self.string(json)))
    }

    /// Chromium : date de dernière activité (commande 21 aussi, mais sans pickle).
    mutating func lastActiveTime(_ tab: Int32) {
        record(21, Self.le(tab) + withUnsafeBytes(of: Int64(13436885930575060).littleEndian) { Data($0) })
    }

    mutating func truncatedRecord() {
        data += Data([0x40, 0x00, 6, 1, 2])
    }
}

struct SessionFileTests {

    /// Une fenêtre Opera à 3 espaces, comme celle observée sur le Mac de test.
    private var operaSession: Data {
        var b = SNSSBuilder()
        b.tab(10, window: 100, index: 0, url: "https://www.reddit.com/", title: "Reddit")
        b.tab(11, window: 100, index: 1, url: "https://macbb.org/", title: "MacBB")
        b.tab(20, window: 100, index: 0, url: "https://selfh.st/apps/", title: "Self-Hosted")
        b.tab(30, window: 100, index: 0, url: "https://github.com/derv82/wifit3", title: "wifit3")
        b.tabExtra(10, "workspaces_state", "0")
        b.tabExtra(11, "workspaces_state", "0")
        b.tabExtra(20, "workspaces_state", "1")
        b.tabExtra(30, "workspaces_state", "2")
        b.windowExtra(100, "workspaces_state", "1")
        b.selectTab(window: 100, index: 0)
        return b.data
    }

    @Test func lesOngletsSontRetrouves() throws {
        let windows = SessionFile.parse(operaSession)
        #expect(windows.count == 1)
        let window = try #require(windows.first)
        #expect(window.id == 100)
        #expect(window.tabs.count == 4)
        #expect(Set(window.tabs.map(\.url)).contains("https://selfh.st/apps/"))
        #expect(window.tabs.first { $0.id == 20 }?.title == "Self-Hosted")
    }

    @Test func lesEspacesSontLus() throws {
        let window = try #require(SessionFile.parse(operaSession).first)
        let spaces = window.tabs.map { SessionFile.text($0.extraData["workspaces_state"]) }
        #expect(spaces.sorted { ($0 ?? "") < ($1 ?? "") } == ["0", "0", "1", "2"])
        #expect(SessionFile.text(window.extraData["workspaces_state"]) == "1")
        #expect(window.selectedTabIndex == 0)
    }

    @Test func laDernierePageAfficheeGagne() throws {
        var b = SNSSBuilder()
        b.tab(1, window: 9, index: 0, url: "https://a.fr/", title: "A")
        b.navigate(1, navIndex: 1, url: "https://a.fr/page2", title: "A2")
        b.navigate(1, navIndex: 0, url: "https://a.fr/", title: "A") // retour arrière
        let tab = try #require(SessionFile.parse(b.data).first?.tabs.first)
        #expect(tab.url == "https://a.fr/")
    }

    @Test func lesOngletsFermesDisparaissent() {
        var b = SNSSBuilder()
        b.tab(1, window: 9, index: 0, url: "https://a.fr/", title: "A")
        b.tab(2, window: 9, index: 1, url: "https://b.fr/", title: "B")
        b.close(tab: 1)
        #expect(SessionFile.parse(b.data).first?.tabs.map(\.url) == ["https://b.fr/"])
    }

    @Test func uneCommandeTronqueeNePlantePas() {
        var b = SNSSBuilder()
        b.tab(1, window: 9, index: 0, url: "https://a.fr/", title: "A")
        b.truncatedRecord()
        #expect(SessionFile.parse(b.data).first?.tabs.count == 1)
    }

    @Test func blocJSONDeVivaldi() throws {
        var b = SNSSBuilder()
        b.tab(1, window: 9, index: 0, url: "https://reddit.com/", title: "Reddit")
        b.tab(2, window: 9, index: 1, url: "http://192.168.1.45:3789/", title: "HomeLab-901")
        b.lastActiveTime(1)
        b.vivaldiExt(2, #"{"ext_id":"fe9c","workspaceId":1.791027980791e+12}"#)
        let tabs = try #require(SessionFile.parse(b.data).first?.tabs)
        #expect(BrowserWorkspaces.workspaceID(of: tabs[0], style: .vivaldi) == BrowserWorkspaces.vivaldiDefaultID)
        #expect(BrowserWorkspaces.workspaceID(of: tabs[1], style: .vivaldi) == "1791027980791")
        // La date Chromium n'a rien ajouté au premier onglet.
        #expect(tabs[0].extraData.isEmpty)
    }

    @Test func pasUnFichierDeSession() {
        #expect(SessionFile.parse(Data("hello world".utf8)).isEmpty)
    }

    @Test func leFichierLePlusRecentEstChoisi() {
        #expect(SessionFile.timestamp(of: "Session_13436884803716912") == 13436884803716912)
        #expect(SessionFile.timestamp(of: "Session_x") == 0)
    }
}

// MARK: - Espaces d'Opera (Preferences)

struct BrowserWorkspacesTests {

    @Test func nomsOrdreEtIcones() {
        let json = #"""
        {"ui":{"workspaces":{"config":{
          "emoji_icons":{"0":"","1":"","2":"🧪"},
          "icons":{"0":"home-icon","1":"doc-icon","2":"day-icon"},
          "names":{"0":"Home","1":"Network-901","2":"A étudier"},
          "next_id":3,"order":["1","0","2"]}}}}
        """#
        let parsed = BrowserWorkspaces.parse(preferences: Data(json.utf8))
        #expect(parsed?.style == .opera)
        let spaces = parsed?.list ?? []
        #expect(spaces.map(\.id) == ["1", "0", "2"])
        #expect(spaces.map(\.name) == ["Network-901", "Home", "A étudier"])
        #expect(spaces[1].icon == "home-icon")
        #expect(spaces[0].emoji == nil)
        #expect(spaces[2].emoji == "🧪")
    }

    @Test func sansEspaces() {
        #expect(BrowserWorkspaces.parse(preferences: Data(#"{"ui":{}}"#.utf8)) == nil)
        #expect(BrowserWorkspaces.parse(preferences: Data("pas du json".utf8)) == nil)
        #expect(BrowserWorkspaces.parse(preferences: Data(#"{"vivaldi":{"workspaces":{"list":[]}}}"#.utf8)) == nil)
    }

    @Test func espacesDeVivaldi() {
        // Extrait réel : l'identifiant est écrit en nombre à virgule ; l'icône est un SVG (ignoré).
        let json = #"""
        {"vivaldi":{"workspaces":{"enabled":true,"list":[
          {"icon":"<svg></svg>","id":1791027980791.0,"name":"Network-901"},
          {"id":1791027999000,"title":"Sans nom de clé name","emoji":"🚀"},
          {"name":"Sans identifiant"}
        ]}}}
        """#
        let parsed = BrowserWorkspaces.parse(preferences: Data(json.utf8))
        #expect(parsed?.style == .vivaldi)
        let spaces = parsed?.list ?? []
        #expect(spaces.map(\.id) == [BrowserWorkspaces.vivaldiDefaultID, "1791027980791", "1791027999000"])
        #expect(spaces.map(\.name) == ["Espace par défaut", "Network-901", "Sans nom de clé name"])
        #expect(spaces[2].emoji == "🚀")
    }

    @Test func identifiantsNumeriques() {
        #expect(BrowserWorkspaces.workspaceKey(NSNumber(value: 1.791027980791e12)) == "1791027980791")
        #expect(BrowserWorkspaces.workspaceKey(NSNumber(value: 1791027980791 as Int64)) == "1791027980791")
        #expect(BrowserWorkspaces.workspaceKey("1.791027980791e+12") == "1791027980791")
        #expect(BrowserWorkspaces.workspaceKey(nil) == nil)
        #expect(BrowserWorkspaces.workspaceKey("abc") == nil)
    }

    @Test func symboles() {
        #expect(BrowserWorkspaces.symbol(for: "home-icon") == "house.fill")
        #expect(BrowserWorkspaces.symbol(for: "doc-icon") == "doc.fill")
        #expect(BrowserWorkspaces.symbol(for: "inconnu") == "square.stack.fill")
        #expect(BrowserWorkspaces.symbol(for: nil) == "square.stack.fill")
    }
}

// MARK: - Fusion AppleScript + fichier de session

struct TabMergerTests {

    private let workspaces = ProfileWorkspaces(style: .opera, list: [
        TabWorkspace(id: "0", name: "Home"),
        TabWorkspace(id: "1", name: "Network-901"),
        TabWorkspace(id: "2", name: "A étudier"),
    ])

    private func sessionWindow() -> SessionWindow {
        func tab(_ id: Int, _ index: Int, _ url: String, _ space: String) -> SessionTab {
            SessionTab(id: id, windowID: 100, index: index, url: url, title: url,
                       extraData: ["workspaces_state": Data(space.utf8)])
        }
        return SessionWindow(id: 100, selectedTabIndex: 0,
                             extraData: ["workspaces_state": Data("1".utf8)],
                             tabs: [tab(10, 0, "https://reddit.com/", "0"),
                                    tab(11, 1, "https://macbb.org/", "0"),
                                    tab(20, 0, "https://selfh.st/", "1"),
                                    tab(30, 0, "https://wifit3/", "2")])
    }

    /// Ce qu'AppleScript renvoie pour Opera : seulement le premier espace (+ un onglet tout neuf).
    private func live() -> [OpenWindow] {
        TabSnapshot.windows(browserID: "opera", windowIDs: [100], modes: ["normal"],
                            urls: [["https://reddit.com/", "https://macbb.org/", "https://nouveau.fr/"]],
                            titles: [["Reddit", "MacBB", "Nouveau"]], activeIndexes: [1])
    }

    @Test func tousLesEspacesApparaissent() throws {
        let session = ProfileSession(profileName: "Default", windows: [sessionWindow()], workspaces: workspaces)
        let window = try #require(TabMerger.merge(live: live(), sessions: [session]).first)

        #expect(window.workspaces.count == 3)
        #expect(window.activeWorkspaceID == "1")
        let groups = window.tabGroups
        #expect(groups.map { $0.workspace?.name } == ["Home", "Network-901", "A étudier"])
        #expect(groups.first { $0.isActive }?.workspace?.id == "1")
        // L'onglet tout neuf (pas encore écrit dans la session) rejoint l'espace lu par AppleScript.
        #expect(groups[0].tabs.map(\.url) == ["https://reddit.com/", "https://macbb.org/", "https://nouveau.fr/"])
        // L'onglet actif est celui de l'espace affiché.
        #expect(window.activeTab?.url == "https://selfh.st/")
    }

    @Test func leProfilNApparaitQuAvecPlusieursProfils() throws {
        let plain = SessionWindow(id: 100, tabs: [SessionTab(id: 1, windowID: 100, url: "https://reddit.com/")])
        let one = [ProfileSession(profileName: "Travail", windows: [plain], workspaces: nil)]
        let two = one + [ProfileSession(profileName: "Perso", windows: [], workspaces: nil)]

        #expect(try #require(TabMerger.merge(live: live(), sessions: one).first).profileName == nil)
        let merged = try #require(TabMerger.merge(live: live(), sessions: two).first)
        #expect(merged.profileName == "Travail")
        // Sans espaces, les onglets restent ceux d'AppleScript (plus à jour).
        #expect(merged.tabs.count == 3)
        #expect(merged.workspaces.isEmpty)
    }

    @Test func fenetreInconnueDuFichierInchangee() {
        let session = ProfileSession(profileName: "Default", windows: [], workspaces: workspaces)
        #expect(TabMerger.merge(live: live(), sessions: [session]) == live())
    }

    // Vivaldi : AppleScript voit tous les onglets, le fichier dit dans quel espace ils sont.

    private let vivaldiSpaces = ProfileWorkspaces(style: .vivaldi, list: [
        TabWorkspace(id: BrowserWorkspaces.vivaldiDefaultID, name: "Espace par défaut"),
        TabWorkspace(id: "1791027980791", name: "Network-901"),
    ])

    private func vivaldiSession(urls: [String], spaces: [String?]) -> SessionWindow {
        let tabs = zip(urls, spaces).enumerated().map { offset, pair in
            SessionTab(id: offset + 1, windowID: 7, index: offset, url: pair.0, title: pair.0,
                       extraData: pair.1.map {
                           [BrowserWorkspaces.vivaldiExtDataKey: Data(#"{"workspaceId":\#($0)}"#.utf8)]
                       } ?? [:])
        }
        return SessionWindow(id: 7, tabs: tabs)
    }

    private func vivaldiLive(_ urls: [String], active: Int) -> [OpenWindow] {
        TabSnapshot.windows(browserID: "vivaldi", windowIDs: [7], modes: ["normal"],
                            urls: [urls], titles: [urls], activeIndexes: [active])
    }

    @Test func vivaldiRangeLesOngletsParEspace() throws {
        let session = vivaldiSession(urls: ["https://reddit.com/", "http://192.168.1.45:3789/", "http://192.168.1.45:3456/login"],
                                     spaces: [nil, "1.791027980791e+12", "1.791027980791e+12"])
        // L'URL du 3e onglet a changé depuis l'écriture du fichier : l'ordre suffit à le reconnaître.
        let live = vivaldiLive(["https://reddit.com/", "http://192.168.1.45:3789/", "http://192.168.1.45:3456/containers"], active: 2)
        let window = try #require(TabMerger.merge(live: live,
                                                  sessions: [ProfileSession(profileName: "Travail", windows: [session], workspaces: vivaldiSpaces)]).first)

        #expect(window.tabs.map(\.workspaceID) == [BrowserWorkspaces.vivaldiDefaultID, "1791027980791", "1791027980791"])
        #expect(window.activeWorkspaceID == "1791027980791")
        #expect(window.tabGroups.map { $0.workspace?.name } == ["Espace par défaut", "Network-901"])
        #expect(window.tabs[2].url.hasSuffix("/containers"))
    }

    @Test func vivaldiSansEspaceUtilisePasDIntertitres() throws {
        let session = vivaldiSession(urls: ["https://a.fr/", "https://b.fr/"], spaces: [nil, nil])
        let live = vivaldiLive(["https://a.fr/", "https://b.fr/"], active: 1)
        let window = try #require(TabMerger.merge(live: live,
                                                  sessions: [ProfileSession(profileName: "Travail", windows: [session], workspaces: vivaldiSpaces)]).first)
        #expect(window.workspaces.isEmpty)
        #expect(window.tabs.allSatisfy { $0.workspaceID == nil })
    }

    @Test func vivaldiOngletNeufRejointLEspaceAffiche() throws {
        let session = vivaldiSession(urls: ["https://a.fr/", "https://b.fr/"], spaces: [nil, "1791027980791"])
        let live = vivaldiLive(["https://a.fr/", "https://b.fr/", "https://nouveau.fr/"], active: 2)
        let window = try #require(TabMerger.merge(live: live,
                                                  sessions: [ProfileSession(profileName: "Travail", windows: [session], workspaces: vivaldiSpaces)]).first)
        #expect(window.tabs.last?.workspaceID == "1791027980791")
    }

    @Test func rapportParEspace() {
        let session = ProfileSession(profileName: "Default", windows: [sessionWindow()], workspaces: workspaces)
        let browser = ChromiumBrowser.known.first { $0.id == "opera" }!
        let merged = TabMerger.merge(live: live(), sessions: [session])
        let text = TabSnapshot.report([BrowserTabs(browser: browser, result: .success(merged))], includePrivate: false)
        #expect(text.contains("Espace « Network-901 » (1 onglet, affiché)"))
        #expect(text.contains("Espace « A étudier » (1 onglet)"))
    }
}

// MARK: - Transfert

struct TransferPlannerTests {

    private func window(_ id: Int, isPrivate: Bool = false) -> OpenWindow {
        OpenWindow(id: "w\(id)", windowID: id, position: id, isPrivate: isPrivate, tabs: [])
    }

    private func tabs(_ urls: String...) -> [OpenTab] {
        urls.enumerated().map { OpenTab(id: "t\($0.offset)", index: $0.offset + 1, title: "", url: $0.element, isActive: false) }
    }

    @Test func uneFenetreParFenetreDOrigine() {
        let plan = TransferPlanner.plan(sources: [
            .init(browserID: "vivaldi", window: window(1), tabs: tabs("https://a.fr/", "https://b.fr/")),
            .init(browserID: "opera", window: window(2), tabs: tabs("https://c.fr/")),
        ], targetBrowserID: "brave", singleWindow: false, keepPrivate: true)
        #expect(plan.windows.map(\.urls) == [["https://a.fr/", "https://b.fr/"], ["https://c.fr/"]])
        #expect(plan.tabCount == 3)
    }

    @Test func toutDansUneSeuleFenetre() {
        let plan = TransferPlanner.plan(sources: [
            .init(browserID: "vivaldi", window: window(1), tabs: tabs("https://a.fr/")),
            .init(browserID: "opera", window: window(2), tabs: tabs("https://c.fr/")),
            .init(browserID: "opera", window: window(3, isPrivate: true), tabs: tabs("https://secret.fr/")),
        ], targetBrowserID: "brave", singleWindow: true, keepPrivate: true)
        // La fenêtre privée reste à part, même en mode « une seule fenêtre ».
        #expect(plan.windows == [TransferWindow(urls: ["https://a.fr/", "https://c.fr/"], isPrivate: false),
                                 TransferWindow(urls: ["https://secret.fr/"], isPrivate: true)])
    }

    @Test func navigationPriveeNonConservee() {
        let plan = TransferPlanner.plan(sources: [
            .init(browserID: "vivaldi", window: window(1, isPrivate: true), tabs: tabs("https://secret.fr/")),
        ], targetBrowserID: "brave", singleWindow: false, keepPrivate: false)
        #expect(plan.windows.first?.isPrivate == false)
    }

    @Test func pagesInternesEtMemeNavigateurIgnores() {
        let plan = TransferPlanner.plan(sources: [
            .init(browserID: "vivaldi", window: window(1), tabs: tabs("https://a.fr/", "vivaldi://settings", "chrome://newtab/")),
            .init(browserID: "brave", window: window(2), tabs: tabs("https://b.fr/")),
            .init(browserID: "opera", window: window(3), tabs: []),
        ], targetBrowserID: "brave", singleWindow: false, keepPrivate: true)
        #expect(plan.windows.map(\.urls) == [["https://a.fr/"]])
        #expect(plan.skippedInternal == 2)
        #expect(plan.skippedSameBrowser == 1)
    }

    @Test func seulesLesPagesWebSeTransferent() {
        #expect(TransferPlanner.isTransferable("https://a.fr/"))
        #expect(TransferPlanner.isTransferable("http://192.168.1.45:3456/containers"))
        #expect(!TransferPlanner.isTransferable("opera://startpage"))
        #expect(!TransferPlanner.isTransferable("about:blank"))
        #expect(!TransferPlanner.isTransferable(""))
    }
}

@MainActor
struct TabWriterTests {

    @Test func guillemetsNeutralises() {
        #expect(TabWriter.quoted(#"https://a.fr/?q="x"\y"#) == #""https://a.fr/?q=\"x\"\\y""#)
    }

    @Test func creationDeFenetre() {
        let script = TabWriter.createWindowScript(bundleID: "com.brave.Browser", isPrivate: false)
        #expect(script.contains(#"tell application id "com.brave.Browser""#))
        #expect(script.contains("set w to make new window\n"))
        #expect(script.contains("return (id of w) as text"))
    }

    @Test func creationDeFenetrePrivee() {
        let script = TabWriter.createWindowScript(bundleID: "x", isPrivate: true)
        #expect(script.contains(#"make new window with properties {mode:"incognito"}"#))
    }

    @Test func remplissageDeLaFenetre() {
        let script = TabWriter.fillWindowScript(bundleID: "x", windowID: 42, urls: ["https://a.fr/", "https://b.fr/"])
        #expect(script.contains("set w to window id 42"))
        #expect(script.contains(#"set URL of active tab of w to "https://a.fr/""#))
        #expect(script.contains(#"make new tab at end of tabs of w with properties {URL:"https://b.fr/"}"#))
        #expect(TabWriter.fillWindowScript(bundleID: "x", windowID: 1, urls: []).isEmpty)
    }

    @Test func argumentsDeLigneDeCommande() {
        #expect(TabWriter.commandLineArguments(for: TransferWindow(urls: ["https://a.fr/", "https://b.fr/"], isPrivate: false))
                == ["--new-window", "https://a.fr/", "https://b.fr/"])
        #expect(TabWriter.commandLineArguments(for: TransferWindow(urls: ["https://a.fr/"], isPrivate: true))
                == ["--incognito", "https://a.fr/"])
    }
}
