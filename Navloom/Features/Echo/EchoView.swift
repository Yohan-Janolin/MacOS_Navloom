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
        .onChange(of: model.selectedProfileID) { model.profileChanged() }
        .onChange(of: model.destinationBrowserID) { model.destinationBrowserChanged() }
        .onChange(of: model.destinationProfileID) { model.destinationProfileChanged() }
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
            Button("Ajouter") { model.apply() }
        } message: {
            Text("Les favoris seront ajoutés à \(destinationLabel). Aucun favori n'est supprimé ni modifié. Des sauvegardes sont créées avant.")
        }
    }

    private var destinationBrowserName: String {
        model.report?.destination.browserName ?? model.destinationBrowser?.name ?? "la destination"
    }

    private var destinationLabel: String {
        guard let destination = model.report?.destination else { return "la destination" }
        return "\(destination.browserName) · \(destination.name)"
    }

    private var confirmationTitle: String {
        let count = model.report?.plan.toAdd.count ?? 0
        return "Ajouter \(count) favori\(count > 1 ? "s" : "") à \(destinationBrowserName) ?"
    }

    // MARK: - Structure

    private var content: some View {
        VStack(spacing: 16) {
            titleHeader
            browserRows

            // Une fois la comparaison faite, ces réglages laissent la place aux résultats ;
            // changer la source, la destination ou « Annuler » les ramène.
            if model.phase == .idle || model.phase == .comparing {
                modeSection
                urlOptionsSection
            }

            if model.isSameProfile && model.phase == .idle {
                Label("La source et la destination sont le même profil : choisis-en un autre.",
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            actionBar
        }
        .padding(20)
    }

    private var titleHeader: some View {
        VStack(spacing: 4) {
            Text("Echo")
                .font(.largeTitle.bold())
                .foregroundStyle(
                    LinearGradient(colors: Self.sourceGradient,
                                   startPoint: .leading, endPoint: .trailing)
                )
            Text("Réplique les favoris d'un navigateur vers un autre")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Deux bandeaux : d'où viennent les favoris, et où ils iraient.
    private var browserRows: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Label("Source", systemImage: "arrow.up.forward.square")
                    .font(.headline)
                    .frame(width: 125, alignment: .leading)
                BrowserProfileBanner(browsers: model.browsers,
                                     profiles: model.profiles,
                                     browserID: $model.selectedBrowserID,
                                     profileID: $model.selectedProfileID,
                                     colors: Self.sourceGradient)
            }
            HStack(spacing: 12) {
                Label("Destination", systemImage: "arrow.down.backward.square")
                    .font(.headline)
                    .frame(width: 125, alignment: .leading)
                BrowserProfileBanner(browsers: model.browsers,
                                     profiles: model.destinationProfiles,
                                     browserID: $model.destinationBrowserID,
                                     profileID: $model.destinationProfileID,
                                     colors: Self.destinationGradient)
            }
        }
        .disabled(model.isBusy)
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Comparaison", selection: $model.matchMode) {
                ForEach(EchoMatchMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(model.matchMode.hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(model.isBusy)
    }

    /// Variantes d'URL à traiter comme identiques, en plus du « / » final (toujours ignoré).
    private var urlOptionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Considérer comme identiques (en plus du « / » final)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 18) {
                Toggle("http et https", isOn: $model.ignoreScheme)
                    .help("http://a.fr et https://a.fr désignent le même favori.")
                Toggle("avec ou sans www.", isOn: $model.ignoreWWW)
                    .help("www.a.fr et a.fr désignent le même favori.")
                Toggle("paramètres (?…)", isOn: $model.ignoreQuery)
                    .help("a.fr/page?x=1 et a.fr/page désignent le même favori. Attention : si la page dépend du paramètre (une vidéo, un article…), des favoris différents seraient fusionnés et ne seraient pas copiés.")
                Spacer(minLength: 0)
            }
            .toggleStyle(.checkbox)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(model.isBusy)
    }

    private func stats(_ report: EchoReport) -> some View {
        HStack(spacing: 12) {
            StatCard(title: "Favoris de la source", value: report.sourceCount,
                     systemImage: "bookmark")
            StatCard(title: "À ajouter", value: report.plan.toAdd.count,
                     systemImage: "plus.circle", tint: Brand.gold)
            StatCard(title: "Déjà présents", value: report.plan.alreadyPresent,
                     systemImage: "checkmark.circle", tint: .green)
        }
    }

    // MARK: - Zone centrale

    @ViewBuilder
    private var middle: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView(
                "Prêt à comparer",
                systemImage: "dot.radiowaves.left.and.right",
                description: Text("Echo compare les favoris de la source à ceux de la destination et montre ce qui serait ajouté. La comparaison ne modifie rien : les navigateurs peuvent rester ouverts.")
            )
        case .comparing:
            ProgressView("Lecture des favoris…")
        case .done:
            resultView
        case .applying:
            ProgressView("Ajout des favoris…")
        case .applied:
            appliedView
        }
    }

    @ViewBuilder
    private var resultView: some View {
        if let report = model.report {
            VStack(spacing: 12) {
                if report.plan.toAdd.isEmpty {
                    ContentUnavailableView("Rien à ajouter",
                                           systemImage: "checkmark.seal",
                                           description: Text("\(report.destination.browserName) · \(report.destination.name) contient déjà tous les favoris web de la source."))
                } else {
                    SyncNotice(browserName: report.destination.browserName,
                               isBrowserRunning: model.isDestinationRunning,
                               syncStatus: model.destinationSyncStatus,
                               operation: .addition)
                    Toggle("Copier aussi les icônes depuis \(report.source.browserName) (sans les retélécharger)",
                           isOn: $model.copyFavicons)
                        .toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    planList(report)
                }

                if report.ignoredCount > 0 {
                    Label("\(report.ignoredCount) favori\(report.ignoredCount > 1 ? "s" : "") non web (vivaldi://, opera://…) ignoré\(report.ignoredCount > 1 ? "s" : "") : ils ne se copient pas d'un navigateur à l'autre.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func planList(_ report: EchoReport) -> some View {
        VStack(spacing: 8) {
            Text(summaryLine(for: report))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            List {
                ForEach(Self.sections(for: report.plan)) { section in
                    Section {
                        ForEach(section.items, id: \.self) { bookmark in
                            EchoRow(bookmark: bookmark)
                        }
                    } header: {
                        HStack {
                            Text(section.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Spacer()
                            Text("\(section.items.count) favori\(section.items.count > 1 ? "s" : "")")
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
        let plan = report.plan
        var parts = ["Dans \(report.destination.browserName) · \(report.destination.name) : \(plan.toAdd.count) à ajouter"]
        if plan.newFolders > 0 {
            parts.append("\(plan.newFolders) dossier\(plan.newFolders > 1 ? "s" : "") à créer")
        }
        parts.append("\(plan.alreadyPresent) déjà présent\(plan.alreadyPresent > 1 ? "s" : "")")
        if plan.skippedSourceDuplicates > 0 {
            parts.append("\(plan.skippedSourceDuplicates) doublon\(plan.skippedSourceDuplicates > 1 ? "s" : "") de la source ignoré\(plan.skippedSourceDuplicates > 1 ? "s" : "")")
        }
        return parts.joined(separator: " · ")
    }

    private struct PlanSection: Identifiable {
        let title: String
        let items: [EchoBookmark]
        var id: String { title }
    }

    /// Favoris à ajouter, regroupés par emplacement dans la destination.
    private static func sections(for plan: EchoPlan) -> [PlanSection] {
        let groups = Dictionary(grouping: plan.toAdd, by: \.locationLabel)
        return groups.keys.sorted().map { PlanSection(title: $0, items: groups[$0] ?? []) }
    }

    // MARK: - Résultat de l'écriture

    private var appliedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            if let summary = model.summary {
                Text("\(summary.added) favori\(summary.added > 1 ? "s" : "") ajouté\(summary.added > 1 ? "s" : "") à \(destinationLabel)")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                VStack(spacing: 4) {
                    if summary.createdFolders > 0 {
                        Text("\(summary.createdFolders) dossier\(summary.createdFolders > 1 ? "s" : "") créé\(summary.createdFolders > 1 ? "s" : "")")
                    }
                    if summary.faviconsCopied > 0 {
                        Text("\(summary.faviconsCopied) icône\(summary.faviconsCopied > 1 ? "s" : "") copiée\(summary.faviconsCopied > 1 ? "s" : "")")
                    }
                    if summary.faviconsMissing > 0 {
                        Text("\(summary.faviconsMissing) favori\(summary.faviconsMissing > 1 ? "s" : "") sans icône dans la source : FaviconSync peut les chercher.")
                    }
                    if summary.faviconsFailed > 0 {
                        Text("\(summary.faviconsFailed) icône\(summary.faviconsFailed > 1 ? "s" : "") n'ont pas pu être écrites.")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                if let note = summary.faviconNote {
                    Label(note, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 24)
                }

                Button("Afficher les sauvegardes dans le Finder") { model.revealBackups() }
            }
            Text("Relance \(destinationBrowserName) pour voir le résultat.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
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
        case .idle:
            Button("Comparer") { model.compare() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canCompare)
        case .comparing:
            Button("Comparaison en cours…") {}
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)
        case .done where model.hasBookmarksToAdd:
            let count = model.report?.plan.toAdd.count ?? 0
            Button("Nouvelle comparaison") { model.compare() }
                .controlSize(.large)
            Button("Ajouter \(count) favori\(count > 1 ? "s" : "")") {
                model.showConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canApply)
        case .done, .applied:
            Button("Nouvelle comparaison") { model.compare() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .applying:
            Button("Ajout en cours…") {}
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)
        }
    }
}

// MARK: - Ligne d'un favori

private struct EchoRow: View {
    let bookmark: EchoBookmark

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bookmark")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(bookmark.name.isEmpty ? bookmark.url : bookmark.name)
                    .lineLimit(1)
                Text(bookmark.url)
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
