//
//  AccountBookmarksStatusTests.swift
//  Navloom
//
//  Created by Yohan Janolin on 05/10/2026.
//


//
//  AccountBookmarksTests.swift
//  Navloom
//

import Testing
import Foundation
@testable import Navloom

// MARK: - Outils communs

private func node(_ id: String, _ name: String, _ url: String) -> String {
    #"{"id":"\#(id)","name":"\#(name)","type":"url","url":"\#(url)"}"#
}

/// Contenu d'un fichier Bookmarks / AccountBookmarks avec les favoris donnés dans la barre de favoris.
private func bookmarksFile(_ nodes: String...) -> String {
    let children = nodes.joined(separator: ",")
    return #"{"roots":{"bookmark_bar":{"id":"1","name":"Barre","type":"folder","children":[\#(children)]},"other":{"id":"2","name":"Autres","type":"folder","children":[]}}}"#
}

/// Profil Chrome dans un dossier temporaire ; seuls les fichiers fournis sont créés.
private func makeChromeProfile(bookmarks: String? = nil,
                               account: String? = nil,
                               preferences: String? = nil) throws -> (ChromiumProfile, cleanup: () -> Void) {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)

    if let bookmarks { try Data(bookmarks.utf8).write(to: dir.appending(path: "Bookmarks")) }
    if let account { try Data(account.utf8).write(to: dir.appending(path: "AccountBookmarks")) }
    if let preferences { try Data(preferences.utf8).write(to: dir.appending(path: "Preferences")) }

    let profile = ChromiumProfile(id: "chrome/Default", name: "Default", directory: dir,
                                  browserName: "Google Chrome", bundleID: "com.google.Chrome")
    return (profile, { try? fm.removeItem(at: dir) })
}

/// Réglages de Chrome où l'option Favoris est cochée ou décochée.
private func preferences(bookmarksOption: Bool) -> String {
    #"{"sync":{"selected_types_per_account":{"hash":{"sync.bookmarks":\#(bookmarksOption),"sync.tabs":true}}}}"#
}

// MARK: - Réglage de l'option Favoris

struct AccountBookmarksStatusTests {

    private func status(_ json: String) -> AccountBookmarksStatus {
        AccountBookmarksStatus.parse(Data(json.utf8))
    }

    @Test func optionDesactiveeSeLitDansLesPreferences() {
        #expect(status(preferences(bookmarksOption: false)) == .disabled)
    }

    @Test func optionActiveeSeLitDansLesPreferences() {
        #expect(status(preferences(bookmarksOption: true)) == .enabled)
    }

    @Test func cleAbsenteDonneInconnuCommeSurLeProfilReleveOptionActivee() {
        // Relevé réel (option activée, jamais basculée) : seuls tabs, typed_urls et saved_tab_groups.
        let json = #"{"sync":{"selected_types_per_account":{"hash":{"sync.saved_tab_groups":true,"sync.tabs":true,"sync.typed_urls":true}}}}"#
        #expect(status(json) == .unknown)
    }

    @Test func laCleEstCherchee_ouQuElleSoit() {
        #expect(status(#"{"a":{"b":[{"sync.bookmarks":false}]}}"#) == .disabled)
    }

    @Test func unCompteQuiAffichentSesFavorisSuffit() {
        let json = #"{"sync":{"x":{"sync.bookmarks":false},"y":{"sync.bookmarks":true}}}"#
        #expect(status(json) == .enabled)
    }

    @Test func fichierIllisibleDonneInconnu() {
        #expect(status("pas du JSON") == .unknown)
    }

    @Test func profilSansFichierPreferencesDonneInconnu() throws {
        let (profile, cleanup) = try makeChromeProfile(bookmarks: bookmarksFile())
        defer { cleanup() }
        #expect(AccountBookmarksStatus.detect(for: profile) == .unknown)
    }
}

// MARK: - Lecture des deux fichiers

struct AccountBookmarksReadingTests {

    @Test func laLectureMarqueLOrigineDesFavoris() throws {
        let data = Data(bookmarksFile(node("3", "A", "https://a.fr")).utf8)

        #expect(try BookmarksReader.parse(data).map(\.source) == [.local])
        #expect(try BookmarksReader.parse(data, source: .account).map(\.source) == [.account])
    }

