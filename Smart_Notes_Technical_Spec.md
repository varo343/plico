# Smart Notes — Product & Technical Specification

**Version:** 1.1 — MVP implementation handoff (aligned with UX/UI specification)  
**Target:** macOS desktop, single user, local-first  
**Status:** Implementation-ready proposal; product assumptions explicitly identified  
**Language:** English for coding-agent handoff; user-facing UI may be Italian or English.

---

## 1. Product vision

Build a fast, elegant native macOS note-taking app that replaces Apple Notes for one user. Its primary value is frictionless capture and organization of notes, plus an optional Outlook inbox that surfaces relevant email messages and lets the user turn them into notes. It is **not** a task-management platform, email client, AI assistant, or agent orchestrator.

### Principles
1. Notes first. Writing is the primary action and always works offline.
2. Local-first. User-authored notes reside in an on-device database; no custom server.
3. Predictable controls. No AI-driven priority assignment or opaque automatic scheduling.
4. Keyboard-first and accessible. Every primary operation has a keyboard alternative.
5. Minimal integrations. Outlook read-only in v1; Azure DevOps direct integration deferred.
6. No paid Apple Developer Program required to build and run locally on the developer's Mac. Public distribution/signing may require additional steps and costs.

### Success criteria (personal beta)
- App launches and opens the most recent note promptly on a typical Mac.
- All editing works offline; no content loss on crash/restart in ordinary use.
- User can create, find, pin, prioritize, schedule, reorder, and delete notes.
- Paragraph/list/checklist blocks can be moved up/down without corrupting content.
- Outlook inbox imports relevant messages on manual refresh and app foreground, when authorized.
- Every imported message links to its original Outlook message; duplicates are avoided.

## 2. Scope

### In scope: v1
- Native macOS app; SwiftUI shell and navigation.
- Notes CRUD, duplicate, pin/unpin, soft delete and restore.
- Rich text block editor: paragraph, H1/H2/H3, bold, italic, underline, strikethrough, inline link, text size presets, font family presets, checklist, bullet/numbered list, inline code optional stretch.
- Per-block drag-and-drop reordering, with keyboard Move Up/Down alternative.
- Notes manual ordering and sort options: manual, updated, created, title, priority, due date.
- Priority: none, low, medium, high.
- Planned date and due date (independent, optional).
- Today view: planned for today, overdue due dates, and due today; completion for checklist items. Note-level 'done' is optional; no mandatory task conversion.
- Search across note title and plain text derived from blocks.
- Outlook account connection via Microsoft identity OAuth with PKCE, delegated read permissions, Keychain tokens, read-only import.
- Outlook inbox cards: sender, subject, snippet, timestamp, source URL, unread/read-in-app state, dismiss-in-app, Create Note from Message.
- Filters for Outlook: all inbox messages vs focused relevance (user-configurable), with safe default **flagged messages and explicitly user-selected senders/keywords**; do not assume Outlook provides a universal '@mentioned me' property.
- Settings: account connection, sync controls, appearance, editor font preferences, data export.
- JSON and Markdown export of user-authored notes (backup/portability).

### Out of scope: v1
- iOS, CloudKit/iCloud sync, web app, shared notes, multi-user collaboration.
- Azure DevOps direct REST integration (planned extension, not silently included).
- AI classification, automatic priority, LLM costs, chat, embeddings, semantic search.
- Email sending, deletion, marking read on Outlook, or calendar editing.
- Outlook webhook backend / guaranteed real-time push.
- Embedded attachments, OCR, handwriting, PDFs, full Markdown/WYSIWYG interchange fidelity.
- Reminder notifications and recurring tasks (later phase).

## 3. Information architecture

**Sidebar**
- Notes (default)
- Today
- Mentions (Outlook-backed; show connection empty state until connected)
- Trash
- Settings (via sidebar footer or app menu; not a main destination)

**Notes layout:** sidebar + sortable note list + editor detail pane. Support compact single-pane mode on smaller windows. New note is always accessible via Cmd+N. Note list shows title, preview, updated date, priority, pin, planned/due date badges. Drag reorder available in Manual sort only. Pinned notes appear above unpinned; manual rank is preserved within each group.

**Today layout:** sections: Overdue, Due Today, Planned Today. De-duplicate notes appearing in more than one section. Note cards open original note. A note scheduled today is not automatically marked urgent. Completed checklist items remain checked and can be hidden via toggle.

**Mentions layout:** Outlook inbox cards, source filters, refresh, account status, open in Outlook, create note. Imported emails are **not automatically editable notes**; this prevents noise and data duplication. User explicitly creates a note from an email, with backlink to the source.

