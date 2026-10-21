import SwiftUI

/// Une entrée de la barre latérale.
/// Ajouter un outil = ajouter un case ici + une vue dans Features/.
enum Feature: String, CaseIterable, Identifiable {
    case home
    case faviconSync
    case twins
    case ghosts
    case echo
    case ferry
    case backups
    case settings
    case about

    var id: String { rawValue }

    /// Accueil et outils, en haut de la barre latérale.
    static let tools: [Feature] = [.home, .faviconSync, .twins, .ghosts, .echo, .ferry]

    /// Entrées fixées en bas, sous un séparateur.
    static let footer: [Feature] = [.backups, .settings, .about]

    /// Les noms des outils (FaviconSync, Twins…) sont des noms propres : ils ne se traduisent pas.
    var title: String {
        switch self {
        case .home: String(localized: "Home")
        case .faviconSync: "FaviconSync"
        case .twins: "Twins"
        case .ghosts: "Ghosts"
        case .echo: "Echo"
        case .ferry: "Ferry"
        case .backups: String(localized: "Backups")
        case .settings: String(localized: "Settings")
        case .about: String(localized: "About")
        }
    }

    /// Nom d'un symbole SF Symbols (l'icône système d'Apple)
    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .faviconSync: "star.fill"
        case .twins: "square.on.square"
        case .ghosts: "eye.slash.fill"
        case .echo: "dot.radiowaves.left.and.right"
        case .ferry: "ferry.fill"
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
        case .ghosts: Brand.green
        case .echo: Brand.pink
        case .ferry: Brand.indigo
        case .backups: Brand.teal
        case .settings: Brand.violet
        case .about: Brand.pink
        }
    }
}
