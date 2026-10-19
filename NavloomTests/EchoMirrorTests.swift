import Testing
import Foundation
@testable import Navloom

// MARK: - Outils communs

private nonisolated func mRoots(_ data: Data) throws -> [String: Any] {
    let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    return try #require(root["roots"] as? [String: Any])
}

private nonisolated func mChildren(_ data: Data, root: String) throws -> [[String: Any]] {
    let node = try #require(try mRoots(data)[root] as? [String: Any])
    return node["children"] as? [[String: Any]] ?? []
}

private nonisolated func mSnapshot(_ json: String) throws -> EchoSnapshot {
    try EchoReader.parse(Data(json.utf8))
}

private nonisolated let mManagedFolder =
    #"{"id":"20","name":"Speed Dial","type":"folder","meta_info":{"Speeddial":"true"},"children":[{"id":"21","name":"S","type":"url","url":"https://s.fr"}]}"#

private nonisolated let mTrashFolder =
    #"{"id":"30","name":"Corbeille","type":"folder","meta_info":{"Trash":"true"},"children":[{"id":"31","name":"T","type":"url","url":"https://t.fr"}]}"#

// MARK: - Lecture : dossiers gérés par le navigateur

struct EchoManagedFolderTests {

    @Test func laLectureIgnoreSpeedDialEtCorbeille() throws {
        let json = wFile(bar: [mManagedFolder, wNode(id: 5, "X", url: "https://x.fr")], other: [mTrashFolder])
        let snapshot = try mSnapshot(json)

        #expect(snapshot.bookmarks.map(\.url) == ["https://x.fr"])
        #expect(snapshot.folders.isEmpty)
        #expect(snapshot.layout.count == 1)
    }

    @Test func unDossierNormalAvecUneMetaInfoQuelconqueEstLu() throws {
        let folder = #"{"id":"8","name":"Perso","type":"folder","meta_info":{"Nickname":"p"},"children":[{"id":"9","name":"P","type":"url","url":"https://p.fr"}]}"#
        let snapshot = try mSnapshot(wFile(bar: [folder]))

        #expect(snapshot.bookmarks.map(\.url) == ["https://p.fr"])
        #expect(snapshot.folders == [EchoFolder(rootKey: "bookmark_bar", path: ["Perso"])])
    }

    @Test func lesRacinesPresentesSontConnues() throws {
        #expect(try mSnapshot(wFile()).rootKeys == ["bookmark_bar", "other"])
        #expect(try mSnapshot(wFile(withSynced: true)).rootKeys == ["bookmark_bar", "other", "synced"])
    }
}

// MARK: - Plan de copie complète

struct EchoMirrorPlanTests {

    @Test func compteCeQuiEstAjouteSupprimeEtIdentique() throws {
        let source = try mSnapshot(wFile(bar: [wNode(id: 3, "A", url: "https://a.fr"), wNode(id: 4, "B", url: "https://b.fr")]))
        let destination = try mSnapshot(wFile(bar: [wNode(id: 3, "B", url: "https://b.fr"), wNode(id: 4, "X", url: "https://x.fr")]))

        let plan = EchoPlanner.mirrorPlan(source: source, destination: destination)

        #expect(plan.toAdd.map(\.url) == ["https://a.fr"])
        #expect(plan.toRemove.map(\.url) == ["https://x.fr"])
        #expect(plan.unchanged == 1)
        #expect(plan.removalCount == 1)
        #expect(!plan.isIdentical)
    }

    @Test func deuxProfilsIdentiquesNeFontRien() throws {
        let json = wFile(bar: [wNode(id: 3, "A", url: "https://a.fr"),
                               wFolder(id: 4, "Dev", wNode(id: 5, "C", url: "https://c.fr"))])
        let plan = EchoPlanner.mirrorPlan(source: try mSnapshot(json), destination: try mSnapshot(json))

        #expect(plan.isIdentical)
        #expect(plan.toAdd.isEmpty && plan.toRemove.isEmpty)
        #expect(plan.unchanged == 2)
    }

