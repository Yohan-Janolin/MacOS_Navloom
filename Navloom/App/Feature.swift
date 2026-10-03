import SwiftUI

/// Une entrée de la barre latérale.
/// Ajouter un outil = ajouter un case ici + une vue dans Features/.
enum Feature: String, CaseIterable, Identifiable {
    case faviconSync
    case twins
    case backups
    case settings

    var id: String { rawValue }

    /// Outils, en haut de la barre latérale.
    static let tools: [Feature] = [.faviconSync, .twins]

    /// Entrées fixées en bas, sous un séparateur.
    static let footer: [Feature] = [.backups, .settings]

    var title: String {
        switch self {
        case .faviconSync: "FaviconSync"
        case .twins: "Twins"
        case .backups: "Sauvegardes"
        case .settings: "Paramètres"
        }
    }

    /// Nom d'un symbole SF Symbols (l'icône système d'Apple)
    var systemImage: String {
        switch self {
        case .faviconSync: "star.fill"
        case .twins: "square.on.square"
        case .backups: "clock.arrow.circlepath"
        case .settings: "gearshape.fill"
        }
    }

    var tint: Color {
        switch self {
        case .faviconSync: Brand.coral
        case .twins: Brand.sky
        case .backups: Brand.teal
        case .settings: Brand.violet
        }
    }
}
