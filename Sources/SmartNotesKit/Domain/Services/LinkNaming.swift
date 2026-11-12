import Foundation

/// Names for pasted and dropped links, so a note shows "github.com › plico"
/// or the page's title instead of the whole address.
public enum LinkNaming {
    /// The longest name made from an address, and the longest page title kept.
    static let maxNameLength = 60
    static let maxTitleLength = 120

    /// `text` is a single web address and nothing else (spaces around it are
    /// fine): `https://…`, `http://…` or `www.…`.
    public static func standaloneURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let lowered = trimmed.lowercased()
        guard lowered.hasPrefix("https://") || lowered.hasPrefix("http://") || lowered.hasPrefix("www.") else { return nil }
        return LinkValidator.validated(trimmed)
    }

    /// A short name read from the address: the site, plus the last part of the
    /// path when it says something ("figma.com › Plico UI", "github.com › pull/12").
    public static func readableName(for url: URL) -> String {
        if url.scheme?.lowercased() == "mailto" {
            return String(url.absoluteString.dropFirst("mailto:".count)).removingPercentEncoding ?? url.absoluteString
        }
        var host = url.host() ?? url.absoluteString
        if host.lowercased().hasPrefix("www.") { host.removeFirst(4) }
        let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard var last = segments.last.map(readableSegment), !last.isEmpty else { return host }
        // An ID or a number alone says little: keep the part before it too.
        if segments.count > 1, looksLikeAnID(segments[segments.count - 1]) {
            let previous = readableSegment(segments[segments.count - 2])
            if !previous.isEmpty, !looksLikeAnID(segments[segments.count - 2]) {
                last = previous + "/" + segments[segments.count - 1]
            }
        }
        return truncated(host + " › " + last, to: maxNameLength)
    }

    private static func readableSegment(_ segment: String) -> String {
        var text = segment.removingPercentEncoding ?? segment
        for suffix in [".html", ".htm", ".php", ".aspx", ".asp", ".jsp"] where text.lowercased().hasSuffix(suffix) {
            text.removeLast(suffix.count)
        }
        if text.contains(where: \.isLetter) {
            text = text.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// A number, or a long run of letters and digits mixed (a hash, a file key).
    private static func looksLikeAnID(_ segment: String) -> Bool {
        if segment.allSatisfy(\.isNumber) { return true }
        let hasDigits = segment.contains(where: \.isNumber)
        return segment.count >= 16 && hasDigits && !segment.contains("-") && !segment.contains("_")
    }

    /// Whether Plico may load the page to read its title. Not for addresses that
    /// look single-use (sign-in, reset, unsubscribe, tokens: loading one could
    /// use it up), nor for this Mac's network (localhost, IP addresses, .local).
    public static func mayFetchTitle(for url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host()?.lowercased(), !host.isEmpty else { return false }
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".internal") { return false }
        if host.allSatisfy({ $0.isNumber || $0 == "." }) || host.contains(":") { return false }
        let singleUseWords: Set<String> = ["magic", "reset", "verify", "verification", "confirm", "confirmation", "unsubscribe",
                                           "login", "signin", "logout", "signout", "activate", "activation", "invite", "invitation",
                                           "token", "otp", "oauth", "authorize", "callback", "password"]
        let pathWords = url.path().lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if pathWords.contains(where: singleUseWords.contains) { return false }
        let sensitiveQuery = ["token", "key", "sig", "auth", "otp", "password", "pwd", "secret", "session",
                              "ticket", "nonce", "magic", "reset", "verify", "confirm", "unsubscribe", "login", "invite"]
        let queryNames = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map { $0.name.lowercased() } ?? []
        return !queryNames.contains { name in name == "code" || name == "state" || sensitiveQuery.contains { name.contains($0) } }
    }

    /// The page's name in its HTML: `og:title`, else `<title>`. Nil for pages
    /// that are not the page itself (a sign-in or error page).
    public static func pageTitle(inHTML html: String) -> String? {
        let candidates = [metaTitle(in: html), titleElement(in: html)].compactMap { $0 }.map(cleaned)
        guard let title = candidates.first(where: { !$0.isEmpty }), !isPlaceholderTitle(title) else { return nil }
        return truncated(title, to: maxTitleLength)
    }

    /// The two sites are the same, give or take "www.".
    public static func isSameSite(_ a: URL, _ b: URL) -> Bool {
        func site(_ url: URL) -> String? {
            guard var host = url.host()?.lowercased() else { return nil }
            if host.hasPrefix("www.") { host.removeFirst(4) }
            return host
        }
        return site(a) != nil && site(a) == site(b)
    }

    private static func metaTitle(in html: String) -> String? {
        let tag = try! NSRegularExpression(pattern: "<meta\\b[^>]*>", options: .caseInsensitive)
        for match in tag.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            let element = String(html[Range(match.range, in: html)!])
            guard let property = attribute("property", in: element) ?? attribute("name", in: element),
                  ["og:title", "twitter:title"].contains(property.lowercased()),
                  let content = attribute("content", in: element) else { continue }
            return content
        }
        return nil
    }

    private static func titleElement(in html: String) -> String? {
        guard let range = html.range(of: "<title\\b[^>]*>([\\s\\S]*?)</title\\s*>", options: [.regularExpression, .caseInsensitive]) else { return nil }
        let element = String(html[range])
        guard let open = element.firstIndex(of: ">"), let close = element.range(of: "</", options: .backwards) else { return nil }
        return String(element[element.index(after: open)..<close.lowerBound])
    }

    private static func attribute(_ name: String, in element: String) -> String? {
        let pattern = try! NSRegularExpression(pattern: "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')", options: .caseInsensitive)
        guard let match = pattern.firstMatch(in: element, range: NSRange(element.startIndex..., in: element)) else { return nil }
        return (1...2).lazy.compactMap { Range(match.range(at: $0), in: element) }.map { String(element[$0]) }.first
    }

    /// Entities decoded, whitespace collapsed.
    private static func cleaned(_ text: String) -> String {
        decodingEntities(text)
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func decodingEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
                     "ndash": "–", "mdash": "—", "hellip": "…", "middot": "·", "rsquo": "’", "lsquo": "‘",
                     "rdquo": "”", "ldquo": "“", "bull": "•", "raquo": "»", "laquo": "«",
                     "agrave": "à", "aacute": "á", "egrave": "è", "eacute": "é", "igrave": "ì", "iacute": "í",
                     "ograve": "ò", "oacute": "ó", "ugrave": "ù", "uacute": "ú", "ccedil": "ç", "ntilde": "ñ",
                     "auml": "ä", "ouml": "ö", "uuml": "ü", "szlig": "ß", "copy": "©", "reg": "®", "trade": "™", "euro": "€"]
        let entity = try! NSRegularExpression(pattern: "&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);")
        var result = ""
        var cursor = text.startIndex
        for match in entity.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let range = Range(match.range, in: text)!
            let body = String(text[Range(match.range(at: 1), in: text)!])
            result += text[cursor..<range.lowerBound]
            cursor = range.upperBound
            if body.hasPrefix("#") {
                let digits = body.dropFirst()
                let value = digits.first.map { $0 == "x" || $0 == "X" } == true
                    ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
                if let value, let scalar = Unicode.Scalar(value) { result.unicodeScalars.append(scalar) } else { result += text[range] }
            } else if let character = named[body] ?? named[body.lowercased()] {
                result += character
            } else {
                result += text[range]
            }
        }
        result += text[cursor...]
        return result
    }

    /// Titles of pages that stand in for the real one.
    private static func isPlaceholderTitle(_ title: String) -> Bool {
        let lowered = title.lowercased()
        let exact = ["sign in", "log in", "login", "error", "redirecting", "loading", "loading…", "loading...",
                     "untitled", "document", "home"]
        let prefixes = ["sign in to", "log in to", "login to", "just a moment", "access denied", "attention required",
                        "403", "404", "500", "502", "503", "forbidden", "not found", "page not found", "before you continue",
                        "are you a robot", "please wait", "redirecting", "you need permission", "request access"]
        return exact.contains(lowered) || prefixes.contains { lowered.hasPrefix($0) }
    }

    private static func truncated(_ text: String, to length: Int) -> String {
        guard text.count > length else { return text }
        return text.prefix(length - 1).trimmingCharacters(in: .whitespaces) + "…"
    }
}
