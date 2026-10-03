//
//  BookmarkSyncStatusTests.swift
//  Navloom
//

import Testing
import Foundation
@testable import Navloom

struct BookmarkSyncStatusTests {

    private func status(_ json: String) -> BookmarkSyncStatus {
        BookmarkSyncStatus.parse(Data(json.utf8))
    }

    @Test func detecteLaSynchroActiveCommeDansLesReglagesDeVivaldi() {
        // Clés relevées sur un vrai profil Vivaldi avec la synchro activée.
        #expect(status(#"{"sync":{"has_setup_completed":true,"keep_everything_synced":true,"bookmarks":true,"local_data_out_of_sync":false}}"#) == .enabled)
    }

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

    @Test func navigateurNonVerifieDonneInconnu() {
        let profile = ChromiumProfile(id: "opera/Default", name: "Default",
                                      directory: URL(fileURLWithPath: "/tmp"),
                                      browserName: "Opera", bundleID: "com.operasoftware.Opera")
        #expect(BookmarkSyncStatus.detect(for: profile) == .unknown)
    }

    @Test func litLeFichierPreferencesDeVivaldi() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        try Data(#"{"sync":{"has_setup_completed":true,"keep_everything_synced":true}}"#.utf8)
            .write(to: dir.appending(path: "Preferences"))
        let profile = ChromiumProfile(id: "vivaldi/Default", name: "Default", directory: dir,
                                      browserName: "Vivaldi", bundleID: "com.vivaldi.Vivaldi")

        #expect(BookmarkSyncStatus.detect(for: profile) == .enabled)
    }
}