## 4. Interaction specification

### Notes lifecycle
- Cmd+N creates untitled note and focuses first paragraph; title inferred from first line only as an optional UI fallback, not destructive transformation.
- Autosave after edits with short debounce (e.g. 300–600 ms), plus immediate save on focus loss/window close where possible.
- Delete moves note to Trash; restore returns note to its prior state. Empty Trash is explicit and irreversible with confirmation.
- No Archive feature in MVP. Notes are either active or in Trash.
- Duplicate clones blocks and formatting but creates fresh IDs and timestamps.
- Undo/redo supports editor actions and block moves; Cmd+Z / Shift+Cmd+Z.

### Rich text editor
- **Block types:** paragraph, heading1, heading2, heading3, bulletItem, numberedItem, checklistItem, quote (stretch).
- **Inline marks:** bold, italic, underline, strikethrough, link. Text size and font family can be chosen from a small, deliberate set; support a default body size and optional per-block overrides.
- Enter splits a block at cursor; Backspace at start merges compatible blocks; Shift+Enter inserts a soft line break within a block.
- Tab/Shift+Tab indent/outdent list/checklist blocks; dragging grip reorders blocks.
- **Reordering semantics:** draggable units are logical blocks/paragraphs, not visual wrapped lines. Preserve inline formatting and checklist state during moves.
- Cmd+B, Cmd+I, Cmd+U, Cmd+K, standard text navigation, paste as plain text option.
- Paste HTML/RTF should degrade gracefully to supported marks/blocks; never silently lose the entire pasted text.
- Multi-block selection and drag are phase 2 unless easily supported.

### Priority and dates
- Priority enum: none / low / medium / high. Never inferred from age alone.
- Planned date means “I intend to work on it”; due date means “deadline.” Both can coexist.
- Today uses device-local calendar/timezone; overdue is strictly due date before today and not deleted.
- An item can be marked complete via checklist blocks. Note-level completion may be added later after testing; don't conflate archival with completion.

### Outlook relevance
- **Important:** an email received by the user is not necessarily an @mention; mail metadata may not expose a reliable universal “mentioned me” signal.
- First iteration supports selectable scopes: Flagged, Inbox, Selected senders, Subject/body keyword matching (limited to permitted fetched content). Default: Flagged, to avoid flooding Notes.
- Optional rules can include direct recipients, excluding automated newsletters; such rules are heuristics and labeled accordingly.
- Import creates a read-only `ExternalItem`, not a `Note`.
- “Create note” generates a new note with subject, source link, short excerpt, and optional copied body only upon explicit user action.
- Dismiss in app hides the card locally and does not archive/delete the message in Outlook.

## 5. Architecture

