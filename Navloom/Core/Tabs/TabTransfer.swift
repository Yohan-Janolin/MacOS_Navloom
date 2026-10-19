import AppKit

/// Un onglet d'origine, à fermer une fois sa copie ouverte dans la cible.
nonisolated struct TabOrigin: Hashable, Sendable {
    let browserID: String
    let windowID: Int
    /// Identifiant de l'onglet dans son navigateur (nil s'il n'a pas pu être lu).
    let tabID: Int?
    /// URL au moment de la lecture : l'onglet n'est fermé que s'il affiche encore cette page.
    let url: String
}

/// Une fenêtre à recréer dans le navigateur cible.
nonisolated struct TransferWindow: Equatable, Sendable {
    let urls: [String]
    /// Rouvrir en navigation privée (la fenêtre d'origine l'était).
    let isPrivate: Bool
    /// Onglets d'origine de ces URL (pour les fermer après le transfert).
    var origins: [TabOrigin] = []
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
    /// Fermeture des onglets d'origine (nil si elle n'était pas demandée).
    var closing: CloseSummary?
}

/// Bilan de la fermeture des onglets d'origine.
nonisolated struct CloseSummary: Equatable, Sendable {
    var closed = 0
    /// L'onglet affichait une autre page qu'à la lecture : laissé ouvert par prudence.
    var changed = 0
    /// Onglet introuvable ou refusé par le navigateur (espace d'Opera non affiché, onglet déjà fermé…).
    var failed = 0
    /// La copie n'a pas été retrouvée dans la cible après le transfert : original gardé par sécurité.
    var unconfirmed = 0

    var notClosed: Int { changed + failed + unconfirmed }

    static func + (lhs: CloseSummary, rhs: CloseSummary) -> CloseSummary {
        CloseSummary(closed: lhs.closed + rhs.closed,
                     changed: lhs.changed + rhs.changed,
                     failed: lhs.failed + rhs.failed,
                     unconfirmed: lhs.unconfirmed + rhs.unconfirmed)
    }
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
        var windows: [(urls: [String], isPrivate: Bool, origins: [TabOrigin])] = []

        for source in sources where !source.tabs.isEmpty {
            if source.browserID == targetBrowserID {
                plan.skippedSameBrowser += source.tabs.count
                continue
            }
            let tabs = source.tabs.filter { isTransferable($0.url) }
            plan.skippedInternal += source.tabs.count - tabs.count
            guard !tabs.isEmpty else { continue }

            let urls = tabs.map(\.url)
            let origins = tabs.map { tab in
                TabOrigin(browserID: source.browserID, windowID: source.window.windowID,
                          tabID: tab.tabID, url: tab.url)
            }
            let isPrivate = keepPrivate && source.window.isPrivate
            if singleWindow, let index = windows.firstIndex(where: { $0.isPrivate == isPrivate }) {
                windows[index].urls += urls
                windows[index].origins += origins
            } else {
                windows.append((urls, isPrivate, origins))
            }
        }

        plan.windows = windows.map { TransferWindow(urls: $0.urls, isPrivate: $0.isPrivate, origins: $0.origins) }
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

    // MARK: - Fermeture des onglets d'origine

    /// Script qui ferme les onglets donnés d'un navigateur, chacun seulement s'il affiche encore
    /// la même page. Renvoie « fermés,changés,échecs ».
    static func closeScript(bundleID: String, origins: [TabOrigin]) -> String {
        var lines = [
            "tell application id \(quoted(bundleID))",
            "    set closedCount to 0",
            "    set changedCount to 0",
            "    set failedCount to 0",
        ]
        for origin in origins {
            guard let tabID = origin.tabID else { continue }
            lines += [
                "    try",
                "        set t to tab id \(tabID) of window id \(origin.windowID)",
                "        if (URL of t) is \(quoted(origin.url)) then",
                "            close t",
                "            set closedCount to closedCount + 1",
                "        else",
                "            set changedCount to changedCount + 1",
                "        end if",
                "    on error",
                "        set failedCount to failedCount + 1",
                "    end try",
            ]
        }
        lines.append("    return (closedCount as text) & \",\" & (changedCount as text) & \",\" & (failedCount as text)")
        lines.append("end tell")
        return lines.joined(separator: "\n")
    }

    /// Lit « fermés,changés,échecs ».
    static func parseCloseResult(_ text: String?) -> CloseSummary? {
        let parts = (text ?? "").split(separator: ",").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return CloseSummary(closed: parts[0], changed: parts[1], failed: parts[2])
    }

    /// Sépare les onglets d'origine dont la copie est bien ouverte dans la cible des autres.
    static func confirmed(_ origins: [TabOrigin], targetURLs: Set<String>) -> (confirmed: [TabOrigin], missing: [TabOrigin]) {
        var confirmed: [TabOrigin] = []
        var missing: [TabOrigin] = []
        for origin in origins {
            if targetURLs.contains(origin.url) { confirmed.append(origin) } else { missing.append(origin) }
        }
        return (confirmed, missing)
    }

    /// Ferme les onglets d'origine, navigateur par navigateur.
    static func close(_ origins: [TabOrigin], browsers: [ChromiumBrowser]) -> CloseSummary {
        var total = CloseSummary()
        for (browserID, group) in Dictionary(grouping: origins, by: \.browserID) {
            let withID = group.filter { $0.tabID != nil }
            total.failed += group.count - withID.count
            guard !withID.isEmpty, let browser = browsers.first(where: { $0.id == browserID }) else {
                total.failed += withID.count
                continue
            }
            switch run(closeScript(bundleID: browser.bundleID, origins: withID)) {
            case .success(let descriptor):
                total = total + (parseCloseResult(descriptor.stringValue) ?? CloseSummary(failed: withID.count))
            case .failure:
                total.failed += withID.count
            }
        }
        return total
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
