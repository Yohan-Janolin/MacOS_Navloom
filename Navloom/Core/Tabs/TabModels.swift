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
    var isActive: Bool
    /// Espace (Opera) auquel appartient l'onglet ; nil si le navigateur n'en a pas.
    var workspaceID: String? = nil

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
    var tabs: [OpenTab]
    /// Profil du navigateur, retrouvé grâce au fichier de session (AppleScript ne le donne pas).
    var profileName: String? = nil
    /// Espaces de la fenêtre, dans l'ordre du navigateur (vide si le navigateur n'en a pas).
    var workspaces: [TabWorkspace] = []
    /// Espace affiché dans la fenêtre.
    var activeWorkspaceID: String? = nil

    var activeTab: OpenTab? {
        tabs.first(where: \.isActive)
    }

    /// Onglets regroupés par espace, dans l'ordre des espaces (un seul groupe sans espace sinon).
    /// Les espaces vides sont omis ; un onglet d'un espace inconnu va dans un groupe à part.
    var tabGroups: [TabGroup] {
        guard !workspaces.isEmpty else {
            return [TabGroup(id: "\(id)/-", workspace: nil, isActive: false, tabs: tabs)]
        }
        var groups = workspaces.compactMap { workspace -> TabGroup? in
            let members = tabs.filter { $0.workspaceID == workspace.id }
            guard !members.isEmpty else { return nil }
            return TabGroup(id: "\(id)/\(workspace.id)", workspace: workspace,
                            isActive: workspace.id == activeWorkspaceID, tabs: members)
        }
        let known = Set(workspaces.map(\.id))
        let others = tabs.filter { tab in
            guard let workspaceID = tab.workspaceID else { return true }
            return !known.contains(workspaceID)
        }
        if !others.isEmpty {
            groups.append(TabGroup(id: "\(id)/?", workspace: nil, isActive: false, tabs: others))
        }
        return groups
    }
}

/// Un espace de travail (Opera) : identifiant, nom et icône définis par l'utilisateur.
nonisolated struct TabWorkspace: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Nom d'icône propre au navigateur (« home-icon »…).
    var icon: String? = nil
    /// Émoji choisi à la place de l'icône, s'il y en a un.
    var emoji: String? = nil
}

/// Onglets d'une fenêtre appartenant au même espace.
nonisolated struct TabGroup: Identifiable, Sendable {
    let id: String
    let workspace: TabWorkspace?
    /// Espace actuellement affiché dans la fenêtre.
    let isActive: Bool
    let tabs: [OpenTab]
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
