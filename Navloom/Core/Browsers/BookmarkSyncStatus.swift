//
//  BookmarkSyncStatus.swift
//  Navloom
//

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

    /// Navigateurs dont les réglages ont été relevés sur une vraie installation (Vivaldi, y compris
    /// Snapshot). Pour les autres, on ne prétend pas savoir : une clé différente donnerait un
    /// faux « désactivée ».
    private static let verifiedBrowsers = ["vivaldi"]

    /// Extrait de `Preferences` : les trois réglages qui décident si les favoris sont synchronisés.
    private nonisolated struct PreferencesFile: Decodable {
        struct Sync: Decodable {
            let has_setup_completed: Bool?
            let keep_everything_synced: Bool?
            let bookmarks: Bool?
        }
        let sync: Sync?
    }

    static func detect(for profile: ChromiumProfile) -> BookmarkSyncStatus {
        let browserID = profile.id.split(separator: "/").first.map(String.init) ?? ""
        guard verifiedBrowsers.contains(where: { browserID.hasPrefix($0) }),
              let data = try? Data(contentsOf: profile.preferencesURL) else {
            return .unknown
        }
        return parse(data)
    }

    /// Séparé de `detect` pour pouvoir tester sans fichier sur le disque.
    static func parse(_ data: Data) -> BookmarkSyncStatus {
        guard let file = try? JSONDecoder().decode(PreferencesFile.self, from: data) else {
            return .unknown
        }
        // Pas de compte configuré : rien n'est synchronisé.
        guard let sync = file.sync, sync.has_setup_completed == true else { return .disabled }
        // « Tout synchroniser » ou la case Favoris cochée.
        return sync.keep_everything_synced == true || sync.bookmarks == true ? .enabled : .disabled
    }
}
