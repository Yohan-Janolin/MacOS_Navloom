import SwiftUI
import AppKit

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

    private(set) var items: [Item] = []
    private(set) var isBrowserRunning = false
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
        isBrowserRunning = selectedProfile?.isBrowserRunning ?? false
    }

    // MARK: Liste

    func reloadBackups() {
        guard let profile = selectedProfile else {
            items = []
            return
        }
        let entries = FaviconBackup.list(label: FaviconBackup.safeLabel(profile.id))
        items = entries.map { Item(entry: $0) }

        // Le nombre de favicons de chaque sauvegarde est lu ensuite, une par une.
        Task { await loadCounts(for: entries) }
    }

    private func loadCounts(for entries: [BackupEntry]) async {
        for entry in entries {
            let state: CountState
            if let database = try? FaviconDatabase(url: entry.url, writable: false),
               let count = try? await database.mappingCount() {
                state = .value(count)
            } else {
                state = .unreadable
            }
            if let index = items.firstIndex(where: { $0.id == entry.id }) {
                items[index].count = state
            }
        }
    }

    // MARK: Actions

    func restore(_ entry: BackupEntry) {
        guard let profile = selectedProfile, !isRestoring else { return }
        refreshBrowserRunning()
        guard !isBrowserRunning else { return }

        banner = nil
        isRestoring = true

        Task {
            do {
                guard await FaviconBackup.isReadable(entry.url) else {
                    throw BackupError.unreadable
                }
                if profile.isBrowserRunning {
                    throw SyncError.browserRunning(profile.browserName)
                }

                // Les copies de fichiers se font hors du thread principal.
                let safety = try await Task.detached {
                    try FaviconBackup.restore(entry, to: profile.faviconsURL, label: profile.id)
                }.value

                var text = "Base restaurée. Relance \(profile.browserName) pour voir le résultat."
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
