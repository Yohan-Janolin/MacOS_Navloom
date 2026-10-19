import SwiftUI
import AppKit

@MainActor
@Observable
final class EchoViewModel {

    enum Phase: Equatable {
        case idle, comparing, done, applying, applied
    }

    // MARK: État observé par la vue

    private(set) var hasLoaded = false
    private(set) var browsers: [ChromiumBrowser] = []

    /// Source : navigateur et profils du navigateur choisi.
    private(set) var profiles: [ChromiumProfile] = []
    var selectedBrowserID: String?
    var selectedProfileID: String?

    /// Destination : navigateur et profils du navigateur choisi.
    private(set) var destinationProfiles: [ChromiumProfile] = []
    var destinationBrowserID: String?
    var destinationProfileID: String?

    /// Ajouter ce qui manque, ou rendre la cible identique à la source.
    var syncMode: EchoSyncMode = .merge

    var matchMode: EchoMatchMode = .anywhere

    /// Variantes d'URL à considérer comme identiques (le « / » final est toujours ignoré).
    var ignoreScheme = false
    var ignoreWWW = false
    var ignoreQuery = false

    /// Copier aussi les icônes des favoris ajoutés (celles de la source, sans les retélécharger).
    var copyFavicons = true

    private(set) var phase: Phase = .idle
    private(set) var report: EchoReport?
    private(set) var summary: EchoApplySummary?
    private(set) var errorMessage: String?

    /// Ce qui peut bloquer l'écriture dans la destination.
    private(set) var isDestinationRunning = false
    private(set) var destinationSyncStatus: BookmarkSyncStatus = .unknown

    /// Vrai quand la boîte de dialogue de confirmation doit s'afficher.
    var showConfirmation = false

    // MARK: Calculés

    var selectedBrowser: ChromiumBrowser? {
        browsers.first { $0.id == selectedBrowserID }
    }

    var selectedProfile: ChromiumProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    var destinationBrowser: ChromiumBrowser? {
        browsers.first { $0.id == destinationBrowserID }
    }

    var destinationProfile: ChromiumProfile? {
        destinationProfiles.first { $0.id == destinationProfileID }
    }

    var isBusy: Bool { phase == .comparing || phase == .applying }

    var urlOptions: EchoURLOptions {
        EchoURLOptions(ignoreScheme: ignoreScheme, ignoreWWW: ignoreWWW, ignoreQuery: ignoreQuery)
    }

    /// On ne réplique pas un profil sur lui-même.
    var isSameProfile: Bool {
        selectedProfileID != nil && selectedProfileID == destinationProfileID
    }

    var canCompare: Bool {
        selectedProfile != nil && destinationProfile != nil && !isSameProfile && !isBusy
    }

    /// Il y a quelque chose à écrire dans la cible, selon le mode choisi.
    var hasChanges: Bool {
        guard let report else { return false }
        switch syncMode {
        case .merge: return !report.plan.toAdd.isEmpty
        case .mirror: return !report.mirror.isIdentical
        }
    }

    /// L'écriture est bloquée si la cible est ouverte, ou si sa synchro des favoris est active :
    /// au lancement suivant, elle mélangerait les favoris écrits avec ceux du compte.
    var canApply: Bool {
        phase == .done && hasChanges && !isDestinationRunning && destinationSyncStatus != .enabled
    }

    // MARK: Sélection

    func loadBrowsersIfNeeded() {
        guard !hasLoaded else { return }
        browsers = ChromiumBrowser.installed()

        if !browsers.contains(where: { $0.id == selectedBrowserID }) {
            selectedBrowserID = browsers.first(where: { $0.id == "vivaldi" })?.id ?? browsers.first?.id
        }
        browserChanged()

        // Destination par défaut : un autre navigateur si possible.
        if !browsers.contains(where: { $0.id == destinationBrowserID }) {
            destinationBrowserID = browsers.first(where: { $0.id != selectedBrowserID })?.id ?? selectedBrowserID
        }
        destinationBrowserChanged()

        hasLoaded = true
    }

    func browserChanged() {
        profiles = selectedBrowser?.profiles() ?? []
        if !profiles.contains(where: { $0.id == selectedProfileID }) {
            selectedProfileID = profiles.first?.id
        }
        reset()
    }

    func profileChanged() {
        reset()
    }

    func destinationBrowserChanged() {
        destinationProfiles = destinationBrowser?.profiles() ?? []
        if !destinationProfiles.contains(where: { $0.id == destinationProfileID }) {
            // Si possible, un profil différent de la source.
            destinationProfileID = (destinationProfiles.first { $0.id != selectedProfileID }
                                    ?? destinationProfiles.first)?.id
        }
        reset()
    }

    func destinationProfileChanged() {
        reset()
    }

    /// Retour à l'état initial (les choix de source et de destination sont conservés).
    func reset() {
        guard !isBusy else { return }
        phase = .idle
        report = nil
        summary = nil
        errorMessage = nil
    }

    // MARK: Comparaison (lecture seule)

    func compare() {
        guard canCompare, let source = selectedProfile, let destination = destinationProfile else { return }
        let mode = matchMode
        let options = urlOptions

        reset()
        phase = .comparing

        Task {
            do {
                report = try await Task.detached {
                    try EchoEngine.compare(source: source, destination: destination,
                                           mode: mode, options: options)
                }.value
                refreshDestinationRunning()
                refreshDestinationSync()
                phase = .done
            } catch {
                errorMessage = error.localizedDescription
                phase = .idle
            }
        }
    }

    // MARK: Surveillance de la destination

    func refreshDestinationRunning() {
        let wasRunning = isDestinationRunning
        isDestinationRunning = destinationProfile?.isBrowserRunning ?? false

        // Le navigateur écrit ses réglages en quittant : on relit la synchro quand il vient de se fermer.
        if wasRunning && !isDestinationRunning {
            refreshDestinationSync()
        }
    }

    func refreshDestinationSync() {
        destinationSyncStatus = destinationProfile.map(BookmarkSyncStatus.detect(for:)) ?? .unknown
    }

    // MARK: Écriture (destination fermée obligatoire, sauvegardes automatiques)

    func apply() {
        guard phase == .done, let report else { return }
        refreshDestinationRunning()
        refreshDestinationSync()
        guard canApply else { return }

        errorMessage = nil
        phase = .applying

        let syncMode = syncMode
        let mode = matchMode
        let options = urlOptions
        let copy = copyFavicons

        Task {
            do {
                summary = try await Task.detached {
                    try await EchoEngine.apply(report, syncMode: syncMode, mode: mode,
                                               options: options, copyFavicons: copy)
                }.value
                phase = .applied
            } catch {
                errorMessage = error.localizedDescription
                phase = .done
            }
        }
    }

    /// Montre les sauvegardes créées avant l'écriture.
    func revealBackups() {
        guard let summary else { return }
        NSWorkspace.shared.activateFileViewerSelecting(
            [summary.bookmarksBackupURL] + (summary.faviconsBackupURL.map { [$0] } ?? []))
    }
}
