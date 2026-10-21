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
            Text(verbatim: "Ghosts")
                .font(.largeTitle.bold())
                .foregroundStyle(
                    LinearGradient(colors: Self.gradient,
                                   startPoint: .leading, endPoint: .trailing)
                )
            Text("Spots bookmarks whose page no longer exists")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Dégradé propre à Ghosts : tons verts (lime → vert).
    private static let gradient = [Brand.lime, Brand.green]

    private func stats(_ report: GhostsReport) -> some View {
        HStack(spacing: 12) {
            StatCard(title: "Web bookmarks", value: report.webBookmarks, systemImage: "bookmark")
            StatCard(title: "Reachable", value: report.aliveCount,
                     systemImage: "checkmark.circle", tint: .green)
            StatCard(title: "Dead", value: report.dead.count,
                     systemImage: "xmark.circle", tint: .red)
            StatCard(title: "To check", value: report.uncertain.count,
                     systemImage: "questionmark.circle", tint: .orange)
        }
    }

    // MARK: - Zone centrale

    @ViewBuilder
    private var middle: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView(
                "Ready to hunt ghosts",
                systemImage: "eye.slash",
                description: Text("Navloom opens each bookmark to see whether its page still responds. The scan doesn't change anything: the browser can stay open. To delete bookmarks afterwards, the browser's bookmark sync must be turned off (as for Twins).")
            )
        case .scanning:
            scanningView
        case .done:
            if let report = model.report, report.dead.isEmpty, report.uncertain.isEmpty, report.moved.isEmpty {
                ContentUnavailableView("No ghosts", systemImage: "checkmark.seal",
                                       description: Text("All your bookmarks respond."))
            } else {
                resultsView
            }
        case .removing:
            ProgressView("Deleting bookmarks…")
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
                Text("Pass \(model.progressPass) · \(model.progressDone)/\(model.progressTotal)")
                Spacer()
                Text(verbatim: model.currentURL).lineLimit(1).truncationMode(.middle)
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
                Text("\(summary.removed) bookmarks deleted")
                    .font(.title2.bold())
                Button("Show Backup in Finder") { model.revealBackup() }
            }
            Text("Relaunch \(browserName) to see the result.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var resultsView: some View {
        VStack(spacing: 12) {
            SyncNotice(browserName: browserName,
                       isBrowserRunning: model.isBrowserRunning,
                       syncStatus: model.syncStatus,
                       operation: .removal(items: String(localized: "the dead links")))

            Picker("Results", selection: $model.selectedCategory) {
                ForEach(GhostsViewModel.Category.allCases) { category in
                    Text(verbatim: "\(category.title) (\(model.rows[category]?.count ?? 0))").tag(category)
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
                    Button("Open in Browser") { model.open(row) }
                    Button("Copy URL") { model.copyURL(row) }
                }
                .onTapGesture(count: 2) { model.open(row) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .overlay {
                if rows.isEmpty {
                    Text("No items").foregroundStyle(.secondary)
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
                Label("Google Account bookmarks (cloud icon) can't be checked: delete them by hand in \(browserName).",
                      systemImage: "icloud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button("Check All") { model.selectAll(in: category) }
                    .disabled(selectable == 0 || checked == selectable)
                Button("Uncheck All") { model.deselectAll(in: category) }
                    .disabled(checked == 0)
                Spacer()
                Text("\(model.selection.count) checked")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func hint(for category: GhostsViewModel.Category) -> String {
        switch category {
        case .dead:
            String(localized: "Page not found (404/410) or domain doesn't exist. Watch out: some sites answer 404 to visitors who aren't signed in even though the page exists for you. Double-click to open it and check before deleting.")
        case .uncertain:
            String(localized: "Timeout, server error, invalid certificate… No conclusion possible: check by hand.")
        case .moved:
            String(localized: "The page responds but redirects elsewhere (another site, or the home page). Often a link to update.")
        }
    }

    // MARK: - Barre d'action

    private var actionBar: some View {
        HStack {
            switch model.phase {
            case .scanning:
                Button("Stop") { model.cancelScan() }
            case .done:
                Button("Cancel") { model.reset() }
                if model.report != nil {
                    Button {
                        model.exportReport()
                    } label: {
                        Label("Export Report", systemImage: "square.and.arrow.up")
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
            Button("Find Dead Links") { model.scan() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.selectedProfile == nil)
        case .scanning:
            Button("Searching…") {}
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)
        case .done:
            Button("New Analysis") { model.scan() }
                .controlSize(.large)
            Button("Delete \(model.selection.count) bookmarks") {
                model.showConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(!model.canRemove)
        case .removing:
            Button("Deleting…") {}
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)
        case .removed:
            Button("New Analysis") { model.scan() }
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
                Toggle("Select", isOn: $isChecked)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
            } else {
                Image(systemName: "icloud")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .help("Google Account bookmark: delete it by hand in the browser")
            }

            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.url)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: row.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Label {
                    Text(verbatim: row.isLocal ? row.folder : String(localized: "Google Account · \(row.folder)"))
                } icon: {
                    Image(systemName: "folder")
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 12)

            // Le motif garde sa place : c'est l'URL qui se raccourcit en premier.
            Text(verbatim: row.detail)
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
