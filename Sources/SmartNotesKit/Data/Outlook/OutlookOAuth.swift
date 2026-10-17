import Foundation

/// Your Microsoft Entra app registration (not secret: a public client has no secret).
public struct OutlookConfiguration: Codable, Equatable, Sendable {
    /// "Application (client) ID" from the app registration.
    public var clientID: String
    /// "common", "organizations", "consumers", or your Directory (tenant) ID.
    public var tenant: String

    public init(clientID: String = "", tenant: String = "common") {
        self.clientID = clientID
        self.tenant = tenant
    }

    public var isComplete: Bool {
        UUID(uuidString: clientID.trimmingCharacters(in: .whitespaces)) != nil && !tenant.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Register exactly this redirect URI under "Mobile and desktop applications".
    public static let redirectURI = "smartnotes://auth"
    public static let callbackScheme = "smartnotes"
    /// Least privilege for this feature: read mail + profile, refresh without re-prompting.
    public static let scopes = ["offline_access", "User.Read", "Mail.Read"]
}

public enum OutlookAuthError: Error, Equatable, LocalizedError {
    case notConfigured
    case cancelled
    case stateMismatch
    case missingCode
    /// The identity platform returned an error (e.g. consent required, blocked by policy).
    case authorizationFailed(String)
    case tokenRequestFailed(String)
    case noRefreshToken

    public var errorDescription: String? {
        switch self {
        case .notConfigured: "Add your app's client ID in Settings ▸ Outlook first."
        case .cancelled: "Sign-in was cancelled."
        case .stateMismatch, .missingCode: "The sign-in response was not valid. Please try again."
        case .authorizationFailed(let message): "Microsoft sign-in failed: \(message)"
        case .tokenRequestFailed(let message): "Couldn't complete sign-in: \(message)"
        case .noRefreshToken: "Your Outlook session expired. Reconnect to continue."
        }
    }
}

/// Microsoft identity platform v2.0: authorization code flow with PKCE.
public enum OutlookOAuth {
    public static func authorizeURL(configuration: OutlookConfiguration, pkce: PKCE, state: String) -> URL {
        var components = URLComponents(string: "https://login.microsoftonline.com/\(configuration.tenant)/oauth2/v2.0/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: OutlookConfiguration.redirectURI),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: OutlookConfiguration.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        return components.url!
    }

    /// Extracts the code from the redirect, checking `state` and surfacing errors.
    public static func authorizationCode(from callback: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw OutlookAuthError.authorizationFailed(value("error_description") ?? error)
        }
        guard value("state") == expectedState else { throw OutlookAuthError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw OutlookAuthError.missingCode }
        return code
    }

    public static func tokenRequest(configuration: OutlookConfiguration, form: [String: String]) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://login.microsoftonline.com/\(configuration.tenant)/oauth2/v2.0/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var fields = form
        fields["client_id"] = configuration.clientID
        fields["scope"] = OutlookConfiguration.scopes.joined(separator: " ")
        var body = URLComponents()
        body.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((body.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        return request
    }

    public static func codeExchange(configuration: OutlookConfiguration, code: String, pkce: PKCE) -> URLRequest {
        tokenRequest(configuration: configuration, form: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": OutlookConfiguration.redirectURI,
            "code_verifier": pkce.verifier,
        ])
    }

    public static func refresh(configuration: OutlookConfiguration, refreshToken: String) -> URLRequest {
        tokenRequest(configuration: configuration, form: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])
    }

    /// Parses a token endpoint response (success or error).
    public static func tokens(from data: Data, status: Int, now: Date = .now, previousRefreshToken: String? = nil) throws -> OAuthTokens {
        struct Success: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int
        }
        struct Failure: Decodable {
            let error: String
            let error_description: String?
        }
        guard (200..<300).contains(status), let success = try? JSONDecoder().decode(Success.self, from: data) else {
            let failure = try? JSONDecoder().decode(Failure.self, from: data)
            // Only the first line: descriptions carry trace IDs, never tokens.
            let message = failure?.error_description?.components(separatedBy: .newlines).first ?? failure?.error ?? "HTTP \(status)"
            throw OutlookAuthError.tokenRequestFailed(message)
        }
        return OAuthTokens(
            accessToken: success.access_token,
            refreshToken: success.refresh_token ?? previousRefreshToken,
            expiresAt: now.addingTimeInterval(TimeInterval(success.expires_in))
        )
    }
}
