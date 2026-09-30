import Testing
import Foundation
@testable import Navloom

struct NetworkTests {

    @Test func iconesDeclareesParPriorite() {
        let html = #"<head><link rel="apple-touch-icon" href="/apple.png"><link rel="shortcut icon" href='/fav.ico'></head>"#
        #expect(HTMLIconParser.iconHrefs(from: html) == ["/fav.ico", "/apple.png"])
    }

    @Test func servicesLocauxNePartagentJamaisIcone() {
        let http = Origin.from(URL(string: "http://192.168.1.45:3067/x")!)
        let https = Origin.from(URL(string: "https://192.168.1.45/")!)
        #expect(http?.key != https?.key)
        #expect(http?.iconKey != https?.iconKey)
    }

    @Test func wwwPartageLIcone() {
        let a = Origin.from(URL(string: "https://www.exemple.fr/a")!)
        let b = Origin.from(URL(string: "https://exemple.fr/b")!)
        #expect(a?.iconKey == b?.iconKey)
    }

    @Test func hotesPrives() {
        #expect(isPrivateHost("192.168.1.1"))
        #expect(isPrivateHost("nas.local"))
        #expect(isPrivateHost("172.20.0.5"))
        #expect(!isPrivateHost("172.32.0.5"))
        #expect(!isPrivateHost("github.com"))
    }
}
