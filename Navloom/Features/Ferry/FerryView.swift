import SwiftUI
import AppKit

struct FerryView: View {
    @Bindable var model: FerryViewModel

    /// Dégradé propre à Ferry : indigo → violet.
    private static let gradient = [Brand.indigo, Brand.violet]

    var body: some View {
        VStack(spacing: 16) {
            titleHeader

            if model.phase == .done {
                filterBanner
            }

            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if model.phase == .done, !model.browsers.isEmpty {
                stats
            }

            middle
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            actionBar
        }
        .padding(20)
        .navigationTitle("Navloom")
    }

    // MARK: - En-tête

    private var titleHeader: some View {
        VStack(spacing: 4) {
            Text("Ferry")
                .font(.largeTitle.bold())
                .foregroundStyle(
                    LinearGradient(colors: Self.gradient,
                                   startPoint: .leading, endPoint: .trailing)
                )
            Text("Rassemble les onglets ouverts de tous tes navigateurs")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Bandeau coloré : recherche, navigation privée, dernière lecture.
    private var filterBanner: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        return HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Rechercher un titre ou une URL", text: $model.searchText)
                    .textFieldStyle(.plain)
                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(maxWidth: .infinity)

            Divider().frame(height: 20)

            Toggle(isOn: $model.showPrivate) {
                Label("Navigation privée", systemImage: "eye.slash")
                    .fontWeight(.semibold)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .fixedSize()

            if let date = model.lastRead {
                Divider().frame(height: 20)
                Label(date.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                    .foregroundStyle(.secondary)
                    .help("Heure de la dernière lecture")
                    .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(colors: Self.gradient.map { $0.opacity(0.18) },
                           startPoint: .leading, endPoint: .trailing),
            in: shape
        )
        .overlay(shape.strokeBorder(Brand.violet.opacity(0.3), lineWidth: 1))
    }

    private var stats: some View {
        HStack(spacing: 12) {
            StatCard(title: "Navigateurs", value: model.browserCount,
                     systemImage: "globe", tint: Brand.indigo)
            StatCard(title: "Fenêtres", value: model.windowCount,
                     systemImage: "macwindow", tint: Brand.violet)
            StatCard(title: "Onglets", value: model.tabCount,
                     systemImage: "square.on.square", tint: Brand.sky)
            StatCard(title: "Privées masquées", value: model.hiddenPrivateCount,
                     systemImage: "eye.slash", tint: .gray)
        }
    }

    // MARK: - Zone centrale

    @ViewBuilder
    private var middle: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView {
                Label("Prêt à embarquer tes onglets", systemImage: "ferry")
            } description: {
                Text("Navloom lit les fenêtres et les onglets des navigateurs ouverts (les navigateurs fermés sont ignorés). La lecture ne ferme ni ne modifie rien. La première fois, macOS te demande d'autoriser Navloom à contrôler chaque navigateur : accepte pour que ses onglets apparaissent.")
            }
        case .reading:
            VStack(spacing: 12) {
                ProgressView()
                Text(model.currentBrowserName.isEmpty
                     ? "Lecture des onglets…"
                     : "Lecture de \(model.currentBrowserName)…")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Si macOS demande une autorisation, réponds-y pour continuer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .done:
            if model.browsers.isEmpty {
                ContentUnavailableView(
                    "Aucun navigateur ouvert",
                    systemImage: "globe",
                    description: Text("Ouvre Vivaldi, Chrome, Brave, Edge ou Opera, puis relance la lecture.")
                )
            } else if model.visibleBrowsers.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            } else {
                resultsView
            }
        }
    }

    private var resultsView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button("Tout déplier") { model.setAllExpanded(true) }
                Button("Tout replier") { model.setAllExpanded(false) }
                Spacer()
                Text("Double-clic sur un onglet pour l'ouvrir dans son navigateur")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            List {
                ForEach(model.visibleBrowsers) { browser in
                    Section {
                        if let error = browser.error {
                            ErrorRow(browserName: browser.browser.name, error: error) {
                                model.openAutomationSettings()
                            }
                        } else {
                            let windows = model.visibleWindows(of: browser)
                            if windows.isEmpty {
                                Text(browser.windows.isEmpty
                                     ? "Aucune fenêtre ouverte"
                                     : "Seulement des fenêtres de navigation privée")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(windows) { window in
                                DisclosureGroup(isExpanded: model.isExpanded(window)) {
                                    ForEach(window.tabs) { tab in
                                        TabRow(tab: tab, favicon: model.favicons[tab.url])
                                            .contentShape(Rectangle())
                                            .onTapGesture(count: 2) { model.open(tab, in: browser.browser) }
                                            .contextMenu {
                                                Button("Ouvrir dans \(browser.browser.name)") {
                                                    model.open(tab, in: browser.browser)
                                                }
                                                Button("Copier l'URL") { model.copyURL(tab) }
                                            }
                                    }
                                } label: {
                                    WindowLabel(window: window)
                                }
                            }
                        }
                    } header: {
                        BrowserHeader(browser: browser, windows: model.visibleWindows(of: browser))
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    // MARK: - Barre d'action

    private var actionBar: some View {
        HStack {
            if model.phase == .done, !model.browsers.isEmpty {
                Button {
                    model.exportReport()
                } label: {
                    Label("Exporter", systemImage: "square.and.arrow.up")
                }
            }

            Spacer()

            switch model.phase {
            case .idle:
                Button("Lire les onglets ouverts") { model.read() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            case .reading:
                Button("Lecture en cours…") {}
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(true)
            case .done:
                Button {
                    model.read()
                } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

// MARK: - En-tête d'un navigateur

private struct BrowserHeader: View {
    let browser: BrowserTabs
    let windows: [OpenWindow]

    var body: some View {
        HStack(spacing: 8) {
            AppIcon(bundleID: browser.browser.bundleID)
                .frame(width: 20, height: 20)
            Text(browser.browser.name)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            if browser.error == nil {
                let tabs = windows.reduce(0) { $0 + $1.tabs.count }
                Text("\(TabSnapshot.plural(windows.count, "fenêtre")) · \(TabSnapshot.plural(tabs, "onglet"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}

/// Icône de l'application installée (celle du Dock).
private struct AppIcon: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
        } else {
            Image(systemName: "globe")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Fenêtre

private struct WindowLabel: View {
    let window: OpenWindow

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: window.isPrivate ? "eye.slash.fill" : "macwindow")
                .foregroundStyle(window.isPrivate ? AnyShapeStyle(.secondary) : AnyShapeStyle(Brand.violet))
                .frame(width: 18)

            Text("Fenêtre \(window.position)")
                .font(.callout.weight(.semibold))

            if window.isPrivate {
                Text("Privée")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }

            Text(TabSnapshot.plural(window.tabs.count, "onglet"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if let active = window.activeTab {
                Text("· \(active.displayTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

// MARK: - Onglet

private struct TabRow: View {
    let tab: OpenTab
    let favicon: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let favicon {
                    Image(nsImage: favicon)
                        .resizable()
                        .interpolation(.high)
                } else {
                    Image(systemName: "globe")
                        .resizable()
                        .foregroundStyle(.tertiary)
                }
            }
            .scaledToFit()
            .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(tab.displayTitle)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(tab.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if tab.isActive {
                Text("Au premier plan")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Brand.indigo)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Brand.indigo.opacity(0.15), in: Capsule())
                    .help("Onglet affiché dans cette fenêtre")
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Erreur de lecture

private struct ErrorRow: View {
    let browserName: String
    let error: TabReadError
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: error == .permissionDenied ? "lock.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 6) {
                Text(error.message)
                    .font(.callout.weight(.semibold))
                if error == .permissionDenied {
                    Text("Ouvre Réglages Système › Confidentialité et sécurité › Automatisation, déplie Navloom et active \(browserName), puis clique sur Actualiser.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Ouvrir les réglages d'Automatisation", action: openSettings)
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    FerryView(model: FerryViewModel())
}
