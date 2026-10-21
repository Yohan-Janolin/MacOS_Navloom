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
        .navigationTitle(Text(verbatim: "Navloom"))
        .confirmationDialog(confirmationTitle,
                            isPresented: $model.showTransferConfirmation,
                            titleVisibility: .visible) {
            if model.closeOriginals {
                Button("Transfer and Close the Originals", role: .destructive) { model.transfer() }
            } else {
                Button("Transfer") { model.transfer() }
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    // MARK: - En-tête

    private var titleHeader: some View {
        VStack(spacing: 4) {
            Text(verbatim: "Ferry")
                .font(.largeTitle.bold())
                .foregroundStyle(
                    LinearGradient(colors: Self.gradient,
                                   startPoint: .leading, endPoint: .trailing)
                )
            Text("Gathers the open tabs of all your browsers and moves them from one to another")
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
                TextField("Search a title or URL", text: $model.searchText)
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
                Label("Private browsing", systemImage: "eye.slash")
                    .fontWeight(.semibold)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .fixedSize()

            if let date = model.lastRead {
                Divider().frame(height: 20)
                Label { Text(verbatim: date.formatted(date: .omitted, time: .shortened)) } icon: { Image(systemName: "clock") }
                    .foregroundStyle(.secondary)
                    .help("Time of the last read")
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
            StatCard(title: "Browsers", value: model.browserCount,
                     systemImage: "globe", tint: Brand.indigo)
            StatCard(title: "Windows", value: model.windowCount,
                     systemImage: "macwindow", tint: Brand.violet)
            StatCard(title: "Tabs", value: model.tabCount,
                     systemImage: "square.on.square", tint: Brand.sky)
            StatCard(title: "Private hidden", value: model.hiddenPrivateCount,
                     systemImage: "eye.slash", tint: .gray)
        }
    }

    // MARK: - Zone centrale

    @ViewBuilder
    private var middle: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView {
                Label("Ready to ship your tabs", systemImage: "ferry")
            } description: {
                Text("Navloom reads the windows and tabs of the open browsers (closed browsers are ignored). Reading doesn't close or change anything. The first time, macOS asks you to allow Navloom to control each browser: accept so that its tabs appear.")
            }
        case .reading:
            VStack(spacing: 12) {
                ProgressView()
                Text(model.currentBrowserName.isEmpty
                     ? String(localized: "Reading tabs…")
                     : String(localized: "Reading \(model.currentBrowserName)…"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("If macOS asks for permission, answer it to continue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .done:
            if model.browsers.isEmpty {
                ContentUnavailableView(
                    "No browser open",
                    systemImage: "globe",
                    description: Text("Open Vivaldi, Chrome, Brave, Edge or Opera, then read again.")
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
                Button("Check All") { model.selectAllVisible() }
                Button("Uncheck All") { model.deselectAll() }
                    .disabled(model.selectedCount == 0)
                Text("\(model.selectedCount) checked")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Expand All") { model.setAllExpanded(true) }
                Button("Collapse All") { model.setAllExpanded(false) }
            }

            Text("Check tabs, a workspace or a whole window, then choose the target browser at the bottom. Double-click a tab to open it in its browser.")
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
                                     ? String(localized: "No open windows")
                                     : String(localized: "Only private browsing windows"))
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
                                        .help("Check the whole window")
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
                WorkspaceHeader(workspace: group.workspace ?? TabWorkspace(id: "?", name: String(localized: "Others")),
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
                Button("Open in \(browser.name)") { model.open(tab, in: browser) }
                Button("Copy URL") { model.copyURL(tab) }
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
                Label("Target browser", systemImage: "arrow.right.circle")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .layoutPriority(1)

                Picker("Target browser", selection: $model.targetBrowserID) {
                    Text("Choose…").tag(String?.none)
                    ForEach(model.installedBrowsers) { browser in
                        Text(verbatim: browser.name).tag(Optional(browser.id))
                    }
                }
                .labelsHidden()
                .fixedSize()

                Spacer(minLength: 0)
            }

            // Options sur une seconde ligne : la fenêtre reste lisible à sa largeur minimale.
            HStack(spacing: 16) {
                Toggle("Single window", isOn: $model.singleWindow)
                    .toggleStyle(.checkbox)
                    .help("Group all tabs in a single window instead of recreating each window")
                Toggle("One window per workspace", isOn: $model.windowPerWorkspace)
                    .toggleStyle(.checkbox)
                    .disabled(model.singleWindow)
                    .help("Workspaces aren't recreated in the target: each source workspace arrives in its own window, to be moved afterwards into the workspace you want")
                Toggle("Keep private browsing", isOn: $model.keepPrivate)
                    .toggleStyle(.checkbox)
                    .help("Reopen in private browsing the tabs that came from a private window")
                Toggle(isOn: $model.closeOriginals) {
                    Text("Close the original tabs")
                        .foregroundStyle(model.closeOriginals ? .red : .primary)
                }
                .toggleStyle(.checkbox)
                .help("Once their copy is open and found in the target, close the original tabs")

                Spacer(minLength: 0)
            }

            if model.targetBrowser != nil, model.selectedCount > 0 {
                Text(verbatim: planDescription(plan))
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
            parts.append(String(localized: "Nothing to transfer"))
        } else {
            let tabs = String(localized: "\(plan.tabCount) tabs")
            let windows = String(localized: "\(plan.windows.count) new windows")
            parts.append(String(localized: "\(tabs) in \(windows)"))
        }
        if plan.skippedSameBrowser > 0 {
            let tabs = String(localized: "\(plan.skippedSameBrowser) tabs")
            parts.append(String(localized: "\(tabs) already in this browser"))
        }
        if plan.skippedInternal > 0 {
            parts.append(String(localized: "\(plan.skippedInternal) internal pages skipped"))
        }
        return parts.joined(separator: " · ")
    }

    /// Progression pendant le transfert, puis bilan.
    @ViewBuilder
    private var transferStatus: some View {
        if let progress = model.transferProgress {
            VStack(alignment: .leading, spacing: 6) {
                ThickProgressBar(value: Double(progress.done), total: Double(max(progress.total, 1)), height: 10)
                let target = model.targetBrowser?.name ?? String(localized: "the browser")
                let windows = String(localized: "\(progress.total) windows")
                Text("Opening in \(target)… \(progress.done)/\(windows)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        } else if let summary = model.transferSummary {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: summary.errors.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(summary.errors.isEmpty ? .green : .orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    let opened = String(localized: "\(summary.openedTabs) tabs opened")
                    let windows = String(localized: "\(summary.openedWindows) windows")
                    Text("\(opened) in \(summary.browserName) (\(windows))")
                        .font(.callout.weight(.semibold))
                    if let closing = summary.closing {
                        Text(verbatim: closingText(closing))
                            .font(.caption)
                            .foregroundStyle(closing.notClosed > 0 ? .orange : .secondary)
                    }
                    if summary.skipped > 0 {
                        let skipped = String(localized: "\(summary.skipped) tabs left aside")
                        Text("\(skipped) (internal pages or already in \(summary.browserName))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(summary.errors.enumerated()), id: \.offset) { _, error in
                        Text(verbatim: error)
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
        var text = String(localized: "\(closing.closed) original tabs closed")
        var kept: [String] = []
        if closing.unconfirmed > 0 {
            kept.append(String(localized: "\(closing.unconfirmed) not found in the target"))
        }
        if closing.changed > 0 {
            kept.append(String(localized: "\(closing.changed) showing another page"))
        }
        if closing.otherSpace > 0 {
            kept.append(String(localized: "\(closing.otherSpace) in another Opera workspace (close by hand)"))
        }
        if closing.failed > 0 {
            kept.append(String(localized: "\(closing.failed) missing"))
        }
        if !kept.isEmpty {
            let list = kept.joined(separator: ", ")
            text += " · " + String(localized: "kept open: \(list)")
        }
        return text
    }

    private var confirmationTitle: String {
        let plan = model.transferPlan
        let tabs = String(localized: "\(plan.tabCount) tabs")
        let target = model.targetBrowser?.name ?? String(localized: "the browser")
        return String(localized: "Open \(tabs) in \(target)?")
    }

    private var confirmationMessage: String {
        let plan = model.transferPlan
        var sentences = [String(localized: "\(plan.windows.count) new windows will be created.")]
        if model.closeOriginals {
            let names = DiskAccess.joinedNames(model.sourceBrowserNames)
            let closing = String(localized: "\(model.tabsToCloseCount) tabs will be closed")
            sentences.append(String(localized: "Then, \(closing) in \(names), but only those whose copy is found in the target and that still show the same page. A window whose tabs are all closed closes too."))
            if model.unclosableCount > 0 {
                sentences.append(String(localized: "\(model.unclosableCount) tabs from other Opera workspaces will be copied but stay open: Opera refuses to close them, close them by hand."))
            }
        } else {
            sentences.append(String(localized: "The original tabs stay open."))
        }
        if let target = model.targetBrowser, !TabReader.isRunning(target) {
            sentences.append(String(localized: "\(target.name) will be launched."))
        }
        if model.selectionHasWorkspaces {
            sentences.append(model.windowPerWorkspace && !model.singleWindow
                ? String(localized: "Each workspace arrives in its own window, in the target's shown workspace: move them afterwards into the workspace you want.")
                : String(localized: "Workspaces aren't recreated: the tabs arrive in the target's shown workspace."))
        }
        return sentences.joined(separator: " ")
    }

    // MARK: - Barre d'action

    private var actionBar: some View {
        HStack {
            if model.phase == .done, !model.browsers.isEmpty {
                Button {
                    model.exportReport()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }

            Spacer()

            switch model.phase {
            case .idle:
                Button("Read Open Tabs") { model.read() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            case .reading:
                Button("Reading…") {}
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(true)
            case .done:
                Button {
                    model.read()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.large)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isTransferring)

                Button {
                    model.showTransferConfirmation = true
                } label: {
                    Label("Transfer \(model.transferPlan.tabCount) tabs", systemImage: "ferry.fill")
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
            Text(verbatim: browser.browser.name)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            if browser.error == nil {
                let tabs = windows.reduce(0) { $0 + $1.tabs.count }
                Text(verbatim: String(localized: "\(windows.count) windows") + " · " + String(localized: "\(tabs) tabs"))
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
        let tabs = String(localized: "\(window.tabs.count) tabs")
        let spaces = Set(window.tabs.compactMap(\.workspaceID)).count
        return window.workspaces.isEmpty ? tabs : tabs + " · " + String(localized: "\(spaces) workspaces")
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: window.isPrivate ? "eye.slash.fill" : "macwindow")
                .foregroundStyle(window.isPrivate ? AnyShapeStyle(.secondary) : AnyShapeStyle(Brand.violet))
                .frame(width: 18)

            Text("Window \(window.position)")
                .font(.callout.weight(.semibold))

            if window.isPrivate {
                Text("Private")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }

            if let profile = window.profileName {
                Label { Text(verbatim: profile) } icon: { Image(systemName: "person.crop.circle") }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Brand.indigo)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Brand.indigo.opacity(0.15), in: Capsule())
                    .lineLimit(1)
            }

            Text(verbatim: countText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if let active = window.activeTab {
                Text(verbatim: "· \(active.displayTitle)")
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
                .help("Check the whole workspace")
            Group {
                if let emoji = workspace.emoji {
                    Text(verbatim: emoji)
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

            Text(verbatim: workspace.name)
                .font(.callout.weight(.bold))

            Text("\(count) tabs")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if isActive {
                Text("Shown")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Brand.indigo)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Brand.indigo.opacity(0.15), in: Capsule())
                    .help("Workspace shown in this window")
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
                Text(verbatim: tab.displayTitle)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(verbatim: tab.url)
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
                    .help("Opera doesn't allow closing the tabs of this workspace: it will be copied but stay open")
            }

            if tab.isActive {
                Text("In front")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Brand.indigo)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Brand.indigo.opacity(0.15), in: Capsule())
                    .help("Tab shown in this window")
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
                Text(verbatim: error.message)
                    .font(.callout.weight(.semibold))
                if error == .permissionDenied {
                    Text("Open System Settings › Privacy & Security › Automation, expand Navloom and turn on \(browserName), then click Refresh.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Automation Settings", action: openSettings)
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
