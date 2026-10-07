import SwiftUI

struct BackupsView: View {
    @Bindable var model: BackupsViewModel

    var body: some View {
        Group {
            if !model.hasLoaded {
                ProgressView()
            } else if model.browsers.isEmpty {
                ContentUnavailableView(
                    "Aucun navigateur détecté",
                    systemImage: "globe",
                    description: Text("Navloom cherche Vivaldi, Chrome, Brave et Edge dans ~/Library/Application Support.")
                )
            } else {
                content
            }
        }
        .navigationTitle("Sauvegardes")
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
            "Restaurer cette sauvegarde ?",
            isPresented: Binding(
                get: { model.pendingRestore != nil },
                set: { if !$0 { model.pendingRestore = nil } }
            ),
            titleVisibility: .visible,
            presenting: model.pendingRestore
        ) { entry in
            Button("Restaurer") { model.restore(entry) }
        } message: { entry in
            Text(restoreMessage(for: entry))
        }
    }

    private func restoreMessage(for entry: BackupEntry) -> String {
        let browser = model.selectedBrowser?.name ?? "ce navigateur"
        let date = entry.date.formatted(date: .long, time: .shortened)
        switch entry.category {
        case .favicons:
            return "La base de favicons de \(browser) sera remplacée par la sauvegarde du \(date). L'état actuel est sauvegardé automatiquement avant."
        case .bookmarks:
            return "Les favoris de \(browser) (fichier Bookmarks) seront remplacés par la sauvegarde du \(date). L'état actuel est sauvegardé automatiquement avant."
        }
    }

    // MARK: - Structure

    private var content: some View {
        VStack(spacing: 16) {
            header

            categoryPicker

            notice

            if let banner = model.banner {
                bannerLabel(banner)
            }

            if model.items.isEmpty {
                ContentUnavailableView(
                    "Aucune sauvegarde",
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
                Label("Ouvrir le dossier", systemImage: "folder")
            }
            .controlSize(.large)
        }
        .disabled(model.isRestoring)
    }

    private var categoryPicker: some View {
        Picker("", selection: $model.selectedCategory) {
            ForEach(BackupCategory.allCases) { category in
                Text("\(category.title) (\(model.count(in: category)))").tag(category)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(model.isRestoring)
    }

    private var emptyDescription: String {
        switch model.selectedCategory {
        case .favicons:
            "Une sauvegarde est créée automatiquement avant chaque écriture dans la base de favicons."
        case .bookmarks:
            "Une sauvegarde est créée automatiquement avant chaque suppression de favoris (Twins, Ghosts)."
        }
    }

    /// Favoris : bandeau complet (le navigateur ouvert ou la synchro active bloquent la restauration).
    /// Favicons : seul le navigateur ouvert bloque, la synchro n'y change rien.
    @ViewBuilder
    private var notice: some View {
        let browserName = model.selectedBrowser?.name ?? "Le navigateur"
        switch model.selectedCategory {
        case .bookmarks:
            SyncNotice(browserName: browserName,
                       isBrowserRunning: model.isBrowserRunning,
                       syncStatus: model.syncStatus,
                       operation: .restoration)
        case .favicons:
            if model.isBrowserRunning {
                SyncNotice(browserName: browserName,
                           isBrowserRunning: true,
                           syncStatus: .disabled,
                           operation: .restoration)
            }
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
                Text(item.entry.date.formatted(date: .long, time: .shortened))
                Text("\(kindLabel) · \(countLabel) · \(sizeLabel)")
                    .font(.caption)
                    .foregroundStyle(item.count == .unreadable ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }

            Spacer()

            Button("Restaurer", action: onRestore)
                .disabled(!canRestore)

            Menu {
                Button("Afficher dans le Finder", action: onReveal)
                Button("Mettre à la corbeille", role: .destructive, action: onDelete)
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
        item.entry.kind == .beforeRestore ? "Avant restauration" : "Avant écriture"
    }

    private var countLabel: String {
        switch item.count {
        case .loading: "lecture…"
        case .value(let count): "\(count) \(item.entry.category.itemName)"
        case .unreadable: "illisible"
        }
    }

    private var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: item.entry.sizeBytes, countStyle: .file)
    }
}

#Preview { BackupsView(model: BackupsViewModel()) }
