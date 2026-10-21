import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Ferry : lit les onglets ouverts de tous les navigateurs et fait passer ceux qu'on coche dans un autre.
@MainActor
@Observable
final class FerryViewModel {

    enum Phase: Equatable {
        case idle, reading, done
    }

    // MARK: État observé par la vue

    private(set) var phase: Phase = .idle
    private(set) var browsers: [BrowserTabs] = []
    private(set) var lastRead: Date?
    private(set) var errorMessage: String?
    /// Navigateur en cours de lecture (la première fois, macOS affiche alors sa demande d'autorisation).
    private(set) var currentBrowserName = ""

    /// Icônes des onglets, par URL.
    private(set) var favicons: [String: NSImage] = [:]

    var showPrivate = false
    var searchText = ""

    /// Fenêtres repliées (par identifiant). Tout est déplié par défaut.
    var collapsedWindows: Set<String> = []

    private var faviconTask: Task<Void, Never>?

    // MARK: État du transfert

    /// Onglets cochés (identifiants `OpenTab.id`).
    private(set) var selection: Set<String> = []
    var targetBrowserID: String?
    /// Tout regrouper dans une seule fenêtre au lieu de recréer chaque fenêtre.
    var singleWindow = false
    /// Rouvrir en navigation privée les onglets qui l'étaient.
    var keepPrivate = true
    /// Fermer les onglets d'origine une fois leur copie ouverte (décoché par défaut : c'est destructif).
    var closeOriginals = false
    /// Recréer chaque espace de travail de la source dans sa propre fenêtre.
    var windowPerWorkspace = true
    var showTransferConfirmation = false
    private(set) var transferProgress: (done: Int, total: Int)?
    private(set) var transferSummary: TransferSummary?

    /// Navigateurs installés, cibles possibles d'un transfert (lancés au besoin).
    let installedBrowsers: [ChromiumBrowser] = ChromiumBrowser.known.filter {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil
    }

    // MARK: - Lecture

    func read() {
        guard phase != .reading else { return }
        phase = .reading
        errorMessage = nil
        faviconTask?.cancel()

        Task {
            var results: [BrowserTabs] = []
            for browser in TabReader.runningBrowsers() {
                currentBrowserName = browser.name
                // Laisse SwiftUI afficher le nom avant l'appel AppleScript (qui bloque le temps de la réponse).
                await Task.yield()
                // Lecture en direct, puis profils et espaces (Opera) tirés des fichiers de session.
                let result = TabReader.read(browser).map { live in
                    TabMerger.merge(live: live, sessions: TabSessions.load(for: browser))
                }
                results.append(BrowserTabs(browser: browser, result: result))
            }
            browsers = results
            // Les coches survivent à l'actualisation tant que l'onglet existe encore.
            let ids = Set(results.flatMap { $0.windows.flatMap { $0.tabs.map(\.id) } })
            selection.formIntersection(ids)
            lastRead = .now
            currentBrowserName = ""
            phase = .done
            loadFavicons()
        }
    }

    private func loadFavicons() {
        let jobs = browsers.map { browser in
            (urls: browser.windows.flatMap { $0.tabs.map(\.url) },
             databases: browser.browser.faviconDatabaseURLs())
        }
        faviconTask = Task {
            for job in jobs {
                let data = await TabFaviconLoader.load(for: job.urls, databases: job.databases)
                guard !Task.isCancelled else { return }
                for (url, bytes) in data where favicons[url] == nil {
                    if let image = NSImage(data: bytes) {
                        favicons[url] = image
                    }
                }
            }
        }
    }

    // MARK: - Ce qui est affiché

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Fenêtres affichées d'un navigateur : navigation privée masquée sauf demande, recherche appliquée.
    func visibleWindows(of browser: BrowserTabs) -> [OpenWindow] {
        browser.windows.compactMap { window in
            if window.isPrivate && !showPrivate { return nil }
            guard isSearching else { return window }
            let tabs = window.tabs.filter { $0.matches(searchText) }
            guard !tabs.isEmpty else { return nil }
            var filtered = window
            filtered.tabs = tabs
            return filtered
        }
    }

