import SwiftUI

struct TwinsView: View {
    @Bindable var model: TwinsViewModel

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
        .diskAccessNotice()
        .navigationTitle("Navloom")
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
            "Supprimer \(model.selection.count) favori\(model.selection.count > 1 ? "s" : "") ?",
            isPresented: $model.showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) { model.removeSelected() }
        } message: {
            Text("Les favoris cochés seront retirés de \(browserName). Une sauvegarde du fichier Bookmarks est créée avant.")
        }
    }

    private var browserName: String {
        model.selectedBrowser?.name ?? "le navigateur"
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
            Text("Twins")
                .font(.largeTitle.bold())
                .foregroundStyle(
                    LinearGradient(colors: Self.gradient,
                                   startPoint: .leading, endPoint: .trailing)
                )
            Text("Retrouve les favoris qui pointent sur la même URL")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Dégradé propre à Twins (FaviconSync utilise corail → violet).
    private static let gradient = [Brand.sky, Brand.teal]

    private var stats: some View {
        HStack(spacing: 12) {
            StatCard(title: "Favoris", value: model.totalBookmarks, systemImage: "bookmark")
            StatCard(title: "URLs en double", value: model.groups.count,
                     systemImage: "square.on.square", tint: Brand.sky)
            StatCard(title: "Favoris en trop", value: model.extraCopies,
                     systemImage: "minus.circle", tint: .orange)
        }
    }

    // MARK: - Zone centrale

    @ViewBuilder
    private var middle: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView(
                "Prêt à chercher les doublons",
                systemImage: "square.on.square",
                description: Text("Navloom regroupe les favoris qui pointent exactement sur la même URL. L'analyse ne modifie rien.")
            )
        case .analyzing:
            ProgressView("Lecture des favoris…")
        case .done:
            if model.groups.isEmpty {
                ContentUnavailableView("Aucun doublon", systemImage: "checkmark.seal",
                                       description: Text("Aucune URL n'apparaît deux fois dans tes favoris."))
            } else {
                VStack(spacing: 12) {
                    SyncNotice(browserName: browserName,
                               isBrowserRunning: model.isBrowserRunning,
                               syncStatus: model.syncStatus,
                               operation: .removal(items: "les doublons"))
                    selectionToolbar
                    accountNote
                    groupsList
                }
            }
        case .removing:
            ProgressView("Suppression des doublons…")
        case .removed:
            removedView
        }
    }

    /// Rappel quand le profil contient des favoris du compte Google (Chrome) : visibles, mais pas cochables.
    @ViewBuilder
    private var accountNote: some View {
        if model.accountBookmarkCount > 0 {
            Label("\(model.accountBookmarkCount) favori\(model.accountBookmarkCount > 1 ? "s" : "") du compte Google (icône nuage) : ils ne sont pas cochables, supprime-les à la main dans \(browserName). Une copie du compte protège son groupe : les copies locales peuvent toutes être cochées.",
                  systemImage: "icloud")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Ligne d'outils au-dessus de la liste : raccourcis de sélection à gauche, compteur à droite.
    private var selectionToolbar: some View {
        HStack(spacing: 10) {
            Button("Garder le premier de chaque groupe") { model.selectAllButFirst() }
            Button("Tout décocher") { model.clearSelection() }
                .disabled(model.selection.isEmpty)
            Spacer()
            Text("\(model.selection.count) coché\(model.selection.count > 1 ? "s" : "")")
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
                Text("\(summary.removed) favori\(summary.removed > 1 ? "s" : "") supprimé\(summary.removed > 1 ? "s" : "")")
                    .font(.title2.bold())
                Button("Afficher la sauvegarde dans le Finder") { model.revealBackup() }
            }
            Text("Relance \(browserName) pour voir le résultat.")
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
                        Text(group.url)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("\(group.bookmarks.count) favoris")
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
                Button("Annuler") { model.reset() }
            }

            Spacer()

            primaryActions
        }
    }

    @ViewBuilder
    private var primaryActions: some View {
        switch model.phase {
        case .done where !model.groups.isEmpty:
            Button("Nouvelle analyse") { model.analyze() }
                .controlSize(.large)
            Button("Supprimer \(model.selection.count) favori\(model.selection.count > 1 ? "s" : "")") {
                model.showConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(!model.canRemove)
        case .done, .removed:
            Button("Nouvelle analyse") { model.analyze() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .removing:
            Button("Suppression en cours…") {}
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)
        case .idle, .analyzing:
            Button("Chercher les doublons") { model.analyze() }
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
        let folder = bookmark.folder.isEmpty ? "Racine" : bookmark.folder
        return bookmark.source == .account ? "Compte Google · \(folder)" : folder
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(bookmark.name).lineLimit(1)
            Label(folderLabel, systemImage: "folder")
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
            .help("Favori du compte Google : à supprimer à la main dans le navigateur")
        }
    }
}

#Preview {
    TwinsView(model: TwinsViewModel())
}
