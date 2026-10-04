import Testing
import Foundation
@testable import Navloom

struct BookmarkBackupTests {

    @Test func reconnaitUneSauvegardeDeFavoris() throws {
        let url = URL(fileURLWithPath: "/tmp/vivaldi-Default-Bookmarks-2026-10-04T10-00-00+02-00.json")
        let entry = try #require(FaviconBackup.entry(for: url))

        #expect(entry.category == .bookmarks)
        #expect(entry.label == "vivaldi-Default")
        #expect(entry.kind == .beforeWrite)
    }

    @Test func reconnaitUneSauvegardeDeFavorisAvantRestauration() throws {
        let url = URL(fileURLWithPath: "/tmp/vivaldi-Default-Bookmarks-2026-10-04T10-00-00+02-00-avant-restauration.json")
        let entry = try #require(FaviconBackup.entry(for: url))

        #expect(entry.category == .bookmarks)
        #expect(entry.kind == .beforeRestore)
    }

    @Test func lesSauvegardesFaviconsRestentDansLeurCategorie() throws {
        let url = URL(fileURLWithPath: "/tmp/vivaldi-Default-Favicons-2026-10-04T10-00-00Z.sqlite")
        #expect(try #require(FaviconBackup.entry(for: url)).category == .favicons)
        // Un .json dont le nom ne suit pas le format n'est pas une sauvegarde.
        #expect(FaviconBackup.entry(for: URL(fileURLWithPath: "/tmp/notes.json")) == nil)
    }

    @Test func laSauvegardeCreeeAvantUneSuppressionApparaitDansLaListe() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let file = root.appending(path: "Bookmarks")
        try Data(#"{"roots":{}}"#.utf8).write(to: file)
        let backups = root.appending(path: "Backups", directoryHint: .isDirectory)

        _ = try BookmarksWriter.backupFile(file, label: "vivaldi/Default", in: backups)

        let entries = FaviconBackup.list(label: "vivaldi-Default", in: backups)
        #expect(entries.count == 1)
        #expect(entries.first?.category == .bookmarks)
    }

    @Test func restaureUneSauvegardeDeFavorisEtConserveLEtatPrecedent() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let backups = root.appending(path: "Backups", directoryHint: .isDirectory)
        try fm.createDirectory(at: backups, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let destination = root.appending(path: "Bookmarks")
        try Data("actuel".utf8).write(to: destination)
        let saved = backups.appending(path: "vivaldi-Default-Bookmarks-2026-10-04T10-00-00Z.json")
        try Data("sauvegarde".utf8).write(to: saved)

        let entry = try #require(FaviconBackup.entry(for: saved))
        let safety = try FaviconBackup.restore(entry, to: destination, label: "vivaldi/Default", in: backups)

        #expect(try Data(contentsOf: destination) == Data("sauvegarde".utf8))
        let safetyURL = try #require(safety)
        #expect(try Data(contentsOf: safetyURL) == Data("actuel".utf8))
        // La copie de sécurité est aussi une sauvegarde de favoris, pas de favicons.
        #expect(FaviconBackup.entry(for: safetyURL)?.category == .bookmarks)
        #expect(FaviconBackup.entry(for: safetyURL)?.kind == .beforeRestore)
    }

    @Test func nettoyageCompteChaqueCategorieSeparement() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        // 3 sauvegardes « avant écriture » de chaque catégorie.
        for hour in 10...12 {
            try Data().write(to: dir.appending(path: "vivaldi-Default-Favicons-2026-09-30T\(hour)-00-00Z.sqlite"))
            try Data().write(to: dir.appending(path: "vivaldi-Default-Bookmarks-2026-09-30T\(hour)-00-00Z.json"))
        }

        let removed = FaviconBackup.prune(
            label: "vivaldi/Default",
            retention: BackupRetention(keepBeforeWrite: 1, keepBeforeRestore: 1),
            in: dir,
            remover: { try FileManager.default.removeItem(at: $0) }
        )

        // 2 retirées par catégorie, 1 gardée par catégorie.
        #expect(removed == 4)
        let remaining = FaviconBackup.list(in: dir)
        #expect(remaining.filter { $0.category == .favicons }.count == 1)
        #expect(remaining.filter { $0.category == .bookmarks }.count == 1)
    }
}
