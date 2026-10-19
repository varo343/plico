import Foundation

/// Fictional workspace for screenshots (`--portfolio-demo`): in-memory notes,
/// plus an Outlook connection that looks signed in with cached mentions.
/// Nothing touches the network, the Keychain or the user's real data.
@MainActor
public enum PortfolioDemo {
    public nonisolated static let account = OutlookAccount(id: "demo", address: "giulia.rossi@lumen.example", displayName: "Giulia Rossi")
    public nonisolated static let configuration = OutlookConfiguration(clientID: "4f6c2a1e-9b3d-4e8a-a7c5-2d1f0b9e6a34", tenant: "organizations")

    public static func dependencies(appearance: AppearancePreference, now: Date = .now) throws -> AppDependencies {
        let defaults = UserDefaults(suiteName: "Plico.PortfolioDemo.\(UUID().uuidString)") ?? .standard
        let tokens = InMemoryTokenStore()
        try tokens.save(OAuthTokens(accessToken: "demo", refreshToken: nil, expiresAt: now.addingTimeInterval(86_400)), account: account.id)
        let deps = AppDependencies(
            modelContainer: try PersistenceController.makeContainer(.inMemory),
            settings: UserDefaultsSettingsStore(defaults: defaults), isInMemory: true,
            outlookSession: OutlookSession(tokenStore: tokens, transport: DemoGraphTransport(messages: mentions(now: now))),
            outlookPreferences: OutlookPreferences(defaults: defaults)
        )
        var settings = deps.settings.load()
        settings.appearance = appearance
        deps.settings.save(settings)
        for note in notes(now: now) { try deps.notes.save(note) }

        deps.outlookPreferences.saveConfiguration(configuration)
        deps.outlookPreferences.saveScope(.mentions)
        deps.outlookPreferences.saveAccount(account)
        _ = try deps.externalItems.upsert(mentions(now: now), syncedAt: now)
        // A fresh sync time keeps the app from trying to reach Microsoft Graph.
        try deps.integrationStates.save(IntegrationState(provider: .outlook, accountId: account.id, lastSyncAt: now))
        return deps
    }

    static func mentions(now: Date) -> [ExternalItemDraft] {
        let mails: [(String, String, String, TimeInterval)] = [
            ("Marco Bianchi", "Checkout v2 — final review on Thursday",
             "@Giulia Rossi can you walk us through the new payment step? 10 minutes is enough, then we decide on the address autocomplete.", -1_200),
            ("Sara Conti", "Onboarding interviews: raw notes are in",
             "Thanks everyone! @Giulia Rossi, the three quotes about the empty state are worth a look before the synthesis.", -9_000),
            ("Luca Ferri", "Design tokens v3 — naming proposal",
             "Proposal attached. @Giulia Rossi I kept your 'surface/raised' idea, let me know if the dark palette works for you.", -26_000),
            ("Elena Greco", "Accessibility audit results",
             "@Giulia Rossi the focus order on the cart page fails on two screens, details in the report.", -93_000),
            ("Davide Marino", "Offsite agenda",
             "Draft agenda below. @Giulia Rossi could you host the 30' design crit on day two?", -180_000),
        ]
        return mails.enumerated().map { index, mail in
            ExternalItemDraft(
                key: ExternalItemKey(provider: .outlook, accountId: account.id, externalId: "demo-\(index)"),
                subject: mail.1, senderName: mail.0,
                senderAddress: mail.0.lowercased().replacingOccurrences(of: " ", with: ".") + "@lumen.example",
                preview: mail.2, receivedAt: now.addingTimeInterval(mail.3),
                webUrl: URL(string: "https://outlook.office.com/mail/"), importRule: OutlookImportScope.mentions.rawValue
            )
        }
    }

