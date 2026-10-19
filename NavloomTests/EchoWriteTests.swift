import Testing
import Foundation
import SQLite3
@testable import Navloom

// MARK: - Outils communs

nonisolated struct SetupError: Error { let message: String }

nonisolated func wNode(id: Int, _ name: String, url: String) -> String {
    #"{"id":"\#(id)","name":"\#(name)","type":"url","url":"\#(url)"}"#
}

nonisolated func wFolder(id: Int, _ name: String, _ children: String...) -> String {
    #"{"id":"\#(id)","name":"\#(name)","type":"folder","children":[\#(children.joined(separator: ","))]}"#
}

/// Fichier Bookmarks avec champs que l'on ne comprend pas : ils doivent survivre à l'écriture.
nonisolated func wFile(bar: [String] = [], other: [String] = [], withSynced: Bool = false) -> String {
    let synced = withSynced ? #","synced":{"id":"9","name":"Mobile","type":"folder","children":[]}"# : ""
    return #"{"checksum":"abc","roots":{"bookmark_bar":{"id":"1","name":"Barre","type":"folder","children":[\#(bar.joined(separator: ","))]},"other":{"id":"2","name":"Autres","type":"folder","children":[\#(other.joined(separator: ","))]}\#(synced),"sync_transaction_version":"7"},"version":1}"#
}

nonisolated func wBookmark(_ url: String, root: String = "bookmark_bar", path: [String] = [], name: String? = nil) -> EchoBookmark {
    EchoBookmark(rootKey: root, folderPath: path, name: name ?? url, url: url)
}

/// Un PNG de 1×1 pixel : seule sa signature compte pour Echo, qui garde les PNG tels quels.
nonisolated let wTinyPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!

nonisolated func wMakeFaviconsDatabase(at url: URL, pages: [(page: String, icon: String)]) throws {
    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw SetupError(message: "open") }
    defer { sqlite3_close(db) }

    let hex = wTinyPNG.map { String(format: "%02x", $0) }.joined()
    var sql = """
    CREATE TABLE favicons(id INTEGER PRIMARY KEY AUTOINCREMENT, url LONGVARCHAR NOT NULL, icon_type INTEGER DEFAULT 1);
    CREATE TABLE favicon_bitmaps(id INTEGER PRIMARY KEY AUTOINCREMENT, icon_id INTEGER NOT NULL, last_updated INTEGER DEFAULT 0, image_data BLOB, width INTEGER DEFAULT 0, height INTEGER DEFAULT 0, last_requested INTEGER DEFAULT 0);
    CREATE TABLE icon_mapping(id INTEGER PRIMARY KEY AUTOINCREMENT, page_url LONGVARCHAR NOT NULL, icon_id INTEGER, page_url_type INTEGER DEFAULT 0);

    """
    var iconIDs: [String: Int] = [:]
    for (page, icon) in pages {
        if iconIDs[icon] == nil {
            let id = iconIDs.count + 1
            iconIDs[icon] = id
            sql += "INSERT INTO favicons(id,url,icon_type) VALUES(\(id),'\(icon)',1);\n"
            sql += "INSERT INTO favicon_bitmaps(icon_id,image_data,width,height) VALUES(\(id),X'\(hex)',16,16);\n"
            sql += "INSERT INTO favicon_bitmaps(icon_id,image_data,width,height) VALUES(\(id),X'\(hex)',32,32);\n"
        }
        sql += "INSERT INTO icon_mapping(page_url,icon_id) VALUES('\(page)',\(iconIDs[icon]!));\n"
    }
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
        throw SetupError(message: String(cString: sqlite3_errmsg(db)))
    }
}

/// Nombre de lignes d'une table, lu directement dans le fichier.
nonisolated func wCount(_ table: String, in url: URL) throws -> Int {
    var db: OpaquePointer?
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        throw SetupError(message: "open")
    }
    defer { sqlite3_close(db) }
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \(table)", -1, &stmt, nil) == SQLITE_OK else {
        throw SetupError(message: "prepare")
    }
    defer { sqlite3_finalize(stmt) }
    guard sqlite3_step(stmt) == SQLITE_ROW else { throw SetupError(message: "step") }
    return Int(sqlite3_column_int64(stmt, 0))
}

