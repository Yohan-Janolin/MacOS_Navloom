import Foundation

/// Ce que le fichier de session d'un profil apprend sur ses fenêtres.
nonisolated struct ProfileSession: Sendable {
    let profileName: String
    let windows: [SessionWindow]
    /// Espaces de travail du profil (nil si le navigateur n'en a pas).
    let workspaces: ProfileWorkspaces?
}

/// Fusionne la lecture en direct (AppleScript) avec les fichiers de session.
///
/// - AppleScript est la source principale : à jour à la seconde, et seul à voir la navigation privée.
/// - Le fichier de session ajoute le **profil** de chaque fenêtre (même identifiant de fenêtre
///   des deux côtés) et l'**espace de travail** de chaque onglet :
///   - Opera : AppleScript ne voit que le premier espace, les autres viennent du fichier ;
///   - Vivaldi : AppleScript voit tout, le fichier sert seulement à ranger les onglets par espace.
nonisolated enum TabMerger {

    static func merge(live: [OpenWindow], sessions: [ProfileSession]) -> [OpenWindow] {
        // Le nom du profil n'apporte rien quand le navigateur n'en a qu'un.
        let showsProfile = sessions.count > 1

        return live.map { window in
            guard let match = find(window.windowID, in: sessions) else { return window }
            let (session, sessionWindow) = match

            var merged = window
            if showsProfile { merged.profileName = session.profileName }

            guard let workspaces = session.workspaces else { return merged }

            switch workspaces.style {
            case .opera:
                let hasWorkspaces = sessionWindow.tabs.contains {
                    BrowserWorkspaces.workspaceID(of: $0, style: .opera) != nil
                }
                guard hasWorkspaces else { return merged }
                merged.workspaces = workspaces.list
                merged.activeWorkspaceID = SessionFile.text(sessionWindow.extraData[BrowserWorkspaces.sessionKey])
                merged.tabs = operaTabs(live: window, session: sessionWindow,
                                        activeWorkspaceID: merged.activeWorkspaceID)
            case .vivaldi:
                let (tabs, active) = vivaldiTabs(live: window, session: sessionWindow)
                // Tout dans l'espace par défaut : pas la peine d'afficher des intertitres.
                guard tabs.contains(where: { $0.workspaceID != BrowserWorkspaces.vivaldiDefaultID }) else {
                    return merged
                }
                merged.workspaces = workspaces.list
                merged.activeWorkspaceID = active
                merged.tabs = tabs
            }
            return merged
        }
    }

    private static func find(_ windowID: Int, in sessions: [ProfileSession]) -> (ProfileSession, SessionWindow)? {
        for session in sessions {
            if let window = session.windows.first(where: { $0.id == windowID }) {
                return (session, window)
            }
        }
        return nil
    }

    // MARK: - Opera

    /// Onglets de tous les espaces, d'après le fichier de session, complétés par les onglets
    /// qu'AppleScript voit mais que le navigateur n'a pas encore écrits (ouverts à l'instant).
    private static func operaTabs(live: OpenWindow, session: SessionWindow,
                                  activeWorkspaceID: String?) -> [OpenTab] {
        func workspace(of tab: SessionTab) -> String? {
            BrowserWorkspaces.workspaceID(of: tab, style: .opera)
        }

        // Onglets qu'AppleScript voit (premier espace) : les seuls qu'Opera accepte de fermer.
        let liveURLs = Set(live.tabs.map(\.url))

        var tabs = session.tabs.map { tab in
            let workspaceID = workspace(of: tab)
            return OpenTab(id: "\(live.id)#s\(tab.id)",
                           index: tab.index + 1,
                           title: tab.title,
                           url: tab.url,
                           isActive: workspaceID == activeWorkspaceID && tab.index == session.selectedTabIndex,
                           workspaceID: workspaceID,
                           // Les identifiants du fichier de session sont ceux du navigateur (comme pour les fenêtres).
                           tabID: tab.id,
                           canClose: liveURLs.contains(tab.url))
        }

        // L'espace qu'AppleScript lit : celui où se trouvent la plupart des onglets reconnus.
        let sessionURLs = Dictionary(session.tabs.map { ($0.url, workspace(of: $0)) },
                                     uniquingKeysWith: { first, _ in first })
        let seen = live.tabs.compactMap { sessionURLs[$0.url] ?? nil }
        let liveWorkspace = Dictionary(seen.map { ($0, 1) }, uniquingKeysWith: +)
            .max { $0.value < $1.value }?.key

        let fresh = live.tabs.filter { sessionURLs[$0.url] == nil }
        let nextIndex = (tabs.filter { $0.workspaceID == liveWorkspace }.map(\.index).max() ?? 0) + 1
        for (offset, tab) in fresh.enumerated() {
            tabs.append(OpenTab(id: "\(live.id)#l\(tab.index)",
                                index: nextIndex + offset,
                                title: tab.title,
                                url: tab.url,
                                isActive: false,
                                workspaceID: liveWorkspace,
                                tabID: tab.tabID))
        }

        return tabs.sorted { ($0.workspaceID ?? "", $0.index) < ($1.workspaceID ?? "", $1.index) }
    }

    // MARK: - Vivaldi

    /// Les onglets d'AppleScript (tous les espaces), chacun rangé dans l'espace que lui donne le
    /// fichier de session. Retourne aussi l'espace affiché : celui de l'onglet au premier plan.
    private static func vivaldiTabs(live: OpenWindow, session: SessionWindow) -> ([OpenTab], String?) {
        let sessionSpaces = session.tabs.map { BrowserWorkspaces.workspaceID(of: $0, style: .vivaldi) }

        // Même nombre d'onglets : on les associe dans l'ordre (une page qui a changé d'URL depuis
        // la dernière écriture reste reconnue). Sinon, on les associe par URL.
        let spaceOf: (OpenTab) -> String?
        if live.tabs.count == session.tabs.count {
            let byIndex = Dictionary(uniqueKeysWithValues: zip(live.tabs.map(\.id), sessionSpaces))
            spaceOf = { byIndex[$0.id] ?? nil }
        } else {
            let byURL = Dictionary(zip(session.tabs.map(\.url), sessionSpaces),
                                   uniquingKeysWith: { first, _ in first })
            spaceOf = { byURL[$0.url] ?? nil }
        }

        let active = live.activeTab.flatMap(spaceOf)
        let fallback = active ?? BrowserWorkspaces.vivaldiDefaultID
        let tabs = live.tabs.map { tab in
            var placed = tab
            placed.workspaceID = spaceOf(tab) ?? fallback
            return placed
        }
        return (tabs, active)
    }
}

/// Lecture des fichiers de session de tous les profils d'un navigateur.
nonisolated enum TabSessions {

    static func load(for browser: ChromiumBrowser) -> [ProfileSession] {
        browser.allProfiles().compactMap { profile in
            guard let file = SessionFile.latestSessionFile(inProfile: profile.directory),
                  let data = try? Data(contentsOf: file) else { return nil }
            return ProfileSession(profileName: profile.name,
                                  windows: SessionFile.parse(data),
                                  workspaces: BrowserWorkspaces.load(inProfile: profile.directory))
        }
    }
}
