import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
@Observable
final class FaviconSyncViewModel {

    /// Les étapes de l'écran, dans l'ordre.
    enum Phase: Equatable {
        case idle, analyzing, analyzed, fetching, fetched, writing, done
    }

    enum ResultCategory: String, CaseIterable, Identifiable {
        case fetched = "Récupérées"
        case none = "Sans favicon"
        case failed = "Échecs"
        var id: String { rawValue }
    }

    struct ResultRow: Identifiable {
        let id = UUID()
        let name: String
        let url: String
        let detail: String?
        let iconData: Data?
    }

    // MARK: État observé par la vue

    private(set) var hasLoaded = false
    private(set) var browsers: [ChromiumBrowser] = []
    private(set) var profiles: [ChromiumProfile] = []
    var selectedBrowserID: String?
    var selectedProfileID: String?

    private(set) var phase: Phase = .idle
    private(set) var analysis: SyncAnalysis?
    private(set) var fetchResult: SyncFetchResult?
    private(set) var summary: WriteSummary?
    private(set) var errorMessage: String?

    private(set) var rows: [ResultCategory: [ResultRow]] = [:]
    var selectedCategory: ResultCategory = .fetched

    private(set) var progressPass = 1
    private(set) var progressDone = 0
    private(set) var progressTotal = 0
    private(set) var currentOrigin = ""
    private(set) var isBrowserRunning = false

    private var engine: FaviconSyncEngine?

    // MARK: Calculés

    var selectedBrowser: ChromiumBrowser? {
        browsers.first { $0.id == selectedBrowserID }
    }

    var selectedProfile: ChromiumProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    /// Vrai pendant qu'une opération tourne : on verrouille alors les sélecteurs.
    var isBusy: Bool {
        phase == .analyzing || phase == .fetching || phase == .writing
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

    /// Retour à l'état initial (changement de profil, bouton Annuler…).
    func reset() {
        guard !isBusy else { return }
        phase = .idle
        analysis = nil
        fetchResult = nil
        summary = nil
        errorMessage = nil
        rows = [:]
        engine = nil
    }

    // MARK: Étape 1 : analyse

    func analyze() {
        guard let profile = selectedProfile, !isBusy else { return }
        reset()
        phase = .analyzing

        let engine = FaviconSyncEngine(profile: profile)
        self.engine = engine

        Task {
            do {
                analysis = try await engine.analyze()
                phase = .analyzed
            } catch {
                fail(error, returnTo: .idle)
            }
        }
    }

    // MARK: Étape 2 : téléchargement

    func fetch() {
        guard let engine, let analysis, !isBusy else { return }
        errorMessage = nil
        progressPass = 1
        progressDone = 0
        progressTotal = 0
        currentOrigin = ""
        phase = .fetching

        // Le moteur tourne hors du thread principal et envoie ses évènements dans ce flux ;
        // on les lit ici, dans l'ordre, pour mettre à jour l'écran.
        let (stream, continuation) = AsyncStream.makeStream(of: SyncEvent.self)

        Task {
            let listener = Task {
                for await event in stream { handle(event) }
            }
            let result = await engine.fetchMissing(analysis) { continuation.yield($0) }
            continuation.finish()
            await listener.value

            fetchResult = result
            buildRows(from: result)
            phase = .fetched
        }
    }

    private func handle(_ event: SyncEvent) {
        switch event {
        case .resolved(let pass, let done, let total, let origin, _):
            progressPass = pass
            progressDone = done
            progressTotal = total
            currentOrigin = origin
        case .retrying(let count, _):
            progressPass = 2
            progressDone = 0
            progressTotal = count
            currentOrigin = "Pause avant le second passage…"
        }
    }

    private func buildRows(from result: SyncFetchResult) {
        rows[.fetched] = result.fetched.map {
            ResultRow(name: $0.bookmark.name, url: $0.bookmark.url,
                      detail: $0.origin.label, iconData: $0.iconData)
        }
        rows[.none] = result.confirmedNone.map {
            ResultRow(name: $0.bookmark.name, url: $0.bookmark.url, detail: $0.reason, iconData: nil)
        }
        rows[.failed] = result.failures.map {
            ResultRow(name: $0.bookmark.name, url: $0.bookmark.url, detail: $0.reason, iconData: nil)
        }
        selectedCategory = result.fetched.isEmpty && !result.failures.isEmpty ? .failed : .fetched
    }

    // MARK: Étape 3 : écriture

    func refreshBrowserRunning() {
        isBrowserRunning = selectedProfile?.isBrowserRunning ?? false
    }

    func apply() {
        guard let engine, let fetchResult, !isBusy else { return }
        refreshBrowserRunning()
        guard !isBrowserRunning else { return }

        errorMessage = nil
        phase = .writing

        Task {
            do {
                summary = try await engine.write(fetchResult)
                phase = .done
            } catch {
                fail(error, returnTo: .fetched)
            }
        }
    }

    // MARK: Export du rapport

    func exportReport() {
        guard let analysis, let fetchResult, let profile = selectedProfile else { return }

        let text = SyncReport.text(browserName: profile.browserName,
                                   profileName: profile.name,
                                   analysis: analysis,
                                   fetchResult: fetchResult,
                                   summary: summary)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "faviconsync-rapport.txt"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Impossible d'écrire le rapport : \(error.localizedDescription)"
        }
    }
    
    func revealBackup() {
        guard let url = summary?.backupURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: Erreurs

    private func fail(_ error: Error, returnTo phase: Phase) {
        errorMessage = error.localizedDescription
        self.phase = phase
    }
}
