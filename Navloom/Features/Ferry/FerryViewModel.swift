import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Ferry, lot 1 : lecture seule des onglets ouverts de tous les navigateurs.
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
