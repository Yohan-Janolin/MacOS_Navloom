import SwiftUI

struct EchoView: View {
    @Bindable var model: EchoViewModel

    /// Dégradé propre à Echo : jaune → corail. La destination l'inverse, pour la distinguer de la source.
    private static let sourceGradient = [Brand.gold, Brand.coral]
    private static let destinationGradient = [Brand.coral, Brand.gold]

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
        .onChange(of: model.selectedProfileID) { model.profileChanged() }
        .onChange(of: model.destinationBrowserID) { model.destinationBrowserChanged() }
        .onChange(of: model.destinationProfileID) { model.destinationProfileChanged() }
        .onChange(of: model.syncMode) { model.reset() }
        .onChange(of: model.matchMode) { model.reset() }
        .onChange(of: model.urlOptions) { model.reset() }
        // Tant qu'on peut ajouter, on surveille si la destination est fermée.
        .task(id: model.phase) {
            guard model.phase == .done else { return }
            while !Task.isCancelled {
                model.refreshDestinationRunning()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: $model.showConfirmation,
            titleVisibility: .visible
        ) {
            switch model.syncMode {
            case .merge:
                Button("Add") { model.apply() }
            case .mirror:
                Button("Replace with the Copy", role: .destructive) { model.apply() }
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var destinationBrowserName: String {
        model.report?.destination.browserName ?? model.destinationBrowser?.name ?? String(localized: "the target")
    }

    private var destinationLabel: String {
        guard let destination = model.report?.destination else { return String(localized: "the target") }
        return "\(destination.browserName) · \(destination.name)"
    }

    private var confirmationTitle: String {
        switch model.syncMode {
        case .merge:
            let count = model.report?.plan.toAdd.count ?? 0
            return String(localized: "Add \(count) bookmarks to \(destinationBrowserName)?")
        case .mirror:
            return String(localized: "Replace the bookmarks of \(destinationBrowserName) with those of the source?")
        }
    }

    private var confirmationMessage: String {
        switch model.syncMode {
        case .merge:
            return String(localized: "The bookmarks will be added to \(destinationLabel). No bookmark is deleted or modified. Backups are created beforehand.")
        case .mirror:
            guard let mirror = model.report?.mirror else { return "" }
            let label = destinationLabel
            let added = String(localized: "\(mirror.toAdd.count) bookmarks added")
            let removed = String(localized: "\(mirror.removalCount) deleted")
            let folders = String(localized: "(and \(mirror.foldersToRemove) folders)")
            return String(localized: "\(label) will become identical to the source: \(added), \(removed) \(folders). Backups are created beforehand: you'll be able to roll back from the Backups screen.")
        }
    }

    // MARK: - Structure

    /// Echo est l'écran le plus haut : sans défilement, sa hauteur minimale dépasserait celle de la
    /// fenêtre et SwiftUI la viderait entièrement (barre latérale comprise). Le contenu défile donc
    /// quand la fenêtre est basse, et remplit toute la hauteur quand elle est assez grande.
    private var content: some View {
        GeometryReader { proxy in
            ScrollView {
                page
                    .frame(minHeight: proxy.size.height)
            }
        }
    }

    private var page: some View {
        VStack(spacing: 16) {
            titleHeader
            browserRows

            // Une fois la comparaison faite, ces réglages laissent la place aux résultats ;
            // changer la source, la destination ou « Annuler » les ramène.
            if model.phase == .idle || model.phase == .comparing {
                comparisonSettings
            }

            if model.isSameProfile && model.phase == .idle {
                Label("The source and the target are the same profile: choose another one.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let report = model.report, model.phase == .done || model.phase == .applying {
                stats(report)
            }

            middle
                .frame(maxWidth: .infinity, minHeight: 240, maxHeight: .infinity)

            actionBar
        }
        .padding(20)
    }

    private var titleHeader: some View {
        VStack(spacing: 4) {
            Text(verbatim: "Echo")
                .font(.largeTitle.bold())
                .foregroundStyle(
                    LinearGradient(colors: Self.sourceGradient,
                                   startPoint: .leading, endPoint: .trailing)
                )
            Text("Replicates the bookmarks of one browser to another")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Deux bandeaux : d'où viennent les favoris, et où ils iraient.
    private var browserRows: some View {
        VStack(spacing: 10) {
            BrowserProfileBanner(browsers: model.browsers,
                                 profiles: model.profiles,
                                 browserID: $model.selectedBrowserID,
                                 profileID: $model.selectedProfileID,
                                 browserTitle: "Source browser",
                                 colors: Self.sourceGradient)
            BrowserProfileBanner(browsers: model.browsers,
                                 profiles: model.destinationProfiles,
                                 browserID: $model.destinationBrowserID,
                                 profileID: $model.destinationProfileID,
                                 browserTitle: "Target browser",
                                 colors: Self.destinationGradient)
        }
        .disabled(model.isBusy)
    }

    /// Que faire dans la cible, et (pour l'ajout) comment comparer : dans un cadre gris.
    private var comparisonSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Mode", selection: $model.syncMode) {
                ForEach(EchoSyncMode.allCases) { mode in
                    Text(verbatim: mode.shortTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 380)

            switch model.syncMode {
            case .merge:
                // Le critère et les variantes d'URL sur une ligne.
                HStack(spacing: 14) {
                    modePicker
                    Divider().frame(height: 20)
                    urlToggles
                    Spacer(minLength: 0)
                }

                Text("\(model.syncMode.hint) \(model.matchMode.hint) Checked boxes make these URL variants count as identical; the trailing “/” always does. Careful with parameters (?…): if the page depends on them (a video, an article…), different bookmarks would be merged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .mirror:
                Label { Text(verbatim: model.syncMode.hint) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .disabled(model.isBusy)
    }

    private var modePicker: some View {
        Picker("Comparison", selection: $model.matchMode) {
            ForEach(EchoMatchMode.allCases) { mode in
                Text(verbatim: mode.title).tag(mode)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }

    /// Variantes d'URL à traiter comme identiques.
    private var urlToggles: some View {
        HStack(spacing: 16) {
            Toggle(isOn: $model.ignoreScheme) { Text(verbatim: "http/https") }
            Toggle(isOn: $model.ignoreWWW) { Text(verbatim: "www") }
            Toggle("parameters ?…", isOn: $model.ignoreQuery)
        }
        .toggleStyle(.checkbox)
        .lineLimit(1)
    }

    private func stats(_ report: EchoReport) -> some View {
        HStack(spacing: 12) {
            StatCard(title: "Source bookmarks", value: report.sourceCount,
                     systemImage: "bookmark")
            switch model.syncMode {
            case .merge:
                StatCard(title: "To add", value: report.plan.toAdd.count,
                         systemImage: "plus.circle", tint: Brand.gold)
                StatCard(title: "Already present", value: report.plan.alreadyPresent,
                         systemImage: "checkmark.circle", tint: .green)
            case .mirror:
                StatCard(title: "To add", value: report.mirror.toAdd.count,
                         systemImage: "plus.circle", tint: Brand.gold)
                StatCard(title: "To delete", value: report.mirror.removalCount,
                         systemImage: "trash", tint: .red)
                StatCard(title: "Identical", value: report.mirror.unchanged,
                         systemImage: "checkmark.circle", tint: .green)
            }
        }
    }

    // MARK: - Zone centrale

    @ViewBuilder
    private var middle: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView(
                "Ready to compare",
                systemImage: "dot.radiowaves.left.and.right",
                description: Text("Echo compares the source bookmarks with the target's and shows what would be added (and, in full copy, deleted). The comparison doesn't change anything: the browsers can stay open.")
            )
        case .comparing:
            ProgressView("Reading bookmarks…")
        case .done:
            resultView
        case .applying:
            ProgressView(model.syncMode == .mirror ? String(localized: "Copying bookmarks…") : String(localized: "Adding bookmarks…"))
        case .applied:
            appliedView
        }
    }

    @ViewBuilder
    private var resultView: some View {
        if let report = model.report {
            VStack(spacing: 12) {
                if !model.hasChanges {
                    let target = "\(report.destination.browserName) · \(report.destination.name)"
                    ContentUnavailableView(model.syncMode == .mirror ? String(localized: "Already identical") : String(localized: "Nothing to add"),
                                           systemImage: "checkmark.seal",
                                           description: Text(model.syncMode == .mirror
                                                             ? String(localized: "\(target) already has exactly the source's bookmarks.")
                                                             : String(localized: "\(target) already contains all the source's web bookmarks.")))
                } else {
                    SyncNotice(browserName: report.destination.browserName,
                               isBrowserRunning: model.isDestinationRunning,
                               syncStatus: model.destinationSyncStatus,
                               operation: model.syncMode == .mirror ? .mirror : .addition)
                    if model.syncMode == .mirror {
                        removalWarning(report.mirror)
                    }
                    let sourceName = report.source.browserName
                    Toggle(model.syncMode == .mirror
                           ? String(localized: "Copy the icons from \(sourceName) for all bookmarks that don't have one (without downloading them again)")
                           : String(localized: "Also copy the icons from \(sourceName) (without downloading them again)"),
                           isOn: $model.copyFavicons)
                        .toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    planList(report)
                }

                if report.ignoredCount > 0 {
                    Label("\(report.ignoredCount) non-web bookmarks (vivaldi://, opera://…) skipped: they aren't copied from one browser to another.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Ce que la copie complète détruirait, en rouge, avant la confirmation.
    @ViewBuilder
    private func removalWarning(_ mirror: EchoMirrorPlan) -> some View {
        if mirror.removalCount > 0 || mirror.foldersToRemove > 0 {
            Label("Will be deleted from the target: \(Self.removalSummary(mirror)). They're listed in red below.",
                  systemImage: "trash.fill")
                .foregroundStyle(.red)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private static func removalSummary(_ mirror: EchoMirrorPlan) -> String {
        var parts: [String] = []
        if !mirror.toRemove.isEmpty {
            parts.append(String(localized: "\(mirror.toRemove.count) bookmarks"))
        }
        if mirror.nonWebToRemove > 0 {
            parts.append(String(localized: "\(mirror.nonWebToRemove) non-web bookmarks"))
        }
        if mirror.foldersToRemove > 0 {
            parts.append(String(localized: "\(mirror.foldersToRemove) folders"))
        }
        return parts.joined(separator: ", ")
    }

    private func planList(_ report: EchoReport) -> some View {
        VStack(spacing: 8) {
            Text(verbatim: summaryLine(for: report))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            List {
                ForEach(sections(for: report)) { section in
                    Section {
                        ForEach(section.items, id: \.self) { bookmark in
                            EchoRow(bookmark: bookmark, isRemoval: section.isRemoval)
                        }
                    } header: {
                        HStack {
                            Text(verbatim: section.title)
                                .font(.headline)
                                .foregroundStyle(section.isRemoval ? Color.red : Color.primary)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Spacer()
                            Text("\(section.items.count) bookmarks")
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
    }

    private func summaryLine(for report: EchoReport) -> String {
        let name = "\(report.destination.browserName) · \(report.destination.name)"
        if model.syncMode == .mirror {
            let mirror = report.mirror
            var parts = [String(localized: "In \(name): \(mirror.toAdd.count) to add")]
            if mirror.foldersToAdd > 0 {
                parts.append(String(localized: "\(mirror.foldersToAdd) folders to create"))
            }
            parts.append(String(localized: "\(mirror.removalCount) to delete"))
            parts.append(String(localized: "\(mirror.unchanged) identical"))
            if mirror.toAdd.isEmpty && mirror.removalCount == 0 {
                parts.append(String(localized: "only the order or the folders change"))
            }
            return parts.joined(separator: " · ")
        }

        let plan = report.plan
        var parts = [String(localized: "In \(name): \(plan.toAdd.count) to add")]
        if plan.newFolders > 0 {
            parts.append(String(localized: "\(plan.newFolders) folders to create"))
        }
        parts.append(String(localized: "\(plan.alreadyPresent) already present"))
        if plan.skippedSourceDuplicates > 0 {
            parts.append(String(localized: "\(plan.skippedSourceDuplicates) source duplicates skipped"))
        }
        return parts.joined(separator: " · ")
    }

    private struct PlanSection: Identifiable {
        let title: String
        let items: [EchoBookmark]
        var isRemoval = false
        var id: String { (isRemoval ? "−" : "+") + title }
    }

    /// Favoris à ajouter (puis, en copie complète, à supprimer), regroupés par emplacement dans la cible.
    private func sections(for report: EchoReport) -> [PlanSection] {
        func grouped(_ bookmarks: [EchoBookmark], isRemoval: Bool) -> [PlanSection] {
            let groups = Dictionary(grouping: bookmarks, by: \.locationLabel)
            return groups.keys.sorted().map {
                PlanSection(title: isRemoval ? String(localized: "Deleted · \($0)") : $0, items: groups[$0] ?? [], isRemoval: isRemoval)
            }
        }
        switch model.syncMode {
        case .merge:
            return grouped(report.plan.toAdd, isRemoval: false)
        case .mirror:
            return grouped(report.mirror.toAdd, isRemoval: false) + grouped(report.mirror.toRemove, isRemoval: true)
        }
    }

    // MARK: - Résultat de l'écriture

    private var appliedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            if let summary = model.summary {
                Text(verbatim: appliedTitle(summary))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                VStack(spacing: 4) {
                    if summary.removed > 0 {
                        Text("\(summary.removed) bookmarks deleted")
                    }
                    if summary.removedFolders > 0 {
                        Text("\(summary.removedFolders) folders deleted")
                    }
                    if summary.createdFolders > 0 {
                        Text("\(summary.createdFolders) folders created")
                    }
                    if summary.faviconsCopied > 0 {
                        Text("\(summary.faviconsCopied) icons copied")
                    }
                    if summary.faviconsMissing > 0 {
                        Text("\(summary.faviconsMissing) bookmarks without an icon in the source: FaviconSync can look for them.")
                    }
                    if summary.faviconsFailed > 0 {
                        Text("\(summary.faviconsFailed) icons couldn't be written.")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                if let note = summary.faviconNote {
                    Label { Text(verbatim: note) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 24)
                }

                Button("Show Backups in Finder") { model.revealBackups() }
            }
            Text("Relaunch \(destinationBrowserName) to see the result.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func appliedTitle(_ summary: EchoApplySummary) -> String {
        switch summary.mode {
        case .merge:
            return String(localized: "\(summary.added) bookmarks added to \(destinationLabel)")
        case .mirror:
            return String(localized: "\(destinationLabel) is now identical to the source")
        }
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

    private var applyTitle: String {
        switch model.syncMode {
        case .merge:
            let count = model.report?.plan.toAdd.count ?? 0
            return String(localized: "Add \(count) bookmarks")
        case .mirror:
            return String(localized: "Start Full Copy")
        }
    }

    @ViewBuilder
    private var primaryActions: some View {
        switch model.phase {
        case .idle:
            Button("Compare") { model.compare() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canCompare)
        case .comparing:
            Button("Comparing…") {}
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)
        case .done where model.hasChanges:
            Button("New Comparison") { model.compare() }
                .controlSize(.large)
            Button(applyTitle) {
                model.showConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .tint(model.syncMode == .mirror ? .red : nil)
            .controlSize(.large)
            .disabled(!model.canApply)
        case .done, .applied:
            Button("New Comparison") { model.compare() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .applying:
            Button(model.syncMode == .mirror ? String(localized: "Copying…") : String(localized: "Adding…")) {}
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)
        }
    }
}

// MARK: - Ligne d'un favori

private struct EchoRow: View {
    let bookmark: EchoBookmark
    var isRemoval = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isRemoval ? "trash" : "bookmark")
                .foregroundStyle(isRemoval ? Color.red : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: bookmark.name.isEmpty ? bookmark.url : bookmark.name)
                    .foregroundStyle(isRemoval ? Color.red : Color.primary)
                    .lineLimit(1)
                Text(verbatim: bookmark.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    EchoView(model: EchoViewModel())
}
