//
//  BookmarksWriterTests.swift
//  Navloom
//

import Testing
import Foundation
@testable import Navloom

struct BookmarksWriterTests {

    private let sample = """
    {
      "checksum": "abc",
      "roots": {
        "bookmark_bar": {"id":"1","name":"Barre","type":"folder","children":[
          {"id":"3","name":"Swift","type":"url","url":"https://swift.org/","meta_info":{"Nickname":"sw"}},
          {"id":"4","name":"Swift bis","type":"url","url":"https://swift.org/"},
          {"id":"5","name":"Dossier","type":"folder","children":[
            {"id":"6","name":"Apple","type":"url","url":"https://apple.com/"}
          ]}
        ]},
        "other": {"id":"2","name":"Autres","type":"folder","children":[]},
        "sync_transaction_version": "7"
      },
      "version": 1
    }
    """

    @Test func retireSeulementLesFavorisDemandes() throws {
        let (data, removed) = try BookmarksWriter.removing(ids: ["4", "6"], from: Data(sample.utf8))
        let bookmarks = try BookmarksReader.parse(data)

        #expect(removed == 2)
        #expect(bookmarks.map(\.nodeID) == ["3"])
    }

    @Test func conserveCeQueLEonNeComprendPas() throws {
        let (data, _) = try BookmarksWriter.removing(ids: ["4"], from: Data(sample.utf8))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let roots = try #require(root["roots"] as? [String: Any])
        let bar = try #require(roots["bookmark_bar"] as? [String: Any])
        let children = try #require(bar["children"] as? [[String: Any]])
        let meta = try #require(children.first?["meta_info"] as? [String: Any])

        #expect(meta["Nickname"] as? String == "sw")
        #expect(roots["sync_transaction_version"] as? String == "7")
        #expect(root["version"] as? Int == 1)
        // Le total de contrôle périmé est retiré (Chromium le recalcule).
        #expect(root["checksum"] == nil)
        // Les dossiers sont toujours là, même vidés.
        #expect(children.contains { $0["id"] as? String == "5" })
    }

    @Test func neSupprimeJamaisUnDossier() throws {
        let (_, removed) = try BookmarksWriter.removing(ids: ["5", "1"], from: Data(sample.utf8))
        #expect(removed == 0)
    }

    @Test func refuseUnFichierQuiNEstPasUnBookmarks() {
        #expect(throws: BookmarksWriteError.self) {
            try BookmarksWriter.removing(ids: ["1"], from: Data(#"{"foo": 1}"#.utf8))
        }
    }

    @Test func sauvegardeEtRemplaceLeFichier() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let backups = root.appending(path: "Backups", directoryHint: .isDirectory)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let file = root.appending(path: "Bookmarks")
        try Data(sample.utf8).write(to: file)

        let summary = try BookmarksWriter.removeBookmarks(ids: ["4"], in: file,
                                                          label: "vivaldi/Default",
                                                          backupDirectory: backups)

        #expect(summary.removed == 1)
        // La sauvegarde est l'ancien fichier, à l'octet près…
        #expect(try Data(contentsOf: summary.backupURL) == Data(sample.utf8))
        #expect(summary.backupURL.lastPathComponent.hasPrefix("vivaldi-Default-Bookmarks-"))
        // …et le fichier du navigateur n'a plus le favori.
        #expect(try BookmarksReader.read(from: file).map(\.nodeID) == ["3", "6"])
    }

    @Test func nEcritRienSiLeFichierADepuisChange() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let backups = root.appending(path: "Backups", directoryHint: .isDirectory)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let file = root.appending(path: "Bookmarks")
        try Data(sample.utf8).write(to: file)

        // « 99 » n'existe pas : le fichier a changé depuis l'analyse.
        #expect(throws: BookmarksWriteError.self) {
            try BookmarksWriter.removeBookmarks(ids: ["4", "99"], in: file,
                                                label: "vivaldi/Default", backupDirectory: backups)
        }
        #expect(try Data(contentsOf: file) == Data(sample.utf8))
        #expect(!fm.fileExists(atPath: backups.path))
    }
}
