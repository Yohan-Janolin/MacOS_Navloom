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

            if model.phase == .done, !model.browsers.isEmpty {
                transferStatus
                transferBanner
            }

            actionBar
        }
        .padding(20)
        .navigationTitle("Navloom")
        .confirmationDialog(confirmationTitle,
                            isPresented: $model.showTransferConfirmation,
                            titleVisibility: .visible) {
            if model.closeOriginals {
                Button("Transférer et fermer les originaux", role: .destructive) { model.transfer() }
            } else {
                Button("Transférer") { model.transfer() }
            }
        } message: {
            Text(confirmationMessage)
        }
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
            Text("Rassemble les onglets ouverts de tous tes navigateurs et fais-les passer de l'un à l'autre")
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
                Button("Tout cocher") { model.selectAllVisible() }
                Button("Tout décocher") { model.deselectAll() }
                    .disabled(model.selectedCount == 0)
                Text("\(model.selectedCount) coché\(model.selectedCount > 1 ? "s" : "")")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Tout déplier") { model.setAllExpanded(true) }
                Button("Tout replier") { model.setAllExpanded(false) }
            }

            Text("Coche des onglets, un espace ou une fenêtre entière, puis choisis le navigateur cible en bas. Double-clic sur un onglet pour l'ouvrir dans son navigateur.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

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
                                    windowContent(window, browser: browser.browser)
                                } label: {
                                    HStack(spacing: 8) {
                                        CheckButton(state: model.state(of: window.tabs)) {
                                            model.toggle(window.tabs)
                                        }
                                        .help("Cocher toute la fenêtre")
                                        WindowLabel(window: window)
                                    }
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

    /// Onglets d'une fenêtre, sous un intertitre par espace de travail (Opera).
    @ViewBuilder
    private func windowContent(_ window: OpenWindow, browser: ChromiumBrowser) -> some View {
        let hasWorkspaces = !window.workspaces.isEmpty
        ForEach(window.tabGroups) { group in
            if hasWorkspaces {
                WorkspaceHeader(workspace: group.workspace ?? TabWorkspace(id: "?", name: "Autres"),
                                count: group.tabs.count,
                                isActive: group.isActive,
                                state: model.state(of: group.tabs)) {
                    model.toggle(group.tabs)
                }
            }
            ForEach(group.tabs) { tab in
                tabRow(tab, browser: browser)
                    .padding(.leading, hasWorkspaces ? 14 : 0)
            }
        }
    }

    private func tabRow(_ tab: OpenTab, browser: ChromiumBrowser) -> some View {
        TabRow(tab: tab, favicon: model.favicons[tab.url],
               isChecked: model.isSelected(tab),
               showsUnclosable: model.closeOriginals && !tab.canClose) {
            model.toggle(tab)
        }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { model.open(tab, in: browser) }
            .contextMenu {
                Button("Ouvrir dans \(browser.name)") { model.open(tab, in: browser) }
                Button("Copier l'URL") { model.copyURL(tab) }
            }
    }

    // MARK: - Transfert

    /// Dégradé du navigateur cible, le même que dans Echo.
    private static let targetGradient = [Brand.coral, Brand.gold]

    private var transferBanner: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let plan = model.transferPlan

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label("Navigateur cible", systemImage: "arrow.right.circle")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .layoutPriority(1)

                Picker("Navigateur cible", selection: $model.targetBrowserID) {
                    Text("Choisir…").tag(String?.none)
                    ForEach(model.installedBrowsers) { browser in
                        Text(browser.name).tag(Optional(browser.id))
                    }
                }
                .labelsHidden()
                .fixedSize()

                Spacer(minLength: 0)
            }

            // Options sur une seconde ligne : la fenêtre reste lisible à sa largeur minimale.
            HStack(spacing: 16) {
                Toggle("Une seule fenêtre", isOn: $model.singleWindow)
                    .toggleStyle(.checkbox)
                    .help("Regrouper tous les onglets dans une seule fenêtre au lieu de recréer chaque fenêtre")
                Toggle("Une fenêtre par espace", isOn: $model.windowPerWorkspace)
                    .toggleStyle(.checkbox)
                    .disabled(model.singleWindow)
                    .help("Les espaces ne se recréent pas dans la cible : chaque espace de la source arrive dans sa propre fenêtre, à ranger ensuite dans l'espace voulu")
                Toggle("Garder la navigation privée", isOn: $model.keepPrivate)
                    .toggleStyle(.checkbox)
                    .help("Rouvrir en navigation privée les onglets qui venaient d'une fenêtre privée")
                Toggle(isOn: $model.closeOriginals) {
                    Text("Fermer les onglets d'origine")
                        .foregroundStyle(model.closeOriginals ? .red : .primary)
                }
                .toggleStyle(.checkbox)
                .help("Une fois leur copie ouverte et retrouvée dans la cible, fermer les onglets d'origine")

                Spacer(minLength: 0)
            }

            if model.targetBrowser != nil, model.selectedCount > 0 {
                Text(planDescription(plan))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(model.isTransferring)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(colors: Self.targetGradient.map { $0.opacity(0.18) },
                           startPoint: .leading, endPoint: .trailing),
            in: shape
        )
        .overlay(shape.strokeBorder(Brand.gold.opacity(0.35), lineWidth: 1))
    }

    private func planDescription(_ plan: TransferPlan) -> String {
        var parts: [String] = []
        if plan.isEmpty {
            parts.append("Rien à transférer")
        } else {
            parts.append("\(TabSnapshot.plural(plan.tabCount, "onglet")) dans \(TabSnapshot.plural(plan.windows.count, "nouvelle fenêtre", "nouvelles fenêtres"))")
        }
        if plan.skippedSameBrowser > 0 {
            parts.append("\(TabSnapshot.plural(plan.skippedSameBrowser, "onglet")) déjà dans ce navigateur")
        }
        if plan.skippedInternal > 0 {
            parts.append(TabSnapshot.plural(plan.skippedInternal, "page interne ignorée", "pages internes ignorées"))
        }
        return parts.joined(separator: " · ")
    }

    /// Progression pendant le transfert, puis bilan.
    @ViewBuilder
    private var transferStatus: some View {
        if let progress = model.transferProgress {
            VStack(alignment: .leading, spacing: 6) {
                ThickProgressBar(value: Double(progress.done), total: Double(max(progress.total, 1)), height: 10)
                Text("Ouverture dans \(model.targetBrowser?.name ?? "le navigateur")… \(progress.done)/\(TabSnapshot.plural(progress.total, "fenêtre"))")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        } else if let summary = model.transferSummary {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: summary.errors.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(summary.errors.isEmpty ? .green : .orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(TabSnapshot.plural(summary.openedTabs, "onglet")) ouvert\(summary.openedTabs > 1 ? "s" : "") dans \(summary.browserName) (\(TabSnapshot.plural(summary.openedWindows, "fenêtre")))")
                        .font(.callout.weight(.semibold))
                    if let closing = summary.closing {
                        Text(closingText(closing))
                            .font(.caption)
                            .foregroundStyle(closing.notClosed > 0 ? .orange : .secondary)
                    }
                    if summary.skipped > 0 {
                        Text("\(TabSnapshot.plural(summary.skipped, "onglet")) laissé\(summary.skipped > 1 ? "s" : "") de côté (pages internes ou déjà dans \(summary.browserName))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(summary.errors.enumerated()), id: \.offset) { _, error in
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Button {
                    model.dismissTransferSummary()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background((summary.errors.isEmpty ? Color.green : Color.orange).opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func closingText(_ closing: CloseSummary) -> String {
        var text = TabSnapshot.plural(closing.closed, "onglet d'origine fermé", "onglets d'origine fermés")
        var kept: [String] = []
        if closing.unconfirmed > 0 {
            kept.append("\(closing.unconfirmed) non retrouvé\(closing.unconfirmed > 1 ? "s" : "") dans la cible")
        }
        if closing.changed > 0 {
            kept.append("\(closing.changed) qui affiche\(closing.changed > 1 ? "nt" : "") une autre page")
        }
        if closing.otherSpace > 0 {
            kept.append("\(closing.otherSpace) dans un autre espace d'Opera (à fermer à la main)")
        }
        if closing.failed > 0 {
            kept.append("\(closing.failed) introuvable\(closing.failed > 1 ? "s" : "")")
        }
        if !kept.isEmpty {
            text += " · gardés ouverts : " + kept.joined(separator: ", ")
        }
        return text
    }

    private var confirmationTitle: String {
        let plan = model.transferPlan
        return "Ouvrir \(TabSnapshot.plural(plan.tabCount, "onglet")) dans \(model.targetBrowser?.name ?? "le navigateur") ?"
    }

    private var confirmationMessage: String {
        let plan = model.transferPlan
        var text = TabSnapshot.plural(plan.windows.count, "nouvelle fenêtre sera créée.", "nouvelles fenêtres seront créées.")
        if model.closeOriginals {
            let names = model.sourceBrowserNames.joined(separator: ", ")
            text += " Ensuite, \(TabSnapshot.plural(model.tabsToCloseCount, "onglet sera fermé", "onglets seront fermés")) dans \(names), mais seulement ceux dont la copie est bien retrouvée dans la cible et qui affichent encore la même page. Une fenêtre dont tous les onglets sont fermés se ferme aussi."
            if model.unclosableCount > 0 {
                text += " \(TabSnapshot.plural(model.unclosableCount, "onglet d'un autre espace d'Opera sera copié mais restera ouvert", "onglets d'autres espaces d'Opera seront copiés mais resteront ouverts")) : Opera refuse de les fermer, ferme-les à la main."
            }
        } else {
            text += " Les onglets d'origine restent ouverts."
        }
        if let target = model.targetBrowser, !TabReader.isRunning(target) {
            text += " \(target.name) sera lancé."
        }
        if model.selectionHasWorkspaces {
            text += model.windowPerWorkspace && !model.singleWindow
                ? " Chaque espace arrive dans sa propre fenêtre, dans l'espace affiché de la cible : range-les ensuite dans l'espace voulu."
                : " Les espaces de travail ne se recréent pas : les onglets arrivent dans l'espace affiché de la cible."
        }
        return text
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
                .controlSize(.large)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isTransferring)

                Button {
                    model.showTransferConfirmation = true
                } label: {
                    Label("Transférer \(TabSnapshot.plural(model.transferPlan.tabCount, "onglet"))",
                          systemImage: "ferry.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canTransfer)
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

    private var countText: String {
        let tabs = TabSnapshot.plural(window.tabs.count, "onglet")
        let spaces = Set(window.tabs.compactMap(\.workspaceID)).count
        return window.workspaces.isEmpty ? tabs : "\(tabs) · \(TabSnapshot.plural(spaces, "espace"))"
    }

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

            if let profile = window.profileName {
                Label(profile, systemImage: "person.crop.circle")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Brand.indigo)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Brand.indigo.opacity(0.15), in: Capsule())
                    .lineLimit(1)
            }

            Text(countText)
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

// MARK: - Espace de travail

private struct WorkspaceHeader: View {
    let workspace: TabWorkspace
    let count: Int
    let isActive: Bool
    let state: FerryViewModel.CheckState
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            CheckButton(state: state, action: onToggle)
                .help("Cocher tout l'espace")
            Group {
                if let emoji = workspace.emoji {
                    Text(emoji)
                        .font(.system(size: 12))
                } else {
                    Image(systemName: BrowserWorkspaces.symbol(for: workspace.icon))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 20, height: 20)
            .background((isActive ? Brand.indigo : Color.gray).gradient,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))

            Text(workspace.name)
                .font(.callout.weight(.bold))

            Text(TabSnapshot.plural(count, "onglet"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if isActive {
                Text("Affiché")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Brand.indigo)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Brand.indigo.opacity(0.15), in: Capsule())
                    .help("Espace affiché dans cette fenêtre")
            }
            Spacer()
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}

// MARK: - Onglet

private struct TabRow: View {
    let tab: OpenTab
    let favicon: NSImage?
    let isChecked: Bool
    /// Signale un onglet qu'Opera refusera de fermer (autre espace), quand la fermeture est demandée.
    var showsUnclosable = false
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            CheckButton(state: isChecked ? .all : .none, action: onToggle)
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

            if showsUnclosable {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("Opera ne laisse pas fermer les onglets de cet espace : il sera copié mais restera ouvert")
            }

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

// MARK: - Case à cocher

/// Case à trois états (aucun, certains, tous), utilisée pour les onglets, les espaces et les fenêtres.
private struct CheckButton: View {
    let state: FerryViewModel.CheckState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state.symbol)
                .font(.system(size: 15))
                .foregroundStyle(state == .none ? AnyShapeStyle(.secondary) : AnyShapeStyle(Brand.indigo))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
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
