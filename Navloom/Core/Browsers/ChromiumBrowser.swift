import AppKit

/// Un profil de navigateur Chromium : un dossier contenant `Bookmarks` et `Favicons`.
nonisolated struct ChromiumProfile: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let directory: URL
    let browserName: String
    let bundleID: String

    var bookmarksURL: URL { directory.appending(path: "Bookmarks") }
    var faviconsURL: URL { directory.appending(path: "Favicons") }

    /// Vrai si le navigateur est en cours d'exécution.
    var isBrowserRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}

/// Un navigateur basé sur Chromium, identifié par son dossier dans Application Support.
nonisolated struct ChromiumBrowser: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let bundleID: String
    /// Chemin relatif à ~/Library/Application Support
    let supportFolder: String

    static let known: [ChromiumBrowser] = [
        .init(id: "vivaldi", name: "Vivaldi", bundleID: "com.vivaldi.Vivaldi", supportFolder: "Vivaldi"),
        .init(id: "chrome", name: "Google Chrome", bundleID: "com.google.Chrome", supportFolder: "Google/Chrome"),
        .init(id: "brave", name: "Brave", bundleID: "com.brave.Browser", supportFolder: "BraveSoftware/Brave-Browser"),
        .init(id: "edge", name: "Microsoft Edge", bundleID: "com.microsoft.edgemac", supportFolder: "Microsoft Edge"),
    ]

    private var root: URL {
        URL.applicationSupportDirectory.appending(path: supportFolder)
    }

    /// Profils trouvés sur le disque : "Default" et "Profile 1", "Profile 2"…
    /// Seuls ceux qui contiennent un fichier Bookmarks sont retournés.
    func profiles() -> [ChromiumProfile] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }

        return names
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .sorted()
            .map {
                ChromiumProfile(id: "\(id)/\($0)", name: $0, directory: root.appending(path: $0),
                                browserName: name, bundleID: bundleID)
            }
            .filter { fm.fileExists(atPath: $0.bookmarksURL.path) }
    }

    /// Navigateurs connus ayant au moins un profil exploitable.
    static func installed() -> [ChromiumBrowser] {
        known.filter { !$0.profiles().isEmpty }
    }
}
