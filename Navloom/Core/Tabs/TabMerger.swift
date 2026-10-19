import Foundation

/// Ce que le fichier de session d'un profil apprend sur ses fenêtres.
nonisolated struct ProfileSession: Sendable {
    let profileName: String
    let windows: [SessionWindow]
    /// Espaces de travail du profil (vide si le navigateur n'en a pas).
    let workspaces: [TabWorkspace]
}

/// Fusionne la lecture en direct (AppleScript) avec les fichiers de session.
///
/// - AppleScript est la source principale : à jour à la seconde, et seul à voir la navigation privée.
/// - Le fichier de session ajoute le **profil** de chaque fenêtre (même identifiant de fenêtre
///   des deux côtés) et, chez Opera, les onglets des **autres espaces**, qu'AppleScript ne voit pas.
nonisolated enum TabMerger {

    static func merge(live: [OpenWindow], sessions: [ProfileSession]) -> [OpenWindow] {
        // Le nom du profil n'apporte rien quand le navigateur n'en a qu'un.
        let showsProfile = sessions.count > 1

        return live.map { window in
            guard let match = find(window.windowID, in: sessions) else { return window }
            let (session, sessionWindow) = match

            var merged = window
            if showsProfile { merged.profileName = session.profileName }

            let hasWorkspaces = !session.workspaces.isEmpty
                && sessionWindow.tabs.contains { $0.extraData[BrowserWorkspaces.sessionKey] != nil }
            guard hasWorkspaces else { return merged }

            merged.workspaces = session.workspaces
            merged.activeWorkspaceID = SessionFile.text(sessionWindow.extraData[BrowserWorkspaces.sessionKey])
            merged.tabs = workspaceTabs(live: window, session: sessionWindow,
                                        activeWorkspaceID: merged.activeWorkspaceID)
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

    /// Onglets de tous les espaces, d'après le fichier de session, complétés par les onglets
    /// qu'AppleScript voit mais que le navigateur n'a pas encore écrits (ouverts à l'instant).
    private static func workspaceTabs(live: OpenWindow, session: SessionWindow,
                                      activeWorkspaceID: String?) -> [OpenTab] {
        func workspace(of tab: SessionTab) -> String? {
            SessionFile.text(tab.extraData[BrowserWorkspaces.sessionKey])
        }

        var tabs = session.tabs.map { tab in
            let workspaceID = workspace(of: tab)
            return OpenTab(id: "\(live.id)#s\(tab.id)",
                           index: tab.index + 1,
                           title: tab.title,
                           url: tab.url,
                           isActive: workspaceID == activeWorkspaceID && tab.index == session.selectedTabIndex,
                           workspaceID: workspaceID)
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
                                workspaceID: liveWorkspace))
        }

        return tabs.sorted { ($0.workspaceID ?? "", $0.index) < ($1.workspaceID ?? "", $1.index) }
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
