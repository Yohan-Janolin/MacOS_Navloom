import SwiftUI

@MainActor
@Observable
final class TwinsViewModel {

    enum Phase: Equatable {
        case idle, analyzing, done
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
    private(set) var errorMessage: String?

    /// Favoris cochés (par identifiant de nœud). Servira à l'étape suivante : la suppression.
    private(set) var selection: Set<String> = []

    // MARK: Calculés

    var selectedBrowser: ChromiumBrowser? {
        browsers.first { $0.id == selectedBrowserID }
    }

    var selectedProfile: ChromiumProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    var isBusy: Bool { phase == .analyzing }

    /// Nombre de favoris en trop : pour 3 favoris identiques, 2 sont des doublons.
    var extraCopies: Int {
        groups.reduce(0) { $0 + $1.bookmarks.count - 1 }
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
        errorMessage = nil
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
}
