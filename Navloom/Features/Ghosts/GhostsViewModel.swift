import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
@Observable
final class GhostsViewModel {

    enum Phase: Equatable {
        case idle, scanning, done, removing, removed
    }

    enum Category: String, CaseIterable, Identifiable {
        case dead = "Morts"
        case uncertain = "À vérifier"
        case moved = "Redirigés"
        var id: String { rawValue }
    }

    struct Row: Identifiable {
        let id = UUID()
        let nodeID: String
        let name: String
        let url: String
        let detail: String
        let folder: String
        /// Faux pour un favori du compte Google : affiché, mais jamais cochable.
        let isLocal: Bool
    }

    // MARK: État observé par la vue

    private(set) var hasLoaded = false
    private(set) var browsers: [ChromiumBrowser] = []
    private(set) var profiles: [ChromiumProfile] = []
    var selectedBrowserID: String?
    var selectedProfileID: String?

    private(set) var phase: Phase = .idle
    private(set) var report: GhostsReport?
    private(set) var errorMessage: String?
    private(set) var rows: [Category: [Row]] = [:]
    var selectedCategory: Category = .dead

    private(set) var progressPass = 1
    private(set) var progressDone = 0
    private(set) var progressTotal = 0
    private(set) var currentURL = ""

    private(set) var isBrowserRunning = false
    private(set) var syncStatus: BookmarkSyncStatus = .unknown
    private(set) var summary: BookmarksWriteSummary?

    /// Favoris cochés (par identifiant de nœud) : ce sont ceux qui seront supprimés.
    private(set) var selection: Set<String> = []

    /// Vrai quand la boîte de dialogue de confirmation doit s'afficher.
    var showConfirmation = false

    private var scanTask: Task<Void, Never>?

    // MARK: Calculés

    var selectedBrowser: ChromiumBrowser? { browsers.first { $0.id == selectedBrowserID } }
    var selectedProfile: ChromiumProfile? { profiles.first { $0.id == selectedProfileID } }
    var isBusy: Bool { phase == .scanning || phase == .removing }

    /// Même règle que Twins : pas de suppression si le navigateur est ouvert ou si la synchro
    /// des favoris est active (elle remettrait les favoris supprimés au lancement suivant).
    var canRemove: Bool {
        phase == .done && !selection.isEmpty && !isBrowserRunning && syncStatus != .enabled
    }

    // MARK: Sélection du navigateur et du profil

    func loadBrowsersIfNeeded() {
        guard !hasLoaded else { return }
        browsers = ChromiumBrowser.installed()
        if !browsers.contains(where: { $0.id == selectedBrowserID }) {
            selectedBrowserID = browsers.first(where: { $0.id == "vivaldi" })?.id ?? browsers.first?.id
        }
        browserChanged()
        hasLoaded = true
    }

    func browserChanged() {
        profiles = selectedBrowser?.profiles() ?? []
        if !profiles.contains(where: { $0.id == selectedProfileID }) {
            selectedProfileID = profiles.first?.id
        }
        reset()
    }

    func reset() {
        guard !isBusy else { return }
        phase = .idle
        report = nil
        errorMessage = nil
        rows = [:]
        selection = []
        summary = nil
    }

    func refreshBrowserRunning() {
        let wasRunning = isBrowserRunning
        isBrowserRunning = selectedProfile?.isBrowserRunning ?? false

        // Le navigateur écrit ses réglages en quittant : on relit la synchro quand il vient de se fermer.
        if wasRunning && !isBrowserRunning {
            refreshSyncStatus()
        }
    }

    func refreshSyncStatus() {
        syncStatus = selectedProfile.map(BookmarkSyncStatus.detect(for:)) ?? .unknown
    }

    // MARK: Recherche

    func scan() {
        guard let profile = selectedProfile, !isBusy else { return }
        reset()
        progressPass = 1
        progressDone = 0
        progressTotal = 0
        currentURL = ""
        phase = .scanning

        let engine = GhostsEngine(profile: profile)
        let (stream, continuation) = AsyncStream.makeStream(of: GhostsEvent.self)

        scanTask = Task {
            let listener = Task {
                for await event in stream { handle(event) }
            }
            do {
                let result = try await engine.scan { continuation.yield($0) }
                continuation.finish()
                await listener.value

                // Arrêt demandé pendant la recherche : les résultats sont incomplets, on les jette.
                if Task.isCancelled {
                    phase = .idle
                    return
                }
                report = result
                buildRows(from: result)
                refreshSyncStatus()
                phase = .done
            } catch {
                continuation.finish()
                await listener.value
                errorMessage = error.localizedDescription
                phase = .idle
            }
        }
    }

