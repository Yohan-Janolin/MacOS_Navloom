import Foundation

/// Extraction des icônes déclarées dans une page HTML.
nonisolated enum HTMLIconParser {

    /// Décode "data:image/svg+xml,%3Csvg…" ou "data:image/png;base64,…" sans requête réseau.
    static func decodeDataURI(_ string: String) -> Data? {
        guard string.lowercased().hasPrefix("data:"), let comma = string.firstIndex(of: ",") else { return nil }
        let metaStart = string.index(string.startIndex, offsetBy: 5)
        let meta = string[metaStart..<comma].lowercased()
        let payload = String(string[string.index(after: comma)...])

        if meta.contains(";base64") {
            let cleaned = payload.removingPercentEncoding ?? payload
            return Data(base64Encoded: cleaned, options: .ignoreUnknownCharacters)
        }
        return payload.removingPercentEncoding?.data(using: .utf8)
    }

    /// Retourne les href des icônes déclarées, les plus pertinentes d'abord
    /// (rel="icon" avant apple-touch-icon).
    static func iconHrefs(from html: String) -> [String] {
        guard let tagRegex = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: [.caseInsensitive]),
              let attrRegex = try? NSRegularExpression(
                pattern: #"([a-zA-Z][a-zA-Z0-9_-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#) else {
            return []
        }

        let htmlNS = html as NSString
        var found: [(priority: Int, index: Int, href: String)] = []

        let tags = tagRegex.matches(in: html, range: NSRange(location: 0, length: htmlNS.length))
        for (index, tagMatch) in tags.enumerated() {
            let tag = htmlNS.substring(with: tagMatch.range)
            let tagNS = tag as NSString

            var attributes: [String: String] = [:]
            for attr in attrRegex.matches(in: tag, range: NSRange(location: 0, length: tagNS.length)) {
                let key = tagNS.substring(with: attr.range(at: 1)).lowercased()
                var value = ""
                for group in 2...4 {
                    let range = attr.range(at: group)
                    if range.location != NSNotFound {
                        value = tagNS.substring(with: range)
                        break
                    }
                }
                attributes[key] = value
            }

            guard let rel = attributes["rel"]?.lowercased(),
                  let href = attributes["href"], !href.isEmpty else { continue }

            let tokens = rel.split(separator: " ").map(String.init)
            let isPlainIcon = tokens.contains("icon")
            let isAppleIcon = tokens.contains { $0.hasPrefix("apple-touch-icon") }
            guard isPlainIcon || isAppleIcon else { continue }

            let cleanedHref = href.replacingOccurrences(of: "&amp;", with: "&")
            found.append((isPlainIcon ? 0 : 1, index, cleanedHref))
        }

        return found
            .sorted { ($0.priority, $0.index) < ($1.priority, $1.index) }
            .map { $0.href }
    }
}
