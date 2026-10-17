import Foundation
import Testing
@testable import SmartNotesKit

/// Scripted HTTP responses, recording every request.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    struct Reply {
        var status: Int
        var body: String
        var headers: [String: String] = [:]
        var error: URLError? = nil
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply = lock.withLock {
            requests.append(request)
            return replies.isEmpty ? Reply(status: 500, body: "") : replies.removeFirst()
        }
        if let error = reply.error { throw error }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!
        return (Data(reply.body.utf8), response)
    }
}

final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var delays: [Duration] = []
    func record(_ d: Duration) { lock.withLock { delays.append(d) } }
}

@Suite struct OutlookOAuthTests {
    /// RFC 7636 Appendix B test vector.
    @Test func pkceMatchesRFCVector() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func randomPKCEIsURLSafeAndLongEnough() {
        let pkce = PKCE()
        #expect(pkce.verifier.count >= 43)
        #expect(pkce.verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(PKCE().verifier != pkce.verifier)
    }

    @Test func authorizeURLCarriesEveryParameter() throws {
        let config = OutlookConfiguration(clientID: "11111111-2222-3333-4444-555555555555", tenant: "organizations")
        let pkce = PKCE(verifier: "verifier")
        let url = OutlookOAuth.authorizeURL(configuration: config, pkce: pkce, state: "xyz")
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(url.host() == "login.microsoftonline.com")
        #expect(url.path() == "/organizations/oauth2/v2.0/authorize")
        #expect(items["client_id"] == config.clientID)
        #expect(items["response_type"] == "code")
        #expect(items["redirect_uri"] == "smartnotes://auth")
        #expect(items["code_challenge"] == pkce.challenge && items["code_challenge_method"] == "S256")
        #expect(items["scope"] == "offline_access User.Read Mail.Read")
        #expect(items["state"] == "xyz")
    }

