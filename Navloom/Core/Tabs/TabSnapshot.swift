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
                        activeIndexes: [Int?]) -> [OpenWindow] {
        windowIDs.enumerated().map { offset, windowID in
            let windowKey = "\(browserID)/\(windowID)"
            let windowURLs = urls[safe: offset] ?? []
            let windowTitles = titles[safe: offset] ?? []
            let active = activeIndexes[safe: offset] ?? nil

            let tabs = windowURLs.enumerated().map { tabOffset, url in
                let index = tabOffset + 1
                return OpenTab(id: "\(windowKey)#\(index)",
                               index: index,
                               title: (windowTitles[safe: tabOffset] ?? nil) ?? "",
                               url: url ?? "",
                               isActive: index == active)
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
        lines.append("Navloom · Ferry — onglets ouverts")
        lines.append(date.formatted(date: .long, time: .shortened))
        if !includePrivate {
            lines.append("Fenêtres de navigation privée non incluses.")
        }

        for browser in browsers {
            lines.append("")
            if let error = browser.error {
                lines.append("\(browser.browser.name) — non lu : \(error.message)")
                continue
            }

            let windows = browser.windows.filter { includePrivate || !$0.isPrivate }
            let tabCount = windows.reduce(0) { $0 + $1.tabs.count }
            lines.append("\(browser.browser.name) — \(plural(windows.count, "fenêtre")), \(plural(tabCount, "onglet"))")

            for window in windows {
                let privateMark = window.isPrivate ? " · privée" : ""
                let profileMark = window.profileName.map { " · profil \($0)" } ?? ""
                lines.append("")
                lines.append("  Fenêtre \(window.position)\(privateMark)\(profileMark) (\(plural(window.tabs.count, "onglet")))")
                for group in window.tabGroups {
                    let indent: String
                    if window.workspaces.isEmpty {
                        indent = "    "
                    } else {
                        let name = group.workspace?.name ?? "Autres"
                        let shown = group.isActive ? ", affiché" : ""
                        lines.append("    Espace « \(name) » (\(plural(group.tabs.count, "onglet"))\(shown))")
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

    /// « 1 onglet », « 3 onglets », « 0 fenêtre »
    static func plural(_ count: Int, _ word: String) -> String {
        "\(count) \(word)\(count > 1 ? "s" : "")"
    }
}

private extension Array {
    /// Élément à cette position, ou nil si la liste est trop courte (au lieu d'un plantage).
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