    /// Navigateurs à afficher : en recherche, ceux sans résultat disparaissent (les erreurs restent).
    var visibleBrowsers: [BrowserTabs] {
        browsers.filter { browser in
            browser.error != nil || !isSearching || !visibleWindows(of: browser).isEmpty
        }
    }

    func isExpanded(_ window: OpenWindow) -> Binding<Bool> {
        Binding(
            get: { [weak self] in
                guard let self else { return true }
                // Pendant une recherche, tout est déplié pour montrer les résultats.
                return self.isSearching || !self.collapsedWindows.contains(window.id)
            },
            set: { [weak self] expanded in
                guard let self else { return }
                if expanded {
                    self.collapsedWindows.remove(window.id)
                } else {
                    self.collapsedWindows.insert(window.id)
                }
            }
        )
    }

    func setAllExpanded(_ expanded: Bool) {
        collapsedWindows = expanded ? [] : Set(browsers.flatMap { $0.windows.map(\.id) })
    }

    // MARK: - Statistiques (hors recherche)

    private var countedWindows: [OpenWindow] {
        browsers.flatMap(\.windows).filter { showPrivate || !$0.isPrivate }
    }

    var browserCount: Int { browsers.filter { $0.error == nil }.count }
    var windowCount: Int { countedWindows.count }
    var tabCount: Int { countedWindows.reduce(0) { $0 + $1.tabs.count } }
    var hiddenPrivateCount: Int {
        showPrivate ? 0 : browsers.flatMap(\.windows).filter(\.isPrivate).count
    }
    var hasPermissionProblem: Bool {
        browsers.contains { $0.error == .permissionDenied }
    }

    // MARK: - Sélection

    enum CheckState {
        case none, some, all

        var symbol: String {
            switch self {
            case .none: "square"
            case .some: "minus.square.fill"
            case .all: "checkmark.square.fill"
            }
        }
    }

    func isSelected(_ tab: OpenTab) -> Bool {
        selection.contains(tab.id)
    }

    func toggle(_ tab: OpenTab) {
        if selection.contains(tab.id) {
            selection.remove(tab.id)
        } else {
            selection.insert(tab.id)
        }
    }

    /// État d'un ensemble d'onglets (fenêtre ou espace) : aucun, certains ou tous cochés.
    func state(of tabs: [OpenTab]) -> CheckState {
        let checked = tabs.filter { selection.contains($0.id) }.count
        if checked == 0 { return .none }
        return checked == tabs.count ? .all : .some
    }

    /// Coche tout l'ensemble, ou le décoche s'il l'était déjà entièrement.
    func toggle(_ tabs: [OpenTab]) {
        let ids = tabs.map(\.id)
        if state(of: tabs) == .all {
            selection.subtract(ids)
        } else {
            selection.formUnion(ids)
        }
    }

    /// Coche tous les onglets affichés (recherche et navigation privée prises en compte).
    func selectAllVisible() {
        for browser in visibleBrowsers {
            for window in visibleWindows(of: browser) {
                selection.formUnion(window.tabs.map(\.id))
            }
        }
    }

    func deselectAll() {
        selection.removeAll()
    }

    var selectedCount: Int { selection.count }

    // MARK: - Transfert

    var targetBrowser: ChromiumBrowser? {
        installedBrowsers.first { $0.id == targetBrowserID }
    }

    /// Ce que le transfert ferait avec les réglages actuels (sert aussi d'aperçu).
    var transferPlan: TransferPlan {
        guard let targetBrowserID else { return TransferPlan() }
        let sources = browsers.flatMap { browser in
            browser.windows.map { window in
                TransferPlanner.Source(browserID: browser.browser.id,
                                       window: window,
                                       tabs: window.tabs.filter { selection.contains($0.id) })
            }
        }
        return TransferPlanner.plan(sources: sources, targetBrowserID: targetBrowserID,
                                    singleWindow: singleWindow, windowPerWorkspace: windowPerWorkspace,
                                    keepPrivate: keepPrivate)
    }

    var isTransferring: Bool { transferProgress != nil }

