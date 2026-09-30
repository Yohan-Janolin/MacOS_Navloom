import Foundation

/// Résultat final pour une origine (partagé par tous les favoris de cette origine).
nonisolated enum HostResult: Sendable {
    case found(Data)
    case confirmedNone(String)                 // le site n'a vraiment pas de favicon, avec la raison
    case failed(String, retryable: Bool)       // on ne sait pas : raison, et intérêt de réessayer

    var isRetryable: Bool {
        if case .failed(_, let retryable) = self { return retryable }
        return false
    }
}

/// Résultat de la lecture d'une page HTML.
nonisolated enum HTMLIconResult {
    case found(Data)
    case noIconDeclared
    case undecodable(String)
    case pageUnavailable(String, retryable: Bool)
}

nonisolated final class FaviconFetcher: @unchecked Sendable {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8     // silence réseau maximal
        config.timeoutIntervalForResource = 20   // durée totale maximale d'une requête
        config.httpMaximumConnectionsPerHost = 2
        session = URLSession(configuration: config, delegate: LenientTrustDelegate(), delegateQueue: nil)
    }

    private func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    // MARK: - Plusieurs origines en parallèle (borné)

    /// `onResult` est appelé à chaque origine terminée, avec le nombre d'origines déjà traitées.
    func resolveAll(origins: [Origin],
                    urlsByKey: [String: [URL]],
                    maxConcurrent: Int,
                    onResult: @Sendable (Origin, HostResult, Int) -> Void) async -> [String: HostResult] {
        var results: [String: HostResult] = [:]
        var nextIndex = 0
        var done = 0

        await withTaskGroup(of: (Origin, HostResult).self) { group in
            while nextIndex < min(maxConcurrent, origins.count) {
                let origin = origins[nextIndex]
                let urls = urlsByKey[origin.key] ?? []
                nextIndex += 1
                group.addTask { (origin, await self.resolveWithDeadline(origin: origin, bookmarkURLs: urls)) }
            }

            for await (origin, result) in group {
                results[origin.key] = result
                done += 1
                onResult(origin, result, done)

                if nextIndex < origins.count {
                    let nextOrigin = origins[nextIndex]
                    let nextURLs = urlsByKey[nextOrigin.key] ?? []
                    nextIndex += 1
                    group.addTask {
                        (nextOrigin, await self.resolveWithDeadline(origin: nextOrigin, bookmarkURLs: nextURLs))
                    }
                }
            }
        }
        return results
    }

    /// Durée maximale pour une origine, tous essais confondus.
    static let originDeadlineSeconds = 20

    /// Un site très lent ne doit pas monopoliser une place : au-delà de la limite, on abandonne
    /// et on le classe en échec à réessayer au second passage.
    private func resolveWithDeadline(origin: Origin, bookmarkURLs: [URL]) async -> HostResult {
        await withTaskGroup(of: HostResult?.self) { group in
            group.addTask { await self.resolve(origin: origin, bookmarkURLs: bookmarkURLs) }
            group.addTask {
                try? await Task.sleep(for: .seconds(Self.originDeadlineSeconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .failed("délai global dépassé (\(Self.originDeadlineSeconds) s)", retryable: true)
        }
    }
    
    // MARK: - Une origine

    /// Racine du site d'abord, puis (en dernier recours) la page réelle des favoris.
    func resolve(origin: Origin, bookmarkURLs: [URL]) async -> HostResult {
        var result = await resolveRoot(origin: origin)
        if case .found = result { return result }

        // Dernier recours : la page exacte du favori. Indispensable pour les sites de projet
        // (ex. utilisateur.github.io/projet/) dont la racine n'existe pas ou n'a pas d'icône,
        // et pour les services locaux sur un port particulier.
        var sawUndecodable = false
        for url in bookmarkURLs.prefix(3) {
            if url.path.isEmpty || url.path == "/" { continue }   // la racine a déjà été essayée

            switch await iconFromPage(url) {
            case .found(let data):
                return .found(data)
            case .undecodable(let reason):
                sawUndecodable = true
                result = .failed(reason, retryable: false)
            case .noIconDeclared:
                // La page du favori répond bien et ne déclare rien : c'est une absence confirmée.
                if !sawUndecodable, case .failed = result {
                    result = .confirmedNone("aucune icône déclarée (page du favori)")
                }
            case .pageUnavailable:
                break
            }
        }
        return result
    }

    /// Essaie l'hôte exact, puis (sur Internet) la version sans "www.".
    private func resolveRoot(origin: Origin) async -> HostResult {
        var candidates = [origin.host]
        if !origin.isPrivate, origin.host.hasPrefix("www.") {
            candidates.append(String(origin.host.dropFirst(4)))
        }

        var firstNone: String?
        var firstFailure: (reason: String, retryable: Bool)?

        for candidate in candidates {
            switch await tryCandidate(origin: origin, host: candidate) {
            case .found(let data):
                return .found(data)
            case .confirmedNone(let reason):
                if firstNone == nil { firstNone = reason }
            case .failed(let reason, let retryable):
                if firstFailure == nil { firstFailure = (reason, retryable) }
            }
        }

        // Une vraie erreur (à réessayer) prime sur une absence confirmée.
        if let failure = firstFailure { return .failed(failure.reason, retryable: failure.retryable) }
        return .confirmedNone(firstNone ?? "aucune favicon trouvée")
    }

    private func tryCandidate(origin: Origin, host: String) async -> HostResult {
        guard let iconURL = origin.url(path: "/favicon.ico", host: host),
              let pageURL = origin.url(path: "/", host: host) else {
            return .failed("URL invalide", retryable: false)
        }

        // 1. /favicon.ico
        var rootNote: String
        var rootRetryable = false
        do {
            let (data, response) = try await get(iconURL)
            let code = response.statusCode
            if code == 200, FaviconImage.isValid(data) {
                return .found(data)
            }
            switch code {
            case 200:
                let finalHost = response.url?.host ?? host
                rootNote = finalHost == host
                    ? "favicon.ico n'est pas une image"
                    : "favicon.ico redirigé vers \(finalHost) (pas une image)"
            case 204, 404, 410:
                rootNote = "pas de favicon.ico (HTTP \(code))"
            default:
                rootNote = "favicon.ico : HTTP \(code)"
                rootRetryable = NetworkFailure.isRetryableStatus(code)
            }
        } catch {
            let failure = NetworkFailure.classify(error)
            if case .dns = failure {
                return .failed(failure.label, retryable: true)   // inutile d'aller plus loin
            }
            rootNote = failure.label
            rootRetryable = failure.isRetryable
        }

        // 2. Page d'accueil : balises <link rel="icon">
        switch await iconFromPage(pageURL) {
        case .found(let data):
            return .found(data)
        case .noIconDeclared:
            return .confirmedNone("aucune icône déclarée (\(rootNote))")
        case .undecodable(let reason):
            return .failed(reason, retryable: false)
        case .pageUnavailable(let reason, let pageRetryable):
            return .failed("\(rootNote) ; page d'accueil : \(reason)", retryable: rootRetryable || pageRetryable)
        }
    }

    /// Lit une page HTML et en extrait l'icône (redirections suivies : la base est l'URL FINALE).
    private func iconFromPage(_ pageURL: URL) async -> HTMLIconResult {
        let pageData: Data
        let pageResponse: HTTPURLResponse
        do {
            (pageData, pageResponse) = try await get(pageURL)
        } catch {
            let failure = NetworkFailure.classify(error)
            return .pageUnavailable(failure.label, retryable: failure.isRetryable)
        }
        let code = pageResponse.statusCode
        guard (200..<300).contains(code) else {
            return .pageUnavailable("HTTP \(code)", retryable: NetworkFailure.isRetryableStatus(code))
        }

        let html = String(data: pageData, encoding: .utf8)
            ?? String(data: pageData, encoding: .isoLatin1)
            ?? ""
        let baseURL = pageResponse.url ?? pageURL

        var hrefs = HTMLIconParser.iconHrefs(from: html)
        var declared = !hrefs.isEmpty

        // Aucune icône déclarée : les navigateurs essaient /favicon.ico sur le host final.
        if hrefs.isEmpty,
           let finalHost = baseURL.host?.lowercased(),
           finalHost != pageURL.host?.lowercased() {
            hrefs = ["/favicon.ico"]
            declared = false
        }
        if hrefs.isEmpty { return .noIconDeclared }

        var attempted = 0
        for href in hrefs.prefix(4) {
            attempted += 1

            if href.lowercased().hasPrefix("data:") {
                if let data = HTMLIconParser.decodeDataURI(href), FaviconImage.isValid(data) { return .found(data) }
                continue
            }
            guard let url = URL(string: href, relativeTo: baseURL)?.absoluteURL else { continue }
            if let (data, response) = try? await get(url),
               response.statusCode == 200, FaviconImage.isValid(data) {
                return .found(data)
            }
        }

        if declared {
            return .undecodable("icône déclarée mais illisible ou inaccessible (\(attempted) essayée(s), SVG ?)")
        }
        return .noIconDeclared
    }
}
