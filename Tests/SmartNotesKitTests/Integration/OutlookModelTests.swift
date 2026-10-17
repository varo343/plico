import Foundation
import Testing
@testable import SmartNotesKit

/// Plays the browser: echoes back a code with the request's own state (or a tampered one).
struct FakeAuthenticator: WebAuthenticator {
    var tamperState = false
    var cancel = false

    @MainActor
    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        if cancel { throw OutlookAuthError.cancelled }
        let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value ?? ""
        return URL(string: "smartnotes://auth?code=CODE&state=\(tamperState ? "evil" : state)")!
    }
}

@MainActor
@Suite(.serialized) struct OutlookModelTests {
    private let config = OutlookConfiguration(clientID: "11111111-2222-3333-4444-555555555555", tenant: "common")
    private let tokenReply = StubTransport.Reply(status: 200, body: #"{"access_token":"AT","refresh_token":"RT","expires_in":3600}"#)
    private let profileReply = StubTransport.Reply(status: 200, body: #"{"id":"user-1","displayName":"You","mail":"you@contoso.com"}"#)

    private func messages(_ ids: [String]) -> StubTransport.Reply {
        let items = ids.map { #"{"id":"\#($0)","subject":"Subject \#($0)","from":{"emailAddress":{"name":"Ada","address":"ada@contoso.com"}},"receivedDateTime":"2026-10-17T08:00:00Z","bodyPreview":"@you please look","webLink":"https://outlook.office.com/mail/id/\#($0)"}"# }
        return .init(status: 200, body: #"{"value":[\#(items.joined(separator: ","))]}"#)
    }

    private func makeModel(_ replies: [StubTransport.Reply], authenticator: FakeAuthenticator = FakeAuthenticator(),
                           tokens: InMemoryTokenStore = InMemoryTokenStore()) throws -> (OutlookModel, AppDependencies, StubTransport, InMemoryTokenStore) {
        let deps = try AppDependencies.inMemory()
        let transport = StubTransport(replies)
        let preferences = OutlookPreferences(defaults: UserDefaults(suiteName: "SNOutlookTests.\(UUID().uuidString)")!)
        let session = OutlookSession(tokenStore: tokens, transport: transport, authenticator: authenticator)
        let model = OutlookModel(repository: deps.externalItems, integrationStates: deps.integrationStates, session: session, preferences: preferences)
        model.configuration = config
        return (model, deps, transport, tokens)
    }

    @Test func connectSignsInStoresTokensAndSyncsMentions() async throws {
        let (model, _, transport, tokens) = try makeModel([tokenReply, profileReply, messages(["m1", "m2"])])
        #expect(model.status == .disconnected)
        #expect(model.scope == .mentions) // default per request
        await model.connect()
        #expect(model.account == OutlookAccount(id: "user-1", address: "you@contoso.com", displayName: "You"))
        #expect(try tokens.load(account: "user-1")?.accessToken == "AT")
        #expect(model.status == .ready && model.lastSyncAt != nil)
        #expect(model.items.map(\.externalId).sorted() == ["m1", "m2"])
        // Code exchange used PKCE; the mail request went to the beta mentions filter.
        let exchange = String(decoding: transport.requests[0].httpBody ?? Data(), as: UTF8.self)
        #expect(exchange.contains("code=CODE") && exchange.contains("code_verifier="))
        #expect(transport.requests[2].url?.absoluteString.contains("graph.microsoft.com/beta") == true)
    }

    @Test func refreshDedupesKeepsDismissalsAndDropsStale() async throws {
        let (model, _, _, _) = try makeModel([tokenReply, profileReply, messages(["m1", "m2", "m3"]), messages(["m1", "m2"])])
        await model.connect()
        let m1 = try #require(model.items.first { $0.externalId == "m1" })
        model.dismiss(m1.id)
        #expect(!model.items.contains { $0.id == m1.id })

        await model.refresh()
        #expect(model.items.map(\.externalId).sorted() == ["m2"]) // m1 stays dismissed, m3 no longer mentions you
    }

    @Test func offlineKeepsSavedEmails() async throws {
        let (model, _, _, _) = try makeModel([tokenReply, profileReply, messages(["m1"]),
                                              .init(status: 0, body: "", error: URLError(.notConnectedToInternet))])
        await model.connect()
        await model.refresh()
        #expect(model.status == .offline)
        #expect(model.items.map(\.externalId) == ["m1"])
    }

    @Test func expiredSessionAsksToReconnect() async throws {
        let (model, _, _, _) = try makeModel([tokenReply, profileReply, messages([]), .init(status: 401, body: "")])
        await model.connect()
        await model.refresh()
        guard case .needsReconnect = model.status else {
            Issue.record("expected needsReconnect, got \(model.status)")
            return
        }
    }

    @Test func expiredTokenIsRefreshedAutomatically() async throws {
        let tokens = InMemoryTokenStore()
        let (model, _, transport, _) = try makeModel([
            .init(status: 200, body: #"{"access_token":"OLD","refresh_token":"RT","expires_in":10}"#), // expires immediately (60 s margin)
            profileReply,
            tokenReply,           // refresh before the first mail request
            messages(["m1"]),
        ], tokens: tokens)
        await model.connect()
        #expect(model.items.count == 1)
        let refresh = String(decoding: transport.requests[2].httpBody ?? Data(), as: UTF8.self)
        #expect(refresh.contains("grant_type=refresh_token") && refresh.contains("refresh_token=RT"))
        #expect(try tokens.load(account: "user-1")?.accessToken == "AT")
    }

    @Test func tamperedStateIsRejected() async throws {
        let (model, _, transport, _) = try makeModel([], authenticator: FakeAuthenticator(tamperState: true))
        await model.connect()
        #expect(model.account == nil)
        guard case .failed = model.status else { Issue.record("expected failure"); return }
        #expect(transport.requests.isEmpty) // no code exchange happened
    }

    @Test func cancelledSignInReturnsToDisconnected() async throws {
        let (model, _, _, _) = try makeModel([], authenticator: FakeAuthenticator(cancel: true))
        await model.connect()
        #expect(model.status == .disconnected)
    }

    @Test func disconnectRemovesTokensAndOptionallyEmails() async throws {
        let (model, deps, _, tokens) = try makeModel([tokenReply, profileReply, messages(["m1"])])
        await model.connect()
        model.disconnect(removeSavedMessages: false)
        #expect(try tokens.load(account: "user-1") == nil)
        #expect(model.account == nil && model.items.isEmpty)
        #expect(try deps.externalItems.items(provider: .outlook, accountId: "user-1", includeDismissed: true).count == 1)
    }

    @Test func createNoteFromEmailLinksBack() async throws {
        let (model, _, _, _) = try makeModel([tokenReply, profileReply, messages(["m1"])])
        await model.connect()
        let item = try #require(model.items.first)
        let note = model.makeNote(from: item, rank: "i")
        #expect(note.title == "Subject m1")
        #expect(note.sourceExternalItemId == item.id)
        #expect(note.blocks[0].content.plainText.hasPrefix("From Ada <ada@contoso.com>"))
        #expect(note.blocks[1].content.runs.first?.link == URL(string: "https://outlook.office.com/mail/id/m1"))
        #expect(note.blocks[2].type == .quote && note.blocks[2].content.plainText == "@you please look")
    }

    @Test func samplesAreNeverStored() async throws {
        let (model, deps, _, _) = try makeModel([])
        model.configuration = OutlookConfiguration()
        model.showSamples(true)
        #expect(model.items.count == 3 && model.isShowingSamples)
        model.dismiss(model.items[0].id)
        #expect(model.items.count == 2)
        #expect(try deps.externalItems.items(provider: .outlook, accountId: "sample", includeDismissed: true).isEmpty)
    }
}
