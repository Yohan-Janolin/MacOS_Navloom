import Foundation

// MARK: - Hôtes privés (réseau local)

nonisolated func isPrivateHost(_ host: String) -> Bool {
    let h = host.lowercased()
    if h == "localhost" || h.hasSuffix(".local") || h.hasSuffix(".lan")
        || h.hasSuffix(".home.arpa") || h.hasSuffix(".localdomain") {
        return true
    }
    let raw = h.split(separator: ".")
    let parts = raw.compactMap { Int($0) }
    guard raw.count == 4, parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else {
        return false
    }
    switch (parts[0], parts[1]) {
    case (10, _), (127, _), (192, 168), (169, 254):
        return true
    case (172, 16...31):
        return true
    default:
        return false
    }
}

// MARK: - Origine (ce qu'on interroge réellement)

/// Un favori sur Internet est regroupé par host, toujours en https.
/// Un favori sur le réseau local garde son schéma ET son port : `http://192.168.1.45:3067`
/// et `https://192.168.1.45` sont deux services différents qui ne doivent jamais partager d'icône.
nonisolated struct Origin: Hashable, Sendable {
    let scheme: String
    let host: String
    let port: Int?

    static func from(_ url: URL) -> Origin? {
        guard let host = url.host?.lowercased() else { return nil }
        if isPrivateHost(host) {
            return Origin(scheme: (url.scheme ?? "https").lowercased(), host: host, port: url.port)
        }
        return Origin(scheme: "https", host: host, port: nil)
    }

    var isPrivate: Bool { isPrivateHost(host) }

    var key: String {
        "\(scheme)://\(host)" + (port.map { ":\($0)" } ?? "")
    }

    /// Libellé court pour l'affichage.
    var label: String { isPrivate ? key : host }

    /// Clé de partage d'icône : www.x.fr et x.fr partagent la même ; les services locaux, jamais.
    var iconKey: String {
        if isPrivate { return key }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var iconSourceURL: String {
        isPrivate ? "\(key)/favicon.ico" : "https://\(iconKey)/favicon.ico"
    }

    func url(path: String, host overrideHost: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = overrideHost ?? host
        components.port = port
        components.path = path
        return components.url
    }
}

/// URL de la page d'un favori telle qu'on va la lire : https pour Internet, inchangée pour le local.
nonisolated func bookmarkPageURL(_ url: URL, origin: Origin) -> URL? {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    if !origin.isPrivate { components.scheme = "https" }
    components.fragment = nil
    return components.url
}
