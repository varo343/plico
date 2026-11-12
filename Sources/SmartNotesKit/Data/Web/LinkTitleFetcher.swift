import Foundation

/// Reads a web page's title, for naming a pasted link.
public protocol LinkTitleFetching: Sendable {
    /// Nil when there is no usable title (no answer, not a web page, a sign-in page).
    func title(for url: URL) async -> String?
}

/// Loads the start of the page and reads its title. Sends no cookies and keeps
/// nothing: the request is the one anyone without an account would make, so a
/// page behind a sign-in gives no title and the link keeps its readable name.
public struct WebLinkTitleFetcher: LinkTitleFetching {
    /// The title is in the page's head; nothing past this is read.
    static let maxBytes = 256 * 1024

    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 10
        session = URLSession(configuration: configuration)
    }

    public func title(for url: URL) async -> String? {
        guard LinkNaming.mayFetchTitle(for: url) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        guard let (bytes, response) = try? await session.bytes(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              http.mimeType?.lowercased().contains("html") == true,
              // Sent elsewhere (often a sign-in or consent page): not this page's title.
              let final = http.url, LinkNaming.isSameSite(url, final) else { return nil }
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count >= Self.maxBytes { break }
                // The head is over: the title, if any, is in what was read.
                if byte == UInt8(ascii: ">"), data.count > 7, data.suffix(7).elementsEqual(Data("</head>".utf8)) { break }
            }
        } catch {
            guard !data.isEmpty else { return nil }
        }
        // Lenient: the last character may have been cut in half.
        let html = String(decoding: data, as: UTF8.self)
        return LinkNaming.pageTitle(inHTML: html)
    }
}
