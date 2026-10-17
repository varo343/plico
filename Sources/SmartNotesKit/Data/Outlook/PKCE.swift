import CryptoKit
import Foundation

/// OAuth 2.0 PKCE (RFC 7636): a random verifier and its S256 challenge.
/// Lets a public desktop client sign in without any client secret.
public struct PKCE: Sendable {
    public let verifier: String
    public let challenge: String

    public init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        self.init(verifier: Data(bytes).base64URLEncoded)
    }

    /// For tests: derive the challenge from a known verifier.
    public init(verifier: String) {
        self.verifier = verifier
        self.challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    }

    /// Random opaque value to bind the authorization response to this request.
    public static func makeState() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }
}

extension Data {
    /// Base64url without padding (RFC 4648 §5).
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
