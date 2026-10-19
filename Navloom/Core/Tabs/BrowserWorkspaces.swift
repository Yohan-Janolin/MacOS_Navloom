import Foundation

/// Espaces de travail d'un profil, lus dans son fichier `Preferences`.
///
/// Opera : `ui.workspaces.config` contient l'ordre, les noms et les icônes ; chaque onglet du
/// fichier de session porte la donnée `workspaces_state` (l'identifiant de son espace, en texte),
/// et chaque fenêtre la même donnée pour l'espace affiché.
nonisolated enum BrowserWorkspaces {

    /// Clé des données ajoutées par Opera dans le fichier de session.
    static let sessionKey = "workspaces_state"

    private struct Preferences: Decodable {
        struct UI: Decodable {
            struct Workspaces: Decodable {
                struct Config: Decodable {
                    let names: [String: String]?
                    let icons: [String: String]?
                    let emoji_icons: [String: String]?
                    let order: [String]?
                }
                let config: Config?
            }
            let workspaces: Workspaces?
        }
        let ui: UI?
    }

    /// Espaces dans l'ordre défini par l'utilisateur (vide si le navigateur n'en a pas).
    static func parse(preferences data: Data) -> [TabWorkspace] {
        guard let prefs = try? JSONDecoder().decode(Preferences.self, from: data),
              let config = prefs.ui?.workspaces?.config,
              let names = config.names, !names.isEmpty else { return [] }

        // Ordre explicite, puis les espaces qu'il aurait oubliés (triés par identifiant).
        let ordered = config.order ?? []
        let remaining = names.keys
            .filter { !ordered.contains($0) }
            .sorted { (Int($0) ?? .max, $0) < (Int($1) ?? .max, $1) }

        return (ordered + remaining).compactMap { id in
            guard let name = names[id] else { return nil }
            let emoji = config.emoji_icons?[id].flatMap { $0.isEmpty ? nil : $0 }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return TabWorkspace(id: id,
                                name: trimmed.isEmpty ? "Espace \((Int(id) ?? 0) + 1)" : trimmed,
                                icon: config.icons?[id],
                                emoji: emoji)
        }
    }

    static func load(inProfile directory: URL) -> [TabWorkspace] {
        guard let data = try? Data(contentsOf: directory.appending(path: "Preferences")) else { return [] }
        return parse(preferences: data)
    }

    /// Symbole SF approchant l'icône choisie dans Opera (repli : une pile).
    static func symbol(for icon: String?) -> String {
        guard let icon = icon?.lowercased() else { return "square.stack.fill" }
        let table: [(String, String)] = [
            ("home", "house.fill"),
            ("doc", "doc.fill"),
            ("day", "sun.max.fill"),
            ("night", "moon.fill"),
            ("work", "briefcase.fill"),
            ("star", "star.fill"),
            ("heart", "heart.fill"),
            ("music", "music.note"),
            ("game", "gamecontroller.fill"),
            ("shop", "cart.fill"),
            ("cart", "cart.fill"),
            ("travel", "airplane"),
            ("code", "chevron.left.forwardslash.chevron.right"),
            ("chat", "bubble.left.fill"),
            ("mail", "envelope.fill"),
            ("news", "newspaper.fill"),
        ]
        return table.first { icon.contains($0.0) }?.1 ?? "square.stack.fill"
    }
}
