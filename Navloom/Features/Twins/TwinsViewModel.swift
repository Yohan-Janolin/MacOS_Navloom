//
//  TwinsViewModel.swift
//  Navloom
//

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
    private(set) var groups: [DuplicateGroup] = []
    private(set) var summary: BookmarksWriteSummary?
    private(set) var errorMessage: String?
    private(set) var isBrowserRunning = false
    private(set) var syncStatus: BookmarkSyncStatus = .unknown

    /// Favoris cochés (par identifiant de nœud) : ce sont ceux qui seront supprimés.
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
    /// de tes favoris. Tant qu'il en reste, la suppression est bloquée.
    var fullySelectedGroupCount: Int {
        groups.filter { group in group.bookmarks.allSatisfy { selection.contains($0.nodeID) } }.count
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

        let url = profile.bookmarksURL
        Task {
            do {
                let bookmarks = try await Task.detached { try BookmarksReader.read(from: url) }.value
                totalBookmarks = bookmarks.count
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
        selection.contains(bookmark.nodeID)
    }

    func toggle(_ bookmark: Bookmark) {
        if selection.contains(bookmark.nodeID) {
            selection.remove(bookmark.nodeID)
        } else {
            selection.insert(bookmark.nodeID)
        }
    }

    /// Coche tous les doublons sauf le premier de chaque groupe (celui qu'on garde).
    func selectAllButFirst() {
        selection = Set(groups.flatMap { $0.bookmarks.dropFirst().map(\.nodeID) })
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
                    try BookmarksWriter.removeBookmarks(ids: ids, in: file, label: label)
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
