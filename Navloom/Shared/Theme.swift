import SwiftUI
import AppKit

extension Color {
    /// Couleur depuis un code hexadécimal : Color(hex: 0xFF7A59)
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// Apparence choisie dans les Paramètres.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Système"
        case .light: "Clair"
        case .dark: "Sombre"
        }
    }

    /// nil = suivre le réglage de macOS
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Palette de l'icône de Navloom.
enum Brand {
    static let coral = Color(hex: 0xFF7A59)
    static let gold = Color(hex: 0xFFC94D)
    static let pink = Color(hex: 0xFF5C8A)
    static let teal = Color(hex: 0x2DD4BF)
    static let sky = Color(hex: 0x60A5FA)
    static let violet = Color(hex: 0xA78BFA)
}

/// Pastille colorée façon Réglages Système : symbole blanc sur carré arrondi dégradé.
struct SidebarIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Barre de progression épaisse, aux couleurs de l'icône.
struct ThickProgressBar: View {
    let value: Double
    let total: Double
    var height: CGFloat = 14

    private var fraction: Double {
        total > 0 ? min(max(value / total, 0), 1) : 0
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(LinearGradient(colors: [Brand.teal, Brand.sky, Brand.violet],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, proxy.size.width * fraction))
            }
            .animation(.smooth, value: fraction)
        }
        .frame(height: height)
    }
}
