import Testing
import Foundation
@testable import Navloom

struct BookmarkSyncStatusTests {

    private func status(_ json: String) -> BookmarkSyncStatus {
        BookmarkSyncStatus.parse(Data(json.utf8))
    }

    // MARK: Réglages relevés sur de vrais profils

    @Test func detecteLaSynchroActiveCommeDansLesReglagesDeVivaldi() {
        #expect(status(#"{"sync":{"has_setup_completed":true,"keep_everything_synced":true,"bookmarks":true,"local_data_out_of_sync":false}}"#) == .enabled)
    }

    @Test func detecteLaSynchroActiveCommeDansLesReglagesDOpera() {
        // Opera, GX, Air et Developer : « Tout synchroniser » décoché, case Favoris cochée.
        #expect(status(#"{"sync":{"has_setup_completed":true,"keep_everything_synced":false,"bookmarks":true,"cached_persistent_auth_error":false,"typed_urls":true}}"#) == .enabled)
    }

    @Test func detecteLaSynchroActiveCommeDansLesReglagesDeBrave() {
        #expect(status(#"{"brave_sync_v2":{"account_deleted_notice_pending":false},"sync":{"apps":true,"bookmarks":true,"has_setup_completed":true,"keep_everything_synced":true}}"#) == .enabled)
    }

    @Test func detecteLaSynchroActiveCommeDansLesReglagesDEdge() {
        #expect(status(#"{"google":{"services":{"consented_to_sync":true}},"sync":{"bookmarks":true,"has_been_enabled":true,"has_setup_completed":true,"keep_everything_synced":true}}"#) == .enabled)
    }

    @Test func lesCasesParDefautSansCompteNeProuventRien() {
        // Edge sans compte : « bookmarks » et « apps » sont à true par défaut, mais pas has_setup_completed.
        #expect(status(#"{"sync":{"apps":true,"autofill":true,"bookmarks":true,"keep_everything_synced":false}}"#) == .disabled)
        // Opera GX sans compte.
        #expect(status(#"{"sync":{"keep_everything_synced":false,"encryption_bootstrap_token_per_account_migration_done":true}}"#) == .disabled)
    }

    // MARK: Cas généraux

    @Test func caseFavorisCocheeSansToutSynchroniser() {
        #expect(status(#"{"sync":{"has_setup_completed":true,"keep_everything_synced":false,"bookmarks":true}}"#) == .enabled)
    }

    @Test func favorisDecochesSansToutSynchroniser() {
        #expect(status(#"{"sync":{"has_setup_completed":true,"keep_everything_synced":false,"bookmarks":false,"passwords":true}}"#) == .disabled)
    }

    @Test func pasDeCompteConfigure() {
        #expect(status(#"{"sync":{"has_setup_completed":false,"keep_everything_synced":true,"bookmarks":true}}"#) == .disabled)
        #expect(status(#"{"autre":1}"#) == .disabled)
    }

    @Test func fichierIllisibleDonneInconnu() {
        #expect(status("pas du JSON") == .unknown)
    }

    // MARK: Lecture du fichier Preferences d'un profil

    @Test func unNavigateurInconnuDonneInconnu() {
        let profile = ChromiumProfile(id: "inconnu/Default", name: "Default",
                                      directory: URL(fileURLWithPath: "/tmp"),
                                      browserName: "Test", bundleID: "test.bundle")
        #expect(BookmarkSyncStatus.detect(for: profile) == .unknown)
    }

    // MARK: Chrome

    @Test func chromeConnecteSansSynchroCompleteNeSynchronisePasLeFichierLocal() {
        // Réglages relevés : compte connecté (selected_types_per_account), pas de has_setup_completed,
        // pas de consented_to_sync. Que « sync.bookmarks » soit à true ou à false, le fichier
        // Bookmarks n'est pas concerné (les favoris du compte sont dans AccountBookmarks).
        let connecte = #"{"sync":{"selected_types_per_account":{"hash":{"sync.tabs":true,"sync.bookmarks":true}}}}"#
        let optionDesactivee = #"{"sync":{"selected_types_per_account":{"hash":{"sync.tabs":true,"sync.bookmarks":false}}}}"#
        #expect(BookmarkSyncStatus.parseChrome(Data(connecte.utf8)) == .disabled)
        #expect(BookmarkSyncStatus.parseChrome(Data(optionDesactivee.utf8)) == .disabled)
    }

    @Test func chromeAvecConsentementALaSynchroBloqueLaSuppression() {
        let json = #"{"google":{"services":{"consented_to_sync":true}}}"#
        #expect(BookmarkSyncStatus.parseChrome(Data(json.utf8)) == .enabled)
    }

    @Test func chromeFichierIllisibleDonneInconnu() {
        #expect(BookmarkSyncStatus.parseChrome(Data("pas du JSON".utf8)) == .unknown)
    }

    @Test func litLeFichierPreferencesDeChrome() throws {
        let fm = FileManager.default
        for id in ["chrome", "chromeBeta", "chromeCanary"] {
            let dir = fm.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: dir) }

            try Data(#"{"sync":{"selected_types_per_account":{"hash":{"sync.bookmarks":true}}}}"#.utf8)
                .write(to: dir.appending(path: "Preferences"))
            let profile = ChromiumProfile(id: "\(id)/Default", name: "Default", directory: dir,
                                          browserName: "Chrome", bundleID: "com.google.Chrome")

            #expect(BookmarkSyncStatus.detect(for: profile) == .disabled, "\(id)")
        }
    }

    @Test func litLeFichierPreferencesDesNavigateursVerifies() throws {
        let fm = FileManager.default
        let ids = ["vivaldi", "vivaldiSnapshot", "brave", "braveBeta", "braveNightly",
                   "edge", "edgeBeta", "edgeDev", "edgeCanary",
                   "opera", "operaGX", "operaAir", "operaDeveloper"]

        for id in ids {
            let dir = fm.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: dir) }

            try Data(#"{"sync":{"has_setup_completed":true,"keep_everything_synced":true}}"#.utf8)
                .write(to: dir.appending(path: "Preferences"))
            let profile = ChromiumProfile(id: "\(id)/Default", name: "Default", directory: dir,
                                          browserName: "Test", bundleID: "test.bundle")

            #expect(BookmarkSyncStatus.detect(for: profile) == .enabled, "\(id)")
        }
    }

    @Test func chromiumSansPreferencesDeSynchroEstDesactive() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        try Data(#"{"profile":{"name":"Personne 1"}}"#.utf8).write(to: dir.appending(path: "Preferences"))
        let profile = ChromiumProfile(id: "chromium/Default", name: "Default", directory: dir,
                                      browserName: "Chromium", bundleID: "org.chromium.Chromium")

        #expect(BookmarkSyncStatus.detect(for: profile) == .disabled)
    }
}