/// Un profil dans un dossier temporaire. `favicons` : nil = pas de base, [] = base vide.
nonisolated func wMakeProfile(id: String,
                          bookmarks: String?,
                          favicons: [(page: String, icon: String)]? = nil,
                          preferences: String? = nil) throws -> (profile: ChromiumProfile, cleanup: () -> Void) {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    if let bookmarks { try Data(bookmarks.utf8).write(to: dir.appending(path: "Bookmarks")) }
    if let preferences { try Data(preferences.utf8).write(to: dir.appending(path: "Preferences")) }
    if let favicons { try wMakeFaviconsDatabase(at: dir.appending(path: "Favicons"), pages: favicons) }

    let profile = ChromiumProfile(id: id, name: "Default", directory: dir,
                                  browserName: id, bundleID: "test.\(id)")
    return (profile, { try? fm.removeItem(at: dir) })
}

nonisolated func wBackupsDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "echo-backups-\(UUID().uuidString)", directoryHint: .isDirectory)
}

// MARK: - Fusion en mémoire

struct EchoWriterTests {

    private let sample = wFile(bar: [
        wNode(id: 3, "A", url: "https://a.fr"),
        wFolder(id: 4, "Dev", wNode(id: 6, "Swift", url: "https://swift.org")),
    ])

    @Test func ajouteAuBonEndroitEtCreeLesDossiersManquants() throws {
        let toAdd = [
            wBookmark("https://b.fr", name: "B"),
            wBookmark("https://c.fr", path: ["Dev"], name: "C"),
            wBookmark("https://d.fr", path: ["Nouveau", "Sous"], name: "D"),
            wBookmark("https://e.fr", path: ["Nouveau", "Sous"], name: "E"),
        ]
        let result = try EchoWriter.merging(toAdd, into: Data(sample.utf8))
        let snapshot = try EchoReader.parse(result.data)

        #expect(result.added == 4)
        // « Nouveau » et « Nouveau / Sous » : deux dossiers, même si deux favoris y vont.
        #expect(result.createdFolders == 2)
        #expect(snapshot.folders.contains(EchoFolder(rootKey: "bookmark_bar", path: ["Nouveau", "Sous"])))
        #expect(snapshot.bookmarks.first { $0.url == "https://c.fr" }?.folderPath == ["Dev"])
        #expect(snapshot.bookmarks.first { $0.url == "https://e.fr" }?.folderPath == ["Nouveau", "Sous"])
        // Les favoris d'origine sont toujours là.
        #expect(snapshot.bookmarks.count == 2 + 4)
    }

