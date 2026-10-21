import SwiftUI

/// Bandeau coloré : choix du navigateur + choix du profil (FaviconSync et Sauvegardes).
struct BrowserProfileBanner: View {
    let browsers: [ChromiumBrowser]
    let profiles: [ChromiumProfile]
    @Binding var browserID: String?
    @Binding var profileID: String?
    /// Vrai : le bandeau occupe toute la largeur. Faux : il s'adapte à son contenu.
    var expands = true
    /// Titre du choix de navigateur (« Navigateur source », « Navigateur cible »…).
    var browserTitle: LocalizedStringKey = "Browser"
    /// Couleurs du dégradé de fond (de gauche à droite) ; la dernière colore aussi le contour.
    var colors: [Color] = [Brand.coral, Brand.violet]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        HStack(spacing: 12) {
            Label(browserTitle, systemImage: "globe")
                .fontWeight(.semibold)
                .lineLimit(1)
                .layoutPriority(1)

            Picker("Browser", selection: $browserID) {
                ForEach(browsers) { browser in
                    Text(verbatim: browser.name).tag(Optional(browser.id))
                }
            }
            .labelsHidden()
            .fixedSize()

            if !profiles.isEmpty {
                Divider().frame(height: 20)

                Label("Profile", systemImage: "person.crop.circle")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .layoutPriority(1)

                Picker("Profile", selection: $profileID) {
                    ForEach(profiles) { profile in
                        Text(verbatim: profile.name).tag(Optional(profile.id))
                    }
                }
                .labelsHidden()
                .fixedSize(horizontal: !expands, vertical: false)
                .frame(maxWidth: expands ? .infinity : nil, alignment: .leading)
            } else if expands {
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(colors: colors.map { $0.opacity(0.18) },
                           startPoint: .leading, endPoint: .trailing),
            in: shape
        )
        .overlay(shape.strokeBorder((colors.last ?? Brand.violet).opacity(0.3), lineWidth: 1))
    }
}
