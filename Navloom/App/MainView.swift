import SwiftUI

struct MainView: View {
    @State private var selection: Feature? = .home

    // Les view models vivent ici, au-dessus des écrans :
    // changer d'onglet ne détruit donc plus une recherche en cours.
    @State private var faviconSync = FaviconSyncViewModel()
    @State private var twins = TwinsViewModel()
    @State private var ghosts = GhostsViewModel()
    @State private var echo = EchoViewModel()
    @State private var ferry = FerryViewModel()
    @State private var backups = BackupsViewModel()

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        } detail: {
            detail
        }
        .frame(minWidth: 760, minHeight: 480)
        .diskAccessAlert()
    }

    // MARK: - Barre latérale

    private var sidebar: some View {
        List(Feature.tools, selection: $selection) { feature in
            Label {
                Text(feature.title)
            } icon: {
                SidebarIcon(systemImage: feature.systemImage, tint: feature.tint)
            }
            .tag(feature)
        }
        // Sauvegardes, Paramètres et À propos : tout en bas, sous un séparateur.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 2) {
                Divider()
                    .padding(.bottom, 6)
                ForEach(Feature.footer) { feature in
                    SidebarFooterRow(feature: feature, isSelected: selection == feature) {
                        selection = feature
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Contenu

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .home:
            HomeView()
        case .faviconSync:
            FaviconSyncView(model: faviconSync)
        case .twins:
            TwinsView(model: twins)
        case .ghosts:
            GhostsView(model: ghosts)
        case .echo:
            EchoView(model: echo)
        case .ferry:
            FerryView(model: ferry)
        case .backups:
            BackupsView(model: backups)
        case .settings:
            SettingsView()
        case .about:
            AboutView()
        case nil:
            ContentUnavailableView("Choose a tool", systemImage: "sidebar.left")
        }
    }
}

/// Ligne du bas de la barre latérale (hors de la liste, donc dessinée à la main).
private struct SidebarFooterRow: View {
    let feature: Feature
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(feature.title)
            } icon: {
                SidebarIcon(systemImage: feature.systemImage, tint: feature.tint)
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MainView()
}
