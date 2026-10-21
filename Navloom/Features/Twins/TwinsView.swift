import SwiftUI

struct TwinsView: View {
    @Bindable var model: TwinsViewModel

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
        .navigationTitle(Text(verbatim: "Navloom"))
        .task { model.loadBrowsersIfNeeded() }
        .onChange(of: model.selectedBrowserID) { model.browserChanged() }
        .onChange(of: model.selectedProfileID) { model.reset() }
        // Tant qu'on peut supprimer, on surveille si le navigateur est fermé.
        .task(id: model.phase) {
            guard model.phase == .done else { return }
            while !Task.isCancelled {
                model.refreshBrowserRunning()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .confirmationDialog(
            "Delete \(model.selection.count) bookmarks?",
            isPresented: $model.showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { model.removeSelected() }
        } message: {
            Text("The checked bookmarks will be removed from \(browserName). A backup of the Bookmarks file is created beforehand.")
        }
    }

    private var browserName: String {
        model.selectedBrowser?.name ?? String(localized: "the browser")
    }

    // MARK: - Structure

    private var content: some View {
        VStack(spacing: 16) {
            titleHeader
            BrowserProfileBanner(browsers: model.browsers,
                                 profiles: model.profiles,
                                 browserID: $model.selectedBrowserID,
                                 profileID: $model.selectedProfileID,
                                 colors: Self.gradient)
                .disabled(model.isBusy)

            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if model.phase == .done || model.phase == .removing {
                stats
            }

            middle
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            actionBar
        }
        .padding(20)
    }

    private var titleHeader: some View {
        VStack(spacing: 4) {
            Text(verbatim: "Twins")
                .font(.largeTitle.bold())
                .foregroundStyle(
                    LinearGradient(colors: Self.gradient,
                                   startPoint: .leading, endPoint: .trailing)
                )
            Text("Finds bookmarks pointing to the same URL")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Dégradé propre à Twins (FaviconSync utilise corail → violet).
    private static let gradient = [Brand.sky, Brand.teal]

    private var stats: some View {
        HStack(spacing: 12) {
            StatCard(title: "Bookmarks", value: model.totalBookmarks, systemImage: "bookmark")
            StatCard(title: "Duplicate URLs", value: model.groups.count,
                     systemImage: "square.on.square", tint: Brand.sky)
            StatCard(title: "Extra bookmarks", value: model.extraCopies,
                     systemImage: "minus.circle", tint: .orange)
        }
    }

    // MARK: - Zone centrale

    @ViewBuilder
    private var middle: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView(
                "Ready to find duplicates",
                systemImage: "square.on.square",
                description: Text("Navloom groups the bookmarks pointing to exactly the same URL. The analysis doesn't change anything.")
            )
        case .analyzing:
            ProgressView("Reading bookmarks…")
        case .done:
            if model.groups.isEmpty {
                ContentUnavailableView("No duplicates", systemImage: "checkmark.seal",
                                       description: Text("No URL appears twice in your bookmarks."))
            } else {
                VStack(spacing: 12) {
                    SyncNotice(browserName: browserName,
                               isBrowserRunning: model.isBrowserRunning,
                               syncStatus: model.syncStatus,
                               operation: .removal(items: String(localized: "the duplicates")))
                    selectionToolbar
                    accountNote
                    groupsList
                }
            }
        case .removing:
            ProgressView("Deleting duplicates…")
        case .removed:
            removedView
        }
    }

    /// Rappel quand le profil contient des favoris du compte Google (Chrome) : visibles, mais pas cochables.
    @ViewBuilder
    private var accountNote: some View {
        if model.accountBookmarkCount > 0 {
            Label("\(model.accountBookmarkCount) Google Account bookmarks (cloud icon): they can't be checked, delete them by hand in \(browserName). An account copy protects its group: the local copies can all be checked.",
                  systemImage: "icloud")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Ligne d'outils au-dessus de la liste : raccourcis de sélection à gauche, compteur à droite.
    private var selectionToolbar: some View {
        HStack(spacing: 10) {
            Button("Keep the First of Each Group") { model.selectAllButFirst() }
            Button("Uncheck All") { model.clearSelection() }
                .disabled(model.selection.isEmpty)
            Spacer()
            Text("\(model.selection.count) checked")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var removedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            if let summary = model.summary {
                Text("\(summary.removed) bookmarks deleted")
                    .font(.title2.bold())
                Button("Show Backup in Finder") { model.revealBackup() }
            }
            Text("Relaunch \(browserName) to see the result.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var groupsList: some View {
        List {
            ForEach(model.groups) { group in
                Section {
                    ForEach(group.bookmarks, id: \.self) { bookmark in
                        TwinRow(
                            bookmark: bookmark,
                            isChecked: Binding(
                                get: { model.isSelected(bookmark) },
                                set: { _ in model.toggle(bookmark) }
                            )
                        )
                        // Au moins une copie reste décochée : la dernière case libre d'un groupe est grisée.
                        .disabled(isLocked(bookmark, in: group))
                    }
                } header: {
                    HStack {
                        Text(verbatim: group.url)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("\(group.bookmarks.count) bookmarks")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .textCase(nil)
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    /// Vrai si cocher ce favori ferait disparaître la dernière copie de son groupe.
    private func isLocked(_ bookmark: Bookmark, in group: DuplicateGroup) -> Bool {
        guard bookmark.source == .local, !model.isSelected(bookmark) else { return false }
        let uncheckedCount = group.bookmarks.filter { !model.isSelected($0) }.count
        return uncheckedCount == 1
    }

    // MARK: - Barre d'action

    private var actionBar: some View {
        HStack {
            if model.phase == .done {
                Button("Cancel") { model.reset() }
            }

            Spacer()

            primaryActions
        }
    }

    @ViewBuilder
    private var primaryActions: some View {
        switch model.phase {
        case .done where !model.groups.isEmpty:
            Button("New Analysis") { model.analyze() }
                .controlSize(.large)
            Button("Delete \(model.selection.count) bookmarks") {
                model.showConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(!model.canRemove)
        case .done, .removed:
            Button("New Analysis") { model.analyze() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .removing:
            Button("Deleting…") {}
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)
        case .idle, .analyzing:
            Button("Find Duplicates") { model.analyze() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.selectedProfile == nil || model.isBusy)
        }
    }
}

// MARK: - Sous-vues

private struct TwinRow: View {
    let bookmark: Bookmark
    @Binding var isChecked: Bool

    private var folderLabel: String {
        let folder = bookmark.folder.isEmpty ? String(localized: "Root") : bookmark.folder
        return bookmark.source == .account ? String(localized: "Google Account · \(folder)") : folder
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: bookmark.name).lineLimit(1)
            Label { Text(verbatim: folderLabel) } icon: { Image(systemName: "folder") }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
    }

    var body: some View {
        if bookmark.source == .local {
            Toggle(isOn: $isChecked) { details }
                .toggleStyle(.checkbox)
                .padding(.vertical, 2)
        } else {
            // Favori du compte Google : pas de case, Chrome le remettrait depuis le serveur.
            HStack(spacing: 6) {
                Image(systemName: "icloud")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                details
            }
            .padding(.vertical, 2)
            .help("Google Account bookmark: delete it by hand in the browser")
        }
    }
}

#Preview {
    TwinsView(model: TwinsViewModel())
}
