import Foundation

/// Icônes des onglets ouverts, lues dans les bases `Favicons` du navigateur (lecture seule,
/// navigateur ouvert possible). Rien n'est téléchargé : une page jamais mise en icône par le
/// navigateur reste sans icône.
nonisolated enum TabFaviconLoader {

    /// Pour chaque URL d'onglet trouvée : les octets de l'image (PNG en pratique).
    /// Cherche d'abord l'URL exacte, puis n'importe quelle page du même site.
    static func load(for urls: [String], databases: [URL]) async -> [String: Data] {
        let wanted = Array(Set(urls.filter { $0.hasPrefix("http") }))
        guard !wanted.isEmpty else { return [:] }

        var found: [String: Data] = [:]

        // 1. URL exacte, base par base (un onglet peut venir de n'importe quel profil).
        for url in databases {
            let missing = wanted.filter { found[$0] == nil }
            guard !missing.isEmpty, let db = try? FaviconDatabase(url: url, writable: false) else { continue }
            if let icons = try? await db.favicons(forPages: missing) {
                for (page, icon) in icons {
                    if let best = FaviconDatabase.bestBitmap(icon.bitmaps) {
                        found[page] = best.png
                    }
                }
            }
        }

        // 2. Repli : une icône de n'importe quelle page du même site (« https://hôte/ »).
        let missing = wanted.filter { found[$0] == nil }
        let prefixByURL = Dictionary(uniqueKeysWithValues: missing.compactMap { url in
            sitePrefix(of: url).map { (url, $0) }
        })
        var iconByPrefix: [String: Data] = [:]
        for url in databases {
            let prefixes = Set(prefixByURL.values).filter { iconByPrefix[$0] == nil }
            guard !prefixes.isEmpty, let db = try? FaviconDatabase(url: url, writable: false) else { continue }
            if let icons = try? await db.anyFavicon(forPrefixes: Array(prefixes)) {
                iconByPrefix.merge(icons) { first, _ in first }
            }
        }
        for (url, prefix) in prefixByURL {
            if let data = iconByPrefix[prefix] { found[url] = data }
        }
        return found
    }

    /// « https://github.com/Yohan/x?y » → « https://github.com/ » (port compris : services locaux).
    static func sitePrefix(of url: String) -> String? {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme, let host = components.host, !host.isEmpty else { return nil }
        let port = components.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)/"
    }
}
