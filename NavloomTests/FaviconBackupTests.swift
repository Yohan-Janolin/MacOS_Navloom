import Testing
import Foundation
@testable import Navloom

struct FaviconBackupTests {

    @Test func decritUneSauvegardeDepuisSonNom() throws {
        let url = URL(fileURLWithPath: "/tmp/vivaldi-Profile 1-Favicons-2026-09-30T12-15-00Z.sqlite")
        let entry = try #require(FaviconBackup.entry(for: url))

        #expect(entry.label == "vivaldi-Profile 1")
        #expect(entry.kind == .beforeWrite)
        #expect(entry.date == ISO8601DateFormatter().date(from: "2026-09-30T12:15:00Z"))
    }

    @Test func reconnaitUneCopieAvantRestauration() throws {
        let url = URL(fileURLWithPath: "/tmp/vivaldi-Default-Favicons-2026-09-30T12-15-00Z-avant-restauration.sqlite")
        let entry = try #require(FaviconBackup.entry(for: url))

        #expect(entry.label == "vivaldi-Default")
        #expect(entry.kind == .beforeRestore)
    }

    @Test func ignoreLesFichiersQuiNeSontPasDesSauvegardes() {
        #expect(FaviconBackup.entry(for: URL(fileURLWithPath: "/tmp/notes.txt")) == nil)
        #expect(FaviconBackup.entry(for: URL(fileURLWithPath: "/tmp/quelquechose.sqlite")) == nil)
    }

    @Test func restaureEtConserveLEtatPrecedent() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let backups = root.appending(path: "Backups", directoryHint: .isDirectory)
        try fm.createDirectory(at: backups, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // La base actuelle du navigateur, et une ancienne sauvegarde
        let destination = root.appending(path: "Favicons")
        try Data("actuel".utf8).write(to: destination)
        let saved = backups.appending(path: "vivaldi-Default-Favicons-2026-09-30T12-15-00Z.sqlite")
        try Data("sauvegarde".utf8).write(to: saved)

        let entry = try #require(FaviconBackup.entry(for: saved))
        let safety = try FaviconBackup.restore(entry, to: destination, label: "vivaldi/Default", in: backups)

        // La base contient maintenant la sauvegarde…
        #expect(try Data(contentsOf: destination) == Data("sauvegarde".utf8))
        // …et l'état précédent a été conservé dans une copie « avant restauration ».
        let safetyURL = try #require(safety)
        #expect(try Data(contentsOf: safetyURL) == Data("actuel".utf8))
        #expect(FaviconBackup.entry(for: safetyURL)?.kind == .beforeRestore)
    }
    
    @Test func nettoyageGardeLesPlusRecentes() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        // 5 sauvegardes « avant écriture » (10 h à 14 h) et 1 « avant restauration »
        for hour in 10...14 {
            try Data().write(to: dir.appending(path: "vivaldi-Default-Favicons-2026-09-30T\(hour)-00-00Z.sqlite"))
        }
        try Data().write(to: dir.appending(path: "vivaldi-Default-Favicons-2026-09-30T09-00-00Z-avant-restauration.sqlite"))

        let removed = FaviconBackup.prune(
            label: "vivaldi/Default",
            retention: BackupRetention(keepBeforeWrite: 2, keepBeforeRestore: 1),
            in: dir,
            remover: { try FileManager.default.removeItem(at: $0) }   // pas de corbeille dans un test
        )

        #expect(removed == 3)
        let remaining = FaviconBackup.list(in: dir)
        #expect(remaining.filter { $0.kind == .beforeWrite }.count == 2)
        #expect(remaining.contains { $0.kind == .beforeRestore })
    }
}
