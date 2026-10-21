import Foundation

/// Assemble les listes renvoyées par AppleScript en fenêtres et onglets, et rédige le rapport texte.
/// Aucun accès aux navigateurs ici : tout peut être testé avec des valeurs écrites à la main.
nonisolated enum TabSnapshot {

    /// AppleScript renvoie une liste par propriété (`id of every window`, `URL of every tab of every window`…).
    /// Les listes sont alignées : l'élément n de chaque liste concerne la fenêtre n.
    /// - Parameters:
    ///   - modes: `nil` si le navigateur n'expose pas le mode des fenêtres (aucune ne sera alors privée).
    ///   - activeIndexes: position (à partir de 1) de l'onglet actif de chaque fenêtre.
    static func windows(browserID: String,
                        windowIDs: [Int],
                        modes: [String?]?,
                        urls: [[String?]],
                        titles: [[String?]],
                        activeIndexes: [Int?],
                        tabIDs: [[Int?]] = []) -> [OpenWindow] {
        windowIDs.enumerated().map { offset, windowID in
            let windowKey = "\(browserID)/\(windowID)"
            let windowURLs = urls[safe: offset] ?? []
            let windowTitles = titles[safe: offset] ?? []
            let active = activeIndexes[safe: offset] ?? nil
            let windowTabIDs = tabIDs[safe: offset] ?? []

            let tabs = windowURLs.enumerated().map { tabOffset, url in
                let index = tabOffset + 1
                return OpenTab(id: "\(windowKey)#\(index)",
                               index: index,
                               title: (windowTitles[safe: tabOffset] ?? nil) ?? "",
                               url: url ?? "",
                               isActive: index == active,
                               tabID: windowTabIDs[safe: tabOffset] ?? nil)
            }

            let mode = modes?[safe: offset] ?? nil
            return OpenWindow(id: windowKey,
                              windowID: windowID,
                              position: offset + 1,
                              isPrivate: mode?.lowercased() == "incognito",
                              tabs: tabs)
        }
    }

    // MARK: - Rapport

    /// Rapport texte, navigateur par navigateur puis fenêtre par fenêtre.
    static func report(_ browsers: [BrowserTabs], includePrivate: Bool, date: Date = .now) -> String {
        var lines: [String] = []
        lines.append(String(localized: "Navloom · Ferry — open tabs"))
        lines.append(date.formatted(date: .long, time: .shortened))
        if !includePrivate {
            lines.append(String(localized: "Private browsing windows not included."))
        }

        for browser in browsers {
            lines.append("")
            if let error = browser.error {
                lines.append(browser.browser.name + " — " + String(localized: "not read: \(error.message)"))
                continue
            }

            let windows = browser.windows.filter { includePrivate || !$0.isPrivate }
            let tabCount = windows.reduce(0) { $0 + $1.tabs.count }
            lines.append(browser.browser.name + " — " + String(localized: "\(windows.count) windows") + ", " + String(localized: "\(tabCount) tabs"))

            for window in windows {
                var title = String(localized: "Window \(window.position)")
                if window.isPrivate { title += " · " + String(localized: "private") }
                if let profile = window.profileName { title += " · " + String(localized: "profile \(profile)") }
                lines.append("")
                lines.append("  \(title) (" + String(localized: "\(window.tabs.count) tabs") + ")")
                for group in window.tabGroups {
                    let indent: String
                    if window.workspaces.isEmpty {
                        indent = "    "
                    } else {
                        let name = group.workspace?.name ?? String(localized: "Others")
                        lines.append("    " + workspaceLine(name: name, tabCount: group.tabs.count, isShown: group.isActive))
                        indent = "      "
                    }
                    for tab in group.tabs {
                        lines.append("\(indent)• \(tab.displayTitle)")
                        lines.append("\(indent)  \(tab.url)")
                    }
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Ligne d'un espace dans le rapport : « Espace « Dev » (3 onglets, affiché) ».
    static func workspaceLine(name: String, tabCount: Int, isShown: Bool) -> String {
        let tabs = String(localized: "\(tabCount) tabs")
        return isShown
            ? String(localized: "Workspace “\(name)” (\(tabs), shown)")
            : String(localized: "Workspace “\(name)” (\(tabs))")
    }
}

private extension Array {
    /// Élément à cette position, ou nil si la liste est trop courte (au lieu d'un plantage).
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