    @Test func callbackValidation() throws {
        #expect(try OutlookOAuth.authorizationCode(from: URL(string: "smartnotes://auth?code=abc&state=s1")!, expectedState: "s1") == "abc")
        #expect(throws: OutlookAuthError.stateMismatch) {
            try OutlookOAuth.authorizationCode(from: URL(string: "smartnotes://auth?code=abc&state=evil")!, expectedState: "s1")
        }
        #expect(throws: OutlookAuthError.authorizationFailed("Need admin approval")) {
            try OutlookOAuth.authorizationCode(from: URL(string: "smartnotes://auth?error=access_denied&error_description=Need%20admin%20approval&state=s1")!, expectedState: "s1")
        }
    }

    @Test func tokenParsing() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let tokens = try OutlookOAuth.tokens(from: Data(#"{"access_token":"A","refresh_token":"R","expires_in":3600}"#.utf8), status: 200, now: now)
        #expect(tokens == OAuthTokens(accessToken: "A", refreshToken: "R", expiresAt: now.addingTimeInterval(3600)))
        // A refresh response may omit the refresh token: keep the previous one.
        let refreshed = try OutlookOAuth.tokens(from: Data(#"{"access_token":"B","expires_in":60}"#.utf8), status: 200, now: now, previousRefreshToken: "R")
        #expect(refreshed.refreshToken == "R")
        #expect(throws: OutlookAuthError.tokenRequestFailed("AADSTS65001: consent required.")) {
            try OutlookOAuth.tokens(from: Data(#"{"error":"invalid_grant","error_description":"AADSTS65001: consent required.\r\nTrace ID: 123"}"#.utf8), status: 400)
        }
    }

    @Test func codeExchangeRequest() throws {
        let config = OutlookConfiguration(clientID: "11111111-2222-3333-4444-555555555555", tenant: "common")
        let request = OutlookOAuth.codeExchange(configuration: config, code: "the-code", pkce: PKCE(verifier: "v"))
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        #expect(request.httpMethod == "POST")
        #expect(body.contains("grant_type=authorization_code") && body.contains("code=the-code") && body.contains("code_verifier=v"))
        #expect(!body.contains("client_secret"))
    }

    @Test func tokenExpiryHasSafetyMargin() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(OAuthTokens(accessToken: "a", refreshToken: nil, expiresAt: now.addingTimeInterval(30)).isExpired(now: now))
        #expect(!OAuthTokens(accessToken: "a", refreshToken: nil, expiresAt: now.addingTimeInterval(600)).isExpired(now: now))
    }
}

@Suite struct GraphClientTests {
    private let page1 = #"{"value":[{"id":"m1","subject":"Review","from":{"emailAddress":{"name":"Ada","address":"ada@contoso.com"}},"receivedDateTime":"2026-10-17T08:30:00Z","bodyPreview":"@you can you check?","webLink":"https://outlook.office.com/mail/id/m1"}],"@odata.nextLink":"https://graph.microsoft.com/beta/me/mailFolders/inbox/messages?$skip=1"}"#
    private let page2 = #"{"value":[{"id":"m2","subject":"","receivedDateTime":"2026-10-16T08:30:00Z","webLink":"javascript:alert(1)"}]}"#

    private func client(_ transport: StubTransport, sleeps: SleepRecorder = SleepRecorder()) -> GraphClient {
        GraphClient(transport: transport, sleep: { sleeps.record($0) }, token: { "token-123" })
    }

    @Test func mentionsUseBetaFilterAndImmutableIDs() async throws {
        let url = GraphClient.messagesURL(scope: .mentions)
        #expect(url.absoluteString.hasPrefix("https://graph.microsoft.com/beta/me/mailFolders/inbox/messages"))
        #expect(url.query(percentEncoded: false)?.contains("mentionsPreview/isMentioned eq true") == true)
        #expect(GraphClient.messagesURL(scope: .flagged).absoluteString.hasPrefix("https://graph.microsoft.com/v1.0/"))

        let transport = StubTransport([.init(status: 200, body: page2)])
        _ = try await client(transport).messages(scope: .mentions)
        let request = try #require(transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-123")
        #expect(request.value(forHTTPHeaderField: "Prefer") == "IdType=\"ImmutableId\"")
    }

    @Test func followsPagingAndMapsSafely() async throws {
        let transport = StubTransport([.init(status: 200, body: page1), .init(status: 200, body: page2)])
        let result = try await client(transport).messages(scope: .mentions)
        #expect(result.complete && result.messages.map(\.id) == ["m1", "m2"])
        let drafts = result.messages.compactMap { $0.draft(accountID: "acct", scope: .mentions) }
        #expect(drafts[0].senderName == "Ada" && drafts[0].subject == "Review")
        #expect(drafts[0].webUrl?.host() == "outlook.office.com")
        #expect(drafts[0].importRule == "mentions")
        #expect(drafts[1].subject == "(no subject)")
        #expect(drafts[1].webUrl == nil) // unsafe link dropped
    }

    @Test func retriesThrottlingWithRetryAfter() async throws {
        let sleeps = SleepRecorder()
        let transport = StubTransport([
            .init(status: 429, body: "", headers: ["Retry-After": "7"]),
            .init(status: 503, body: ""),
            .init(status: 200, body: page2),
        ])
        let result = try await client(transport, sleeps: sleeps).messages(scope: .flagged)
        #expect(result.messages.count == 1)
        #expect(sleeps.delays == [.seconds(7), .seconds(2)]) // Retry-After honored, then exponential backoff
    }

    @Test func givesUpAfterRetries() async {
        let transport = StubTransport(Array(repeating: .init(status: 429, body: ""), count: 5))
        await #expect(throws: GraphError.throttled) { _ = try await client(transport).messages(scope: .inbox) }
        #expect(transport.requests.count == 4) // first try + 3 retries
    }

    @Test func mapsAuthPermissionAndOfflineErrors() async {
        await #expect(throws: GraphError.unauthorized) {
            _ = try await client(StubTransport([.init(status: 401, body: "")])).messages(scope: .inbox)
        }
        await #expect(throws: GraphError.forbidden("Access is denied.")) {
            _ = try await client(StubTransport([.init(status: 403, body: #"{"error":{"message":"Access is denied."}}"#)])).messages(scope: .inbox)
        }
        await #expect(throws: GraphError.offline) {
            _ = try await client(StubTransport([.init(status: 0, body: "", error: URLError(.notConnectedToInternet))])).messages(scope: .inbox)
        }
    }

    @Test func inMemoryTokenStore() throws {
        let store = InMemoryTokenStore()
        let tokens = OAuthTokens(accessToken: "a", refreshToken: "r", expiresAt: .now)
        try store.save(tokens, account: "x")
        #expect(try store.load(account: "x") == tokens)
        try store.delete(account: "x")
        #expect(try store.load(account: "x") == nil)
    }
}