    @Test func lesDeuxFichiersSontFusionnesMemeAvecLeMemeIdentifiant() throws {
        let (profile, cleanup) = try makeChromeProfile(
            bookmarks: bookmarksFile(node("3", "Local", "https://a.fr")),
            account: bookmarksFile(node("3", "Cloud", "https://a.fr")))
        defer { cleanup() }

        let all = try BookmarksReader.readAll(for: profile)

        #expect(all.map(\.source) == [.local, .account])
        #expect(all.map(\.nodeID) == ["3", "3"])
        #expect(all.map(\.name) == ["Local", "Cloud"])
    }

    @Test func unProfilAvecSeulementAccountBookmarksEstLu() throws {
        let (profile, cleanup) = try makeChromeProfile(account: bookmarksFile(node("3", "Cloud", "https://a.fr")))
        defer { cleanup() }

        #expect(try BookmarksReader.readAll(for: profile).map(\.source) == [.account])
    }

    @Test func optionDesactiveeIgnoreAccountBookmarks() throws {
        let (profile, cleanup) = try makeChromeProfile(
            bookmarks: bookmarksFile(node("3", "Local", "https://a.fr")),
            account: bookmarksFile(node("4", "Cloud", "https://b.fr")),
            preferences: preferences(bookmarksOption: false))
        defer { cleanup() }

        let all = try BookmarksReader.readAll(for: profile)

        #expect(all.map(\.name) == ["Local"])
    }

    @Test func optionActiveeGardeAccountBookmarks() throws {
        let (profile, cleanup) = try makeChromeProfile(
            bookmarks: bookmarksFile(node("3", "Local", "https://a.fr")),
            account: bookmarksFile(node("4", "Cloud", "https://b.fr")),
            preferences: preferences(bookmarksOption: true))
        defer { cleanup() }

        #expect(try BookmarksReader.readAll(for: profile).map(\.name) == ["Local", "Cloud"])
    }

    @Test func optionDesactiveeSansFichierLocalDonneUneListeVideSansErreur() throws {
        let (profile, cleanup) = try makeChromeProfile(
            account: bookmarksFile(node("4", "Cloud", "https://b.fr")),
            preferences: preferences(bookmarksOption: false))
        defer { cleanup() }

        #expect(try BookmarksReader.readAll(for: profile).isEmpty)
    }

    @Test func unFichierDuCompteIllisibleEstIgnore() throws {
        let (profile, cleanup) = try makeChromeProfile(
            bookmarks: bookmarksFile(node("3", "Local", "https://a.fr")),
            account: "pas du JSON")
        defer { cleanup() }

        #expect(try BookmarksReader.readAll(for: profile).map(\.source) == [.local])
    }

    @Test func sansAucunFichierLaLectureEchoue() throws {
        let (profile, cleanup) = try makeChromeProfile()
        defer { cleanup() }

        var failed = false
        do { _ = try BookmarksReader.readAll(for: profile) } catch { failed = true }
        #expect(failed)
    }
}

// MARK: - Doublons entre les deux fichiers

struct AccountBookmarksDuplicatesTests {

    private func bookmark(_ id: String, _ url: String, _ source: BookmarkSource) -> Bookmark {
        Bookmark(name: "Favori \(id)", url: url, folder: "", nodeID: id, source: source)
    }

    @Test func uneCopieDuCompteProtegeSonGroupeEtLesCopiesLocalesSontCochees() {
        let groups = DuplicateFinder.groups(in: [
            bookmark("10", "https://a.fr", .local),
            bookmark("10", "https://a.fr", .account),
            bookmark("20", "https://b.fr", .local),
            bookmark("21", "https://b.fr", .local),
            bookmark("22", "https://b.fr", .account),
        ])

        #expect(DuplicateFinder.removableKeepingFirst(in: groups) == ["10", "20", "21"])
    }

    @Test func sansCopieDuCompteOnGardeLaPremiereCopieLocale() {
        let groups = DuplicateFinder.groups(in: [
            bookmark("1", "https://a.fr", .local),
            bookmark("2", "https://a.fr", .local),
            bookmark("3", "https://a.fr", .local),
        ])

        #expect(DuplicateFinder.removableKeepingFirst(in: groups) == ["2", "3"])
    }

    @Test func desCopiesDuCompteSeulesNeSontJamaisCochees() {
        let groups = DuplicateFinder.groups(in: [
            bookmark("5", "https://a.fr", .account),
            bookmark("6", "https://a.fr", .account),
        ])

        #expect(DuplicateFinder.removableKeepingFirst(in: groups).isEmpty)
    }

