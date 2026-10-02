import SwiftUI

/// Bandeau coloré : choix du navigateur + choix du profil (FaviconSync et Sauvegardes).
struct BrowserProfileBanner: View {
    let browsers: [ChromiumBrowser]
    let profiles: [ChromiumProfile]
    @Binding var browserID: String?
    @Binding var profileID: String?
    /// Vrai : le bandeau occupe toute la largeur. Faux : il s'adapte à son contenu.
    var expands = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        HStack(spacing: 12) {
            Label("Navigateur", systemImage: "globe")
                .fontWeight(.semibold)
            Picker("Navigateur", selection: $browserID) {
                ForEach(browsers) { browser in
                    Text(browser.name).tag(Optional(browser.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 220)

            if !profiles.isEmpty {
                Divider().frame(height: 20)

                Label("Profil", systemImage: "person.crop.circle")
                    .fontWeight(.semibold)
                Picker("Profil", selection: $profileID) {
                    ForEach(profiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
            }

            if expands { Spacer() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(colors: [Brand.coral.opacity(0.18), Brand.violet.opacity(0.18)],
                           startPoint: .leading, endPoint: .trailing),
            in: shape
        )
        .overlay(shape.strokeBorder(Brand.violet.opacity(0.3), lineWidth: 1))
    }
}