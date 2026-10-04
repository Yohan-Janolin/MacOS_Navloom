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
        .navigationTitle("Navloom")
        .task { model.loadBrowsersIfNeeded() }
        .onChange(of: model.selectedBrowserID) { model.browserChanged() }
        .onChange(of: model.selectedProfileID) { model.reset() }
    }

    // MARK: - Structure

    private var content: some View {
        VStack(spacing: 16) {
            titleHeader

            BrowserProfileBanner(browsers: model.browsers,
                                 profiles: model.profiles,
                                 browserID: $model.selectedBrowserID,
                                 profileID: $model.selectedProfileID)
                .disabled(model.isBusy)

            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let report = model.report {
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
                    LinearGradient(colors: [Brand.violet, Brand.pink],
                                   startPoint: .leading, endPoint: .trailing)
                )
            Text("Repère les favoris dont la page n'existe plus")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func stats(_ report: GhostsReport) -> some View {
        HStack(spacing: 12) {
            GhostStatCard(title: "Favoris web", value: report.webBookmarks, systemImage: "bookmark")
            GhostStatCard(title: "Accessibles", value: report.aliveCount,
                          systemImage: "checkmark.circle", tint: .green)
            GhostStatCard(title: "Morts", value: report.dead.count,
                          systemImage: "xmark.circle", tint: .red)
            GhostStatCard(title: "À vérifier", value: report.uncertain.count,
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
                description: Text("Navloom ouvre chaque favori pour voir si sa page répond encore. Rien n'est modifié : le navigateur peut rester ouvert.")
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

    private var resultsView: some View {
        VStack(spacing: 12) {
            Picker("", selection: $model.selectedCategory) {
                ForEach(GhostsViewModel.Category.allCases) { category in
                    Text("\(category.rawValue) (\(model.rows[category]?.count ?? 0))").tag(category)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(hint(for: model.selectedCategory))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            let rows = model.rows[model.selectedCategory] ?? []
            List(rows) { row in
                GhostRowView(row: row, category: model.selectedCategory)
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

    private func hint(for category: GhostsViewModel.Category) -> String {
        switch category {
        case .dead:
            "Page introuvable (404/410) ou domaine inexistant. Double-clic pour ouvrir le lien et vérifier."
        case .uncertain:
            "Délai dépassé, erreur serveur, certificat invalide… Impossible de conclure : à contrôler à la main."
        case .moved:
            "La page répond mais renvoie ailleurs (autre site, ou page d'accueil). Souvent un lien à mettre à jour."
        }
    }

    // MARK: - Barre d'action

    private var actionBar: some View {
        HStack {
            if model.report != nil, model.phase == .done {
                Button {
                    model.exportReport()
                } label: {
                    Label("Exporter le rapport", systemImage: "square.and.arrow.up")
                }
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
            Button("Rechercher les liens morts") { model.scan() }
                .disabled(model.selectedProfile == nil)
        case .scanning:
            Button("Recherche en cours…") {}.disabled(true)
        case .done:
            Button("Nouvelle recherche") { model.scan() }
        }
    }
}

// MARK: - Sous-vues

private struct GhostStatCard: View {
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

private struct GhostRowView: View {
    let row: GhostsViewModel.Row
    let category: GhostsViewModel.Category

    var body: some View {
        HStack(spacing: 10) {
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
            }
            Spacer(minLength: 12)

            Text(row.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 260, alignment: .trailing)
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