    @Test func unAutreOrdreNEstPasIdentique() throws {
        let source = try mSnapshot(wFile(bar: [wNode(id: 3, "A", url: "https://a.fr"), wNode(id: 4, "B", url: "https://b.fr")]))
        let destination = try mSnapshot(wFile(bar: [wNode(id: 3, "B", url: "https://b.fr"), wNode(id: 4, "A", url: "https://a.fr")]))

        let plan = EchoPlanner.mirrorPlan(source: source, destination: destination)

        #expect(plan.toAdd.isEmpty && plan.toRemove.isEmpty)
        #expect(!plan.isIdentical)
    }

    @Test func uneURLAvecOuSansSlashFinalEstUneDifference() throws {
        let source = try mSnapshot(wFile(bar: [wNode(id: 3, "A", url: "https://a.fr/")]))
        let destination = try mSnapshot(wFile(bar: [wNode(id: 3, "A", url: "https://a.fr")]))

        let plan = EchoPlanner.mirrorPlan(source: source, destination: destination)

        #expect(plan.toAdd.count == 1 && plan.toRemove.count == 1)
    }

    @Test func compteLesDossiersAjoutesEtSupprimes() throws {
        let source = try mSnapshot(wFile(bar: [wFolder(id: 3, "Neuf", wNode(id: 4, "C", url: "https://c.fr"))]))
        let destination = try mSnapshot(wFile(bar: [wFolder(id: 3, "Vieux", wNode(id: 4, "Z", url: "https://z.fr"))]))

        let plan = EchoPlanner.mirrorPlan(source: source, destination: destination)

        #expect(plan.foldersToAdd == 1)
        #expect(plan.foldersToRemove == 1)
    }

    @Test func lesFavorisNonWebDeLaCibleSontComptesPourSuppression() throws {
        let internalNode = #"{"id":"9","name":"Réglages","type":"url","url":"vivaldi://settings"}"#
        let json = wFile(bar: [wNode(id: 3, "A", url: "https://a.fr")])
        let destination = try mSnapshot(wFile(bar: [wNode(id: 3, "A", url: "https://a.fr"), internalNode]))

        let plan = EchoPlanner.mirrorPlan(source: try mSnapshot(json), destination: destination)

        #expect(plan.nonWebToRemove == 1)
        #expect(plan.removalCount == 1)
        #expect(!plan.isIdentical)
    }

    @Test func uneRacineAbsenteDeLaCibleVaDansAutresFavoris() throws {
        let synced = #"{"roots":{"bookmark_bar":{"id":"1","name":"B","type":"folder","children":[]},"other":{"id":"2","name":"O","type":"folder","children":[]},"synced":{"id":"3","name":"M","type":"folder","children":[{"id":"4","name":"S","type":"url","url":"https://s.fr"}]}}}"#
        let plan = EchoPlanner.mirrorPlan(source: try mSnapshot(synced), destination: try mSnapshot(wFile()))

        #expect(plan.toAdd.map(\.rootKey) == ["other"])
        #expect(!plan.isIdentical)
    }
}

// MARK: - Réécriture

struct EchoMirrorWriterTests {

    private let source = wFile(bar: [
        wNode(id: 3, "A", url: "https://a.fr"),
        wFolder(id: 4, "Dev", wNode(id: 5, "C", url: "https://c.fr"), wNode(id: 6, "D", url: "https://d.fr")),
        wNode(id: 7, "B", url: "https://b.fr"),
    ])

    private let target = wFile(bar: [
        wNode(id: 3, "B", url: "https://b.fr"),
        wNode(id: 4, "X", url: "https://x.fr"),
        wFolder(id: 5, "Dev", wNode(id: 6, "D", url: "https://d.fr"), wNode(id: 7, "Z", url: "https://z.fr")),
    ], other: [wNode(id: 8, "O", url: "https://o.fr")])

