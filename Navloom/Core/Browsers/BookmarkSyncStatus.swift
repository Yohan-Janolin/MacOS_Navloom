import Foundation

/// Le navigateur synchronise-t-il les favoris avec un compte ?
///
/// Si oui, modifier le fichier Bookmarks navigateur fermé ne tient pas : au lancement suivant,
/// la synchro remet les favoris supprimés (observé avec Vivaldi).
nonisolated enum BookmarkSyncStatus: Equatable, Sendable {
    case enabled
    case disabled
    /// Navloom ne sait pas lire cet état pour ce navigateur.
    case unknown

    /// Navigateurs dont les réglages ont été relevés sur un profil où la synchro est réellement
    /// activée, ET sur un profil sans compte : Vivaldi, Opera (et GX, Air, Developer), Brave et Edge
    /// (toutes variantes) y écrivent les mêmes clés `sync.*`. Chromium n'a pas de synchro.
    private static let verifiedBrowsers: Set<String> = [
        "chromium",
        "vivaldi", "vivaldiSnapshot",
        "brave", "braveBeta", "braveNightly",
        "edge", "edgeBeta", "edgeDev", "edgeCanary",
        "opera", "operaGX", "operaAir", "operaDeveloper",
    ]

    /// Google Chrome fonctionne autrement : connecté à un compte, il range les favoris du compte dans
    /// un fichier à part (`AccountBookmarks`) et ne touche pas au fichier `Bookmarks` local
    /// (vérifié sur Chrome stable : un favori créé sans l'option reste après l'avoir activée puis
    /// désactivée). Seule la synchro complète, avec consentement, peut synchroniser `Bookmarks`.
    private static let chromeBrowsers: Set<String> = ["chrome", "chromeBeta", "chromeCanary"]

    /// Extrait de `Preferences` : les trois réglages qui décident si les favoris sont synchronisés.
    private nonisolated struct PreferencesFile: Decodable {
        struct Sync: Decodable {
            let has_setup_completed: Bool?
            let keep_everything_synced: Bool?
            let bookmarks: Bool?
        }
        struct Google: Decodable {
            struct Services: Decodable {
                let consented_to_sync: Bool?
            }
            let services: Services?
        }
        let sync: Sync?
        let google: Google?
    }

    static func detect(for profile: ChromiumProfile) -> BookmarkSyncStatus {
        let browserID = profile.id.split(separator: "/").first.map(String.init) ?? ""
        let isChrome = chromeBrowsers.contains(browserID)
        guard isChrome || verifiedBrowsers.contains(browserID),
              let data = try? Data(contentsOf: profile.preferencesURL) else {
            return .unknown
        }
        return isChrome ? parseChrome(data) : parse(data)
    }

    /// Séparé de `detect` pour pouvoir tester sans fichier sur le disque.
    static func parse(_ data: Data) -> BookmarkSyncStatus {
        guard let file = try? JSONDecoder().decode(PreferencesFile.self, from: data) else {
            return .unknown
        }
        // Pas de compte configuré : rien n'est synchronisé. Les cases par type de données
        // (bookmarks, apps…) existent par défaut même sans compte, elles ne prouvent rien.
        guard let sync = file.sync, sync.has_setup_completed == true else { return .disabled }
        // « Tout synchroniser » ou la case Favoris cochée.
        return sync.keep_everything_synced == true || sync.bookmarks == true ? .enabled : .disabled
    }

    /// Chrome : le fichier `Bookmarks` n'est synchronisé que si l'utilisateur a consenti à la synchro
    /// complète. Connecté simplement à un compte, les favoris du compte vont dans `AccountBookmarks`
    /// et le fichier local n'est pas concerné. La clé de consentement est celle de Chromium (Edge
    /// l'écrit aussi), mais son passage à `true` n'a pas été observé dans Chrome : dans ce cas, on
    /// bloque la suppression par précaution.
    static func parseChrome(_ data: Data) -> BookmarkSyncStatus {
        guard let file = try? JSONDecoder().decode(PreferencesFile.self, from: data) else {
            return .unknown
        }
        return file.google?.services?.consented_to_sync == true ? .enabled : .disabled
    }
}
