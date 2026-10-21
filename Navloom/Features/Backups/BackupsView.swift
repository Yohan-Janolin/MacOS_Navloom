import SwiftUI

struct BackupsView: View {
    @Bindable var model: BackupsViewModel

    var body: some View {
        Group {
            if !model.hasLoaded {
                ProgressView()
            } else if model.browsers.isEmpty {
                ContentUnavailableView(
                    "No browser detected",
                    systemImage: "globe",
                    description: Text("Navloom looks for Vivaldi, Chrome, Brave and Edge in ~/Library/Application Support.")
                )
            } else {
                content
            }
        }
        .navigationTitle("Backups")
        .task { model.loadBrowsersIfNeeded() }
        .onAppear { model.reloadBackups() }   // une nouvelle sauvegarde a pu apparaître entre-temps
        .task {
            // Surveille l'état du navigateur : on ne peut restaurer que s'il est fermé.
            while !Task.isCancelled {
                model.refreshBrowserRunning()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onChange(of: model.selectedBrowserID) { model.browserChanged() }
        .onChange(of: model.selectedProfileID) { model.reloadBackups() }
        .confirmationDialog(
            "Restore this backup?",
            isPresented: Binding(
                get: { model.pendingRestore != nil },
                set: { if !$0 { model.pendingRestore = nil } }
            ),
            titleVisibility: .visible,
            presenting: model.pendingRestore
        ) { entry in
            Button("Restore") { model.restore(entry) }
        } message: { entry in
            Text(restoreMessage(for: entry))
        }
    }

    private func restoreMessage(for entry: BackupEntry) -> String {
        let browser = model.selectedBrowser?.name ?? String(localized: "this browser")
        let date = entry.date.formatted(date: .long, time: .shortened)
        switch entry.category {
        case .favicons:
            return String(localized: "The favicon database of \(browser) will be replaced by the backup from \(date). The current state is backed up automatically beforehand.")
        case .bookmarks:
            return String(localized: "The bookmarks of \(browser) (Bookmarks file) will be replaced by the backup from \(date). The current state is backed up automatically beforehand.")
        }
    }

    // MARK: - Structure

    private var content: some View {
        VStack(spacing: 16) {
            header

            filterPicker

            notice

            if let banner = model.banner {
                bannerLabel(banner)
            }

            if model.items.isEmpty {
                ContentUnavailableView(
                    "No backups",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(emptyDescription)
                )
                .frame(maxHeight: .infinity)
            } else {
                List(model.items) { item in
                    BackupRow(
                        item: item,
                        canRestore: model.canRestore(item),
                        onRestore: { model.pendingRestore = item.entry },
                        onReveal: { model.reveal(item.entry) },
                        onDelete: { model.delete(item.entry) }
                    )
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .padding(20)
    }

    private var header: some View {
        HStack(spacing: 16) {
            BrowserProfileBanner(browsers: model.browsers,
                                 profiles: model.profiles,
                                 browserID: $model.selectedBrowserID,
                                 profileID: $model.selectedProfileID,
                                 expands: false)
            Spacer()
            Button {
                model.revealFolder()
            } label: {
                Label("Open Folder", systemImage: "folder")
            }
            .controlSize(.large)
        }
        .disabled(model.isRestoring)
    }

    /// Un filtre par outil : chaque sauvegarde est rangée sous l'outil qui l'a créée.
    private var filterPicker: some View {
        Picker("Tool", selection: $model.selectedFilter) {
            ForEach(model.filters) { filter in
                Text(verbatim: "\(filter.title) (\(model.count(in: filter)))").tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(model.isRestoring)
    }

    private var emptyDescription: String {
        switch model.selectedFilter {
        case .all:
            String(localized: "A backup is created automatically before every write to a browser's files.")
        case .tool(.faviconSync):
            String(localized: "A backup is created automatically before every write to the favicon database.")
        case .tool(.twins):
            String(localized: "A backup is created automatically before every deletion of duplicates.")
        case .tool(.ghosts):
            String(localized: "A backup is created automatically before every deletion of dead links.")
        case .tool(.echo):
            String(localized: "A backup is created automatically before every addition of bookmarks: the Bookmarks file and, if icons are copied, the favicon database.")
        case .legacy:
            String(localized: "No old backups.")
        }
    }

    /// Dès qu'une sauvegarde de favoris est affichée : bandeau complet (le navigateur ouvert ou la synchro
    /// active bloquent la restauration). Pour les seules favicons, seul le navigateur ouvert bloque :
    /// la synchro n'y change rien.
    @ViewBuilder
    private var notice: some View {
        let browserName = model.selectedBrowser?.name ?? String(localized: "The browser")
        if model.items.contains(where: { $0.entry.category == .bookmarks }) {
            SyncNotice(browserName: browserName,
                       isBrowserRunning: model.isBrowserRunning,
                       syncStatus: model.syncStatus,
                       operation: .restoration)
        } else if model.isBrowserRunning {
            SyncNotice(browserName: browserName,
                       isBrowserRunning: true,
                       syncStatus: .disabled,
                       operation: .restoration)
        }
    }

    private func bannerLabel(_ banner: BackupsViewModel.Banner) -> some View {
        let tint: Color = banner.isError ? .red : .green
        return Label(banner.text,
                     systemImage: banner.isError ? "xmark.octagon.fill" : "checkmark.circle.fill")
            .foregroundStyle(tint)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Outil d'une sauvegarde

private extension BackupTool {
    /// L'entrée de la barre latérale correspondante : même nom, même icône, même couleur.
    var feature: Feature {
        switch self {
        case .faviconSync: .faviconSync
        case .twins: .twins
        case .ghosts: .ghosts
        case .echo: .echo
        }
    }
}

/// Pastille « outil » : le même symbole et la même couleur que dans la barre latérale.
private struct ToolPill: View {
    let tool: BackupTool?

    var body: some View {
        let style = appearance
        Label { Text(verbatim: style.title) } icon: { Image(systemName: style.systemImage) }
            .font(.caption.bold())
            .foregroundStyle(style.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(style.tint.opacity(0.15), in: Capsule())
            .help(style.help)
    }

    private var appearance: (title: String, systemImage: String, tint: Color, help: String) {
        if let tool {
            return (tool.title, tool.feature.systemImage, tool.feature.tint,
                    String(localized: "Backup created by \(tool.title)"))
        }
        return (String(localized: "Twins or Ghosts"), "questionmark.circle", .secondary,
                String(localized: "Bookmark backup created before Navloom recorded which tool made it: Twins or Ghosts."))
    }
}

// MARK: - Ligne d'une sauvegarde

private struct BackupRow: View {
    let item: BackupsViewModel.Item
    let canRestore: Bool
    let onRestore: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.entry.kind == .beforeRestore ? "arrow.uturn.backward.circle" : "externaldrive")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(item.entry.date.formatted(date: .long, time: .shortened))
                    ToolPill(tool: item.entry.effectiveTool)
                }
                Text(verbatim: "\(kindLabel) · \(countLabel) · \(sizeLabel)")
                    .font(.caption)
                    .foregroundStyle(item.count == .unreadable ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }

            Spacer()

            Button("Restore", action: onRestore)
                .disabled(!canRestore)

            Menu {
                Button("Show in Finder", action: onReveal)
                Button("Move to Trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 4)
    }

    private var kindLabel: String {
        item.entry.kind == .beforeRestore ? String(localized: "Before restore") : String(localized: "Before write")
    }

    private var countLabel: String {
        switch item.count {
        case .loading: String(localized: "reading…")
        case .value(let count): item.entry.category.countLabel(count)
        case .unreadable: String(localized: "unreadable")
        }
    }

    private var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: item.entry.sizeBytes, countStyle: .file)
    }
}

#Preview { BackupsView(model: BackupsViewModel()) }