    @Test func lesNouveauxIdentifiantsSontUniquesEtApresLesAnciens() throws {
        let toAdd = [wBookmark("https://b.fr"), wBookmark("https://c.fr", path: ["Nouveau"])]
        let result = try EchoWriter.merging(toAdd, into: Data(sample.utf8))
        let ids = try BookmarksReader.parse(result.data).map(\.nodeID)

        #expect(Set(ids).count == ids.count)
        let newIDs = try BookmarksReader.parse(result.data)
            .filter { $0.url == "https://b.fr" || $0.url == "https://c.fr" }
            .map { try #require(Int($0.nodeID)) }
        // Le plus grand identifiant d'origine est 6 (9 pour la racine « synced » absente ici).
        #expect(newIDs.allSatisfy { $0 > 6 })
    }

    @Test func unDossierExistantEstReconnuParSonNom() throws {
        let result = try EchoWriter.merging([wBookmark("https://c.fr", path: ["Dev"])], into: Data(sample.utf8))
        #expect(result.createdFolders == 0)
    }

    @Test func conserveCeQueLEonNeComprendPas() throws {
        let file = wFile(bar: [#"{"id":"3","name":"A","type":"url","url":"https://a.fr","meta_info":{"Nickname":"a"}}"#])
        let result = try EchoWriter.merging([wBookmark("https://b.fr")], into: Data(file.utf8))

        let root = try #require(try JSONSerialization.jsonObject(with: result.data) as? [String: Any])
        let roots = try #require(root["roots"] as? [String: Any])
        let bar = try #require(roots["bookmark_bar"] as? [String: Any])
        let children = try #require(bar["children"] as? [[String: Any]])
        let meta = try #require(children.first?["meta_info"] as? [String: Any])

        #expect(meta["Nickname"] as? String == "a")
        #expect(roots["sync_transaction_version"] as? String == "7")
        #expect(root["version"] as? Int == 1)
        // Le total de contrôle périmé est retiré (Chromium le recalcule).
        #expect(root["checksum"] == nil)
        // Le favori existant garde sa place : les nouveaux sont ajoutés à la fin.
        #expect(children.map { $0["url"] as? String } == ["https://a.fr", "https://b.fr"])
    }

    @Test func lesNouveauxNoeudsOntLesChampsDeChromium() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let result = try EchoWriter.merging([wBookmark("https://b.fr", path: ["Nouveau"], name: "B")],
                                            into: Data(sample.utf8), now: now)

        let root = try #require(try JSONSerialization.jsonObject(with: result.data) as? [String: Any])
        let roots = try #require(root["roots"] as? [String: Any])
        let bar = try #require(roots["bookmark_bar"] as? [String: Any])
        let children = try #require(bar["children"] as? [[String: Any]])
        let folder = try #require(children.first { $0["name"] as? String == "Nouveau" })
        let item = try #require((folder["children"] as? [[String: Any]])?.first)

        #expect(folder["type"] as? String == "folder")
        #expect(item["type"] as? String == "url")
        #expect(item["name"] as? String == "B")
        #expect(item["url"] as? String == "https://b.fr")
        #expect(UUID(uuidString: try #require(item["guid"] as? String)) != nil)
        #expect(item["date_last_used"] as? String == "0")
        // Chromium compte en microsecondes depuis 1601 : 11 644 473 600 s séparent 1601 de 1970.
        #expect(item["date_added"] as? String == "\((1_800_000_000 + 11_644_473_600) * 1_000_000)")
        #expect(folder["date_modified"] as? String == item["date_added"] as? String)
    }

    @Test func uneRacineAbsenteDeLaDestinationVaDansAutresFavoris() throws {
        // `sample` n'a pas de racine « synced » (Favoris mobiles).
        let result = try EchoWriter.merging([wBookmark("https://m.fr", root: "synced")], into: Data(sample.utf8))
        let snapshot = try EchoReader.parse(result.data)

        #expect(snapshot.bookmarks.first { $0.url == "https://m.fr" }?.rootKey == "other")
    }

    @Test func refuseUnFichierQuiNEstPasUnBookmarks() {
        #expect(throws: EchoError.self) {
            try EchoWriter.merging([wBookmark("https://a.fr")], into: Data(#"{"foo":1}"#.utf8))
        }
    }
}

// MARK: - Lecture et réutilisation d'icônes

struct FaviconCopyTests {

    @Test func litLIconeDUnePageEtSesBitmaps() async throws {
        let (profile, cleanup) = try wMakeProfile(
            id: "vivaldi", bookmarks: wFile(),
            favicons: [("https://a.fr", "https://a.fr/f.ico")])
        defer { cleanup() }

        let database = try FaviconDatabase(url: profile.faviconsURL, writable: false)
        let icons = try await database.favicons(forPages: ["https://a.fr", "https://inconnue.fr"])

        #expect(icons.count == 1)
        #expect(icons["https://a.fr"]?.iconURL == "https://a.fr/f.ico")
        #expect(icons["https://a.fr"]?.bitmaps.map(\.size) == [16, 32])
        #expect(icons["https://a.fr"]?.bitmaps.first?.png == wTinyPNG)
    }

    @Test func retrouveUneIconeDejaPresente() async throws {
        let (profile, cleanup) = try wMakeProfile(
            id: "vivaldi", bookmarks: wFile(),
            favicons: [("https://a.fr", "https://a.fr/f.ico")])
        defer { cleanup() }

        let database = try FaviconDatabase(url: profile.faviconsURL, writable: false)
        #expect(try await database.iconID(forIconURL: "https://a.fr/f.ico") != nil)
        #expect(try await database.iconID(forIconURL: "https://autre.fr/f.ico") == nil)
    }
}

// MARK: - Écriture de bout en bout (vrais fichiers dans des dossiers temporaires)

struct EchoApplyTests {

    private let sourceBookmarks = wFile(bar: [
        wNode(id: 3, "A", url: "https://a.fr"),
        wNode(id: 4, "B", url: "https://b.fr"),
        wFolder(id: 5, "Dev", wNode(id: 6, "C", url: "https://c.fr")),
    ])
    private let destinationBookmarks = wFile(bar: [wNode(id: 3, "B", url: "https://b.fr")])

    @Test func ajouteLesFavorisEtLeursIcones() async throws {
        let (source, cleanSource) = try wMakeProfile(
            id: "vivaldi", bookmarks: sourceBookmarks,
            favicons: [("https://a.fr", "https://a.fr/f.ico"), ("https://c.fr", "https://c.fr/f.ico")])
        let (destination, cleanDestination) = try wMakeProfile(id: "opera", bookmarks: destinationBookmarks, favicons: [])
        let backups = wBackupsDirectory()
        defer { cleanSource(); cleanDestination(); try? FileManager.default.removeItem(at: backups) }

        let report = try EchoEngine.compare(source: source, destination: destination, mode: .anywhere)
        let summary = try await EchoEngine.apply(report, mode: .anywhere, copyFavicons: true, backupDirectory: backups)

        #expect(summary.added == 2)
        #expect(summary.createdFolders == 1)
        #expect(summary.faviconsCopied == 2)
        #expect(summary.faviconsMissing == 0)
        #expect(summary.faviconsFailed == 0)
        #expect(summary.faviconNote == nil)

        // Favoris : les deux manquants sont là, le dossier est créé.
        let snapshot = try EchoReader.read(from: destination.bookmarksURL)
        #expect(Set(snapshot.bookmarks.map(\.url)) == ["https://a.fr", "https://b.fr", "https://c.fr"])
        #expect(snapshot.folders.contains(EchoFolder(rootKey: "bookmark_bar", path: ["Dev"])))

        // Icônes : une par page ajoutée.
        let database = try FaviconDatabase(url: destination.faviconsURL, writable: false)
        #expect(try await database.urlsWithFavicon() == ["https://a.fr", "https://c.fr"])
        #expect(try wCount("favicon_bitmaps", in: destination.faviconsURL) == 4)

        // Sauvegardes : l'état d'avant, à l'octet près.
        #expect(try Data(contentsOf: summary.bookmarksBackupURL) == Data(destinationBookmarks.utf8))
        #expect(summary.bookmarksBackupURL.lastPathComponent.hasPrefix("opera-Bookmarks-"))
        let faviconsBackup = try #require(summary.faviconsBackupURL)
        #expect(faviconsBackup.lastPathComponent.hasPrefix("opera-Favicons-"))

        // Une seconde comparaison ne trouve plus rien à ajouter.
        let again = try EchoEngine.compare(source: source, destination: destination, mode: .anywhere)
        #expect(again.plan.toAdd.isEmpty)
    }

    @Test func nEcritPasLesIconesQuandOnNeLesDemandePas() async throws {
        let (source, cleanSource) = try wMakeProfile(
            id: "vivaldi", bookmarks: sourceBookmarks,
            favicons: [("https://a.fr", "https://a.fr/f.ico")])
        let (destination, cleanDestination) = try wMakeProfile(id: "opera", bookmarks: destinationBookmarks, favicons: [])
        let backups = wBackupsDirectory()
        defer { cleanSource(); cleanDestination(); try? FileManager.default.removeItem(at: backups) }

        let faviconsBefore = try Data(contentsOf: destination.faviconsURL)
        let report = try EchoEngine.compare(source: source, destination: destination, mode: .anywhere)
        let summary = try await EchoEngine.apply(report, mode: .anywhere, copyFavicons: false, backupDirectory: backups)

        #expect(summary.added == 2)
        #expect(summary.faviconsCopied == 0)
        #expect(summary.faviconsBackupURL == nil)
        #expect(try Data(contentsOf: destination.faviconsURL) == faviconsBefore)
    }

    @Test func compteLesFavorisSansIconeDansLaSource() async throws {
        let (source, cleanSource) = try wMakeProfile(
            id: "vivaldi", bookmarks: sourceBookmarks,
            favicons: [("https://a.fr", "https://a.fr/f.ico")])
        let (destination, cleanDestination) = try wMakeProfile(id: "opera", bookmarks: destinationBookmarks, favicons: [])
        let backups = wBackupsDirectory()
        defer { cleanSource(); cleanDestination(); try? FileManager.default.removeItem(at: backups) }

        let report = try EchoEngine.compare(source: source, destination: destination, mode: .anywhere)
        let summary = try await EchoEngine.apply(report, mode: .anywhere, copyFavicons: true, backupDirectory: backups)

        // A a une icône, C n'en a pas.
        #expect(summary.faviconsCopied == 1)
        #expect(summary.faviconsMissing == 1)
    }

    @Test func deuxPagesDeLaMemeIconeNeCreentQuUneIcone() async throws {
        let twoPages = wFile(bar: [wNode(id: 3, "A", url: "https://a.fr"), wNode(id: 4, "A2", url: "https://a.fr/page")])
        let (src, cleanSource) = try wMakeProfile(
            id: "vivaldi", bookmarks: twoPages,
            favicons: [("https://a.fr", "https://a.fr/f.ico"), ("https://a.fr/page", "https://a.fr/f.ico")])
        let (destination, cleanDestination) = try wMakeProfile(id: "opera", bookmarks: wFile(), favicons: [])
        let backups = wBackupsDirectory()
        defer { cleanSource(); cleanDestination(); try? FileManager.default.removeItem(at: backups) }

        let report = try EchoEngine.compare(source: src, destination: destination, mode: .anywhere)
        let summary = try await EchoEngine.apply(report, mode: .anywhere, copyFavicons: true, backupDirectory: backups)

        #expect(summary.faviconsCopied == 2)
        #expect(try wCount("favicons", in: destination.faviconsURL) == 1)
        #expect(try wCount("icon_mapping", in: destination.faviconsURL) == 2)
    }

    @Test func ajouteLesFavorisSansIconeQuandUneBaseManque() async throws {
        let (source, cleanSource) = try wMakeProfile(id: "vivaldi", bookmarks: sourceBookmarks, favicons: nil)
        let (destination, cleanDestination) = try wMakeProfile(id: "opera", bookmarks: destinationBookmarks, favicons: [])
        let backups = wBackupsDirectory()
        defer { cleanSource(); cleanDestination(); try? FileManager.default.removeItem(at: backups) }

        let report = try EchoEngine.compare(source: source, destination: destination, mode: .anywhere)
        let summary = try await EchoEngine.apply(report, mode: .anywhere, copyFavicons: true, backupDirectory: backups)

        #expect(summary.added == 2)
        #expect(summary.faviconsCopied == 0)
        #expect(summary.faviconNote != nil)
    }

    @Test func nEcritRienSiLaDestinationAChangeDepuisLaComparaison() async throws {
        let (source, cleanSource) = try wMakeProfile(id: "vivaldi", bookmarks: sourceBookmarks)
        let (destination, cleanDestination) = try wMakeProfile(id: "opera", bookmarks: destinationBookmarks)
        let backups = wBackupsDirectory()
        defer { cleanSource(); cleanDestination(); try? FileManager.default.removeItem(at: backups) }

        let report = try EchoEngine.compare(source: source, destination: destination, mode: .anywhere)

        // Entre la comparaison et l'écriture, le navigateur ajoute un favori.
        let changed = wFile(bar: [wNode(id: 3, "B", url: "https://b.fr"), wNode(id: 7, "A", url: "https://a.fr")])
        try Data(changed.utf8).write(to: destination.bookmarksURL)

        await #expect(throws: EchoWriteError.self) {
            try await EchoEngine.apply(report, mode: .anywhere, copyFavicons: false, backupDirectory: backups)
        }
        #expect(try Data(contentsOf: destination.bookmarksURL) == Data(changed.utf8))
        #expect(!FileManager.default.fileExists(atPath: backups.path))
    }

    @Test func refuseSiLaSynchroDesFavorisEstActive() async throws {
        let syncOn = #"{"sync":{"has_setup_completed":true,"keep_everything_synced":true}}"#
        let (source, cleanSource) = try wMakeProfile(id: "vivaldi", bookmarks: sourceBookmarks)
        let (destination, cleanDestination) = try wMakeProfile(id: "opera", bookmarks: destinationBookmarks,
                                                                 preferences: syncOn)
        let backups = wBackupsDirectory()
        defer { cleanSource(); cleanDestination(); try? FileManager.default.removeItem(at: backups) }

        let report = try EchoEngine.compare(source: source, destination: destination, mode: .anywhere)

        await #expect(throws: EchoWriteError.self) {
            try await EchoEngine.apply(report, mode: .anywhere, copyFavicons: false, backupDirectory: backups)
        }
        #expect(try Data(contentsOf: destination.bookmarksURL) == Data(destinationBookmarks.utf8))
        #expect(!FileManager.default.fileExists(atPath: backups.path))
    }

    @Test func refuseQuandIlNYARienAAjouter() async throws {
        let (source, cleanSource) = try wMakeProfile(id: "vivaldi", bookmarks: destinationBookmarks)
        let (destination, cleanDestination) = try wMakeProfile(id: "opera", bookmarks: destinationBookmarks)
        defer { cleanSource(); cleanDestination() }

        let report = try EchoEngine.compare(source: source, destination: destination, mode: .anywhere)

        await #expect(throws: EchoWriteError.self) {
            try await EchoEngine.apply(report, mode: .anywhere, copyFavicons: false)
        }
    }
}

// MARK: - Images

struct EchoImageTests {

    @Test func unPngValideEstGardeTelQuel() {
        let bitmaps = EchoEngine.pngBitmaps(from: [FaviconBitmap(size: 16, png: wTinyPNG)])
        #expect(bitmaps.count == 1)
        #expect(bitmaps.first?.png == wTinyPNG)
    }

    @Test func uneImageIllisibleEstEcartee() {
        let bitmaps = EchoEngine.pngBitmaps(from: [FaviconBitmap(size: 16, png: Data("pas une image".utf8))])
        #expect(bitmaps.isEmpty)
    }
}
