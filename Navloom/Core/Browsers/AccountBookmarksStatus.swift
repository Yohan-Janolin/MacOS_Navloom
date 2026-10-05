import Foundation

/// Chrome affiche-t-il actuellement les favoris du compte Google (fichier `AccountBookmarks`) ?
///
/// Désactiver l'option « Favoris » dans « Dans votre compte Google » masque ces favoris dans Chrome,
/// mais le fichier reste sur le disque. Sans cette vérification, Navloom montrerait des favoris
/// que Chrome n'affiche plus, donc impossibles à retrouver pour les supprimer à la main.
///
/// Ce qui a été relevé sur Chrome stable : option activée, la clé `sync.bookmarks` n'existe pas dans
/// `Preferences` ; une fois l'option basculée, Chrome l'écrit (`true` activée, `false` désactivée).
/// Seul un `false` explicite compte donc comme « désactivée ». Chemin exact de la clé non relevé :
/// on la cherche à n'importe quel niveau du fichier.
nonisolated enum AccountBookmarksStatus: Equatable, Sendable {
    case enabled
    case disabled
    /// Aucune trace de la clé : on lit le fichier, comme avant que l'option soit basculée.
    case unknown

    static func detect(for profile: ChromiumProfile) -> AccountBookmarksStatus {
        guard let data = try? Data(contentsOf: profile.preferencesURL) else { return .unknown }
        return parse(data)
    }

    /// Séparé de `detect` pour pouvoir tester sans fichier sur le disque.
    static func parse(_ data: Data) -> AccountBookmarksStatus {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return .unknown }

        var values: [Bool] = []
        collect(root, into: &values)

        if values.contains(true) { return .enabled }
        return values.isEmpty ? .unknown : .disabled
    }

    /// Cherche toutes les clés « sync.bookmarks » (une par compte connecté), où qu'elles soient.
    private static func collect(_ node: Any, into values: inout [Bool]) {
        if let dictionary = node as? [String: Any] {
            for (key, value) in dictionary {
                if key == "sync.bookmarks", let flag = value as? Bool {
                    values.append(flag)
                } else {
                    collect(value, into: &values)
                }
            }
        } else if let array = node as? [Any] {
            for item in array { collect(item, into: &values) }
        }
    }
}
