import SwiftUI

/// Carte de statistique partagée par FaviconSync, Twins et Ghosts : fond et contour teintés.
struct StatCard: View {
    let title: LocalizedStringKey
    let value: Int
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(value, format: .number)
                    .font(.title2.bold().monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.12), in: shape)
        .overlay(shape.strokeBorder(tint.opacity(0.25), lineWidth: 1))
    }
}
