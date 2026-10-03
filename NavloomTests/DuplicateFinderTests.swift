//
//  DuplicateFinderTests.swift
//  Navloom
//

import Testing
import Foundation
@testable import Navloom

struct DuplicateFinderTests {

    @Test func regroupeLesUrlsExactementIdentiques() {
        let bookmarks = [
            Bookmark(name: "Swift", url: "https://swift.org/", folder: "Barre / Dev", nodeID: "1"),
            Bookmark(name: "Apple", url: "https://apple.com/", nodeID: "2"),
            Bookmark(name: "Swift (copie)", url: "https://swift.org/", folder: "Autres", nodeID: "3"),
        ]
        let groups = DuplicateFinder.groups(in: bookmarks)

        #expect(groups.count == 1)
        #expect(groups.first?.url == "https://swift.org/")
        #expect(groups.first?.bookmarks.map(\.nodeID) == ["1", "3"])
    }

    @Test func neNormalisePasLesUrls() {
        // Avec ou sans « / » final, c'est une URL différente : pas un doublon exact.
        let bookmarks = [
            Bookmark(name: "A", url: "https://exemple.fr", nodeID: "1"),
            Bookmark(name: "B", url: "https://exemple.fr/", nodeID: "2"),
        ]
        #expect(DuplicateFinder.groups(in: bookmarks).isEmpty)
    }

    @Test func lesPlusGrosGroupesPassentEnPremier() {
        let bookmarks = [
            Bookmark(name: "A1", url: "https://a.fr", nodeID: "1"),
            Bookmark(name: "A2", url: "https://a.fr", nodeID: "2"),
            Bookmark(name: "B1", url: "https://b.fr", nodeID: "3"),
            Bookmark(name: "B2", url: "https://b.fr", nodeID: "4"),
            Bookmark(name: "B3", url: "https://b.fr", nodeID: "5"),
        ]
        #expect(DuplicateFinder.groups(in: bookmarks).map(\.url) == ["https://b.fr", "https://a.fr"])
    }

    @Test func lecteurConserveDossierEtIdentifiant() throws {
        let json = """
        {"roots":{
          "bookmark_bar":{"name":"Barre","type":"folder","children":[
            {"name":"Dossier","type":"folder","children":[
              {"id":"42","name":"Swift","type":"url","url":"https://swift.org/"}
            ]}
          ]},
          "other":{"name":"Autres","type":"folder","children":[]}
        }}
        """
        let bookmark = try #require(try BookmarksReader.parse(Data(json.utf8)).first)
        #expect(bookmark.folder == "Barre / Dossier")
        #expect(bookmark.nodeID == "42")
    }
}
