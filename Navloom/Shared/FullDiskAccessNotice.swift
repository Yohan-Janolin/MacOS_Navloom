import SwiftUI
import AppKit

/// Message « Accès complet au disque » : sous macOS 27, Chrome, Edge et Brave (versions stables)
/// n'apparaissent dans la liste que si Navloom a cette autorisation. Quand macOS en bloque un,
/// une alerte système l'explique au lancement et propose d'ouvrir le réglage, puis de relancer l'app.
/// (Une alerte plutôt qu'un bandeau : elle n'ajoute rien à la mise en page des outils.)

/// Navigateurs bloqués, calculés une seule fois hors de l'interface : une autorisation accordée
/// ensuite ne s'applique de toute façon qu'après un redémarrage de l'app.
@MainActor
@Observable
final class DiskAccessNoticeState {
    private(set) var blocked: [ChromiumBrowser] = []
    private var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        blocked = await Task.detached { ChromiumBrowser.blockedByMacOS() }.value
    }

    var message: String {
        let names = DiskAccess.joinedNames(blocked.map(\.name))
        return String(localized: "macOS blocks access to the data of \(names), so they don't appear in the list of browsers.\n\nTo use them, open System Settings › Privacy & Security › Full Disk Access, add Navloom with the “+” button if it isn't there, turn it on, then relaunch Navloom.")
    }
}

private struct DiskAccessAlertModifier: ViewModifier {
    @State private var state = DiskAccessNoticeState()
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .task {
                await state.loadIfNeeded()
                isPresented = !state.blocked.isEmpty
            }
            .alert("Full Disk Access required", isPresented: $isPresented) {
                Button("Open Settings") { DiskAccessActions.openFullDiskAccessSettings() }
                Button("Relaunch Navloom") { DiskAccessActions.relaunch() }
                Button("Later", role: .cancel) {}
            } message: {
                Text(state.message)
            }
    }
}

extension View {
    /// À poser une seule fois, sur la fenêtre principale.
    func diskAccessAlert() -> some View {
        modifier(DiskAccessAlertModifier())
    }
}

enum DiskAccessActions {

    /// Ouvre le volet « Accès complet au disque ». Deux adresses sont essayées (la forme a changé
    /// avec Réglages Système) ; à défaut, on ouvre simplement Réglages Système.
    static func openFullDiskAccessSettings() {
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
    static func relaunch() {
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
