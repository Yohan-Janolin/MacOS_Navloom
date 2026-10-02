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
        .init(id: "chromium", name: "Chromium", bundleID: "org.chromium.Chromium", supportFolder: "Chromium"),
        .init(id: "vivaldi", name: "Vivaldi", bundleID: "com.vivaldi.Vivaldi", supportFolder: "Vivaldi"),
        .init(id: "vivaldiSnapshot", name: "Vivaldi Snapshot", bundleID: "com.vivaldi.Vivaldi.snapshot", supportFolder: "Vivaldi Snapshot"),
        .init(id: "chrome", name: "Google Chrome", bundleID: "com.google.Chrome", supportFolder: "Google/Chrome"),
        .init(id: "chromeBeta", name: "Chrome Beta", bundleID: "com.google.Chrome.beta", supportFolder: "Google/Chrome Beta"),
        .init(id: "chromeCanary", name: "Chrome Canary", bundleID: "com.google.Chrome.canary", supportFolder: "Google/Chrome Canary"),
        .init(id: "brave", name: "Brave", bundleID: "com.brave.Browser", supportFolder: "BraveSoftware/Brave-Browser"),
        .init(id: "braveBeta", name: "Brave Beta", bundleID: "com.brave.Browser.beta", supportFolder: "BraveSoftware/Brave-Browser-Beta"),
        .init(id: "braveNightly", name: "Brave Nightly", bundleID: "com.brave.Browser.nightly", supportFolder: "BraveSoftware/Brave-Browser-Nightly"),
        .init(id: "edge", name: "Microsoft Edge", bundleID: "com.microsoft.edgemac", supportFolder: "Microsoft Edge"),
        .init(id: "edgeBeta", name: "Edge Beta", bundleID: "com.microsoft.edgemac.Beta", supportFolder: "Microsoft Edge Beta"),
        .init(id: "edgeDev", name: "Edge Dev", bundleID: "com.microsoft.edgemac.Dev", supportFolder: "Microsoft Edge Dev"),
        .init(id: "edgeCanary", name: "Edge Canary", bundleID: "com.microsoft.edgemac.Canary", supportFolder: "Microsoft Edge Canary"),
        .init(id: "opera", name: "Opera", bundleID: "com.operasoftware.Opera", supportFolder: "com.operasoftware.Opera"),
    ]

    private var root: URL {
        URL.applicationSupportDirectory.appending(path: supportFolder)
    }
    
    /// Extrait de `Local State` : nom du profil et compte associé (s'il y en a un).
    private nonisolated struct LocalState: Decodable {
        struct Profile: Decodable {
            struct Info: Decodable {
                let name: String?
                let user_name: String?
            }
            let info_cache: [String: Info]?
        }
        let profile: Profile?
    }

    /// Extrait de `Preferences` : seul Vivaldi y range le nom de son compte.
    private nonisolated struct Preferences: Decodable {
        struct Vivaldi: Decodable {
            struct Account: Decodable { let username: String? }
            let vivaldi_account: Account?
        }
        let vivaldi: Vivaldi?
    }

    private static func clean(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private func infoCache() -> [String: LocalState.Profile.Info] {
        guard let data = try? Data(contentsOf: root.appending(path: "Local State")),
              let state = try? JSONDecoder().decode(LocalState.self, from: data) else { return [:] }
        return state.profile?.info_cache ?? [:]
    }

    private func vivaldiAccount(in directory: URL) -> String? {
        guard id.hasPrefix("vivaldi"),
              let data = try? Data(contentsOf: directory.appending(path: "Preferences")),
              let prefs = try? JSONDecoder().decode(Preferences.self, from: data) else { return nil }
        return Self.clean(prefs.vivaldi?.vivaldi_account?.username)
    }

    /// Profils trouvés sur le disque : "Default" et "Profile 1", "Profile 2"…
    /// Seuls ceux qui contiennent un fichier Bookmarks sont retournés.
    func profiles() -> [ChromiumProfile] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }

        let cache = infoCache()

        return names
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .sorted()
            .map { folder in
                let directory = root.appending(path: folder)
                let info = cache[folder]
                let profileName = Self.clean(info?.name) ?? folder
                let account = Self.clean(info?.user_name) ?? vivaldiAccount(in: directory)

                var label = profileName
                if let account, account != profileName {
                    label += " (\(account))"
                }
                return ChromiumProfile(id: "\(id)/\(folder)", name: label, directory: directory,
                                       browserName: name, bundleID: bundleID)
            }
            .filter { fm.fileExists(atPath: $0.bookmarksURL.path) }
    }

    /// Navigateurs connus ayant au moins un profil exploitable.
    static func installed() -> [ChromiumBrowser] {
        known.filter { !$0.profiles().isEmpty }
    }
}
