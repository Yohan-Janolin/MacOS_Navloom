import Foundation

/// Catégories d'erreurs réseau, avec un libellé lisible pour le rapport.
nonisolated enum NetworkFailure {
    case dns, timeout, tls, localNetwork, connectionLost, insecureBlocked, other(Int)

    var label: String {
        switch self {
        case .dns: "domaine introuvable (DNS)"
        case .timeout: "délai dépassé"
        case .tls: "erreur TLS / certificat"
        case .localNetwork: "réseau local refusé (permission macOS)"
        case .connectionLost: "connexion coupée par le serveur"
        case .insecureBlocked: "HTTP en clair bloqué (App Transport Security)"
        case .other(let code): "erreur réseau (code \(code))"
        }
    }

    /// Un DNS en échec n'est pas une preuve que le domaine est mort (filtrage, résolveur injoignable…),
    /// donc on le réessaie aussi. Seules les erreurs TLS et ATS sont considérées comme durables.
    var isRetryable: Bool {
        switch self {
        case .tls, .insecureBlocked: false
        default: true
        }
    }

    static func classify(_ error: Error) -> NetworkFailure {
        let nsError = error as NSError
        // La permission "Réseau local" n'a pas de code dédié : elle apparaît dans le chemin réseau.
        if String(describing: nsError.userInfo).contains("Local network prohibited") {
            return .localNetwork
        }
        guard let urlError = error as? URLError else { return .other(nsError.code) }

        switch urlError.code {
        case .cannotFindHost, .dnsLookupFailed:
            return .dns
        case .timedOut:
            return .timeout
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
             .clientCertificateRejected, .clientCertificateRequired:
            return .tls
        case .networkConnectionLost, .cannotConnectToHost:
            return .connectionLost
        case .appTransportSecurityRequiresSecureConnection:
            return .insecureBlocked
        default:
            return .other(urlError.errorCode)
        }
    }

    static func isRetryableStatus(_ code: Int) -> Bool {
        code == 429 || (500..<600).contains(code)
    }
}

/// Accepte les certificats invalides (auto-signés, mauvais nom…) UNIQUEMENT pour les hôtes privés
/// (box, imprimante, NAS…). Pour tout le reste, la validation normale s'applique.
nonisolated final class LenientTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           isPrivateHost(space.host),
           let trust = space.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
