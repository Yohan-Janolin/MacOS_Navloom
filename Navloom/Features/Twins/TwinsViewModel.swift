import SwiftUI
import AppKit

@MainActor
@Observable
final class TwinsViewModel {

    enum Phase: Equatable {
        case idle, analyzing, done, removing, removed
    }

    // MARK: État observé par la vue

    private(set) var hasLoaded = false
    private(set) var browsers: [ChromiumBrowser] = []
    private(set) var profiles: [ChromiumProfile] = []
    var selectedBrowserID: String?
    var selectedProfileID: String?

    private(set) var phase: Phase = .idle
    private(set) var totalBookmarks = 0
    /// Favoris du compte Google (Chrome) : affichés, mais jamais cochables.
    private(set) var accountBookmarkCount = 0
    private(set) var groups: [DuplicateGroup] = []
    private(set) var summary: BookmarksWriteSummary?
    private(set) var errorMessage: String?
    private(set) var isBrowserRunning = false
    private(set) var syncStatus: BookmarkSyncStatus = .unknown

    /// Favoris cochés (par identifiant de nœud, favoris locaux uniquement) : ce sont ceux qui seront supprimés.
    private(set) var selection: Set<String> = []

    /// Vrai quand la boîte de dialogue de confirmation doit s'afficher.
    var showConfirmation = false

    // MARK: Calculés

    var selectedBrowser: ChromiumBrowser? {
        browsers.first { $0.id == selectedBrowserID }
    }

    var selectedProfile: ChromiumProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    var isBusy: Bool { phase == .analyzing || phase == .removing }

    /// Nombre de favoris en trop : pour 3 favoris identiques, 2 sont des doublons.
    var extraCopies: Int {
        groups.reduce(0) { $0 + $1.bookmarks.count - 1 }
    }

    /// Groupes dont TOUTES les copies sont cochées : les supprimer ferait disparaître l'URL
    /// de tes favoris. Une copie du compte n'est jamais cochée, donc elle protège son groupe.
    var fullySelectedGroupCount: Int {
        groups.filter { group in group.bookmarks.allSatisfy { isSelected($0) } }.count
    }

    /// La suppression est bloquée si la synchro des favoris est active : au lancement suivant,
    /// le navigateur remettrait les favoris supprimés.
    var canRemove: Bool {
        phase == .done && !selection.isEmpty && fullySelectedGroupCount == 0
            && !isBrowserRunning && syncStatus != .enabled
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
        totalBookmarks = 0
        accountBookmarkCount = 0
        groups = []
        selection = []
        summary = nil
        errorMessage = nil
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

    // MARK: Analyse (lecture seule)

    func analyze() {
        guard let profile = selectedProfile, !isBusy else { return }
        reset()
        phase = .analyzing

        Task {
            do {
                let bookmarks = try await Task.detached { try BookmarksReader.readAll(for: profile) }.value
                totalBookmarks = bookmarks.count
                accountBookmarkCount = bookmarks.filter { $0.source == .account }.count
                groups = DuplicateFinder.groups(in: bookmarks)
                refreshSyncStatus()
                phase = .done
            } catch {
                errorMessage = error.localizedDescription
                phase = .idle
            }
        }
    }

    // MARK: Cases à cocher

    func isSelected(_ bookmark: Bookmark) -> Bool {
        bookmark.source == .local && selection.contains(bookmark.nodeID)
    }

    func toggle(_ bookmark: Bookmark) {
        // Un favori du compte ne se coche pas ; et deux fichiers peuvent partager un même identifiant.
        guard bookmark.source == .local, !bookmark.nodeID.isEmpty else { return }
        if selection.contains(bookmark.nodeID) {
            selection.remove(bookmark.nodeID)
        } else {
            selection.insert(bookmark.nodeID)
        }
    }

    /// Coche les doublons à supprimer dans chaque groupe (voir `DuplicateFinder.removableKeepingFirst`).
    func selectAllButFirst() {
        selection = DuplicateFinder.removableKeepingFirst(in: groups)
    }

    func clearSelection() {
        selection = []
    }

    // MARK: Suppression (navigateur fermé obligatoire, sauvegarde automatique)

    func removeSelected() {
        guard let profile = selectedProfile, phase == .done, !selection.isEmpty else { return }
        refreshBrowserRunning()
        refreshSyncStatus()
        guard !isBrowserRunning, syncStatus != .enabled, fullySelectedGroupCount == 0 else { return }

        errorMessage = nil
        phase = .removing

        let ids = selection
        let file = profile.bookmarksURL
        let label = profile.id

        Task {
            do {
                summary = try await Task.detached {
                    try BookmarksWriter.removeBookmarks(ids: ids, in: file, label: label, tool: .twins)
                }.value
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
}
