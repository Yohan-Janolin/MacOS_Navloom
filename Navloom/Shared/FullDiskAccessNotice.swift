import SwiftUI
import AppKit

/// Bandeau affiché au-dessus des outils quand macOS interdit à Navloom de lire les données de
/// certains navigateurs (ils n'apparaissent alors pas dans la liste). Explique l'autorisation à
/// accorder et propose d'ouvrir le réglage, puis de relancer l'app.
struct FullDiskAccessNotice: View {
    let blocked: [ChromiumBrowser]
    let onDismiss: () -> Void

    var body: some View {
        let tint = Color.orange

        VStack(alignment: .leading, spacing: 10) {
            Label("Accès complet au disque requis", systemImage: "lock.shield.fill")
                .font(.headline)
                .foregroundStyle(tint)

            Text("macOS bloque l'accès aux données de \(DiskAccess.joinedNames(blocked.map(\.name))) : ils n'apparaissent donc pas dans la liste des navigateurs. Pour les utiliser, ouvre Réglages Système › Confidentialité et sécurité › Accès complet au disque, ajoute Navloom avec le bouton « + » s'il n'y est pas, active-le, puis relance Navloom.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Ouvrir les réglages") { Self.openFullDiskAccessSettings() }
                    .buttonStyle(.borderedProminent)
                Button("Relancer Navloom") { Self.relaunch() }
                Spacer()
                Button("Masquer", action: onDismiss)
                    .buttonStyle(.link)
                    .help("Masque ce message jusqu'au prochain lancement")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Actions

    /// Ouvre le volet « Accès complet au disque ». Deux adresses sont essayées (la forme a changé
    /// avec Réglages Système) ; à défaut, on ouvre simplement Réglages Système.
    private static func openFullDiskAccessSettings() {
        let addresses = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
        ]
        for address in addresses {
            if let url = URL(string: address), NSWorkspace.shared.open(url) { return }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    /// Lance une nouvelle instance de Navloom puis quitte celle-ci : l'autorisation n'est prise en
    /// compte qu'au démarrage. Si le lancement échoue, l'app reste ouverte.
    private static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundlePath]
        do {
            try process.run()
        } catch {
            return
        }
        NSApplication.shared.terminate(nil)
    }
}

#Preview {
    FullDiskAccessNotice(blocked: Array(ChromiumBrowser.known.prefix(3)), onDismiss: {})
        .padding()
}
