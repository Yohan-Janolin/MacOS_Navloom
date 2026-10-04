//
//  LinkCheckerTests.swift
//  Navloom
//
//  Created by Yohan Janolin on 04/10/2026.
//


import Testing
import Foundation
@testable import Navloom

// MARK: - Interprétation d'une réponse HTTP (aucun réseau)

struct LinkCheckerTests {

    private func verdict(_ code: Int, from: String = "https://a.fr/page", to: String? = nil) -> LinkCheckResult {
        LinkChecker.verdict(statusCode: code,
                            from: URL(string: from)!,
                            to: URL(string: to ?? from))
    }

    @Test func pageQuiRepondEstAccessible() {
        #expect(verdict(200) == .alive)
    }

    @Test func introuvableEstMort() {
        #expect(verdict(404) == .dead("HTTP 404"))
        #expect(verdict(410) == .dead("HTTP 410"))
    }

    @Test func unServeurQuiRefuseLesRobotsRepondToutDeMeme() {
        for code in [401, 403, 405, 429, 451, 999] {
            #expect(verdict(code) == .alive)
        }
    }

    @Test func erreurServeurSeReessaieAutreErreurNon() {
        #expect(verdict(503) == .uncertain("HTTP 503", retryable: true))
        #expect(verdict(418) == .uncertain("HTTP 418", retryable: false))
    }

    @Test func redirectionVersUnAutreSiteEstSignalee() {
        #expect(verdict(200, from: "https://a.fr/page", to: "https://b.fr/") == .moved("redirigé vers b.fr"))
    }

    @Test func redirectionVersLAccueilEstSignalee() {
        #expect(verdict(200, from: "https://a.fr/page", to: "https://a.fr/") == .moved("redirigé vers la page d'accueil"))
    }

    @Test func redirectionsBanalesNeSontPasSignalees() {
        // www., http → https, même page : rien d'anormal.
        #expect(verdict(200, from: "https://a.fr/page", to: "https://www.a.fr/page") == .alive)
        #expect(verdict(200, from: "http://a.fr/page", to: "https://a.fr/page") == .alive)
        // Un favori qui pointe déjà sur l'accueil n'est pas « redirigé vers l'accueil ».
        #expect(verdict(200, from: "https://a.fr/", to: "https://a.fr/") == .alive)
    }

    @Test func seulsLesEchecsTransitoiresSontReessayes() {
        #expect(LinkCheckResult.unresolved("DNS").isRetryable)
        #expect(LinkCheckResult.uncertain("délai", retryable: true).isRetryable)
        #expect(!LinkCheckResult.uncertain("TLS", retryable: false).isRetryable)
        #expect(!LinkCheckResult.dead("HTTP 404").isRetryable)
        #expect(!LinkCheckResult.alive.isRetryable)
    }
}

// MARK: - Moteur (faux vérificateur, vrai fichier Bookmarks)

/// Répond selon un scénario : une liste de verdicts par URL (le dernier est répété), et compte les appels.
private actor StubChecker: LinkChecking {
    private var script: [String: [LinkCheckResult]]
    private var calls: [String: Int] = [:]

    init(_ script: [String: [LinkCheckResult]]) {
        self.script = script
    }

    func check(_ url: URL) async -> LinkCheckResult {
        let key = url.absoluteString
        calls[key, default: 0] += 1
        var queue = script[key] ?? [.alive]
        let result = queue.count > 1 ? queue.removeFirst() : queue[0]
        script[key] = queue
        return result
    }

    func callCount(_ key: String) -> Int { calls[key] ?? 0 }
}

struct GhostsEngineTests {

    private let bookmarksJSON = """
    {"roots":{
      "bookmark_bar":{"id":"1","name":"Barre","type":"folder","children":[
        {"id":"3","name":"Vivant","type":"url","url":"https://alive.fr/"},
        {"id":"4","name":"Mort","type":"url","url":"https://dead.fr/x"},
        {"id":"5","name":"Lent","type":"url","url":"https://slow.fr/"},
        {"id":"6","name":"Sans DNS","type":"url","url":"https://nodns.fr/"},
        {"id":"7","name":"Déplacé","type":"url","url":"https://moved.fr/page"},
        {"id":"8","name":"Réglages","type":"url","url":"vivaldi://settings"},
        {"id":"9","name":"Dossier","type":"folder","children":[
          {"id":"10","name":"Mort (copie)","type":"url","url":"https://dead.fr/x"}
        ]}
      ]},
      "other":{"id":"2","name":"Autres","type":"folder","children":[]}
    }}
    """

