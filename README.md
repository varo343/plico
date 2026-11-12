# Plico

_Formerly "Smart Notes". The bundle ID and data location keep the old name so existing notes carry over._

A native, local-first macOS note-taking app (SwiftUI + SwiftData). Specs:
`Smart_Notes_Technical_Spec.md` (architecture, data, security) and
`Smart_Notes_UX_UI_Design_Spec.md` (layout, visuals, interactions).

**Status:** Milestones 0–3 and 5 complete. Outlook (M4) is built and needs your Microsoft app registration to connect. Some interactions still need manual checks; see docs/MILESTONES.md. See [`docs/MILESTONES.md`](docs/MILESTONES.md).

## Download
1. Get `Plico.zip` from the [latest release](https://github.com/varo343/plico/releases/latest) and unzip it.
2. Move `Plico.app` to Applications.
3. The app is not notarized by Apple, so the first time **right-click it ▸ Open ▸ Open**
   (or System Settings ▸ Privacy & Security ▸ Open Anyway).

Requires macOS 14 Sonoma or later. Your notes stay on your Mac; the app has no server and collects no data.

## Requirements (building from source)
- macOS 14 Sonoma or later (developed on macOS 27 / Xcode 27 / Swift 6.4)
- Xcode (full install, not only Command Line Tools)
- No paid Apple Developer account needed for local builds (ad-hoc signing)
- No third-party dependencies

## Build, run, test
```sh
swift test                       # unit + integration tests
scripts/build-app.sh             # → build/Plico.app (release, ad-hoc signed, with icon)
scripts/make-icon.sh             # regenerate Resources/AppIcon.icns from the PlicoLogo view
open build/Plico.app             # real notes store
open -n build/Plico.app --args --sample-data   # demo data, in-memory only
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
  A web address on its own (pasted or dropped) becomes a named link: the title that came with it, else a readable name from the address, replaced by the page's title when `WebLinkTitleFetcher` gets one (no cookies, single-use-looking addresses never loaded).
  Plain text is read as Markdown (`MarkdownImport`: `**bold**`, `*italic*`, `~~strike~~`, `` `code` ``, links, headings, lists, checklists, quotes, `\` escapes, `&amp;` entities); so is RTF/HTML that carries no formatting of its own (code editors, Terminal). Paste and Match Style keeps the symbols as typed.
- **Saving:** autosave writes only title and blocks (`updateContent`). Pin, rank and dates go through `updateMetadata`, so neither can overwrite the other.
- **Rich text storage:** each block stores a versioned JSON payload
  (`{"version":1,"runs":[{"text":"…","marks":["bold"]}]}`) with deterministic encoding.
  Not an opaque `NSAttributedString` archive. Unknown versions are rejected, not guessed.
- **Ordering:** blocks and notes use fractional-index string ranks, so a move rewrites a single row.
- **Dates:** planned and due dates are `LocalDay` (`YYYY-MM-DD`), with no time or timezone, so they stay stable across timezone and DST changes.
- **Block tags:** any block can carry one tag: High, Medium, Low or a custom word (hover a line and click the tag icon, or type `/tag`; click a tag to change it). Stored as `BlockRecord.tagRaw` (schema V2, migrated lightweight from V1), included in search, JSON export and Markdown (`#high`).
- **Sorting rows:** the Sort button under the title (or Format ▸ Sort Rows, ⌥⌘S for severity) sorts each list in the note — a run of consecutive list items or tagged rows; headings and plain text stay put and separate lists. Severity High → Low: High, Medium, Low, custom tags, untagged, completed rows last; Low → High (⇧⌥⌘S) is the mirror, completed rows still last. Completion: Open First or Completed First, otherwise unchanged. Indented rows move with their row and are sorted among themselves; with several rows selected, only those are sorted. "Move Checked Rows Down" (on by default, `AppSettings.movesCheckedRowsDown`) moves a row below its list when checked, back above the completed ones when unchecked. Pure functions in `RowSorting.swift`; one undo step each.
- **Row tools:** ⌥-drag a row's grip to drop a copy (`BlockEditing.duplicate`); right click a row (text, grip or picture) for `RowMenu`, a Plico `SNMenuList` at the pointer: Duplicate (⇧⌘D), Copy Row, Move to Right/Left Column, Delete Row and more. The row shows selected while its menu is open (`NoteEditorModel.menuRowID`).
- **Two columns:** `NoteBlock.column` puts a block in the left (0) or right (1) column. `Note.blocks` stays in reading order (left column, then right) with ranks rising the same way, so block editing works unchanged; Backspace, Move Up/Down, sorting and numbering stop at a column's edge. Drag a block past the right edge, use Format ▸ Move to Right / Left Column (⌃⌘→ / ⌃⌘←) or "/column". `ColumnsLayout` measures each column once (an HStack re-measured every text view per keystroke). A two-column note is up to 1200 pt wide (760 with one column); title and blocks widen together in one animation.
- **Pictures:** `.image` blocks hold a `NoteImage` (the file's bytes) with the block's text as caption. Drop files or images on the note, paste a screenshot, or Format ▸ Insert Image… (⌥⌘I) / "/image". Stored with SwiftData external storage (schema V4; V5 adds the chosen width); big or TIFF pictures are scaled down/re-encoded on import. Drops read files first, then promised files (screenshot thumbnail, browsers), and only then image data, which is often just the drag's preview. Drag the corner to resize; click to open it large. A picture dropped onto a row is attached under its text (`NoteBlock.image` on a text block) and can be dragged to another row or back out.
- **Nested text:** any block can hold longer text under it (e.g. the draft of an email under "write the marketing email"), hidden until the row is expanded. Open it with the chevron at the end of the row, `/nested`, Format ▸ Nested Text (⌥⌘N) or the context menu. Dragging a row by its grip onto the middle of another row tucks it into that row's nested text (near a row's top or bottom edge, a drag still reorders). Each row of nested text has its own grip in the margin: dragged between rows it becomes a block again (`BlockEditing.unnest` reads back the marker, `[tag]` and indented lines), dragged onto another row it moves into that row's nested text. Return adds a line inside it; Backspace in empty nested text closes it. Stored as `BlockRecord.detailData` (schema V3, migrated lightweight from V2), included in search, JSON export and Markdown (a quote under the item). Expanded/collapsed is not saved: notes open collapsed.
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

## Security
- Plico ships with no API keys or secrets. Outlook sign-in is OAuth with PKCE (no client secret);
  each user registers their own Microsoft app and pastes its client ID in Settings.
- Tokens are stored only in the macOS Keychain, never in files, logs or this repository.
- Pasting a web address on its own loads the start of that page, without cookies, to name the link after its title.
  Addresses that look single-use (password resets, sign-in or unsubscribe links, tokens) and local addresses are never loaded.
- Found a vulnerability? Please open a private report via GitHub ▸ Security ▸ Report a vulnerability, not a public issue.

## License
[MIT](LICENSE)
