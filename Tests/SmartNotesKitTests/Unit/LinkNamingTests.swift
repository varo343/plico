import AppKit
import Testing
@testable import SmartNotesKit

@MainActor
struct LinkNamingTests {
    private let template = TextRun("")

    private func url(_ string: String) -> URL { URL(string: string)! }

    @Test func onlyAnAddressOnItsOwnIsALink() {
        #expect(LinkNaming.standaloneURL(in: "  https://example.com/a?b=1 \n") == url("https://example.com/a?b=1"))
        #expect(LinkNaming.standaloneURL(in: "www.example.com") == url("https://www.example.com"))
        #expect(LinkNaming.standaloneURL(in: "see https://example.com") == nil)
        #expect(LinkNaming.standaloneURL(in: "example.com") == nil) // a word with a dot, not clearly an address
        #expect(LinkNaming.standaloneURL(in: "javascript:alert(1)") == nil)
        #expect(LinkNaming.standaloneURL(in: "file:///etc/hosts") == nil)
    }

    @Test func readableNamesShowTheSiteAndWhatThePageIs() {
        #expect(LinkNaming.readableName(for: url("https://www.apple.com")) == "apple.com")
        #expect(LinkNaming.readableName(for: url("https://www.apple.com/")) == "apple.com")
        #expect(LinkNaming.readableName(for: url("https://www.figma.com/design/Hqkx1QC5qPNUjPjBo2h0dV/Plico-UI?node-id=1-2"))
                == "figma.com › Plico UI")
        #expect(LinkNaming.readableName(for: url("https://github.com/acme/plico/pull/12")) == "github.com › pull/12")
        #expect(LinkNaming.readableName(for: url("https://example.com/docs/getting_started.html")) == "example.com › getting started")
        #expect(LinkNaming.readableName(for: url("https://example.com/caf%C3%A9-menu")) == "example.com › café menu")
        #expect(LinkNaming.readableName(for: url("mailto:anna@example.com")) == "anna@example.com")
        let long = LinkNaming.readableName(for: url("https://example.com/" + String(repeating: "word-", count: 30)))
        #expect(long.count <= LinkNaming.maxNameLength && long.hasSuffix("…"))
    }

    @Test func singleUseAndLocalAddressesAreNotLoaded() {
        #expect(LinkNaming.mayFetchTitle(for: url("https://github.com/microsoft/vscode")))
        #expect(LinkNaming.mayFetchTitle(for: url("https://www.youtube.com/watch?v=abc")))
        #expect(!LinkNaming.mayFetchTitle(for: url("https://example.com/reset-password/abc")))
        #expect(!LinkNaming.mayFetchTitle(for: url("https://example.com/auth/magic?x=1")))
        #expect(!LinkNaming.mayFetchTitle(for: url("https://example.com/welcome?token=abc")))
        #expect(!LinkNaming.mayFetchTitle(for: url("https://example.com/cb?code=abc&state=x")))
        #expect(!LinkNaming.mayFetchTitle(for: url("https://example.com/email/unsubscribe")))
        #expect(!LinkNaming.mayFetchTitle(for: url("http://localhost:3000/")))
        #expect(!LinkNaming.mayFetchTitle(for: url("http://192.168.1.10/admin")))
        #expect(!LinkNaming.mayFetchTitle(for: url("http://printer.local/")))
        #expect(!LinkNaming.mayFetchTitle(for: url("mailto:anna@example.com")))
    }

    @Test func pageTitlesPreferOpenGraphAndSkipStandInPages() {
        let page = """
        <html><head><title>Plico — Notes &amp; tasks | Example</title>
        <meta property="og:title" content="Plico &#8212; Notes &amp; tasks"></head></html>
        """
        #expect(LinkNaming.pageTitle(inHTML: page) == "Plico — Notes & tasks")
        #expect(LinkNaming.pageTitle(inHTML: "<title>\n  Release   notes\n</title>") == "Release notes")
        #expect(LinkNaming.pageTitle(inHTML: "<TITLE data-x='1'>Caf&eacute; &#x2014; menu</TITLE>") == "Café — menu")
        #expect(LinkNaming.pageTitle(inHTML: "<title>Sign in to your account</title>") == nil)
        #expect(LinkNaming.pageTitle(inHTML: "<title>Just a moment...</title>") == nil)
        #expect(LinkNaming.pageTitle(inHTML: "<title>   </title>") == nil)
        #expect(LinkNaming.pageTitle(inHTML: "<p>no title</p>") == nil)
    }

    @Test func redirectsToAnotherSiteDoNotCount() {
        #expect(LinkNaming.isSameSite(url("https://example.com/a"), url("https://www.example.com/b")))
        #expect(!LinkNaming.isSameSite(url("https://contoso.sharepoint.com/x"), url("https://login.microsoftonline.com/y")))
    }

    // MARK: Pasting

    private func board(_ fill: (NSPasteboard) -> Void) -> NSPasteboard {
        let board = NSPasteboard(name: .init("SmartNotesTests-\(UUID().uuidString)"))
        board.clearContents()
        fill(board)
        return board
    }

    @Test func aPastedAddressBecomesANamedLink() throws {
        let board = board { $0.setString("https://github.com/acme/plico/pull/12", forType: .string) }
        defer { board.releaseGlobally() }
        let paragraphs = try #require(PasteConverter.paragraphs(from: board, plainOnly: false, template: template))
        #expect(paragraphs.map(\.content.runs) == [[TextRun("github.com › pull/12", link: url("https://github.com/acme/plico/pull/12"))]])
    }

    @Test func aTitleThatCameWithTheAddressNamesIt() throws {
        // Safari: the address and the page's title.
        let safari = board {
            $0.declareTypes([.string, PasteConverter.urlName], owner: nil)
            $0.setString("https://example.com/notes", forType: .string)
            $0.setString("Release notes", forType: PasteConverter.urlName)
        }
        defer { safari.releaseGlobally() }
        #expect(try #require(PasteConverter.paragraphs(from: safari, plainOnly: false, template: template)).first?.content.runs
                == [TextRun("Release notes", link: url("https://example.com/notes"))])

        // Chrome and Edge: the address plus HTML with the link.
        let chrome = board {
            $0.declareTypes([.string, .html], owner: nil)
            $0.setString("https://example.com/notes", forType: .string)
            $0.setString("<a href=\"https://example.com/notes\">Release <b>notes</b></a>", forType: .html)
        }
        defer { chrome.releaseGlobally() }
        #expect(try #require(PasteConverter.paragraphs(from: chrome, plainOnly: false, template: template)).first?.content.runs
                == [TextRun("Release notes", link: url("https://example.com/notes"))])
    }

    @Test func pasteAndMatchStyleKeepsTheWholeAddress() throws {
        let board = board { $0.setString("https://example.com/notes", forType: .string) }
        defer { board.releaseGlobally() }
        let paragraphs = try #require(PasteConverter.paragraphs(from: board, plainOnly: true, template: template))
        #expect(paragraphs.map(\.content.runs) == [[TextRun("https://example.com/notes")]])
    }

    @Test func anAddressInsideTextIsLeftAsIs() throws {
        let board = board { $0.setString("see https://example.com", forType: .string) }
        defer { board.releaseGlobally() }
        let paragraphs = try #require(PasteConverter.paragraphs(from: board, plainOnly: false, template: template))
        #expect(paragraphs.map(\.content.plainText) == ["see https://example.com"])
    }
}
