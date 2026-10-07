import SwiftUI
import AppKit

struct GhostsView: View {
    @Bindable var model: GhostsViewModel

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

            if let report = model.report, model.phase == .done || model.phase == .removing {
                stats(report)
            }

            middle
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            actionBar
        }
        .padding(20)
    }

    private var titleHeader: some View {
        VStack(spacing: 4) {
            Text("Ghosts")
                .font(.largeTitle.bold())
                .foregroundStyle(
                    LinearGradient(colors: Self.gradient,
                                   startPoint: .leading, endPoint: .trailing)
                )
            Text("Repère les favoris dont la page n'existe plus")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Dégradé propre à Ghosts : tons verts (lime → vert).
    private static let gradient = [Brand.lime, Brand.green]

    private func stats(_ report: GhostsReport) -> some View {
        HStack(spacing: 12) {
            StatCard(title: "Favoris web", value: report.webBookmarks, systemImage: "bookmark")
            StatCard(title: "Accessibles", value: report.aliveCount,
                     systemImage: "checkmark.circle", tint: .green)
            StatCard(title: "Morts", value: report.dead.count,
                     systemImage: "xmark.circle", tint: .red)
            StatCard(title: "À vérifier", value: report.uncertain.count,
                     systemImage: "questionmark.circle", tint: .orange)
        }
    }

    // MARK: - Zone centrale

    @ViewBuilder
    private var middle: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView(
                "Prêt à chasser les fantômes",
                systemImage: "eye.slash",
                description: Text("Navloom ouvre chaque favori pour voir si sa page répond encore. La recherche ne modifie rien : le navigateur peut rester ouvert. Pour supprimer ensuite des favoris, la synchro des favoris du navigateur doit être désactivée (comme pour Twins).")
            )
        case .scanning:
            scanningView
        case .done:
            if let report = model.report, report.dead.isEmpty, report.uncertain.isEmpty, report.moved.isEmpty {
                ContentUnavailableView("Aucun fantôme", systemImage: "checkmark.seal",
                                       description: Text("Tous tes favoris répondent."))
            } else {
                resultsView
            }
        case .removing:
            ProgressView("Suppression des favoris…")
        case .removed:
            removedView
        }
    }

    private var scanningView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer()
            ThickProgressBar(value: Double(model.progressDone),
                             total: Double(max(model.progressTotal, 1)))
            HStack {
                Text("Passage \(model.progressPass) · \(model.progressDone)/\(model.progressTotal)")
                Spacer()
                Text(model.currentURL).lineLimit(1).truncationMode(.middle)
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
            Spacer()
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

    private var resultsView: some View {
        VStack(spacing: 12) {
            SyncNotice(browserName: browserName,
                       isBrowserRunning: model.isBrowserRunning,
                       syncStatus: model.syncStatus,
                       operation: .removal(items: "les liens morts"))

            Picker("", selection: $model.selectedCategory) {
                ForEach(GhostsViewModel.Category.allCases) { category in
                    Text("\(category.rawValue) (\(model.rows[category]?.count ?? 0))").tag(category)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            selectionToolbar

            let rows = model.rows[model.selectedCategory] ?? []
            List(rows) { row in
                GhostRowView(
                    row: row,
                    category: model.selectedCategory,
                    isChecked: Binding(
                        get: { model.isSelected(row) },
                        set: { _ in model.toggle(row) }
                    )
                )
                .contextMenu {
                    Button("Ouvrir dans le navigateur") { model.open(row) }
                    Button("Copier l'URL") { model.copyURL(row) }
                }
                .onTapGesture(count: 2) { model.open(row) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .overlay {
                if rows.isEmpty {
                    Text("Aucun élément").foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Explication de l'onglet, puis raccourcis de sélection (qui agissent sur l'onglet affiché) et compteur.
    private var selectionToolbar: some View {
        let category = model.selectedCategory
        let selectable = model.selectableCount(in: category)
        let checked = model.checkedCount(in: category)
        let hasAccountRows = model.rows[category]?.contains { !$0.isLocal } ?? false

        return VStack(spacing: 8) {
            Text(hint(for: category))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hasAccountRows {
                Label("Les favoris du compte Google (icône nuage) ne sont pas cochables : supprime-les à la main dans \(browserName).",
                      systemImage: "icloud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button("Tout cocher") { model.selectAll(in: category) }
                    .disabled(selectable == 0 || checked == selectable)
                Button("Tout décocher") { model.deselectAll(in: category) }
                    .disabled(checked == 0)
                Spacer()
                Text("\(model.selection.count) coché\(model.selection.count > 1 ? "s" : "")")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func hint(for category: GhostsViewModel.Category) -> String {
        switch category {
        case .dead:
            "Page introuvable (404/410) ou domaine inexistant. Attention : certains sites répondent 404 aux visiteurs non connectés alors que la page existe pour toi. Double-clic pour l'ouvrir et vérifier avant de supprimer."
        case .uncertain:
            "Délai dépassé, erreur serveur, certificat invalide… Impossible de conclure : à contrôler à la main."
        case .moved:
            "La page répond mais renvoie ailleurs (autre site, ou page d'accueil). Souvent un lien à mettre à jour."
        }
    }

    // MARK: - Barre d'action

    private var actionBar: some View {
        HStack {
            switch model.phase {
            case .scanning:
                Button("Arrêter") { model.cancelScan() }
            case .done:
                Button("Annuler") { model.reset() }
                if model.report != nil {
                    Button {
                        model.exportReport()
                    } label: {
                        Label("Exporter le rapport", systemImage: "square.and.arrow.up")
                    }
                }
            default:
                EmptyView()
            }

            Spacer()

            primaryActions
        }
    }

    @ViewBuilder
    private var primaryActions: some View {
        switch model.phase {
        case .idle:
            Button("Rechercher les liens morts") { model.scan() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.selectedProfile == nil)
        case .scanning:
            Button("Recherche en cours…") {}
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)
        case .done:
            Button("Nouvelle analyse") { model.scan() }
                .controlSize(.large)
            Button("Supprimer \(model.selection.count) favori\(model.selection.count > 1 ? "s" : "")") {
                model.showConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(!model.canRemove)
        case .removing:
            Button("Suppression en cours…") {}
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)
        case .removed:
            Button("Nouvelle analyse") { model.scan() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}

// MARK: - Ligne d'un résultat

private struct GhostRowView: View {
    let row: GhostsViewModel.Row
    let category: GhostsViewModel.Category
    @Binding var isChecked: Bool

    var body: some View {
        HStack(spacing: 10) {
            // La case est séparée du texte : un double-clic sur la ligne ouvre le lien sans cocher.
            // Un favori du compte Google n'a pas de case : Chrome le remettrait depuis le serveur.
            if row.isLocal {
                Toggle("", isOn: $isChecked)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
            } else {
                Image(systemName: "icloud")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .help("Favori du compte Google : à supprimer à la main dans le navigateur")
            }

            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.url)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(row.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Label(row.isLocal ? row.folder : "Compte Google · \(row.folder)", systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 12)

            // Le motif garde sa place : c'est l'URL qui se raccourcit en premier.
            Text(row.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 300, alignment: .trailing)
                .layoutPriority(1)
        }
        .padding(.vertical, 2)
    }

    private var symbol: String {
        switch category {
        case .dead: "xmark.circle.fill"
        case .uncertain: "questionmark.circle.fill"
        case .moved: "arrow.turn.up.right.circle.fill"
        }
    }

    private var tint: Color {
        switch category {
        case .dead: .red
        case .uncertain: .orange
        case .moved: Brand.sky
        }
    }
}

#Preview {
    GhostsView(model: GhostsViewModel())
}
