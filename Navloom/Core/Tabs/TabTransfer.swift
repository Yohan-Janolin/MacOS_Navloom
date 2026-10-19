import AppKit

/// Une fenêtre à recréer dans le navigateur cible.
nonisolated struct TransferWindow: Equatable, Sendable {
    let urls: [String]
    /// Rouvrir en navigation privée (la fenêtre d'origine l'était).
    let isPrivate: Bool
}

/// Ce qui sera transféré : fenêtres à créer et onglets laissés de côté.
nonisolated struct TransferPlan: Equatable, Sendable {
    var windows: [TransferWindow] = []
    /// Pages internes (chrome://, vivaldi://…) : propres à chaque navigateur, elles ne se transfèrent pas.
    var skippedInternal = 0
    /// Onglets qui sont déjà dans le navigateur cible.
    var skippedSameBrowser = 0

    var tabCount: Int { windows.reduce(0) { $0 + $1.urls.count } }
    var isEmpty: Bool { windows.isEmpty }
}

/// Bilan d'un transfert.
nonisolated struct TransferSummary: Equatable, Sendable {
    let browserName: String
    var openedTabs = 0
    var openedWindows = 0
    var skipped = 0
    var errors: [String] = []
}

/// Prépare le transfert : quelles fenêtres créer, avec quels onglets. Aucun accès aux navigateurs.
nonisolated enum TransferPlanner {

    /// Une source : les onglets cochés d'une fenêtre d'un navigateur.
    struct Source: Sendable {
        let browserID: String
        let window: OpenWindow
        let tabs: [OpenTab]
    }

    /// Seules les pages web passent d'un navigateur à l'autre.
    static func isTransferable(_ url: String) -> Bool {
        guard let scheme = URL(string: url)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// - Parameters:
    ///   - singleWindow: tout regrouper dans une seule fenêtre (une seconde, privée, si besoin).
    ///   - keepPrivate: rouvrir en navigation privée les onglets qui l'étaient.
    static func plan(sources: [Source], targetBrowserID: String,
                     singleWindow: Bool, keepPrivate: Bool) -> TransferPlan {
        var plan = TransferPlan()
        var windows: [(urls: [String], isPrivate: Bool)] = []

        for source in sources where !source.tabs.isEmpty {
            if source.browserID == targetBrowserID {
                plan.skippedSameBrowser += source.tabs.count
                continue
            }
            let urls = source.tabs.map(\.url).filter(isTransferable)
            plan.skippedInternal += source.tabs.count - urls.count
            guard !urls.isEmpty else { continue }

            let isPrivate = keepPrivate && source.window.isPrivate
            if singleWindow, let index = windows.firstIndex(where: { $0.isPrivate == isPrivate }) {
                windows[index].urls += urls
            } else {
                windows.append((urls, isPrivate))
            }
        }

        plan.windows = windows.map { TransferWindow(urls: $0.urls, isPrivate: $0.isPrivate) }
        return plan
    }
}

/// Ouvre des fenêtres et des onglets dans un navigateur Chromium par AppleScript.
@MainActor
enum TabWriter {

    /// Script qui crée une fenêtre et y ouvre les URL dans l'ordre, la première au premier plan.
    static func script(bundleID: String, window: TransferWindow) -> String {
        guard let first = window.urls.first else { return "" }
        let properties = window.isPrivate ? " with properties {mode:\"incognito\"}" : ""
        var lines = [
            "tell application id \(quoted(bundleID))",
            "    set w to make new window\(properties)",
            "    set URL of active tab of w to \(quoted(first))",
        ]
        for url in window.urls.dropFirst() {
            lines.append("    make new tab at end of tabs of w with properties {URL:\(quoted(url))}")
        }
        lines.append("    set active tab index of w to 1")
        lines.append("end tell")
        return lines.joined(separator: "\n")
    }

    /// Chaîne AppleScript : guillemets et barres obliques inverses neutralisés.
    static func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func open(_ window: TransferWindow, in browser: ChromiumBrowser) -> Result<Void, TabReadError> {
        guard let script = NSAppleScript(source: script(bundleID: browser.bundleID, window: window)) else {
            return .failure(.script(code: 0, message: "Script AppleScript invalide"))
        }
        var errorInfo: NSDictionary?
        _ = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "erreur inconnue"
            return .failure(TabReader.error(code: code, message: message))
        }
        return .success(())
    }

    /// Lance le navigateur s'il est fermé et attend qu'il soit prêt (15 secondes au plus).
    static func launchIfNeeded(_ browser: ChromiumBrowser) async -> Bool {
        if TabReader.isRunning(browser) { return true }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) else {
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)

        for _ in 0..<30 {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).first,
               app.isFinishedLaunching {
                // Laisse le navigateur ouvrir sa première fenêtre avant de lui parler.
                try? await Task.sleep(for: .seconds(1.5))
                return true
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }
}