    private func makeProfile() throws -> (ChromiumProfile, cleanup: () -> Void) {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(bookmarksJSON.utf8).write(to: dir.appending(path: "Bookmarks"))
        let profile = ChromiumProfile(id: "vivaldi/Default", name: "Default", directory: dir,
                                      browserName: "Vivaldi", bundleID: "com.vivaldi.Vivaldi")
        return (profile, { try? fm.removeItem(at: dir) })
    }

    private func makeStub() -> StubChecker {
        StubChecker([
            "https://dead.fr/x": [.dead("HTTP 404")],
            // Échoue au premier passage, répond au second.
            "https://slow.fr/": [.uncertain("délai dépassé", retryable: true), .alive],
            // DNS toujours en échec : mort après le second passage.
            "https://nodns.fr/": [.unresolved("domaine introuvable (DNS)")],
            "https://moved.fr/page": [.moved("redirigé vers la page d'accueil")],
        ])
    }

    @Test func classeChaqueFavoriSelonSonVerdict() async throws {
        let (profile, cleanup) = try makeProfile()
        defer { cleanup() }

        let engine = GhostsEngine(profile: profile, checker: makeStub(), retryDelaySeconds: 0)
        let report = try await engine.scan { _ in }

        // vivaldi:// est ignoré : 6 favoris web.
        #expect(report.webBookmarks == 6)
        // « Vivant » et « Lent » (répond au second passage).
        #expect(report.aliveCount == 2)
        // Deux copies de la page 404, plus le DNS toujours en échec.
        #expect(Set(report.dead.map(\.bookmark.nodeID)) == ["4", "10", "6"])
        #expect(report.moved.map(\.bookmark.nodeID) == ["7"])
        #expect(report.uncertain.isEmpty)
    }

    @Test func verifieUneSeuleFoisChaqueUrlExacte() async throws {
        let (profile, cleanup) = try makeProfile()
        defer { cleanup() }

        let stub = makeStub()
        let engine = GhostsEngine(profile: profile, checker: stub, retryDelaySeconds: 0)
        _ = try await engine.scan { _ in }

        #expect(await stub.callCount("https://dead.fr/x") == 1)
        // Seuls les échecs transitoires passent une seconde fois.
        #expect(await stub.callCount("https://slow.fr/") == 2)
        #expect(await stub.callCount("https://nodns.fr/") == 2)
        #expect(await stub.callCount("https://alive.fr/") == 1)
    }

    @Test func lesResultatsGardentLeDossierDuFavori() async throws {
        let (profile, cleanup) = try makeProfile()
        defer { cleanup() }

        let engine = GhostsEngine(profile: profile, checker: makeStub(), retryDelaySeconds: 0)
        let report = try await engine.scan { _ in }

        let copy = try #require(report.dead.first { $0.bookmark.nodeID == "10" })
        #expect(copy.bookmark.folder == "Barre / Dossier")
    }
}

// MARK: - Rapport texte

struct GhostsReportTests {

    @Test func lesRapportsIndiquentLeDossierDesFavoris() {
        let report = GhostsReport(
            webBookmarks: 2, aliveCount: 0,
            dead: [
                BookmarkIssue(bookmark: Bookmark(name: "A", url: "https://a.fr", folder: "Barre / Dev", nodeID: "1"),
                              reason: "HTTP 404"),
                BookmarkIssue(bookmark: Bookmark(name: "B", url: "https://b.fr", folder: "", nodeID: "2"),
                              reason: "HTTP 404"),
            ],
            uncertain: [], moved: []
        )
        let text = report.text(browserName: "Vivaldi", profileName: "Default")

        #expect(text.contains("[HTTP 404]"))
        #expect(text.contains("- A (https://a.fr)"))
        #expect(text.contains("Dossier : Barre / Dev"))
        #expect(text.contains("Dossier : Racine"))
    }
}