### Technology stack
- Swift 6-compatible codebase, Xcode, SwiftUI for macOS app shell.
- SwiftData for local persistence **if** editor models and schema migration tests pass; Core Data is acceptable fallback if SwiftData introduces instability. Keep persistence behind repositories.
- AppKit NSTextView / NSTextStorage integration via NSViewRepresentable for editing text where SwiftUI TextEditor lacks required rich text control. For robust block-level editing, prefer separate block editors backed by attributed text or a carefully scoped custom NSTextView coordinator. **Do not assume SwiftUI TextEditor supports rich text and block drag out of the box.**
- Keychain Services for auth tokens; Microsoft Authentication Library (MSAL) for native public client auth if compatible with deployment target, or standards-compliant OAuth 2.0 authorization code + PKCE via ASWebAuthenticationSession. No client secret in desktop app.
- URLSession for Microsoft Graph requests; structured concurrency, cancellation, backoff.
- Local-only initial storage; no CloudKit, custom backend, third-party analytics, or AI API.
- Minimum macOS version: **macOS 14 Sonoma** (proposal; adjust based on the developer's Mac and SwiftData behavior).

### Module boundaries
```
SmartNotesApp/
  App/              # entry point, dependency composition, navigation
  Features/
    Notes/          # list, editor, note commands
    Today/          # date-derived views
    Outlook/        # inbox, connect, refresh, external item detail
    Settings/
  Domain/
    Models/         # Note, Block, ExternalItem, enums
    Services/       # sorting, search, Today rules
    Repositories/   # protocols
  Data/
    Persistence/    # SwiftData schemas, migrations, repository impl
    Outlook/        # auth, Graph client, delta sync, mappings
    Security/       # Keychain wrapper
  Shared/
    UI/             # common components, design tokens
    Utilities/
  Tests/
    Unit/
    Integration/
    UI/
```

### Data flow
```
User action -> SwiftUI ViewModel -> Domain command -> Repository -> SwiftData
                                                   -> UI observable state

Outlook Connect -> MSAL/OAuth PKCE -> Keychain token
Outlook Refresh -> Graph Client -> mapper -> dedupe/upsert ExternalItem -> SwiftData
Outlook item -> explicit Create Note -> Note Repository
```

## 6. Domain model

### Note
- `id: UUID`
- `title: String`
- `createdAt: Date`
- `updatedAt: Date`
- `isPinned: Bool`
- `deletedAt: Date?`
- `priority: Priority` (`none`, `low`, `medium`, `high`)
- `plannedDate: Date?` (date-only semantic in user's timezone)
- `dueDate: Date?` (date-only semantic)
- `manualRank: Double` or stable sortable rank string
- `sourceExternalItemId: UUID?`
- `blocks: [NoteBlock]` ordered by rank
- `searchText: String` derived/updated on save

### NoteBlock
- `id: UUID`
- `noteId: UUID`
- `type: BlockType`
- `rank: String` (stable fractional indexing or explicit integer normalization)
- `content: AttributedTextPayload` — versioned serialized attributed runs or restricted rich-text representation
- `isChecked: Bool` (checklist only)
- `indentLevel: Int` (bounded)

**Storage caution:** define a deterministic, versioned format for inline marks; do not store opaque platform archives without migration tests. Suggested JSON payload: `{ "version": 1, "runs": [{ "text": "...", "marks": ["bold"], "link": null }] }`. Font family/size can be optional per-run attributes. Newlines in a block represent soft breaks only.

### ExternalItem
- `id: UUID`
- `provider: outlook`
- `accountId: String`
- `externalId: String` (prefer immutable Graph message IDs when configured)
- `internetMessageId: String?`
- `subject: String`
- `senderName: String?`
- `senderAddress: String?`
- `preview: String`
- `receivedAt: Date`
- `webUrl: URL?`
- `isDismissedLocally: Bool`
- `isSeenLocally: Bool`
- `importRule: String`
- `lastSyncedAt: Date`
- Unique composite key: `(provider, accountId, externalId)` enforced in repository/upsert logic.

### IntegrationState
- `provider: outlook`
- `accountId: String`
- `lastSyncAt: Date?`
- `deltaLink: String?` (treat as sensitive operational metadata; protect appropriately)
- `syncStatus: idle|syncing|error|reauthRequired`
- `lastError: String?` (redacted; never tokens)

### Settings
- `defaultFontFamily`, `defaultFontSize`, `appearance`, `outlookFilterMode`, `outlookRules`, `sortMode`.

## 7. Outlook integration: implementation contract

### Authentication
1. Register a native/public client application in Microsoft Entra ID; supported account types depend on personal vs organizational account requirements.
2. Use authorization code flow with PKCE, system browser auth, delegated permissions, least privilege.
3. Start with `User.Read` and `Mail.Read` if reading message bodies/metadata is required; request `offline_access` only for refresh functionality and handle consent requirements. Confirm exact permission needs in official Microsoft Graph docs during implementation.
4. Store tokens via MSAL secure token cache/Keychain; never in SwiftData or logs.
5. Offer Disconnect, which clears local tokens and optionally locally cached imported message metadata after user confirmation.
6. Organizational tenant policy may block app registration or consent; show actionable error and keep Notes fully usable.

### Fetch and sync
- Initial: retrieve selected mail folder/filter pages, minimum required fields (`id`, `subject`, `from`, `receivedDateTime`, `bodyPreview`, `webLink`, `flag`, `isRead` where needed).
- Subsequent: use Graph delta query for supported mail folder/message scope; preserve and follow returned `@odata.nextLink` / `@odata.deltaLink`. Delta may return more than filtered matches; filter locally as needed. Do not invent support for arbitrary server-side delta filters.
- Use immutable IDs via `Prefer: IdType="ImmutableId"` consistently when supported; confirm response semantics.
- Refresh on app launch, foreground, and user command. Optional best-effort periodic refresh while app is running. No guaranteed background/instant updates without a server/webhook architecture.
- Handle 401 reauth, 403 permissions, 429 throttling with `Retry-After`, transient 5xx with bounded exponential backoff, network offline, pagination, deleted messages, delta token invalidation/full resync.
- Fetch minimal data; avoid retaining full bodies by default. Deduplicate on stable provider/account/external IDs.
- `Open in Outlook` uses original `webLink`; do not mutate remote message state in v1.

### Future Azure DevOps
- Direct integration is **not** part of v1. If added: separate connector module, explicit user/work item identity matching, comment mentions, assigned work items, source deep links, and independent permission assessment. Do not assume Azure DevOps mentions are delivered as Outlook emails in all organizations.

## 8. Data privacy and security

- Notes stored locally, accessible without Microsoft connection.
- Microsoft data may be confidential employer data. Before using corporate credentials, confirm company policy for third-party apps, data storage, and permissions.
- Cache only minimal message metadata/preview; support removal of cached Outlook data without deleting authored notes.
- No hardcoded secrets; no tokens, message bodies, or note contents in logs/crash reports.
- Enforce HTTPS and standard system auth session; never embed a login webview that captures credentials.
- Validate imported URLs, sanitize HTML if any content is rendered, and avoid treating external content as executable instructions.
- Export user notes on demand; allow full deletion of local app data via explicit confirmation.
- No analytics SDK or cloud LLM calls in MVP.

## 9. UX behavior and design system

**Design source of truth:** `Smart_Notes_UX_UI_Design_Spec.md`. If the technical and design specs conflict on visual presentation, the design spec wins; if they conflict on security, persistence or API capabilities, the technical spec wins. Escalate behavioral scope conflicts rather than guessing.

- Three-pane macOS navigation; collapsible sidebar; consistent empty/loading/error states.
- Persistent primary floating New Note button anchored to bottom-right of content region, organic cartoon silhouette with plus sign; always also Cmd+N. Ensure it does not obscure editor text or list actions.
- Native platform controls, semantic typography, light/dark mode, Dynamic Type/accessibility where applicable.
- Keyboard: Cmd+N new, Cmd+F search, Cmd+S optional manual flush, Cmd+B/I/U formatting, Cmd+K link, Cmd+Delete trash selected note (with safeguards), Cmd+Z undo, Shift+Cmd+Z redo, Up/Down via focus and shortcuts.
- Drag handles appear on block hover; show insertion line while dragging; keyboard alternative via context menu.
- Focus mode optional: hide note list/sidebar, but not required for MVP.
- Always show sync/connection state for Outlook; never imply an email was imported in real time if it was not.
- Avoid badges/counts that treat every imported email as an urgent task.

## 10. Acceptance criteria / QA checklist

### Notes
- [ ] Create note, type, quit app, reopen: content retained.
- [ ] Edit title and multiple blocks; formatting persists across relaunch.
- [ ] Duplicate note: new IDs, original unaffected.
- [ ] Pin/unpin and manual reorder persist across relaunch.
- [ ] Manual reorder disabled/explained when a computed sort is selected.
- [ ] Move block up/down by drag and keyboard; inline formatting and checkbox state preserved.
- [ ] Undo/redo text edits and moves work as specified.
- [ ] Delete -> Trash -> Restore; empty trash requires confirmation.
- [ ] Search finds title and body text and excludes trashed notes by default.
- [ ] Date-only values remain stable across timezone/DST changes.

### Today
- [ ] Planned today shown.
- [ ] Due today shown.
- [ ] Overdue shown without duplicate cards.
- [ ] Trashed notes excluded.
- [ ] No auto-assigned priorities or phantom deadlines.

### Outlook
- [ ] App works with no Microsoft account.
- [ ] Sign in and sign out; credentials not logged or saved in plaintext.
- [ ] Initial fetch displays correct sender, subject, preview, date and source URL.
- [ ] Second fetch does not duplicate existing messages.
- [ ] Flagged/selected-rule filters work as documented.
- [ ] Create Note from email creates editable local note with backlink.
- [ ] Dismissing a card does not modify remote Outlook email.
- [ ] Network failure preserves existing cache and provides Retry.
- [ ] Permission denied/expired token shows reconnect action.
- [ ] 429 throttling respects server backoff.

### Quality
- [ ] Unit tests for sort, Today rules, block ordering, dedupe, search text.
- [ ] Persistence migration tests with representative formatted notes.
- [ ] Accessibility labels and keyboard-only flow tested.
- [ ] Large-note editing tested (e.g., 100+ blocks) without unacceptable lag.
- [ ] No loss of notes during interrupted autosave simulation.

## 11. Implementation plan and milestones

**Milestone 0 — Bootstrap (1–2 days):** macOS project, folder structure, DI, persistence schema, sample fixtures, unit test target.

**Milestone 1 — Notes foundation (3–5 days):** sidebar/list/editor shell, CRUD, autosave, trash, search, sorting, pinning.

**Milestone 2 — Block editor (5–10+ days):** rich text formatting, block split/merge, checklist, drag reorder, keyboard alternatives, undo/redo. This is the largest technical risk; prototype before committing to the editor approach.

**Milestone 3 — Priority, dates, Today (2–4 days):** metadata controls, due/planned semantics, Today filters, tests.

**Milestone 4 — Outlook (4–8+ days):** Microsoft app registration, auth, Graph fetch/delta, inbox, filtering, create-note action, error states. Corporate consent may block testing.

**Milestone 5 — Polish (3–5 days):** accessibility, performance, exports, recovery, tests, empty states.

Estimates are rough development effort, not promises; coding agents may accelerate scaffolding but editor behavior and OAuth need manual validation.

## 12. Technical decisions and known risks

| Decision | Why | Risk / mitigation |
|---|---|---|
| macOS only | Zero need for cross-device infrastructure | No phone capture; revisit later |
| Local SwiftData | Simple personal app | Migration/corruption; repository abstraction, backups/tests |
| Rich block editor | Enables predictable reorder | Hardest component; spike with NSTextView first |
| Manual Today | Trustworthy, transparent | No intelligent resurfacing in MVP |
| Outlook read-only | Least risky permissions | Can't reply or manage inbox from app |
| On-open refresh | No backend | Not real-time; clear refresh state |
| Outlook cards separate from notes | Avoids flooding notes | One extra click to convert to a note |
| Azure DevOps deferred | Keeps MVP small | Some comment mentions may be missed |

## 13. Coding-agent execution instructions

**Mission:** Implement the exact v1 scope above as a native macOS application. Do not add AI, iOS, a web backend, subscription features, or Azure DevOps integration without approval.

**Working method:**
1. Inspect the development machine, Xcode/macOS version and existing repository. State assumptions and blockers before changing code.
2. Create a milestone checklist. Build and test one milestone at a time; do not fabricate build success.
3. Implement domain models and repository protocols before tightly coupling views to persistence.
4. Prototype the rich-text block editor early; demonstrate drag reorder, formatting preservation and undo before expanding features.
5. Use mock Outlook fixtures until credentials and tenant permissions are available. Never ask the user to paste tokens or passwords into source files.
6. Keep auth isolated; use system browser PKCE and secure token storage.
7. Add unit tests for every nontrivial business rule. Run build/tests after each milestone and report failures accurately.
8. Maintain README with setup steps, permissions, environment configuration, architecture and known limitations.
9. Provide screenshots or short screen recordings of key flows when tools permit, plus a manual test checklist.
10. Ask for confirmation only on choices that materially affect data safety or scope; otherwise use defaults in this spec.

**Definition of Done:** Mac app runs locally; notes CRUD + rich blocks + sorting/reorder + priority/dates + Today work reliably offline; Outlook connection and refresh work for an authorized test account; no secrets stored insecurely; tests pass; README explains how to run and export data.

## 14. Open decisions (safe defaults)

1. **App name:** `Smart Notes` placeholder.
2. **Editor:** block editor with rich inline text, not arbitrary visual-line dragging.
3. **Outlook import default:** flagged messages only, with configurable broader filters; this avoids overwhelming the user. A visible Inbox-all filter is available for the user who wants every received email.
4. **Notes created from email:** explicit user action, not automatic creation of editable notes.
5. **Date semantics:** planned and due dates separate; no notification service in MVP.
6. **Font controls:** system font default; limited font presets and size presets, rather than unconstrained font picker initially.
7. **Backup:** user-triggered JSON + Markdown export; optional automatic local backup later.

---

## 15. Suggested next iteration after personal testing (not part of MVP)

- Lightweight resurfacing of forgotten notes, controlled by user settings.
- Global quick-capture shortcut.
- Reminders and local notifications.
- Direct Azure DevOps mentions/work-item integration.
- Additional note attachments and drag-in images.
- Optional iCloud sync if a mobile client is later justified.

**Scope guard:** Ship the smallest version that can replace the user's daily Apple Notes habit before adding any of the above.

## 16. Visual design handoff

Read `Smart_Notes_UX_UI_Design_Spec.md` before implementing SwiftUI views. It defines the approved modern-cartoon visual language, exact navigation, FAB behavior, design tokens, UI states, responsive macOS behavior, and accessibility constraints. Do not add Archive to the sidebar. The UX/UI document is a separate required implementation input.