    /// Interrompt la recherche en cours (rien n'a été modifié, donc retour à l'état initial).
    func cancelScan() {
        scanTask?.cancel()
    }

    private func handle(_ event: GhostsEvent) {
        switch event {
        case .checked(let pass, let done, let total, let url):
            progressPass = pass
            progressDone = done
            progressTotal = total
            currentURL = url
        case .retrying(let count, _):
            progressPass = 2
            progressDone = 0
            progressTotal = count
            currentURL = "Pause avant le second passage…"
        }
    }

    private func buildRows(from report: GhostsReport) {
        func make(_ issues: [BookmarkIssue]) -> [Row] {
            issues.map {
                Row(nodeID: $0.bookmark.nodeID,
                    name: $0.bookmark.name, url: $0.bookmark.url, detail: $0.reason,
                    folder: $0.bookmark.folder.isEmpty ? "Racine" : $0.bookmark.folder,
                    isLocal: $0.bookmark.source == .local)
            }
        }
        rows[.dead] = make(report.dead)
        rows[.uncertain] = make(report.uncertain)
        rows[.moved] = make(report.moved)

        if !report.dead.isEmpty { selectedCategory = .dead }
        else if !report.uncertain.isEmpty { selectedCategory = .uncertain }
        else { selectedCategory = .moved }
    }

    // MARK: Cases à cocher

    func isSelected(_ row: Row) -> Bool {
        row.isLocal && selection.contains(row.nodeID)
    }

    func toggle(_ row: Row) {
        // Deux fichiers peuvent partager un même identifiant : un favori du compte ne se coche jamais.
        guard row.isLocal, !row.nodeID.isEmpty else { return }
        if selection.contains(row.nodeID) {
            selection.remove(row.nodeID)
        } else {
            selection.insert(row.nodeID)
        }
    }

    /// « Tout cocher » et « Tout décocher » agissent sur l'onglet affiché ; le compteur, lui,
    /// reste global (un favori coché dans un autre onglet sera aussi supprimé).
    func selectAll(in category: Category) {
        for row in rows[category] ?? [] where row.isLocal && !row.nodeID.isEmpty {
            selection.insert(row.nodeID)
        }
    }

    func deselectAll(in category: Category) {
        for row in rows[category] ?? [] where row.isLocal {
            selection.remove(row.nodeID)
        }
    }

    /// Favoris de l'onglet qu'on peut cocher (hors favoris du compte).
    func selectableCount(in category: Category) -> Int {
        (rows[category] ?? []).filter { $0.isLocal && !$0.nodeID.isEmpty }.count
    }

    func checkedCount(in category: Category) -> Int {
        (rows[category] ?? []).filter { isSelected($0) }.count
    }

    // MARK: Suppression (navigateur fermé obligatoire, sauvegarde automatique)

    func removeSelected() {
        guard let profile = selectedProfile, phase == .done, !selection.isEmpty else { return }
        refreshBrowserRunning()
        refreshSyncStatus()
        guard !isBrowserRunning, syncStatus != .enabled else { return }

        errorMessage = nil
        phase = .removing

        let ids = selection
        let file = profile.bookmarksURL
        let label = profile.id

        Task {
            do {
                summary = try await Task.detached {
                    try BookmarksWriter.removeBookmarks(ids: ids, in: file, label: label)
                }.value
                selection = []
                phase = .removed
            } catch {
                errorMessage = error.localizedDescription
                phase = .done
            }
        }
    }

    func revealBackup() {
        guard let url = summary?.backupURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: Actions sur une ligne

    func open(_ row: Row) {
        guard let url = URL(string: row.url) else { return }
        NSWorkspace.shared.open(url)
    }

    func copyURL(_ row: Row) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(row.url, forType: .string)
    }

    // MARK: Export

    func exportReport() {
        guard let report, let profile = selectedProfile else { return }
        let text = report.text(browserName: profile.browserName, profileName: profile.name)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "ghosts-rapport.txt"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Impossible d'écrire le rapport : \(error.localizedDescription)"
        }
    }
}
