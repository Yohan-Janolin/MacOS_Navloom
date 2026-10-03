import Testing
import Foundation
@testable import Navloom

struct ChromiumBrowserTests {

    @Test func ajouteLeDossierSeulementQuandLesLibellesSeRepetent() {
        let result = ChromiumBrowser.disambiguated(
            labels: ["Travail", "Travail", "Perso"],
            folders: ["Default", "Profile 1", "Profile 2"]
        )
        #expect(result == ["Travail · Default", "Travail · Profile 1", "Perso"])
    }

    @Test func neChangeRienSansDoublon() {
        let result = ChromiumBrowser.disambiguated(
            labels: ["Travail (a@b.fr)", "Perso"],
            folders: ["Default", "Profile 1"]
        )
        #expect(result == ["Travail (a@b.fr)", "Perso"])
    }
    
    @Test func litNomEtCompteDansLocalState() {
        let json = #"""
        {"profile":{"info_cache":{
          "Default":{"name":"Travail","user_name":"moi@exemple.fr"},
          "Profile 1":{"name":"  Perso  ","user_name":""}
        }}}
        """#
        let cache = ChromiumBrowser.parseInfoCache(Data(json.utf8))

        #expect(cache["Default"] == ChromiumBrowser.ProfileInfo(name: "Travail", account: "moi@exemple.fr"))
        // Espaces retirés, compte vide = pas de compte
        #expect(cache["Profile 1"] == ChromiumBrowser.ProfileInfo(name: "Perso", account: nil))
    }

    @Test func localStateIllisibleOuSansProfilsDonneUnCacheVide() {
        #expect(ChromiumBrowser.parseInfoCache(Data("pas du json".utf8)).isEmpty)
        #expect(ChromiumBrowser.parseInfoCache(Data(#"{"autre":1}"#.utf8)).isEmpty)
        #expect(ChromiumBrowser.parseInfoCache(Data(#"{"profile":{}}"#.utf8)).isEmpty)
    }

    @Test func ignoreLesChampsInconnusEtLesProfilsSansInfos() {
        let json = #"{"profile":{"info_cache":{"Default":{"avatar_icon":"x","gaia_name":"Y"}}}}"#
        let cache = ChromiumBrowser.parseInfoCache(Data(json.utf8))
        #expect(cache["Default"] == ChromiumBrowser.ProfileInfo(name: nil, account: nil))
    }

    @Test func litLeCompteVivaldiDansPreferences() {
        let json = #"{"vivaldi":{"vivaldi_account":{"username":"YJanolin"}},"sync":{"gaia_id":"YJanolin"}}"#
        #expect(ChromiumBrowser.parseVivaldiAccount(Data(json.utf8)) == "YJanolin")
        #expect(ChromiumBrowser.parseVivaldiAccount(Data(#"{"vivaldi":{}}"#.utf8)) == nil)
        #expect(ChromiumBrowser.parseVivaldiAccount(Data("illisible".utf8)) == nil)
    }

    @Test func libelleSelonLesInformationsDisponibles() {
        let complet = ChromiumBrowser.ProfileInfo(name: "Travail", account: "moi@exemple.fr")
        #expect(ChromiumBrowser.label(folder: "Default", info: complet) == "Travail (moi@exemple.fr)")

        let sansCompte = ChromiumBrowser.ProfileInfo(name: "Perso", account: nil)
        #expect(ChromiumBrowser.label(folder: "Profile 1", info: sansCompte) == "Perso")

        // Compte identique au nom : pas de répétition
        let memeNom = ChromiumBrowser.ProfileInfo(name: "moi@exemple.fr", account: "moi@exemple.fr")
        #expect(ChromiumBrowser.label(folder: "Default", info: memeNom) == "moi@exemple.fr")

        // Pas d'infos du tout : nom du dossier
        #expect(ChromiumBrowser.label(folder: "Profile 2", info: nil) == "Profile 2")

        // Compte Vivaldi (lu dans Preferences) quand Local State n'en donne pas
        let vivaldi = ChromiumBrowser.ProfileInfo(name: "Travail", account: nil)
        #expect(ChromiumBrowser.label(folder: "Default", info: vivaldi, fallbackAccount: "YJanolin") == "Travail (YJanolin)")
    }
}