    static func notes(now: Date, calendar: Calendar = .current) -> [Note] {
        let today = LocalDay(date: now, calendar: calendar)
        let ranks = Rank.evenlySpaced(7)
        func blocks(_ specs: [(BlockType, RichText, Bool, Int)]) -> [NoteBlock] {
            zip(specs, Rank.evenlySpaced(specs.count)).map { spec, rank in
                NoteBlock(type: spec.0, rank: rank, content: spec.1, isChecked: spec.2, indentLevel: spec.3)
            }
        }
        func p(_ text: String) -> RichText { RichText(plain: text) }

        return [
            Note(title: "Checkout v2 — review prep", createdAt: now.addingTimeInterval(-86_400 * 4),
                 updatedAt: now.addingTimeInterval(-600), isPinned: true, priority: .high,
                 plannedDate: today, dueDate: today.adding(days: 2), manualRank: ranks[0],
                 blocks: blocks([
                    (.heading1, p("Goal"), false, 0),
                    (.paragraph, RichText(runs: [
                        TextRun("Cut the payment step from "), TextRun("three screens to one", marks: [.bold]),
                        TextRun(" without losing trust signals. Prototype in "),
                        TextRun("Figma", link: URL(string: "https://www.figma.com")), TextRun("."),
                    ]), false, 0),
                    (.heading2, p("Before Thursday"), false, 0),
                    (.checklistItem, p("Update the flow with the address autocomplete"), true, 0),
                    (.checklistItem, p("Prepare 3 variants of the error state"), true, 0),
                    (.checklistItem, p("Ask Marco for the conversion data"), false, 0),
                    (.checklistItem, p("Rehearse the 10' walkthrough"), false, 0),
                    (.heading2, p("Open questions"), false, 0),
                    (.bulletItem, p("Do we keep the order summary sticky on mobile?"), false, 0),
                    (.bulletItem, p("Apple Pay first, or card first?"), false, 0),
                    (.bulletItem, p("Depends on the market split"), false, 1),
                    (.quote, RichText(runs: [TextRun("Fewer steps, same confidence.", marks: [.italic], fontFamily: .serif)]), false, 0),
                 ])),
            Note(title: "Onboarding interviews — synthesis", createdAt: now.addingTimeInterval(-86_400 * 6),
                 updatedAt: now.addingTimeInterval(-7_200), priority: .medium, plannedDate: today, manualRank: ranks[1],
                 blocks: blocks([
                    (.paragraph, p("8 interviews, 3 recurring themes."), false, 0),
                    (.numberedItem, p("The empty state feels like an error"), false, 0),
                    (.numberedItem, p("People want a template to start from"), false, 0),
                    (.numberedItem, p("Shortcuts are discovered by accident"), false, 0),
                    (.quote, p("\"I didn't know where to click first.\" — P4"), false, 0),
                 ])),
            Note(title: "Accessibility fixes", createdAt: now.addingTimeInterval(-86_400 * 9),
                 updatedAt: now.addingTimeInterval(-86_400), priority: .high, dueDate: today.adding(days: -1), manualRank: ranks[2],
                 blocks: blocks([
                    (.checklistItem, p("Focus order on cart page"), false, 0),
                    (.checklistItem, p("Contrast of secondary buttons"), true, 0),
                    (.checklistItem, p("VoiceOver labels on icons"), false, 0),
                 ])),
            Note(title: "1:1 with Marco", createdAt: now.addingTimeInterval(-86_400 * 2),
                 updatedAt: now.addingTimeInterval(-3_600 * 5), plannedDate: today, manualRank: ranks[3],
                 blocks: blocks([
                    (.bulletItem, p("Feedback on the design crit format"), false, 0),
                    (.bulletItem, p("Q1 growth goals"), false, 0),
                    (.checklistItem, p("Share the research repository"), false, 0),
                 ])),
            Note(title: "Design tokens v3", createdAt: now.addingTimeInterval(-86_400 * 12),
                 updatedAt: now.addingTimeInterval(-86_400 * 2), priority: .low, plannedDate: today.adding(days: 5), manualRank: ranks[4],
                 blocks: blocks([
                    (.heading2, p("Naming"), false, 0),
                    (.bulletItem, p("surface / raised / sunken"), false, 0),
                    (.bulletItem, p("ink / ink-muted / ink-faint"), false, 0),
                    (.paragraph, RichText(runs: [TextRun("Check "), TextRun("color.surface.raised", marks: [.code], fontFamily: .monospaced), TextRun(" in dark mode.")]), false, 0),
                 ])),
            Note(title: "Micro-interaction ideas", createdAt: now.addingTimeInterval(-86_400 * 20),
                 updatedAt: now.addingTimeInterval(-86_400 * 6), manualRank: ranks[5],
                 blocks: blocks([
                    (.bulletItem, p("Icons that move by meaning: trash tips, sun turns, mail lifts"), false, 0),
                    (.bulletItem, p("Hand-drawn hover shapes, never perfect"), false, 0),
                 ])),
            Note(title: "Lisbon weekend", createdAt: now.addingTimeInterval(-86_400 * 30),
                 updatedAt: now.addingTimeInterval(-86_400 * 10), dueDate: today.adding(days: 12), manualRank: ranks[6],
                 blocks: blocks([
                    (.checklistItem, p("Book the tram 28 early in the morning"), false, 0),
                    (.checklistItem, p("Pastéis de Belém"), false, 0),
                 ])),
        ]
    }
}

/// Answers Microsoft Graph requests locally with the demo mentions, so
/// "Refresh" works in the demo without any network access.
private struct DemoGraphTransport: HTTPTransport {
    let messages: [ExternalItemDraft]

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://graph.microsoft.com")!
        let body: Any
        if url.path.hasSuffix("/me") {
            body = ["id": PortfolioDemo.account.id, "displayName": "Giulia Rossi", "mail": PortfolioDemo.account.address]
        } else {
            let formatter = ISO8601DateFormatter()
            body = ["value": messages.map { message in
                [
                    "id": message.key.externalId,
                    "subject": message.subject,
                    "from": ["emailAddress": ["name": message.senderName ?? "", "address": message.senderAddress ?? ""]],
                    "receivedDateTime": formatter.string(from: message.receivedAt),
                    "bodyPreview": message.preview,
                    "webLink": message.webUrl?.absoluteString ?? "",
                ] as [String: Any]
            }]
        }
        let data = try JSONSerialization.data(withJSONObject: body)
        return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
    }
}

