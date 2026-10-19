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

    /// Comment une fenêtre a été ouverte (pour le bilan et les tests).
    enum Method: Equatable {
        case appleScript
        /// Le navigateur refuse de créer une fenêtre par AppleScript (Opera) : ligne de commande.
        case commandLine
    }

    /// Navigateurs dont on sait déjà qu'ils refusent `make new window` : inutile de réessayer.
    private static var noWindowCreation: Set<String> = []

    /// Étape 1 : créer une fenêtre vide et renvoyer son identifiant.
    static func createWindowScript(bundleID: String, isPrivate: Bool) -> String {
        let properties = isPrivate ? " with properties {mode:\"incognito\"}" : ""
        return """
        tell application id \(quoted(bundleID))
            set w to make new window\(properties)
            return (id of w) as text
        end tell
        """
    }

    /// Étape 2 : remplir la fenêtre créée, la première URL au premier plan.
    static func fillWindowScript(bundleID: String, windowID: Int, urls: [String]) -> String {
        guard let first = urls.first else { return "" }
        var lines = [
            "tell application id \(quoted(bundleID))",
            "    set w to window id \(windowID)",
            "    set URL of active tab of w to \(quoted(first))",
        ]
        for url in urls.dropFirst() {
            lines.append("    make new tab at end of tabs of w with properties {URL:\(quoted(url))}")
        }
        lines.append("    set active tab index of w to 1")
        lines.append("end tell")
        return lines.joined(separator: "\n")
    }

    /// Arguments de lancement Chromium : une nouvelle fenêtre (privée ou non) avec ces URL.
    /// Si le navigateur est déjà ouvert, l'instance lancée les lui transmet puis se ferme.
    static func commandLineArguments(for window: TransferWindow) -> [String] {
        [window.isPrivate ? "--incognito" : "--new-window"] + window.urls
    }

    /// Chaîne AppleScript : guillemets et barres obliques inverses neutralisés.
    static func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Ouvre une fenêtre avec ses onglets : par AppleScript si le navigateur sait créer une fenêtre,
    /// sinon en ligne de commande. Une fois la fenêtre créée, une erreur n'entraîne pas de second essai
    /// (on ne veut pas de fenêtre en double).
    static func open(_ window: TransferWindow, in browser: ChromiumBrowser) async -> Result<Method, TabReadError> {
        guard !window.urls.isEmpty else { return .success(.appleScript) }

        if !noWindowCreation.contains(browser.bundleID) {
            switch run(createWindowScript(bundleID: browser.bundleID, isPrivate: window.isPrivate)) {
            case .success(let descriptor):
                // Renvoyé en texte : les identifiants Chromium dépassent souvent la taille d'un entier AppleScript.
                guard let windowID = descriptor.stringValue.flatMap({ Int($0) }) else {
                    return .failure(.script(code: 0, message: "Identifiant de fenêtre illisible"))
                }
                return run(fillWindowScript(bundleID: browser.bundleID, windowID: windowID, urls: window.urls))
                    .map { _ in .appleScript }
            case .failure(let error) where error == .permissionDenied:
                return .failure(error)
            case .failure:
                // Opera : « Le gestionnaire AppleEvent a échoué » (-10000) sur make new window.
                noWindowCreation.insert(browser.bundleID)
            }
        }
        return await openWithCommandLine(window, in: browser)
    }

    private static func openWithCommandLine(_ window: TransferWindow, in browser: ChromiumBrowser) async -> Result<Method, TabReadError> {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) else {
            return .failure(.notRunning)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = commandLineArguments(for: window)
        // Équivalent de « open -n » : sans cela, macOS se contente d'activer l'instance ouverte
        // et les arguments sont perdus.
        configuration.createsNewApplicationInstance = true
        configuration.activates = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            // Laisse l'instance de passage transmettre les URL à la fenêtre principale.
            try? await Task.sleep(for: .seconds(1))
            return .success(.commandLine)
        } catch {
            return .failure(.script(code: 0, message: "Lancement impossible : \(error.localizedDescription)"))
        }
    }

    private static func run(_ source: String) -> Result<NSAppleEventDescriptor, TabReadError> {
        guard let script = NSAppleScript(source: source) else {
            return .failure(.script(code: 0, message: "Script AppleScript invalide"))
        }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "erreur inconnue"
            return .failure(TabReader.error(code: code, message: message))
        }
        return .success(descriptor)
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
