import SwiftUI
import AppKit

struct FaviconSyncView: View {
    @State private var model = FaviconSyncViewModel()

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
        .navigationTitle("FaviconSync")
        .task { model.loadBrowsers() }
        .onChange(of: model.selectedBrowserID) { model.browserChanged() }
        .onChange(of: model.selectedProfileID) { model.reset() }
        // Tant qu'on attend le feu vert pour écrire, on surveille si le navigateur est fermé.
        .task(id: model.phase) {
            guard model.phase == .fetched else { return }
            while !Task.isCancelled {
                model.refreshBrowserRunning()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Structure

    private var content: some View {
        VStack(spacing: 16) {
            header

            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let analysis = model.analysis {
                stats(analysis)
            }

            middle
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            actionBar
        }
        .padding(20)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Picker("Navigateur", selection: $model.selectedBrowserID) {
                ForEach(model.browsers) { browser in
                    Text(browser.name).tag(Optional(browser.id))
                }
            }
            .frame(maxWidth: 260)

            if model.profiles.count > 1 {
                Picker("Profil", selection: $model.selectedProfileID) {
                    ForEach(model.profiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                .frame(maxWidth: 220)
            }
            Spacer()
        }
        .disabled(model.isBusy)
    }

    private func stats(_ analysis: SyncAnalysis) -> some View {
        HStack(spacing: 12) {
            StatCard(title: "Favoris web", value: analysis.webBookmarks, systemImage: "bookmark")
            StatCard(title: "Avec favicon", value: analysis.withFaviconCount,
                     systemImage: "checkmark.circle", tint: .green)
            StatCard(title: "Sans favicon", value: analysis.missing.count,
                     systemImage: "questionmark.circle", tint: .orange)
        }
    }

    // MARK: - Zone centrale selon l'étape

    @ViewBuilder
    private var middle: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView(
                "Prêt à analyser",
                systemImage: "star.square",
                description: Text("Navloom compare tes favoris aux favicons déjà connues du navigateur. L'analyse ne modifie rien.")
            )
        case .analyzing:
            ProgressView("Lecture des favoris…")
        case .analyzed:
            if let analysis = model.analysis, analysis.missing.isEmpty {
                ContentUnavailableView("Tout est en ordre", systemImage: "checkmark.seal",
                                       description: Text("Tous tes favoris ont déjà une favicon."))
            } else {
                Spacer()
            }
        case .fetching:
            fetchingView
        case .fetched, .writing:
            resultsView
        case .done:
            doneView
        }
    }

    private var fetchingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer()
            ProgressView(value: Double(model.progressDone), total: Double(max(model.progressTotal, 1)))
            HStack {
                Text("Passage \(model.progressPass) · \(model.progressDone)/\(model.progressTotal)")
                Spacer()
                Text(model.currentOrigin).lineLimit(1).truncationMode(.middle)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var resultsView: some View {
        VStack(spacing: 12) {
            if model.phase == .fetched { writeNotice }

            Picker("", selection: $model.selectedCategory) {
                ForEach(FaviconSyncViewModel.ResultCategory.allCases) { category in
                    Text("\(category.rawValue) (\(model.rows[category]?.count ?? 0))").tag(category)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            let rows = model.rows[model.selectedCategory] ?? []
            List(rows) { row in
                ResultRowView(row: row)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .overlay {
                if rows.isEmpty {
                    Text("Aucun élément").foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Bandeau affiché avant l'écriture : avertissement si le navigateur est ouvert, sinon rappel de la sauvegarde.
    @ViewBuilder
    private var writeNotice: some View {
        if model.isBrowserRunning {
            Label("\(model.selectedBrowser?.name ?? "Le navigateur") est ouvert. Ferme-le complètement (Cmd + Q) pour pouvoir écrire.",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        } else {
            Label("Une sauvegarde de la base sera créée automatiquement avant l'écriture.",
                  systemImage: "externaldrive")
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var doneView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            if let summary = model.summary {
                Text("\(summary.success) favicons ajoutées")
                    .font(.title2.bold())
                Text("\(summary.uniqueIcons) icônes uniques · \(summary.failure) échec(s)")
                    .foregroundStyle(.secondary)

                if summary.backupURL != nil {
                    Button("Afficher la sauvegarde dans le Finder") { model.revealBackup() }
                }
            }
            Text("Relance \(model.selectedBrowser?.name ?? "le navigateur") pour voir les nouvelles icônes.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Barre d'action

    private var actionBar: some View {
        HStack {
            if model.phase == .analyzed || model.phase == .fetched {
                Button("Annuler") { model.reset() }
            }
            Spacer()
            primaryAction
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch model.phase {
        case .idle:
            Button("Analyser") { model.analyze() }
                .disabled(model.selectedProfile == nil)
        case .analyzing:
            Button("Analyse en cours…") {}.disabled(true)
        case .analyzed:
            if let analysis = model.analysis, !analysis.missing.isEmpty {
                Button("Chercher \(analysis.missing.count) favicons") { model.fetch() }
            }
        case .fetching:
            Button("Recherche en cours…") {}.disabled(true)
        case .fetched:
            Button("Appliquer à \(model.selectedBrowser?.name ?? "la base")") { model.apply() }
                .disabled(model.isBrowserRunning || (model.fetchResult?.fetched.isEmpty ?? true))
        case .writing:
            Button("Écriture en cours…") {}.disabled(true)
        case .done:
            Button("Nouvelle analyse") { model.analyze() }
        }
    }
}

// MARK: - Sous-vues

private struct StatCard: View {
    let title: String
    let value: Int
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(.title2.bold().monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ResultRowView: View {
    let row: FaviconSyncViewModel.ResultRow

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.name).lineLimit(1)
                Text(row.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)

            if let detail = row.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 260, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var icon: some View {
        if let data = row.iconData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Image(systemName: "questionmark.square.dashed")
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    FaviconSyncView()
}
