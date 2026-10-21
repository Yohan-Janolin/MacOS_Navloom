import SwiftUI
import AppKit

struct FaviconSyncView: View {
    @Bindable var model: FaviconSyncViewModel

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

            if let analysis = model.analysis {
                stats(analysis)
            }

            middle
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            actionBar
        }
        .padding(20)
    }

    private var titleHeader: some View {
        VStack(spacing: 4) {
            Text(verbatim: "FaviconSync")
                .font(.largeTitle.bold())
                .foregroundStyle(
                    LinearGradient(colors: [Brand.coral, Brand.pink],
                                   startPoint: .leading, endPoint: .trailing)
                )
            Text("Finds the missing favicons of your bookmarks")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func stats(_ analysis: SyncAnalysis) -> some View {
        HStack(spacing: 12) {
            StatCard(title: "Web bookmarks", value: analysis.webBookmarks, systemImage: "bookmark")
            StatCard(title: "With favicon", value: analysis.withFaviconCount,
                     systemImage: "checkmark.circle", tint: .green)
            StatCard(title: "Without favicon", value: analysis.missing.count,
                     systemImage: "questionmark.circle", tint: .orange)
        }
    }

    // MARK: - Zone centrale selon l'étape

    @ViewBuilder
    private var middle: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView(
                "Ready to analyze",
                systemImage: "star.square",
                description: Text("Navloom compares your bookmarks with the favicons the browser already knows. The analysis doesn't change anything.")
            )
        case .analyzing:
            ProgressView("Reading bookmarks…")
        case .analyzed:
            if let analysis = model.analysis, analysis.missing.isEmpty {
                ContentUnavailableView("Everything is in order", systemImage: "checkmark.seal",
                                       description: Text("All your bookmarks already have a favicon."))
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
        VStack(alignment: .leading, spacing: 10) {
            Spacer()
            ThickProgressBar(value: Double(model.progressDone),
                             total: Double(max(model.progressTotal, 1)))
            HStack {
                Text("Pass \(model.progressPass) · \(model.progressDone)/\(model.progressTotal)")
                Spacer()
                Text(model.currentOrigin).lineLimit(1).truncationMode(.middle)
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var resultsView: some View {
        VStack(spacing: 12) {
            if model.phase == .fetched { writeNotice }

            Picker("Results", selection: $model.selectedCategory) {
                ForEach(FaviconSyncViewModel.ResultCategory.allCases) { category in
                    Text(verbatim: "\(category.title) (\(model.rows[category]?.count ?? 0))").tag(category)
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
                    Text("No items").foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Bandeau affiché avant l'écriture : avertissement si le navigateur est ouvert, sinon rappel de la sauvegarde.
    @ViewBuilder
    private var writeNotice: some View {
        if model.isBrowserRunning {
            let name = model.selectedBrowser?.name ?? String(localized: "The browser")
            Label("\(name) is open. Quit it completely (Cmd + Q) to be able to write.",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        } else {
            Label("A backup of the database will be created automatically before writing.",
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
                Text("\(summary.success) favicons added")
                    .font(.title2.bold())
                Text("\(summary.uniqueIcons) unique icons · \(summary.failure) failure(s)")
                    .foregroundStyle(.secondary)

                if summary.backupURL != nil {
                    Button("Show Backup in Finder") { model.revealBackup() }
                }
            }
            let name = model.selectedBrowser?.name ?? String(localized: "the browser")
            Text("Relaunch \(name) to see the new icons.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Barre d'action

    private var actionBar: some View {
        HStack {
            if model.phase == .analyzed || model.phase == .fetched {
                Button("Cancel") { model.reset() }
            }

            if model.fetchResult != nil, model.phase == .fetched || model.phase == .done {
                Button {
                    model.exportReport()
                } label: {
                    Label("Export Report", systemImage: "square.and.arrow.up")
                }
            }

            Spacer()
            if model.phase == .fetched {
                Button {
                    model.analyze()
                } label: {
                    Label("Analyze Again", systemImage: "arrow.clockwise")
                }
                .controlSize(.large)
            }
            primaryAction
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch model.phase {
        case .idle:
            Button("Analyze") { model.analyze() }
                .disabled(model.selectedProfile == nil)
        case .analyzing:
            Button("Analyzing…") {}.disabled(true)
        case .analyzed:
            if let analysis = model.analysis, !analysis.missing.isEmpty {
                Button("Find \(analysis.missing.count) favicons") { model.fetch() }
            }
        case .fetching:
            Button("Searching…") {}.disabled(true)
        case .fetched:
            let target = model.selectedBrowser?.name ?? String(localized: "the database")
            Button("Apply to \(target)") { model.apply() }
                .disabled(model.isBrowserRunning || (model.fetchResult?.fetched.isEmpty ?? true))
        case .writing:
            Button("Writing…") {}.disabled(true)
        case .done:
            Button("New Analysis") { model.analyze() }
        }
    }
}

// MARK: - Sous-vues

private struct ResultRowView: View {
    let row: FaviconSyncViewModel.ResultRow

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: row.name).lineLimit(1)
                Text(verbatim: row.url)
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
    FaviconSyncView(model: FaviconSyncViewModel())
}
