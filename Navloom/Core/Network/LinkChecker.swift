import Foundation

/// Verdict pour une URL.
nonisolated enum LinkCheckResult: Sendable, Equatable {
    case alive
    case moved(String)                              // répond, mais redirige ailleurs (info)
    case dead(String)                               // 404 / 410 : la page n'existe plus
    case unresolved(String)                         // DNS en échec : confirmé « mort » après le second passage
    case uncertain(String, retryable: Bool)         // délai, 5xx, TLS… on ne sait pas

    var isRetryable: Bool {
        switch self {
        case .unresolved: true
        case .uncertain(_, let retryable): retryable
        default: false
        }
    }
}

/// Ce dont le moteur a besoin pour vérifier un lien (permet de le remplacer par un faux dans les tests).
nonisolated protocol LinkChecking: Sendable {
    func check(_ url: URL) async -> LinkCheckResult
}

/// Teste si une page répond encore. Un GET dont on abandonne le corps dès réception des en-têtes
/// (beaucoup de serveurs répondent mal aux requêtes HEAD).
nonisolated final class LinkChecker: LinkChecking, @unchecked Sendable {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 25
        config.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: config, delegate: LenientTrustDelegate(), delegateQueue: nil)
    }

    private enum Raw {
        case response(HTTPURLResponse)
        case failure(NetworkFailure)
    }

    private func fetch(_ url: URL) async -> Raw {
        var request = URLRequest(url: url)
        request.setValue(FaviconFetcher.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,*/*;q=0.8", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            bytes.task.cancel()   // seuls les en-têtes nous intéressent
            guard let http = response as? HTTPURLResponse else {
                return .failure(.other(URLError.badServerResponse.rawValue))
            }
            return .response(http)
        } catch {
            return .failure(NetworkFailure.classify(error))
        }
    }

    func check(_ url: URL) async -> LinkCheckResult {
        var raw = await fetch(url)

        // HTTP en clair bloqué par macOS (ATS) : on teste la version https, comme le ferait un navigateur moderne.
        if case .failure(.insecureBlocked) = raw,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            if let upgraded = components.url { raw = await fetch(upgraded) }
        }

        switch raw {
        case .failure(let failure):
            if case .dns = failure { return .unresolved(failure.label) }
            return .uncertain(failure.label, retryable: failure.isRetryable)
        case .response(let http):
            return Self.verdict(statusCode: http.statusCode, from: url, to: http.url)
        }
    }

    // MARK: - Interprétation d'une réponse (pure, donc testable sans réseau)

    static func verdict(statusCode code: Int, from original: URL, to final: URL?) -> LinkCheckResult {
        switch code {
        case 200..<400:
            if let note = redirectNote(from: original, to: final) { return .moved(note) }
            return .alive
        case 404, 410:
            return .dead("HTTP \(code)")
        case 401, 403, 405, 429, 451, 999:
            // Le serveur répond mais refuse un client automatique : la page existe très probablement.
            return .alive
        case 500..<600:
            return .uncertain("HTTP \(code)", retryable: true)
        default:
            return .uncertain("HTTP \(code)", retryable: false)
        }
    }

    private static func normalizedHost(_ url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Une redirection http→https ou vers « /page/ » n'a rien d'anormal ; changer de site, ou atterrir
    /// sur l'accueil alors qu'on visait une page précise (404 déguisée), si.
    static func redirectNote(from original: URL, to final: URL?) -> String? {
        guard let final, let finalHost = normalizedHost(final) else { return nil }

        if let originalHost = normalizedHost(original), originalHost != finalHost {
            return String(localized: "redirected to \(finalHost)")
        }
        let originalIsDeep = !(original.path.isEmpty || original.path == "/")
        let finalIsRoot = final.path.isEmpty || final.path == "/"
        if originalIsDeep && finalIsRoot {
            return String(localized: "redirected to the home page")
        }
        return nil
    }
}
