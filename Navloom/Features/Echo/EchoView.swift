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
                Button("Ajouter") { model.apply() }
            case .mirror:
                Button("Remplacer par la copie", role: .destructive) { model.apply() }
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var destinationBrowserName: String {
        model.report?.destination.browserName ?? model.destinationBrowser?.name ?? "la cible"
    }

    private var destinationLabel: String {
        guard let destination = model.report?.destination else { return "la cible" }
        return "\(destination.browserName) · \(destination.name)"
    }

    private var confirmationTitle: String {
        switch model.syncMode {
        case .merge:
            let count = model.report?.plan.toAdd.count ?? 0
            return "Ajouter \(count) favori\(count > 1 ? "s" : "") à \(destinationBrowserName) ?"
        case .mirror:
            return "Remplacer les favoris de \(destinationBrowserName) par ceux de la source ?"
        }
    }

    private var confirmationMessage: String {
        switch model.syncMode {
        case .merge:
            return "Les favoris seront ajoutés à \(destinationLabel). Aucun favori n'est supprimé ni modifié. Des sauvegardes sont créées avant."
        case .mirror:
            guard let mirror = model.report?.mirror else { return "" }
            return "\(destinationLabel) deviendra identique à la source : \(mirror.toAdd.count) favori\(mirror.toAdd.count > 1 ? "s" : "") ajouté\(mirror.toAdd.count > 1 ? "s" : ""), \(mirror.removalCount) supprimé\(mirror.removalCount > 1 ? "s" : "") (et \(mirror.foldersToRemove) dossier\(mirror.foldersToRemove > 1 ? "s" : "")). Des sauvegardes sont créées avant : tu pourras revenir en arrière depuis l'écran Sauvegardes."
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
                Label("La source et la cible sont le même profil : choisis-en un autre.",
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
            BrowserProfileBanner(browsers: model.browsers,
                                 profiles: model.profiles,
                                 browserID: $model.selectedBrowserID,
                                 profileID: $model.selectedProfileID,
                                 browserTitle: "Navigateur source",
                                 colors: Self.sourceGradient)
            BrowserProfileBanner(browsers: model.browsers,
                                 profiles: model.destinationProfiles,
                                 browserID: $model.destinationBrowserID,
                                 profileID: $model.destinationProfileID,
                                 browserTitle: "Navigateur cible",
                                 colors: Self.destinationGradient)
        }
        .disabled(model.isBusy)
    }

    /// Que faire dans la cible, et (pour l'ajout) comment comparer : dans un cadre gris.
    private var comparisonSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Mode", selection: $model.syncMode) {
                ForEach(EchoSyncMode.allCases) { mode in
                    Text(mode.shortTitle).tag(mode)
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

                Text("\(model.syncMode.hint) \(model.matchMode.hint) Les cases cochées font traiter ces variantes d'URL comme identiques ; le « / » final l'est toujours. Attention aux paramètres (?…) : si la page en dépend (une vidéo, un article…), des favoris différents seraient fusionnés.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .mirror:
                Label(model.syncMode.hint, systemImage: "exclamationmark.triangle.fill")
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
        Picker("Comparaison", selection: $model.matchMode) {
            ForEach(EchoMatchMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }

    /// Variantes d'URL à traiter comme identiques.
    private var urlToggles: some View {
        HStack(spacing: 16) {
            Toggle("http/https", isOn: $model.ignoreScheme)
            Toggle("www", isOn: $model.ignoreWWW)
            Toggle("paramètres ?…", isOn: $model.ignoreQuery)
        }
        .toggleStyle(.checkbox)
        .lineLimit(1)
    }

    private func stats(_ report: EchoReport) -> some View {
        HStack(spacing: 12) {
            StatCard(title: "Favoris de la source", value: report.sourceCount,
                     systemImage: "bookmark")
            switch model.syncMode {
            case .merge:
                StatCard(title: "À ajouter", value: report.plan.toAdd.count,
                         systemImage: "plus.circle", tint: Brand.gold)
                StatCard(title: "Déjà présents", value: report.plan.alreadyPresent,
                         systemImage: "checkmark.circle", tint: .green)
            case .mirror:
                StatCard(title: "À ajouter", value: report.mirror.toAdd.count,
                         systemImage: "plus.circle", tint: Brand.gold)
                StatCard(title: "À supprimer", value: report.mirror.removalCount,
                         systemImage: "trash", tint: .red)
                StatCard(title: "Identiques", value: report.mirror.unchanged,
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
                "Prêt à comparer",
                systemImage: "dot.radiowaves.left.and.right",
                description: Text("Echo compare les favoris de la source à ceux de la cible et montre ce qui serait ajouté (et, en copie complète, supprimé). La comparaison ne modifie rien : les navigateurs peuvent rester ouverts.")
            )
        case .comparing:
            ProgressView("Lecture des favoris…")
        case .done:
            resultView
        case .applying:
            ProgressView(model.syncMode == .mirror ? "Copie des favoris…" : "Ajout des favoris…")
        case .applied:
            appliedView
        }
    }

    @ViewBuilder
    private var resultView: some View {
        if let report = model.report {
            VStack(spacing: 12) {
                if !model.hasChanges {
                    ContentUnavailableView(model.syncMode == .mirror ? "Déjà identiques" : "Rien à ajouter",
                                           systemImage: "checkmark.seal",
                                           description: Text(model.syncMode == .mirror
                                                             ? "\(report.destination.browserName) · \(report.destination.name) a déjà exactement les favoris de la source."
                                                             : "\(report.destination.browserName) · \(report.destination.name) contient déjà tous les favoris web de la source."))
                } else {
                    SyncNotice(browserName: report.destination.browserName,
                               isBrowserRunning: model.isDestinationRunning,
                               syncStatus: model.destinationSyncStatus,
                               operation: model.syncMode == .mirror ? .mirror : .addition)
                    if model.syncMode == .mirror {
                        removalWarning(report.mirror)
                    }
                    Toggle(model.syncMode == .mirror
                           ? "Copier les icônes depuis \(report.source.browserName) pour tous les favoris qui n'en ont pas (sans les retélécharger)"
                           : "Copier aussi les icônes depuis \(report.source.browserName) (sans les retélécharger)",
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

    /// Ce que la copie complète détruirait, en rouge, avant la confirmation.
    @ViewBuilder
    private func removalWarning(_ mirror: EchoMirrorPlan) -> some View {
        if mirror.removalCount > 0 || mirror.foldersToRemove > 0 {
            Label("Seront supprimés de la cible : \(Self.removalSummary(mirror)). Ils sont listés en rouge ci-dessous.",
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
            parts.append("\(mirror.toRemove.count) favori\(mirror.toRemove.count > 1 ? "s" : "")")
        }
        if mirror.nonWebToRemove > 0 {
            parts.append("\(mirror.nonWebToRemove) favori\(mirror.nonWebToRemove > 1 ? "s" : "") non web")
        }
        if mirror.foldersToRemove > 0 {
            parts.append("\(mirror.foldersToRemove) dossier\(mirror.foldersToRemove > 1 ? "s" : "")")
        }
        return parts.joined(separator: ", ")
    }

    private func planList(_ report: EchoReport) -> some View {
        VStack(spacing: 8) {
            Text(summaryLine(for: report))
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
                            Text(section.title)
                                .font(.headline)
                                .foregroundStyle(section.isRemoval ? Color.red : Color.primary)
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
        let name = "\(report.destination.browserName) · \(report.destination.name)"
        if model.syncMode == .mirror {
            let mirror = report.mirror
            var parts = ["Dans \(name) : \(mirror.toAdd.count) à ajouter"]
            if mirror.foldersToAdd > 0 {
                parts.append("\(mirror.foldersToAdd) dossier\(mirror.foldersToAdd > 1 ? "s" : "") à créer")
            }
            parts.append("\(mirror.removalCount) à supprimer")
            parts.append("\(mirror.unchanged) identique\(mirror.unchanged > 1 ? "s" : "")")
            if mirror.toAdd.isEmpty && mirror.removalCount == 0 {
                parts.append("seul l'ordre ou les dossiers changent")
            }
            return parts.joined(separator: " · ")
        }

        let plan = report.plan
        var parts = ["Dans \(name) : \(plan.toAdd.count) à ajouter"]
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
        var isRemoval = false
        var id: String { (isRemoval ? "−" : "+") + title }
    }

    /// Favoris à ajouter (puis, en copie complète, à supprimer), regroupés par emplacement dans la cible.
    private func sections(for report: EchoReport) -> [PlanSection] {
        func grouped(_ bookmarks: [EchoBookmark], isRemoval: Bool) -> [PlanSection] {
            let groups = Dictionary(grouping: bookmarks, by: \.locationLabel)
            return groups.keys.sorted().map {
                PlanSection(title: isRemoval ? "Supprimés · \($0)" : $0, items: groups[$0] ?? [], isRemoval: isRemoval)
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
                Text(appliedTitle(summary))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                VStack(spacing: 4) {
                    if summary.removed > 0 {
                        Text("\(summary.removed) favori\(summary.removed > 1 ? "s" : "") supprimé\(summary.removed > 1 ? "s" : "")")
                    }
                    if summary.removedFolders > 0 {
                        Text("\(summary.removedFolders) dossier\(summary.removedFolders > 1 ? "s" : "") supprimé\(summary.removedFolders > 1 ? "s" : "")")
                    }
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

    private func appliedTitle(_ summary: EchoApplySummary) -> String {
        switch summary.mode {
        case .merge:
            return "\(summary.added) favori\(summary.added > 1 ? "s" : "") ajouté\(summary.added > 1 ? "s" : "") à \(destinationLabel)"
        case .mirror:
            return "\(destinationLabel) est maintenant identique à la source"
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

    private var applyTitle: String {
        switch model.syncMode {
        case .merge:
            let count = model.report?.plan.toAdd.count ?? 0
            return "Ajouter \(count) favori\(count > 1 ? "s" : "")"
        case .mirror:
            return "Lancer la copie complète"
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
        case .done where model.hasChanges:
            Button("Nouvelle comparaison") { model.compare() }
                .controlSize(.large)
            Button(applyTitle) {
                model.showConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .tint(model.syncMode == .mirror ? .red : nil)
            .controlSize(.large)
            .disabled(!model.canApply)
        case .done, .applied:
            Button("Nouvelle comparaison") { model.compare() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .applying:
            Button(model.syncMode == .mirror ? "Copie en cours…" : "Ajout en cours…") {}
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
                Text(bookmark.name.isEmpty ? bookmark.url : bookmark.name)
                    .foregroundStyle(isRemoval ? Color.red : Color.primary)
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
