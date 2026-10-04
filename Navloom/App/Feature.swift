import SwiftUI

/// Une entrée de la barre latérale.
/// Ajouter un outil = ajouter un case ici + une vue dans Features/.
enum Feature: String, CaseIterable, Identifiable {
    case home
    case faviconSync
    case twins
    case backups
    case settings
    case about

    var id: String { rawValue }

    /// Accueil et outils, en haut de la barre latérale.
    static let tools: [Feature] = [.home, .faviconSync, .twins]

    /// Entrées fixées en bas, sous un séparateur.
    static let footer: [Feature] = [.backups, .settings, .about]

    var title: String {
        switch self {
        case .home: "Accueil"
        case .faviconSync: "FaviconSync"
        case .twins: "Twins"
        case .backups: "Sauvegardes"
        case .settings: "Paramètres"
        case .about: "À propos"
        }
    }

    /// Nom d'un symbole SF Symbols (l'icône système d'Apple)
    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .faviconSync: "star.fill"
        case .twins: "square.on.square"
        case .backups: "clock.arrow.circlepath"
        case .settings: "gearshape.fill"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .home: Brand.gold
        case .faviconSync: Brand.coral
        case .twins: Brand.sky
        case .backups: Brand.teal
        case .settings: Brand.violet
        case .about: Brand.pink
        }
    }
}
