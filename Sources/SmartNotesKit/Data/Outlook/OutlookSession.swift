import AppKit
import AuthenticationServices
import Foundation

/// Opens the sign-in page in the system browser session and returns the redirect.
public protocol WebAuthenticator: Sendable {
    @MainActor func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

/// `ASWebAuthenticationSession`: Microsoft's page runs in a system browser
/// sheet; the app never sees the password.
public final class SystemWebAuthenticator: NSObject, WebAuthenticator, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    private var session: ASWebAuthenticationSession?

    @MainActor
    public func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: OutlookAuthError.cancelled)
                } else {
                    continuation.resume(throwing: OutlookAuthError.authorizationFailed(error?.localizedDescription ?? "unknown error"))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: OutlookAuthError.authorizationFailed("couldn't open the sign-in window"))
            }
        }
    }

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor() }
    }
}

/// The connected Microsoft account (non-secret; tokens live in the Keychain).
public struct OutlookAccount: Codable, Equatable, Sendable {
    public var id: String
    public var address: String
    public var displayName: String?
}

/// Sign-in, token refresh and authenticated Graph access.
@MainActor
public final class OutlookSession {
    private let tokenStore: TokenStore
    private let transport: HTTPTransport
    private let authenticator: WebAuthenticator
    private let now: () -> Date

    public init(tokenStore: TokenStore, transport: HTTPTransport = URLSessionTransport(),
                authenticator: WebAuthenticator = SystemWebAuthenticator(), now: @escaping () -> Date = Date.init) {
        self.tokenStore = tokenStore
        self.transport = transport
        self.authenticator = authenticator
        self.now = now
    }

    /// Full sign-in: browser → code → tokens → profile. Tokens are stored under the account ID.
    public func signIn(configuration: OutlookConfiguration) async throws -> OutlookAccount {
        guard configuration.isComplete else { throw OutlookAuthError.notConfigured }
        let pkce = PKCE()
        let state = PKCE.makeState()
        let callback = try await authenticator.authenticate(
            url: OutlookOAuth.authorizeURL(configuration: configuration, pkce: pkce, state: state),
            callbackScheme: OutlookConfiguration.callbackScheme
        )
        let code = try OutlookOAuth.authorizationCode(from: callback, expectedState: state)
        let (data, response) = try await transport.data(for: OutlookOAuth.codeExchange(configuration: configuration, code: code, pkce: pkce))
        let tokens = try OutlookOAuth.tokens(from: data, status: response.statusCode, now: now())

        let profile = try await GraphClient(transport: transport, token: { tokens.accessToken }).profile()
        try tokenStore.save(tokens, account: profile.id)
        return OutlookAccount(id: profile.id, address: profile.address, displayName: profile.displayName)
    }

    public func signOut(account: OutlookAccount) throws {
        try tokenStore.delete(account: account.id)
    }

    /// A valid access token, refreshing it (and storing the new one) when needed.
    public func accessToken(account: OutlookAccount, configuration: OutlookConfiguration) async throws -> String {
        guard let tokens = try tokenStore.load(account: account.id) else { throw GraphError.unauthorized }
        guard tokens.isExpired(now: now()) else { return tokens.accessToken }
        guard let refreshToken = tokens.refreshToken else { throw OutlookAuthError.noRefreshToken }
        let (data, response) = try await transport.data(for: OutlookOAuth.refresh(configuration: configuration, refreshToken: refreshToken))
        let refreshed = try OutlookOAuth.tokens(from: data, status: response.statusCode, now: now(), previousRefreshToken: refreshToken)
        try tokenStore.save(refreshed, account: account.id)
        return refreshed.accessToken
    }

    public func client(account: OutlookAccount, configuration: OutlookConfiguration) -> GraphClient {
        GraphClient(transport: transport) { [weak self] in
            guard let self else { throw GraphError.unauthorized }
            return try await self.accessToken(account: account, configuration: configuration)
        }
    }
}
