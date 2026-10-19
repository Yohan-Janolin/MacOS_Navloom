import AppKit

/// Lit les fenêtres et onglets ouverts d'un navigateur Chromium par AppleScript (Apple Events).
///
/// - Seuls les navigateurs **déjà ouverts** sont interrogés : un `tell application` lancerait
///   un navigateur fermé.
/// - La première fois, macOS demande à l'utilisateur d'autoriser Navloom à contrôler chaque
///   navigateur (Réglages Système › Confidentialité et sécurité › Automatisation). La phrase
///   affichée vient de la clé `NSAppleEventsUsageDescription` de l'Info.plist : sans elle,
///   macOS refuse sans rien demander.
/// - `NSAppleScript` doit être utilisé sur le thread principal, d'où `@MainActor`.
@MainActor
enum TabReader {

    /// Navigateurs connus actuellement ouverts, dans l'ordre de `ChromiumBrowser.known`.
    static func runningBrowsers() -> [ChromiumBrowser] {
        ChromiumBrowser.known.filter(isRunning)
    }

    static func isRunning(_ browser: ChromiumBrowser) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty
    }

    /// Lit toutes les fenêtres du navigateur, navigation privée comprise (le filtrage se fait à l'affichage).
    static func read(_ browser: ChromiumBrowser) -> Result<[OpenWindow], TabReadError> {
        guard isRunning(browser) else { return .failure(.notRunning) }

        switch run(source(bundleID: browser.bundleID, withModes: true)) {
        case .success(let descriptor):
            return .success(parse(descriptor, browserID: browser.id, hasModes: true))
        case .failure(let error) where error == .permissionDenied || error == .notRunning:
            return .failure(error)
        case .failure(let firstError):
            // Un navigateur qui n'exposerait pas « mode » : on réessaie sans (aucune fenêtre ne sera vue comme privée).
            switch run(source(bundleID: browser.bundleID, withModes: false)) {
            case .success(let descriptor):
                return .success(parse(descriptor, browserID: browser.id, hasModes: false))
            case .failure:
                return .failure(firstError)
            }
        }
    }

    // MARK: - Script

    /// Une seule requête par propriété (et non par onglet) : la lecture reste rapide même avec 200 onglets.
    static func source(bundleID: String, withModes: Bool) -> String {
        """
        tell application id "\(bundleID)"
            set winIDs to id of every window
            \(withModes ? "set winModes to mode of every window" : "set winModes to {}")
            set tabURLs to URL of every tab of every window
            set tabTitles to title of every tab of every window
            set activeIdx to active tab index of every window
            return {winIDs, winModes, tabURLs, tabTitles, activeIdx}
        end tell
        """
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
            return .failure(error(code: code, message: message))
        }
        return .success(descriptor)
    }

    /// Traduit les codes d'erreur Apple Events utiles.
    static func error(code: Int, message: String) -> TabReadError {
        switch code {
        case -1743, -1744:
            // errAEEventNotPermitted / errAEEventWouldRequireUserConsent
            .permissionDenied
        case -600, -609:
            // procNotFound / connectionInvalid : l'application n'est plus là
            .notRunning
        default:
            .script(code: code, message: message)
        }
    }

    // MARK: - Lecture du résultat

    private static func parse(_ descriptor: NSAppleEventDescriptor, browserID: String, hasModes: Bool) -> [OpenWindow] {
        let parts = items(of: descriptor)
        func part(_ index: Int) -> [NSAppleEventDescriptor] {
            index < parts.count ? items(of: parts[index]) : []
        }

        let windowIDs = part(0).map { integer($0) ?? 0 }
        let modes = hasModes ? part(1).map(string) : nil
        let urls = part(2).map { items(of: $0).map(string) }
        let titles = part(3).map { items(of: $0).map(string) }
        let activeIndexes = part(4).map(integer)

        return TabSnapshot.windows(browserID: browserID,
                                   windowIDs: windowIDs,
                                   modes: modes,
                                   urls: urls,
                                   titles: titles,
                                   activeIndexes: activeIndexes)
    }

    /// Éléments d'une liste AppleScript (numérotés à partir de 1).
    private static func items(of descriptor: NSAppleEventDescriptor) -> [NSAppleEventDescriptor] {
        let count = descriptor.numberOfItems
        guard count > 0 else { return [] }
        return (1...count).compactMap { descriptor.atIndex($0) }
    }

    private static func string(_ descriptor: NSAppleEventDescriptor) -> String? {
        isMissing(descriptor) ? nil : descriptor.stringValue
    }

    private static func integer(_ descriptor: NSAppleEventDescriptor) -> Int? {
        guard !isMissing(descriptor) else { return nil }
        if let text = descriptor.stringValue, let value = Int(text) { return value }
        return Int(descriptor.int32Value)
    }

    /// `missing value` d'AppleScript (une page sans titre, par exemple).
    private static func isMissing(_ descriptor: NSAppleEventDescriptor) -> Bool {
        let type = descriptor.descriptorType
        if type == fourCharCode("null") { return true }
        return type == fourCharCode("type") && descriptor.typeCodeValue == fourCharCode("msng")
    }

    /// Code à quatre lettres d'Apple Events (« msng » → 0x6D736E67).
    private static func fourCharCode(_ text: String) -> FourCharCode {
        text.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }
}
