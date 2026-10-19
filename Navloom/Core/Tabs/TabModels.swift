import Foundation

/// Un onglet ouvert, tel que le navigateur le décrit en AppleScript.
nonisolated struct OpenTab: Identifiable, Hashable, Sendable {
    /// Unique dans toute la liste : « navigateur/fenêtre#position »
    let id: String
    /// Position dans la fenêtre (à partir de 1, comme en AppleScript).
    let index: Int
    let title: String
    let url: String
    /// Onglet affiché au premier plan dans sa fenêtre.
    let isActive: Bool

    var host: String? {
        URL(string: url)?.host()
    }

    /// Titre à afficher : certaines pages n'en ont pas (page en chargement, outil local…).
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return host ?? url
    }

    /// Vrai si le texte cherché apparaît dans le titre ou l'URL (sans tenir compte de la casse).
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(query)
            || url.localizedCaseInsensitiveContains(query)
    }
}

/// Une fenêtre de navigateur et ses onglets.
nonisolated struct OpenWindow: Identifiable, Hashable, Sendable {
    /// Unique dans toute la liste : « navigateur/identifiant de fenêtre »
    let id: String
    /// Identifiant donné par le navigateur (stable tant que la fenêtre reste ouverte).
    let windowID: Int
    /// Numéro d'ordre affiché (« Fenêtre 1 », « Fenêtre 2 »…), de la plus récente à la plus ancienne.
    let position: Int
    /// Navigation privée (« incognito » pour les navigateurs Chromium).
    let isPrivate: Bool
    let tabs: [OpenTab]

    var activeTab: OpenTab? {
        tabs.first(where: \.isActive)
    }
}

/// Pourquoi les onglets d'un navigateur n'ont pas pu être lus.
nonisolated enum TabReadError: Error, Equatable, Sendable {
    /// L'utilisateur a refusé (ou pas encore accordé) l'autorisation « Automatisation ».
    case permissionDenied
    /// Le navigateur s'est fermé entre-temps.
    case notRunning
    /// Autre erreur AppleScript (numéro et message).
    case script(code: Int, message: String)

    var message: String {
        switch self {
        case .permissionDenied:
            "Navloom n'a pas l'autorisation de lire les onglets de ce navigateur."
        case .notRunning:
            "Le navigateur s'est fermé pendant la lecture."
        case .script(let code, let message):
            "Erreur AppleScript \(code) : \(message)"
        }
    }
}

/// Résultat de la lecture d'un navigateur ouvert.
nonisolated struct BrowserTabs: Identifiable, Sendable {
    let browser: ChromiumBrowser
    let result: Result<[OpenWindow], TabReadError>

    var id: String { browser.id }

    var windows: [OpenWindow] {
        (try? result.get()) ?? []
    }

    var error: TabReadError? {
        if case .failure(let error) = result { return error }
        return nil
    }
}