    @Test func unIdentifiantDuCompteNeSeConfondPasAvecUnIdentifiantLocal() {
        // « 7 » existe dans les deux fichiers, pour des favoris différents.
        let groups = DuplicateFinder.groups(in: [
            bookmark("7", "https://a.fr", .account),
            bookmark("8", "https://a.fr", .account),
            bookmark("7", "https://b.fr", .local),
            bookmark("9", "https://b.fr", .local),
        ])

        // Seul le favori local « 9 » est à retirer ; « 7 » local est la copie gardée.
        #expect(DuplicateFinder.removableKeepingFirst(in: groups) == ["9"])
    }
}

// MARK: - Suppression : le fichier du compte n'est jamais modifié

struct AccountBookmarksRemovalTests {

    @Test func supprimerUnFavoriLocalNeToucheJamaisAccountBookmarks() throws {
        let local = bookmarksFile(node("3", "Local", "https://a.fr"), node("4", "Autre", "https://b.fr"))
        let account = bookmarksFile(node("3", "Cloud", "https://a.fr"))
        let (profile, cleanup) = try makeChromeProfile(bookmarks: local, account: account)
        defer { cleanup() }

        let backups = profile.directory.appending(path: "Backups", directoryHint: .isDirectory)
        let accountBefore = try Data(contentsOf: profile.accountBookmarksURL)

        // « 3 » existe dans les deux fichiers : seul celui du fichier local doit disparaître.
        let summary = try BookmarksWriter.removeBookmarks(ids: ["3"], in: profile.bookmarksURL,
                                                          label: profile.id, backupDirectory: backups)

        #expect(summary.removed == 1)
        #expect(try BookmarksReader.read(from: profile.bookmarksURL).map(\.name) == ["Autre"])
        #expect(try Data(contentsOf: profile.accountBookmarksURL) == accountBefore)
        #expect(FaviconBackup.list(label: "chrome-Default", in: backups).map(\.category) == [.bookmarks])
    }
}

// MARK: - Ghosts

/// Répond selon un scénario et compte les appels, pour vérifier qu'une URL n'est testée qu'une fois.
private actor AccountStubChecker: LinkChecking {
    private let verdicts: [String: LinkCheckResult]
    private var calls: [String: Int] = [:]

    init(_ verdicts: [String: LinkCheckResult]) {
        self.verdicts = verdicts
    }

    func check(_ url: URL) async -> LinkCheckResult {
        calls[url.absoluteString, default: 0] += 1
        return verdicts[url.absoluteString] ?? .alive
    }

    func callCount(_ key: String) -> Int { calls[key] ?? 0 }
}

struct AccountBookmarksGhostsTests {

    @Test func lesFavorisDuCompteSontAnalysesEtGardentLeurOrigine() async throws {
        let (profile, cleanup) = try makeChromeProfile(
            bookmarks: bookmarksFile(node("5", "Local mort", "https://dead.fr/x"),
                                     node("6", "Local vivant", "https://alive.fr/")),
            account: bookmarksFile(node("5", "Cloud mort", "https://dead.fr/x")))
        defer { cleanup() }

        let stub = AccountStubChecker(["https://dead.fr/x": .dead("HTTP 404")])
        let engine = GhostsEngine(profile: profile, checker: stub, retryDelaySeconds: 0)
        let report = try await engine.scan { _ in }

        #expect(report.webBookmarks == 3)
        #expect(report.aliveCount == 1)
        #expect(Set(report.dead.map(\.bookmark.source)) == [.local, .account])
        // La même URL dans les deux fichiers n'est testée qu'une fois.
        #expect(await stub.callCount("https://dead.fr/x") == 1)
    }

    @Test func leRapportIndiqueQuUnFavoriVientDuCompte() {
        let report = GhostsReport(
            webBookmarks: 2, aliveCount: 0,
            dead: [
                BookmarkIssue(bookmark: Bookmark(name: "Cloud", url: "https://a.fr", folder: "Barre",
                                                 nodeID: "1", source: .account), reason: "HTTP 404"),
                BookmarkIssue(bookmark: Bookmark(name: "Local", url: "https://b.fr", folder: "Barre",
                                                 nodeID: "2", source: .local), reason: "HTTP 404"),
            ],
            uncertain: [], moved: []
        )
        let lines = report.text(browserName: "Chrome", profileName: "Default").split(separator: "\n")

        #expect(lines.filter { $0.contains("favori du compte Google") }.count == 1)
    }
}