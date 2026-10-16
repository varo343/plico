import Foundation

/// Only web and mail links are allowed in notes. Anything else (file:, javascript:,
/// custom app schemes) is rejected so a click can never launch something unexpected.
public enum LinkValidator {
    public static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

    /// Normalizes user input ("example.com" → "https://example.com") and validates it.
    public static func validated(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let candidate: String
        if trimmed.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) != nil {
            candidate = trimmed
        } else if trimmed.contains("@"), !trimmed.contains("/") {
            candidate = "mailto:" + trimmed
        } else {
            candidate = "https://" + trimmed
        }
        guard let url = URL(string: candidate) else { return nil }
        return isAllowed(url) ? url : nil
    }

    public static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), allowedSchemes.contains(scheme) else { return false }
        if scheme == "mailto" { return url.absoluteString.count > "mailto:".count }
        guard let host = url.host(), !host.isEmpty else { return false }
        return host.contains(".") || host == "localhost"
    }
}