    @Test func laCibleDevientLImageDeLaSourceDansLeMemeOrdre() throws {
        let result = try EchoWriter.mirroring(source: Data(source.utf8), into: Data(target.utf8))

        let after = try EchoReader.parse(result)
        #expect(after.layout == (try mSnapshot(source)).layout)
        #expect(after.bookmarks.map(\.url) == ["https://a.fr", "https://c.fr", "https://d.fr", "https://b.fr"])
        #expect(!String(decoding: result, as: UTF8.self).contains("https://x.fr"))
        #expect(!String(decoding: result, as: UTF8.self).contains("https://o.fr"))
    }

    @Test func gardeLesNoeudsIdentiquesAvecLeurIdentifiant() throws {
        let result = try EchoWriter.mirroring(source: Data(source.utf8), into: Data(target.utf8))
        let bar = try mChildren(result, root: "bookmark_bar")

        let b = try #require(bar.first { $0["name"] as? String == "B" })
        #expect(b["id"] as? String == "3")
        let dev = try #require(bar.first { $0["name"] as? String == "Dev" })
        #expect(dev["id"] as? String == "5")
        let d = try #require((dev["children"] as? [[String: Any]])?.first { $0["name"] as? String == "D" })
        #expect(d["id"] as? String == "6")
    }

    @Test func lesNouveauxNoeudsOntDesIdentifiantsUniques() throws {
        let result = try EchoWriter.mirroring(source: Data(source.utf8), into: Data(target.utf8))

        var ids: [String] = []
        func collect(_ nodes: [[String: Any]]) {
            for node in nodes {
                if let id = node["id"] as? String { ids.append(id) }
                collect(node["children"] as? [[String: Any]] ?? [])
            }
        }
        collect(try mChildren(result, root: "bookmark_bar"))
        collect(try mChildren(result, root: "other"))

        #expect(Set(ids).count == ids.count)
        // Les nouveaux démarrent après le plus grand identifiant d'avant (9 : la racine « synced » n'existe pas, 8 + 1).
        #expect(ids.compactMap { Int($0) }.max() ?? 0 >= 9)
    }

    @Test func conserveLesChampsInconnusEtRetireLeChecksum() throws {
        let result = try EchoWriter.mirroring(source: Data(source.utf8), into: Data(target.utf8))
        let root = try #require(try JSONSerialization.jsonObject(with: result) as? [String: Any])

        #expect(root["checksum"] == nil)
        #expect(root["version"] as? Int == 1)
        // Chromium range « sync_transaction_version » dans « roots », à côté des racines
        // (voir wFile et EchoWriteTests) : il doit y rester, intact.
        let roots = try mRoots(result)
        #expect(roots["sync_transaction_version"] as? String == "7")
        #expect(roots.keys.sorted() == ["bookmark_bar", "other", "sync_transaction_version"])
    }

    @Test func neToucheNiAuSpeedDialNiALaCorbeilleDeLaCible() throws {
        let target = wFile(bar: [mManagedFolder, wNode(id: 5, "X", url: "https://x.fr")], other: [mTrashFolder])
        let source = wFile(bar: [wNode(id: 3, "A", url: "https://a.fr")])

        let result = try EchoWriter.mirroring(source: Data(source.utf8), into: Data(target.utf8))
        let text = String(decoding: result, as: UTF8.self)

        #expect(text.contains("https://s.fr"))
        #expect(text.contains("https://t.fr"))
        #expect(!text.contains("https://x.fr"))
        #expect(try EchoReader.parse(result).bookmarks.map(\.url) == ["https://a.fr"])
    }

    @Test func neCopiePasLeSpeedDialNiLaCorbeilleDeLaSource() throws {
        let source = wFile(bar: [mManagedFolder, wNode(id: 5, "A", url: "https://a.fr")], other: [mTrashFolder])
        let target = wFile()

        let result = try EchoWriter.mirroring(source: Data(source.utf8), into: Data(target.utf8))
        let text = String(decoding: result, as: UTF8.self)

        #expect(!text.contains("https://s.fr"))
        #expect(!text.contains("https://t.fr"))
        #expect(text.contains("https://a.fr"))
    }

