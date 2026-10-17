import Foundation

/// Minimal HTTP seam so the Graph client is testable without the network.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// Which messages Mentions shows.
public enum OutlookImportScope: String, Codable, CaseIterable, Sendable {
    /// Messages that @mention you (Graph beta: `mentionsPreview/isMentioned`).
    case mentions
    /// Flagged messages in the inbox (Graph v1.0).
    case flagged
    /// Everything in the inbox (Graph v1.0).
    case inbox

    public var title: String {
        switch self {
        case .mentions: "Mentions of me"
        case .flagged: "Flagged"
        case .inbox: "All inbox"
        }
    }

    public var explanation: String {
        switch self {
        case .mentions: "Emails where someone @mentioned you."
        case .flagged: "Inbox emails you flagged in Outlook."
        case .inbox: "Every email in your inbox (newest first)."
        }
    }
}

public enum GraphError: Error, Equatable, LocalizedError {
    /// 401: the token is invalid or expired; reconnecting fixes it.
    case unauthorized
    /// 403: missing permission or blocked by organization policy.
    case forbidden(String)
    /// Still throttled after the allowed retries.
    case throttled
    case offline
    case server(Int)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .unauthorized: "Your Outlook session expired. Reconnect to continue."
        case .forbidden(let message): "Outlook refused access: \(message)"
        case .throttled: "Outlook asked to slow down. Try again in a minute."
        case .offline: "You're offline. Showing the messages saved on this Mac."
        case .server(let status): "Outlook had a problem (HTTP \(status)). Try again later."
        case .invalidResponse: "Outlook sent an unexpected response."
        }
    }
}

/// Fields we read from Graph messages (minimal data; no bodies).
public struct GraphMessage: Decodable, Equatable, Sendable {
    public struct Address: Decodable, Equatable, Sendable {
        public struct Email: Decodable, Equatable, Sendable {
            public var name: String?
            public var address: String?
        }
        public var emailAddress: Email?
    }

    public var id: String
    public var subject: String?
    public var from: Address?
    public var receivedDateTime: String?
    public var bodyPreview: String?
    public var webLink: String?
    public var internetMessageId: String?
}

private struct GraphPage: Decodable {
    let value: [GraphMessage]
    let nextLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
    }
}

public struct GraphProfile: Decodable, Equatable, Sendable {
    public var id: String
    public var displayName: String?
    public var mail: String?
    public var userPrincipalName: String?

    public var address: String { mail ?? userPrincipalName ?? displayName ?? id }
}

/// Read-only Microsoft Graph client with paging, throttling and retries.
public struct GraphClient: Sendable {
    public typealias TokenProvider = @Sendable () async throws -> String

    private let transport: HTTPTransport
    private let token: TokenProvider
    private let maxRetries: Int
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(
        transport: HTTPTransport = URLSessionTransport(),
        maxRetries: Int = 3,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        token: @escaping TokenProvider
    ) {
        self.transport = transport
        self.token = token
        self.maxRetries = maxRetries
        self.sleep = sleep
    }

    static let select = "id,subject,from,receivedDateTime,bodyPreview,webLink,internetMessageId"

    public static func messagesURL(scope: OutlookImportScope, pageSize: Int = 50) -> URL {
        // The mentions filter is only available in the beta endpoint.
        let base = scope == .mentions ? "https://graph.microsoft.com/beta" : "https://graph.microsoft.com/v1.0"
        var components = URLComponents(string: "\(base)/me/mailFolders/inbox/messages")!
        var items = [URLQueryItem(name: "$select", value: select), URLQueryItem(name: "$top", value: "\(pageSize)")]
        switch scope {
        case .mentions: items.append(URLQueryItem(name: "$filter", value: "mentionsPreview/isMentioned eq true"))
        case .flagged: items.append(URLQueryItem(name: "$filter", value: "flag/flagStatus eq 'flagged'"))
        case .inbox: items.append(URLQueryItem(name: "$orderby", value: "receivedDateTime desc"))
        }
        components.queryItems = items
        return components.url!
    }

    public func profile() async throws -> GraphProfile {
        let data = try await get(URL(string: "https://graph.microsoft.com/v1.0/me?$select=id,displayName,mail,userPrincipalName")!)
        guard let profile = try? JSONDecoder().decode(GraphProfile.self, from: data) else { throw GraphError.invalidResponse }
        return profile
    }

    /// Messages for `scope`, following `@odata.nextLink` up to `limit`.
    /// `complete` is false when the limit cut the list short.
    public func messages(scope: OutlookImportScope, limit: Int = 200) async throws -> (messages: [GraphMessage], complete: Bool) {
        var url: URL? = Self.messagesURL(scope: scope)
        var all: [GraphMessage] = []
        while let next = url {
            let data = try await get(next)
            guard let page = try? JSONDecoder().decode(GraphPage.self, from: data) else { throw GraphError.invalidResponse }
            all += page.value
            if all.count >= limit { return (Array(all.prefix(limit)), page.nextLink == nil && all.count == limit) }
            url = page.nextLink.flatMap(URL.init(string:))
        }
        return (all, true)
    }

    /// GET with immutable IDs; retries 429 (honoring Retry-After) and 5xx with backoff.
    func get(_ url: URL) async throws -> Data {
        var attempt = 0
        while true {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
            request.setValue("IdType=\"ImmutableId\"", forHTTPHeaderField: "Prefer")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await transport.data(for: request)
            } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost].contains(error.code) {
                throw GraphError.offline
            }
            switch response.statusCode {
            case 200..<300:
                return data
            case 401:
                throw GraphError.unauthorized
            case 403:
                throw GraphError.forbidden(Self.errorMessage(in: data) ?? "permission denied")
            case 429, 500..<600:
                guard attempt < maxRetries else {
                    throw response.statusCode == 429 ? GraphError.throttled : GraphError.server(response.statusCode)
                }
                let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                let delay = retryAfter ?? pow(2, Double(attempt)) // 1, 2, 4 s
                try await sleep(.seconds(min(delay, 60)))
                attempt += 1
            default:
                throw GraphError.server(response.statusCode)
            }
        }
    }

    private static func errorMessage(in data: Data) -> String? {
        struct Envelope: Decodable {
            struct Inner: Decodable { let message: String? }
            let error: Inner?
        }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.error?.message
    }
}

extension GraphMessage {
    /// Maps to an import draft. Unsafe links are dropped (only https Outlook links are kept).
    public func draft(accountID: String, scope: OutlookImportScope) -> ExternalItemDraft? {
        let formatter = ISO8601DateFormatter()
        guard let received = receivedDateTime.flatMap(formatter.date(from:)) else { return nil }
        let link = webLink.flatMap(URL.init(string:)).flatMap { url -> URL? in
            guard url.scheme == "https", let host = url.host()?.lowercased(),
                  host.hasSuffix("outlook.office.com") || host.hasSuffix("outlook.office365.com") || host.hasSuffix("outlook.live.com")
            else { return nil }
            return url
        }
        return ExternalItemDraft(
            key: ExternalItemKey(provider: .outlook, accountId: accountID, externalId: id),
            internetMessageId: internetMessageId,
            subject: (subject?.isEmpty == false ? subject! : "(no subject)"),
            senderName: from?.emailAddress?.name,
            senderAddress: from?.emailAddress?.address,
            preview: String((bodyPreview ?? "").prefix(300)),
            receivedAt: received,
            webUrl: link,
            importRule: scope.rawValue
        )
    }
}