    var canTransfer: Bool {
        phase == .done && !isTransferring && targetBrowser != nil && !transferPlan.isEmpty
    }

    func dismissTransferSummary() {
        transferSummary = nil
    }

    func transfer() {
        guard canTransfer, let target = targetBrowser else { return }
        let plan = transferPlan
        transferSummary = nil
        transferProgress = (0, plan.windows.count)

        Task {
            var summary = TransferSummary(browserName: target.name,
                                          skipped: plan.skippedInternal + plan.skippedSameBrowser)
            /// Onglets d'origine des fenêtres ouvertes avec succès : les seuls qu'on peut fermer.
            var transferred: [TabOrigin] = []

            if await TabWriter.launchIfNeeded(target) {
                windows: for (offset, window) in plan.windows.enumerated() {
                    await Task.yield()
                    switch await TabWriter.open(window, in: target) {
                    case .success:
                        summary.openedWindows += 1
                        summary.openedTabs += window.urls.count
                        transferred += window.origins
                    case .failure(let error):
                        summary.errors.append(error.message)
                        // Sans autorisation, inutile d'insister fenêtre après fenêtre.
                        if error == .permissionDenied { break windows }
                    }
                    transferProgress = (offset + 1, plan.windows.count)
                }
            } else {
                summary.errors.append("\(target.name) n'a pas pu être lancé.")
            }

            if closeOriginals, !transferred.isEmpty {
                summary.closing = closeTransferred(transferred, target: target)
            }

            transferProgress = nil
            transferSummary = summary
            if summary.openedTabs > 0 {
                selection.removeAll()
                read()
            }
        }
    }

    /// Ferme les originaux dont la copie est vraiment ouverte dans la cible (vérifié en la relisant).
    private func closeTransferred(_ origins: [TabOrigin], target: ChromiumBrowser) -> CloseSummary {
        let targetURLs: Set<String>
        if case .success(let windows) = TabReader.read(target) {
            targetURLs = Set(windows.flatMap { $0.tabs.map(\.url) })
        } else {
            targetURLs = []
        }
        let (closable, otherSpace) = TabWriter.closable(origins)
        let (confirmed, missing) = TabWriter.confirmed(closable, targetURLs: targetURLs)
        var closing = TabWriter.close(confirmed, browsers: browsers.map(\.browser))
        closing.unconfirmed += missing.count
        closing.otherSpace += otherSpace
        return closing
    }

    /// Onglets que la fermeture concernerait (pour la confirmation).
    var tabsToCloseCount: Int {
        transferPlan.windows.reduce(0) { $0 + $1.origins.filter(\.canClose).count }
    }

    /// Onglets copiés qui resteront ouverts (autres espaces d'Opera).
    var unclosableCount: Int {
        transferPlan.windows.reduce(0) { $0 + $1.origins.filter { !$0.canClose }.count }
    }

    /// Vrai si au moins une fenêtre cochée a des espaces de travail.
    var selectionHasWorkspaces: Bool {
        browsers.flatMap(\.windows).contains { window in
            !window.workspaces.isEmpty && window.tabs.contains { selection.contains($0.id) }
        }
    }

    /// Navigateurs d'où partiraient les onglets (pour la confirmation).
    var sourceBrowserNames: [String] {
        let ids = Set(transferPlan.windows.flatMap { $0.origins.map(\.browserID) })
        return browsers.map(\.browser).filter { ids.contains($0.id) }.map(\.name)
    }

    // MARK: - Actions

    /// Ouvre l'onglet dans le navigateur d'où il vient (pas forcément le navigateur par défaut).
    func open(_ tab: OpenTab, in browser: ChromiumBrowser) {
        guard let url = URL(string: tab.url) else { return }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func copyURL(_ tab: OpenTab) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tab.url, forType: .string)
    }

    /// Réglages Système › Confidentialité et sécurité › Automatisation
    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    func exportReport() {
        let text = TabSnapshot.report(browsers, includePrivate: showPrivate)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "ferry-onglets.txt"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Impossible d'écrire le rapport : \(error.localizedDescription)"
        }
    }
}