    @Test func retireLesFavorisNonWebDeLaCible() throws {
        let internalNode = #"{"id":"9","name":"Réglages","type":"url","url":"vivaldi://settings"}"#
        let target = wFile(bar: [wNode(id: 3, "A", url: "https://a.fr"), internalNode])
        let source = wFile(bar: [wNode(id: 3, "A", url: "https://a.fr")])

        let result = try EchoWriter.mirroring(source: Data(source.utf8), into: Data(target.utf8))

        #expect(try EchoReader.parse(result).ignoredCount == 0)
        #expect(!String(decoding: result, as: UTF8.self).contains("vivaldi://settings"))
    }

    @Test func uneRacineAbsenteDeLaCibleVaALaFinDeAutresFavoris() throws {
        let source = #"{"roots":{"bookmark_bar":{"id":"1","name":"B","type":"folder","children":[]},"other":{"id":"2","name":"O","type":"folder","children":[{"id":"5","name":"O1","type":"url","url":"https://o1.fr"}]},"synced":{"id":"3","name":"M","type":"folder","children":[{"id":"4","name":"S","type":"url","url":"https://s.fr"}]}}}"#

        let result = try EchoWriter.mirroring(source: Data(source.utf8), into: Data(wFile().utf8))

        let after = try EchoReader.parse(result)
        #expect(after.bookmarks.map(\.url) == ["https://o1.fr", "https://s.fr"])
        #expect(after.bookmarks.allSatisfy { $0.rootKey == "other" })
    }

    @Test func refuseUnFichierQuiNEstPasUnBookmarks() {
        #expect(throws: (any Error).self) {
            try EchoWriter.mirroring(source: Data(source.utf8), into: Data("[]".utf8))
        }
    }
}

// MARK: - Écriture complète (fichiers temporaires)

struct EchoMirrorApplyTests {

    private let sourceBookmarks = wFile(bar: [
        wNode(id: 3, "A", url: "https://a.fr"),
        wNode(id: 4, "B", url: "https://b.fr"),
        wFolder(id: 5, "Dev", wNode(id: 6, "C", url: "https://c.fr")),
    ])
    private let internalNode = #"{"id":"9","name":"Réglages","type":"url","url":"vivaldi://settings"}"#

    private var destinationBookmarks: String {
        wFile(bar: [
            wNode(id: 3, "B", url: "https://b.fr"),
            wNode(id: 4, "X", url: "https://x.fr"),
            internalNode,
        ])
    }

    @Test func rendLaCibleIdentiqueEtCopieLesIcones() async throws {
        let (source, cleanSource) = try wMakeProfile(
            id: "vivaldi", bookmarks: sourceBookmarks,
            favicons: [("https://a.fr", "https://a.fr/f.ico"), ("https://c.fr", "https://c.fr/f.ico")])
        let original = destinationBookmarks
        let (destination, cleanDestination) = try wMakeProfile(id: "opera", bookmarks: original, favicons: [])
        let backups = wBackupsDirectory()
        defer { cleanSource(); cleanDestination(); try? FileManager.default.removeItem(at: backups) }

        let report = try EchoEngine.compare(source: source, destination: destination, mode: .anywhere)
        #expect(!report.mirror.isIdentical)

        let summary = try await EchoEngine.apply(report, syncMode: .mirror, mode: .anywhere,
                                                 copyFavicons: true, backupDirectory: backups)

        #expect(summary.mode == .mirror)
        #expect(summary.added == 2)
        #expect(summary.removed == 2)          // X + le favori non web
        #expect(summary.removedFolders == 0)
        #expect(summary.createdFolders == 1)
        #expect(summary.faviconsCopied == 2)
        #expect(summary.faviconsMissing == 1)  // B : sans icône dans la source comme dans la cible
        #expect(summary.faviconNote == nil)

        // L'arbre est celui de la source, dans le même ordre.
        let after = try EchoReader.read(from: destination.bookmarksURL)
        #expect(after.layout == (try EchoReader.read(from: source.bookmarksURL)).layout)

        // Sauvegardes : l'état d'avant, à l'octet près, marquées Echo.
        #expect(try Data(contentsOf: summary.bookmarksBackupURL) == Data(original.utf8))
        #expect(FaviconBackup.entry(for: summary.bookmarksBackupURL)?.tool == .echo)
        let faviconsBackup = try #require(summary.faviconsBackupURL)
        #expect(FaviconBackup.entry(for: faviconsBackup)?.tool == .echo)

        // Une nouvelle comparaison les trouve identiques.
        let again = try EchoEngine.compare(source: source, destination: destination, mode: .anywhere)
        #expect(again.mirror.isIdentical)
    }

