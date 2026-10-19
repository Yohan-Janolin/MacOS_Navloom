import AppKit

/// Un profil de navigateur Chromium : un dossier contenant `Bookmarks` et `Favicons`.
nonisolated struct ChromiumProfile: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let directory: URL
    let browserName: String
    let bundleID: String

    var bookmarksURL: URL { directory.appending(path: "Bookmarks") }
    /// Chrome connecté à un compte Google y range les favoris enregistrés dans le compte.
    var accountBookmarksURL: URL { directory.appending(path: "AccountBookmarks") }
    var faviconsURL: URL { directory.appending(path: "Favicons") }
    var preferencesURL: URL { directory.appending(path: "Preferences") }

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
        .init(id: "chrome", name: "Chrome", bundleID: "com.google.Chrome", supportFolder: "Google/Chrome"),
        .init(id: "chromeBeta", name: "Chrome Beta", bundleID: "com.google.Chrome.beta", supportFolder: "Google/Chrome Beta"),
        .init(id: "chromeCanary", name: "Chrome Canary", bundleID: "com.google.Chrome.canary", supportFolder: "Google/Chrome Canary"),
        .init(id: "brave", name: "Brave", bundleID: "com.brave.Browser", supportFolder: "BraveSoftware/Brave-Browser"),
        .init(id: "braveBeta", name: "Brave Beta", bundleID: "com.brave.Browser.beta", supportFolder: "BraveSoftware/Brave-Browser-Beta"),
        .init(id: "braveNightly", name: "Brave Nightly", bundleID: "com.brave.Browser.nightly", supportFolder: "BraveSoftware/Brave-Browser-Nightly"),
        .init(id: "edge", name: "Edge", bundleID: "com.microsoft.edgemac", supportFolder: "Microsoft Edge"),
        .init(id: "edgeBeta", name: "Edge Beta", bundleID: "com.microsoft.edgemac.Beta", supportFolder: "Microsoft Edge Beta"),
        .init(id: "edgeDev", name: "Edge Dev", bundleID: "com.microsoft.edgemac.Dev", supportFolder: "Microsoft Edge Dev"),
        .init(id: "edgeCanary", name: "Edge Canary", bundleID: "com.microsoft.edgemac.Canary", supportFolder: "Microsoft Edge Canary"),
        .init(id: "opera", name: "Opera", bundleID: "com.operasoftware.Opera", supportFolder: "com.operasoftware.Opera"),
        .init(id: "operaDeveloper", name: "Opera Developer", bundleID: "com.operasoftware.OperaDeveloper", supportFolder: "com.operasoftware.OperaDeveloper"),
        .init(id: "operaGX", name: "Opera GX", bundleID: "com.operasoftware.OperaGX", supportFolder: "com.operasoftware.OperaGX"),
        .init(id: "operaAir", name: "Opera Air", bundleID: "com.operasoftware.OperaAir", supportFolder: "com.operasoftware.OperaAir"),
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
    
    /// Ce que Local State dit d'un profil (valeurs déjà nettoyées).
    nonisolated struct ProfileInfo: Equatable, Sendable {
        let name: String?
        let account: String?
    }

    private static func clean(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
    
    /// Ajoute le nom du dossier aux libellés qui se répètent, pour que chaque profil reste identifiable.
    static func disambiguated(labels: [String], folders: [String]) -> [String] {
        let counts = Dictionary(labels.map { ($0, 1) }, uniquingKeysWith: +)
        return zip(labels, folders).map { label, folder in
            counts[label, default: 0] > 1 ? "\(label) · \(folder)" : label
        }
    }

    /// Lit le contenu de `Local State` (séparé de la lecture du fichier pour pouvoir être testé).
    static func parseInfoCache(_ data: Data) -> [String: ProfileInfo] {
        guard let state = try? JSONDecoder().decode(LocalState.self, from: data),
              let cache = state.profile?.info_cache else { return [:] }
        return cache.mapValues { ProfileInfo(name: clean($0.name), account: clean($0.user_name)) }
    }

    /// Lit le nom de compte Vivaldi dans le contenu de `Preferences`.
    static func parseVivaldiAccount(_ data: Data) -> String? {
        guard let prefs = try? JSONDecoder().decode(Preferences.self, from: data) else { return nil }
        return clean(prefs.vivaldi?.vivaldi_account?.username)
    }

    /// Libellé affiché : « Nom (compte) », « Nom » seul, ou le nom du dossier en dernier recours.
    static func label(folder: String, info: ProfileInfo?, fallbackAccount: String? = nil) -> String {
        let profileName = info?.name ?? folder
        let account = info?.account ?? fallbackAccount
        if let account, account != profileName {
            return "\(profileName) (\(account))"
        }
        return profileName
    }

    private func infoCache() -> [String: ProfileInfo] {
        guard let data = try? Data(contentsOf: root.appending(path: "Local State")) else { return [:] }
        return Self.parseInfoCache(data)
    }

    private func vivaldiAccount(in directory: URL) -> String? {
        guard id.hasPrefix("vivaldi"),
              let data = try? Data(contentsOf: directory.appending(path: "Preferences")) else { return nil }
        return Self.parseVivaldiAccount(data)
    }

    /// Profils trouvés sur le disque : "Default" et "Profile 1", "Profile 2"…
    /// Seuls ceux qui contiennent un fichier Bookmarks (ou AccountBookmarks, pour Chrome) sont retournés.
    func profiles() -> [ChromiumProfile] {
        profiles(requiringBookmarks: true)
    }

    /// Tous les profils, même sans favoris : Ferry s'en sert pour lire les fichiers de session.
    func allProfiles() -> [ChromiumProfile] {
        profiles(requiringBookmarks: false)
    }

    private func profiles(requiringBookmarks: Bool) -> [ChromiumProfile] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }

        let cache = infoCache()

        let folders = names
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .sorted()
            .filter { folder in
                // Pour les outils de favoris, seuls les profils qui ont des favoris sont gardés.
                guard requiringBookmarks else { return true }
                let directory = root.appending(path: folder)
                return fm.fileExists(atPath: directory.appending(path: "Bookmarks").path)
                    || fm.fileExists(atPath: directory.appending(path: "AccountBookmarks").path)
            }

        let labels = folders.map { folder in
            Self.label(folder: folder,
                       info: cache[folder],
                       fallbackAccount: vivaldiAccount(in: root.appending(path: folder)))
        }

        return zip(folders, Self.disambiguated(labels: labels, folders: folders)).map { folder, label in
            ChromiumProfile(id: "\(id)/\(folder)", name: label,
                            directory: root.appending(path: folder),
                            browserName: name, bundleID: bundleID)
        }
    }

    /// Bases `Favicons` de tous les profils, y compris ceux sans favoris.
    /// Ferry s'en sert pour les icônes des onglets : AppleScript ne dit pas à quel profil
    /// appartient une fenêtre, donc on cherche l'icône dans chacun.
    func faviconDatabaseURLs() -> [URL] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        return names
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .sorted()
            .map { root.appending(path: $0).appending(path: "Favicons") }
            .filter { fm.fileExists(atPath: $0.path) }
    }

    /// Navigateurs connus ayant au moins un profil exploitable.
    static func installed() -> [ChromiumBrowser] {
        return known.filter { !$0.profiles().isEmpty }
    }
}
