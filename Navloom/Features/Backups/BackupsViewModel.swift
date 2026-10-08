import SwiftUI
import AppKit

/// Ce que l'écran Sauvegardes affiche : tout, les sauvegardes d'un outil, ou les anciennes sauvegardes
/// de favoris (d'avant que le nom de fichier note l'outil : Twins ou Ghosts, on ne sait pas lequel).
nonisolated enum BackupFilter: Hashable, Identifiable, Sendable {
    case all
    case tool(BackupTool)
    case legacy

    var id: String {
        switch self {
        case .all: "all"
        case .tool(let tool): tool.rawValue
        case .legacy: "legacy"
        }
    }

    var title: String {
        switch self {
        case .all: "Tout"
        case .tool(let tool): tool.title
        case .legacy: "Anciennes"
        }
    }

    func includes(_ entry: BackupEntry) -> Bool {
        switch self {
        case .all: true
        case .tool(let tool): entry.effectiveTool == tool
        case .legacy: entry.effectiveTool == nil
        }
    }
}

@MainActor
@Observable
final class BackupsViewModel {

    enum CountState: Equatable {
        case loading
        case value(Int)
        case unreadable
    }

    struct Item: Identifiable {
        let entry: BackupEntry
        var count: CountState = .loading
        var id: URL { entry.id }
    }

    struct Banner {
        let text: String
        let isError: Bool
    }

    // MARK: État observé par la vue

    private(set) var hasLoaded = false
    private(set) var browsers: [ChromiumBrowser] = []
    private(set) var profiles: [ChromiumProfile] = []
    var selectedBrowserID: String?
    var selectedProfileID: String?

    /// Filtre affiché : toutes les sauvegardes, ou celles d'un outil.
    var selectedFilter: BackupFilter = .all

    private var allItems: [Item] = []
    private(set) var isBrowserRunning = false
    private(set) var syncStatus: BookmarkSyncStatus = .unknown
    private(set) var isRestoring = false
    private(set) var banner: Banner?

    /// Sauvegarde en attente de confirmation (la vue affiche alors une boîte de dialogue).
    var pendingRestore: BackupEntry?

    var selectedBrowser: ChromiumBrowser? {
        browsers.first { $0.id == selectedBrowserID }
    }

    var selectedProfile: ChromiumProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    /// Sauvegardes du filtre affiché.
    var items: [Item] {
        allItems.filter { selectedFilter.includes($0.entry) }
    }

    func count(in filter: BackupFilter) -> Int {
        allItems.filter { filter.includes($0.entry) }.count
    }

    /// Un filtre pour chaque outil, plus « Anciennes » tant qu'il en reste.
    var filters: [BackupFilter] {
        var result: [BackupFilter] = [.all]
        result += BackupTool.allCases.map { BackupFilter.tool($0) }
        if count(in: .legacy) > 0 { result.append(.legacy) }
        return result
    }

    // MARK: Sélection

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
        reloadBackups()
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

    // MARK: Liste

    func reloadBackups() {
        refreshSyncStatus()
        guard let profile = selectedProfile else {
            allItems = []
            selectedFilter = .all
            return
        }
        let entries = FaviconBackup.list(label: FaviconBackup.safeLabel(profile.id))
        allItems = entries.map { Item(entry: $0) }

        // Le filtre « Anciennes » disparaît quand il n'en reste plus.
        if !filters.contains(selectedFilter) { selectedFilter = .all }

        // Le contenu de chaque sauvegarde est compté ensuite, une par une.
        Task { await loadCounts(for: entries) }
    }

    private func loadCounts(for entries: [BackupEntry]) async {
        for entry in entries {
            let state: CountState
            if let count = await FaviconBackup.itemCount(of: entry) {
                state = .value(count)
            } else {
                state = .unreadable
            }
            if let index = allItems.firstIndex(where: { $0.id == entry.id }) {
                allItems[index].count = state
            }
        }
    }

    // MARK: Actions

    /// Peut-on restaurer cette sauvegarde maintenant ?
    /// Pour les favoris, la synchro active défairait la restauration au lancement suivant.
    func canRestore(_ item: Item) -> Bool {
        guard !isBrowserRunning, !isRestoring, item.count != .unreadable else { return false }
        if item.entry.category == .bookmarks && syncStatus == .enabled { return false }
        return true
    }

    func restore(_ entry: BackupEntry) {
        guard let profile = selectedProfile, !isRestoring else { return }
        refreshBrowserRunning()
        refreshSyncStatus()
        guard !isBrowserRunning else { return }
        if entry.category == .bookmarks && syncStatus == .enabled { return }

        let destination = entry.category == .favicons ? profile.faviconsURL : profile.bookmarksURL

        banner = nil
        isRestoring = true

        Task {
            do {
                guard await FaviconBackup.isReadable(entry) else {
                    throw BackupError.unreadable
                }
                if profile.isBrowserRunning {
                    throw SyncError.browserRunning(profile.browserName)
                }

                // Les copies de fichiers se font hors du thread principal.
                let safety = try await Task.detached {
                    try FaviconBackup.restore(entry, to: destination, label: profile.id)
                }.value

                let what = entry.category == .favicons ? "Base restaurée." : "Favoris restaurés."
                var text = "\(what) Relance \(profile.browserName) pour voir le résultat."
                if let safety {
                    text += " L'état précédent est conservé dans « \(safety.lastPathComponent) »."
                }
                banner = Banner(text: text, isError: false)
            } catch {
                banner = Banner(text: error.localizedDescription, isError: true)
            }
            isRestoring = false
            reloadBackups()
        }
    }

    func delete(_ entry: BackupEntry) {
        do {
            try FaviconBackup.delete(entry)
            banner = Banner(text: "Sauvegarde mise à la corbeille.", isError: false)
        } catch {
            banner = Banner(text: error.localizedDescription, isError: true)
        }
        reloadBackups()
    }

    func reveal(_ entry: BackupEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }

    func revealFolder() {
        try? FileManager.default.createDirectory(at: FaviconBackup.directory,
                                                 withIntermediateDirectories: true)
        NSWorkspace.shared.open(FaviconBackup.directory)
    }
}

nonisolated enum BackupError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unreadable: "Cette sauvegarde est illisible : elle n'a pas été appliquée."
        }
    }
}