    @Test func refuseQuandLesDeuxProfilsSontDejaIdentiques() async throws {
        let (source, cleanSource) = try wMakeProfile(id: "vivaldi", bookmarks: sourceBookmarks)
        let (destination, cleanDestination) = try wMakeProfile(id: "opera", bookmarks: sourceBookmarks)
        defer { cleanSource(); cleanDestination() }

        let report = try EchoEngine.compare(source: source, destination: destination, mode: .anywhere)

        await #expect(throws: EchoWriteError.self) {
            try await EchoEngine.apply(report, syncMode: .mirror, mode: .anywhere, copyFavicons: false)
        }
    }

    @Test func refuseDeViderLaCibleAvecUneSourceSansFavoris() async throws {
        let (source, cleanSource) = try wMakeProfile(id: "vivaldi", bookmarks: wFile())
        let (destination, cleanDestination) = try wMakeProfile(id: "opera", bookmarks: destinationBookmarks)
        let backups = wBackupsDirectory()
        defer { cleanSource(); cleanDestination(); try? FileManager.default.removeItem(at: backups) }

        let report = try EchoEngine.compare(source: source, destination: destination, mode: .anywhere)

        await #expect(throws: EchoWriteError.self) {
            try await EchoEngine.apply(report, syncMode: .mirror, mode: .anywhere,
                                       copyFavicons: false, backupDirectory: backups)
        }
        // Rien n'a bougé : ni le fichier, ni de sauvegarde.
        #expect(try Data(contentsOf: destination.bookmarksURL) == Data(destinationBookmarks.utf8))
        #expect(!FileManager.default.fileExists(atPath: backups.path))
    }

    @Test func nEcritRienSiLaCibleAChangeDepuisLaComparaison() async throws {
        let (source, cleanSource) = try wMakeProfile(id: "vivaldi", bookmarks: sourceBookmarks)
        let (destination, cleanDestination) = try wMakeProfile(id: "opera", bookmarks: destinationBookmarks)
        let backups = wBackupsDirectory()
        defer { cleanSource(); cleanDestination(); try? FileManager.default.removeItem(at: backups) }

        let report = try EchoEngine.compare(source: source, destination: destination, mode: .anywhere)

        // Un favori de plus dans la cible depuis la comparaison.
        let changed = wFile(bar: [wNode(id: 3, "B", url: "https://b.fr"), wNode(id: 4, "Y", url: "https://y.fr")])
        try Data(changed.utf8).write(to: destination.bookmarksURL)

        await #expect(throws: EchoWriteError.self) {
            try await EchoEngine.apply(report, syncMode: .mirror, mode: .anywhere,
                                       copyFavicons: false, backupDirectory: backups)
        }
        #expect(try Data(contentsOf: destination.bookmarksURL) == Data(changed.utf8))
    }

    @Test func laFusionNeSupprimeToujoursRien() async throws {
        let (source, cleanSource) = try wMakeProfile(id: "vivaldi", bookmarks: sourceBookmarks)
        let (destination, cleanDestination) = try wMakeProfile(id: "opera", bookmarks: destinationBookmarks)
        let backups = wBackupsDirectory()
        defer { cleanSource(); cleanDestination(); try? FileManager.default.removeItem(at: backups) }

        let report = try EchoEngine.compare(source: source, destination: destination, mode: .anywhere)
        let summary = try await EchoEngine.apply(report, mode: .anywhere, copyFavicons: false, backupDirectory: backups)

        #expect(summary.mode == .merge)
        #expect(summary.removed == 0)
        let urls = try EchoReader.read(from: destination.bookmarksURL).bookmarks.map(\.url)
        #expect(urls.contains("https://x.fr"))
    }
}
