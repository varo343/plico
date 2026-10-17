# Smart Notes

A native, local-first macOS note-taking app (SwiftUI + SwiftData). Specs:
`Smart_Notes_Technical_Spec.md` (architecture, data, security) and
`Smart_Notes_UX_UI_Design_Spec.md` (layout, visuals, interactions).

**Status:** Milestones 0–3 and 5 complete. Outlook (M4) is built and needs your Microsoft app registration to connect. Some interactions still need manual checks; see docs/MILESTONES.md. See [`docs/MILESTONES.md`](docs/MILESTONES.md).

## Requirements
- macOS 14 Sonoma or later (developed on macOS 27 / Xcode 27 / Swift 6.4)
- Xcode (full install, not only Command Line Tools)
- No paid Apple Developer account needed for local builds (ad-hoc signing)
- No third-party dependencies

## Build, run, test
```sh
swift test                       # unit + integration tests
scripts/build-app.sh             # → build/Smart Notes.app (release, ad-hoc signed)
open "build/Smart Notes.app"     # real notes store
open -n "build/Smart Notes.app" --args --sample-data   # demo data, in-memory only
```
You can also open `Package.swift` in Xcode and run the `SmartNotes` scheme.

Launch arguments:
| Argument | Effect |
|---|---|
| *(none)* | On-disk store at `~/Library/Application Support/SmartNotes/SmartNotes.store` |
| `--sample-data` | In-memory store seeded with fixtures; never touches real notes |
| `--in-memory` | Empty in-memory store |

## Project layout
```
Package.swift
Sources/
  SmartNotesApp/App/        @main entry point (thin)
  SmartNotesKit/
    App/                    composition root (AppDependencies), root navigation
    Features/Notes/         list, Trash, editor (NotesModel, NoteEditorModel, per-block NSTextView)
    Features/Today/         TodayModel, TodayView (Overdue / Due today / Planned today)
    Features/Settings/      SettingsModel, SettingsView, DataExporter
    Features/Outlook/       (not built; M4 skipped)
    Domain/Models/          Note, NoteBlock, RichText, LocalDay, ExternalItem, settings
    Domain/Services/        Rank, NoteText, NoteSorter/ManualOrdering, BlockEditing, EditHistory,
                            TodayRules, LinkValidator
    Domain/Repositories/    repository protocols
    Data/Persistence/       SwiftData schema V1, migration plan, repository impls
    Data/Outlook, Security/ (M4: Graph client, OAuth PKCE, Keychain)
    Shared/UI/              design tokens, shared components
    Shared/Utilities/       logging, sample fixtures
Tests/SmartNotesKitTests/   Unit/ and Integration/ (Swift Testing)
scripts/build-app.sh        builds the .app bundle
```
The spec's layout is kept, with one difference: code lives in a `SmartNotesKit`
library plus a thin executable target so business rules can be unit-tested.
SwiftPM was chosen over a hand-written `.xcodeproj` because the machine has no
project generator, and adding one (xcodegen/tuist) would be an extra dependency.

## Architecture notes
- **Data flow:** View → model (`NotesModel` / `NoteEditorModel`) → repository protocol → SwiftData. Views never touch SwiftData directly.
- **Editor:** one TextKit 1 `NSTextView` per block. Inline marks live in custom attributes inside the text view and convert losslessly to and from `RichText`. Structural edits (Enter, Backspace) are pure functions in `BlockEditing`.
- **Slash commands:** `SlashTrigger` and `SlashCommand` (domain) detect "/query" at the caret. The model holds the menu state, and the text view routes ↑/↓/↩/esc to it while the menu is open.
- **Floating UI:** dropdowns, date panels and the slash menu are child `NSPanel`s (`FloatingPanelController`), so they are never clipped by columns.
- **Undo:** one note-level history in `NoteEditorModel` (`EditHistory`). The block text views have their own undo turned off and forward ⌘Z to the model.
- **Paste:** `PasteConverter` maps RTF/HTML to supported marks and blocks. HTML first goes through `HTMLSanitizer`, an allowlist, so importing it can't load remote resources.
- **Saving:** autosave writes only title and blocks (`updateContent`). Pin, rank and dates go through `updateMetadata`, so neither can overwrite the other.
- **Rich text storage:** each block stores a versioned JSON payload
  (`{"version":1,"runs":[{"text":"…","marks":["bold"]}]}`) with deterministic encoding.
  Not an opaque `NSAttributedString` archive. Unknown versions are rejected, not guessed.
- **Ordering:** blocks and notes use fractional-index string ranks, so a move rewrites a single row.
- **Dates:** planned and due dates are `LocalDay` (`YYYY-MM-DD`), with no time or timezone, so they stay stable across timezone and DST changes.
- **Outlook items** are separate `ExternalItem` records, deduplicated on `(provider, accountId, externalId)`. Re-syncing never resets local dismissed/seen state.
- **Settings** are a JSON blob in UserDefaults. Unknown values fall back field by field.
- **Logging** uses `os.Logger`. Note contents, email data and tokens are never logged.

## Backup and data
- **Export:** File ▸ Export All Notes… (⇧⌘E), or Settings ▸ Data. It writes `notes.json` (a complete backup) and Markdown files.
- **Delete everything:** Settings ▸ Data ▸ Delete All…, after a confirmation.

## Outlook / Microsoft sign-in
1. Create an app registration in Microsoft Entra (Settings ▸ Outlook lists the steps): platform
   "Public client/native", redirect URI `smartnotes://auth`, delegated permissions `User.Read`, `Mail.Read`, `offline_access`.
2. Paste the Application (client) ID in Settings ▸ Outlook and press Connect.
- Read-only. Tokens live only in the Keychain. No client secret.
- "Mentions of me" uses the Microsoft Graph **beta** `mentionsPreview` filter. "Flagged" and "All inbox" use v1.0.
- Refreshes on launch, when the app becomes active, and on demand (no background push).
- Work accounts: check your company's policy; your organization may need to approve the app. Until a Microsoft Entra app registration exists,
Mentions will run on mock fixtures. Tokens will live in the Keychain only.
Never put credentials or tokens in source files.

## Known limitations
- `deltaLink` is stored in SwiftData for now. M4 will decide whether it moves to the Keychain (the spec treats it as sensitive).
- No real-time Outlook updates by design (no backend).
