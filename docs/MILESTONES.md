# Milestone checklist

Status legend: ✅ done and verified · 🟡 partial · ⬜ not started

## Milestone 0 — Bootstrap ✅
- ✅ SwiftPM project (library + app + tests), Swift 6 language mode, macOS 14 minimum
- ✅ Folder structure per spec §5
- ✅ Domain models: Note, NoteBlock, RichText (versioned payload), LocalDay, Priority, BlockType, ExternalItem, IntegrationState, AppSettings
- ✅ Repository protocols + SwiftData implementations (notes, external items, integration state)
- ✅ Versioned schema (V1) + migration plan scaffold
- ✅ Settings store (UserDefaults JSON, tolerant decoding)
- ✅ Fractional-index ranks, search-text/preview derivation
- ✅ DI composition root, launch-argument store selection, startup failure screen
- ✅ Design tokens (light/dark), minimal shell: 4 destinations, Settings in footer/app menu
- ✅ Sample fixtures (`--sample-data`)
- ✅ `.app` bundling script with ad-hoc signing
- ✅ Tests: 46 passing (`swift test`)
- ✅ App launched and screenshotted (dark mode, sample data)

## Milestone 1 — Notes foundation ✅ (automated) · 🟡 manual checks pending
- ✅ Custom warm sidebar: exactly Notes / Today / Mentions / Trash (⌘1–⌘4), Settings in footer + app menu
- ✅ Note list: title (fallback to first line), 2-line preview, relative time, pin, priority and date chips (wrap, never truncate)
- ✅ Pinned group above others; sort modes Manual / Updated / Created / Title / Priority / Due date (persisted)
- ✅ Manual drag reorder (only in Manual sort, not while searching; explained in header + tooltip)
- ✅ Search (⌘F) over title + body, case/diacritic-insensitive, zero-state with Clear
- ✅ Create (FAB / ⌘N → note at top, caret in body), Duplicate (⌘D), Pin (⇧⌘P), context menu
- ✅ Move to Trash (⌘⌫ / Delete) with Undo banner; Trash view with Restore, confirmed permanent delete and Empty Trash
- ✅ Autosave: 400 ms debounce + flush on note switch, destination change, ⌘S, app deactivate/quit, window close
- ✅ Content and metadata saved through separate paths (an autosave can't undo a pin/reorder)
- ✅ Save failure: non-dismissable banner with Retry; changes stay in memory, never shown as saved
- ✅ Editor core (pulled forward from M2, needed for lossless editing): one TextKit 1 view per block,
  lossless rich text round-trip, Enter split, Backspace merge, Shift+Return soft break,
  arrow keys across blocks, checklist toggle, all block types rendered, plain-text paste
- ✅ OrganicNewNoteButton: fixed blob path, ink outline, hover/press with Reduce Motion, focus ring, VoiceOver label
- ✅ Single-window app (prevents two editors on the same note)
- ✅ 107 tests passing, 5 consecutive runs, including 10 tests that drive the real editor with key events
- ✅ Screenshots checked in light and dark mode

**Manual checks pending.** These can't be automated here: no Accessibility permission, no computer-use tools.
- [ ] Drag a note row in Manual sort, quit, relaunch: order kept
- [ ] ⌘F focuses Smart Notes search (not the system Find bar)
- [ ] ⌘⌫ while typing deletes to line start; ⌘⌫ with the list focused moves the note to Trash
- [ ] FAB hover lift / press squash; Tab reaches FAB and shows its focus ring
- [ ] Narrow window (~820 pt): columns collapse sensibly, FAB doesn't cover text
- [ ] VoiceOver reads note rows, FAB, checkboxes

**Known M1 limitations (planned for M2):** no inline formatting commands or toolbar yet (⌘B/I/U/K),
no block type changes, indent, block drag or Move Up/Down, undo is per block only, rich paste is plain text.

## Milestone 2 — Block editor ✅ (automated) · 🟡 manual checks pending
- ✅ Inline formatting: Bold ⌘B, Italic ⌘I, Underline ⌘U, Strikethrough ⇧⌘X, Inline Code (Format menu)
  - with a selection: reformats it (undoable), selection kept; with only a caret: applies to the next typing
- ✅ Links ⌘K: sheet with validation (http/https/mailto only; "example.com" → https), edit/remove,
  insert address when nothing is selected; clicks open only safe schemes
- ✅ Font family presets (System/Serif/Rounded/Mono) and size presets (12–28 pt): selection, or whole block
- ✅ Formatting bar: appears on selection or via "Aa"; fixed height, so text never moves
- ✅ Block types: Format menu (⌥⌘0–3 body/headings, ⇧⌘7 bullets, ⇧⌘8 numbers, ⇧⌘L checklist, Quote) + bar menu
- ✅ Indent: Tab / Shift+Tab on list items, ⌘] / ⌘[ in the menu
- ✅ Move Block Up/Down: ⌃⌘↑ / ⌃⌘↓, text context menu, handle context menu, VoiceOver actions
- ✅ Block drag: grip on hover (in the margin, no layout shift), insertion line, private drag type
- ✅ Note-level undo/redo (⌘Z / ⇧⌘Z) across typing (coalesced), formatting, Enter/Backspace, moves,
  type changes, indent, checkbox, paste; caret restored; undo results are autosaved
- ✅ Paste: rich RTF/HTML → supported marks, links and list blocks; multiple paragraphs → multiple blocks;
  HTML sanitized (allowlist) before import; unsafe links dropped, text kept; Paste and Match Style = plain
- ✅ Copy inside Smart Notes is lossless (private RichText type); other apps get RTF + plain text
- ✅ Ranks renormalized automatically when keys grow long; duplicate ranks repaired on move
- ✅ Multi-block text selection: drag across blocks (or Shift-click, or ⌘A twice); copy/cut keep block
  kinds inside Plico (plain text with list markers for other apps); Delete, typing, Return and paste
  replace it; ⌘B/I/U, font presets and block type apply to every selected block; ⌘Z undoes in one step
- ✅ 150 tests passing (3 consecutive runs); hosted tests drive the real text views for formatting,
  typing after toggling a mark, Tab, undo/redo across blocks, menu validation, copy/paste, multi-paragraph paste, moves

**Manual checks pending:**
- [ ] Drag a block by its grip: insertion line follows the pointer; drop lands in the right place; ⌘Z undoes it
- [ ] Edit menu Undo/Redo enable/disable correctly and act on the note (not just the focused block)
- [ ] ⌘B/I/U and ⌘K from the menu bar act on the focused block
- [ ] Paste from Safari, Chrome, Pages and Word: formatting maps sensibly, no text lost
- [ ] Right-click in text shows Move Block Up/Down
- [ ] Drag-select from a paragraph into a checklist with the real mouse, also past the window edge (autoscroll)

**Known limitations:**
- The title field has its own undo history (the standard text field one), separate from the note body.
- Multi-block drag (moving several selected blocks at once) is not supported (phase 2 in the spec).
- Pasted headings become body text with bold; heading levels aren't inferred from pasted font sizes.

## Milestone 3 — Priority, dates, Today ✅ (automated) · 🟡 manual checks pending
- ✅ Metadata strip under the title: Priority (None/Low/Medium/High), Planned date, Due date, Pin
  - date popover: calendar plus Today / Tomorrow / Next Week / Clear, with a one-line meaning for each date
  - saved through the metadata path (no content autosave conflict); doesn't change "updated" time
- ✅ Dates stored as local calendar days (`LocalDay`): stable across timezone and DST changes
- ✅ Today screen: heading with localized date; sections Overdue → Due today → Planned today
  - each note appears once (a deadline wins over a plan); trashed notes excluded; empty sections hidden
  - sorting: overdue by oldest deadline, then priority; others by priority, then title
  - cards: title, priority, date chips; click opens the note in the editor column (Today stays selected)
  - read-only checklist preview, "n of m done"; completed items hidden unless "Show completed" is on
  - empty state "Nothing scheduled for today" with Go to Notes; nothing suggested or inferred
- ✅ Day rollover: refreshes at midnight, on timezone change and when the app becomes active
- ✅ No automatic priorities or deadlines: new notes have none (tested)
- ✅ No schema change: Today reads checklist items from notes, so existing stores open unchanged
- ✅ 163 tests passing; Today and the strip rendered and checked in light and dark mode

**Manual checks pending:**
- [ ] Date popover: pick a date, Today/Tomorrow/Next Week/Clear; the list chips and Today update immediately
- [ ] Leave the app open past midnight (or change the timezone): Today moves "due today" notes to Overdue
- [ ] Keyboard only: Tab reaches priority, dates and pin; popovers work with the keyboard

**Interpretation to confirm:** the spec's "completed checklist items can be hidden via toggle" is
implemented as a read-only checklist preview on Today cards, with completed items hidden by default.
Cards have no completion controls, per the UX spec.

**Known limitations:** metadata changes are not part of the editor's ⌘Z history (they are explicit,
single-click actions and easy to reverse in the strip).

## Milestone 4 — Outlook ✅ built and tested with fakes · ⏳ needs your Microsoft app registration
- ✅ Sign-in: OAuth 2.0 authorization code + PKCE (RFC 7636 vector tested) in the system browser
  (`ASWebAuthenticationSession`); `state` checked; no client secret; tokens only in the Keychain
  (this device only, after first unlock), refreshed automatically
- ✅ Scopes: `offline_access User.Read Mail.Read` (read-only; nothing is ever sent, deleted, moved or marked read)
- ✅ "Mentions of me" (default, your request): `GET /beta/me/mailFolders/inbox/messages?$filter=mentionsPreview/isMentioned eq true`.
  **Graph beta only**: Microsoft documents `mentionsPreview` as beta ("not supported in production").
  Stable fallbacks: Flagged and All inbox (v1.0).
- ✅ Graph client: immutable IDs, paging, 429 with Retry-After, 5xx exponential backoff, 401/403/offline mapping
- ✅ Sync: dedupe on (provider, account, message ID), local dismiss/seen kept, items that stop matching are
  removed when the list is complete, refresh on launch, on app activation and on demand; offline keeps saved emails
- ✅ Mentions UI: status line ("From … · updated …"), reconnect/retry banners, email cards, filter + refresh,
  detail with Create Note (subject, sender, link back to Outlook, preview quote), Open in Outlook, Dismiss
- ✅ Settings ▸ Outlook: connection, what to show, client ID / tenant, redirect URI with Copy, setup steps
- ✅ Sample emails while not configured (in memory only, never stored)
- ✅ Disconnect: removes tokens; optionally the saved emails; notes are never touched. Delete All also disconnects.
- ✅ 23 new tests (OAuth, Graph client, sync flow with fake browser + network)

**To finish (you):** create the app registration (Settings ▸ Outlook shows the 5 steps), paste the client ID,
press Connect. Real sign-in and real mailbox data have **not** been tested yet: they need your account.

## Milestone 5 — Polish, export, recovery ✅ (automated) · 🟡 manual checks pending
**UI redesign** (against the UX spec):
- ✅ Window: unified toolbar without a title; each column's warm surface runs up under the title bar
- ✅ Sidebar: app mark (fixed organic shape, ink outline) + wordmark; organic selection pill
- ✅ Note list: custom rows instead of a system table. Selected card with outline; one quiet
  metadata line, with color only where attention is needed (High, Overdue); pinned/notes section labels;
  ↑/↓ to move, Return to edit, Delete to trash; drag to reorder (Manual sort) with insertion line
- ✅ Editor: formatting moved into a floating pill (on selection, or via "Aa"); the editor no longer has
  an empty top bar; quiet metadata row with "Aa" and a note-actions menu (Pin, Duplicate, Trash)
- ✅ Illustrated empty states (tinted organic blob + ink outline): first note, no matches, Today, Trash, Mentions
- ✅ Trash: custom rows, titles wrap, Restore / delete permanently
- ✅ Dark mode: new `outline` token, so cartoon outlines stay visible on dark surfaces
- ✅ Narrow windows: below 880 pt the sidebar collapses automatically and comes back when wider
  (a manual collapse is respected); relaxed column minimums so nothing is clipped at 820 pt

**Features:**
- ✅ Settings window: Appearance (System/Light/Dark), editor default font and size with preview,
  Data (Export, Show in Finder, Delete All)
- ✅ Export (File ▸ Export All Notes… ⇧⌘E): dated folder with notes.json (lossless) + one Markdown
  file per note (with front matter), Trash in a subfolder; never overwrites an earlier export
- ✅ Delete all local data (confirmed): notes incl. Trash, cached Outlook data, sync state, settings
- ✅ Recovery: save-failure banner offers "Copy as Text" (Markdown) as well as Retry
- ✅ Settings writes never clobber the list's saved sort mode (tested)

**Bugs fixed:**
- ✅ Blocks could overlap after the editor changed width. The text was laid out at a different width than
  its frame, because measuring resized the live text container. Measurement now uses a scratch copy.
  A regression test in the real three-column layout fails on the old code and passes on the fix.

- ✅ 172 tests passing (2 consecutive runs)

**Manual checks pending:**
- [ ] Settings ▸ Appearance switches immediately; editor font/size changes apply to open notes
- [ ] Export: choose a folder, open notes.json and a few .md files
- [ ] Delete All asks for confirmation, then leaves an empty app
- [ ] Note list: ↑/↓/Return/Delete with keyboard; drag a note in Manual sort
- [ ] Resize the window from wide to 820 pt and back: sidebar hides and returns
- [ ] VoiceOver pass over list rows, editor metadata row, formatting pill

## Design iteration 2 (your feedback, Oct 17) ✅ automated · 🟡 manual checks pending
- ✅ Sidebar removed. Above "Notes" there is an icon-only section switcher (Notes, Today, Mentions, Trash)
  plus Settings. Labels and shortcuts appear on hover (⌘1–⌘4, ⌘,).
- ✅ Hover states on every control: shared icon and capsule button styles, hover labels, Today cards,
  Trash actions, checkboxes, banners, metadata row
- ✅ Product dropdowns replace system menus (sort, note actions, priority, block type, font, size) and the
  date popovers. A floating panel with ink outline and cartoon shadow, keyboard-navigable (↑/↓, ↩, esc).
  **Concentric radii:** panel 14 − padding 5 = items 9; switcher 12 − 3 = 9; capsule highlights inside
  the capsule formatting bar. Context menus and the Settings window stay native (per spec).
- ✅ Badges unified (`SNBadge`): tinted capsule + ink outline + small hard "sticker" shadow, opaque colors
  in both themes (new `accentSun` token); same component in list, editor and Today
- ✅ Slash commands: "/" at the start of a block or after a space opens a filterable menu
  (/text /h1 /h2 /h3 /checkbox /bullet /numbered /quote, with aliases such as /todo, /list, /elenco).
  ↑/↓ + ↩ or Tab to apply, esc to close; typing "/checkbox " (with a space) applies directly.
  URLs and "1/2" never trigger it. One undo step.
- ✅ Formatting bar gained one-click Checklist / Bulleted / Numbered buttons
- ✅ Fixed: lists and editor showed an empty band at the bottom (scroll insets); content now reaches the edge
- ✅ 183 tests (2 consecutive runs), including 6 hosted tests that type slash commands

**Manual checks pending:** open each dropdown with mouse and keyboard; type "/" in a note and pick with
↑/↓/↩; hover every icon in the switcher; check the date calendar panel.

## Design iteration 3 (your feedback, Oct 17) ✅ automated · 🟡 manual checks pending
- ✅ Section switcher: hovering an icon morphs it into its name; Settings is the fifth section
- ✅ Cartoon style limited to the primary button (New Note). Menus, tooltips, the formatting bar, badges,
  selections and empty-state shapes use a normal, rounder style (hairline border, soft shadow)
- ✅ **Fixed: dropdowns opened in the wrong place.** Positions came from SwiftUI's `.global` space, which is
  per hosting view; they are now taken from the control's real AppKit view (`AnchorBox`). Regression test.
- ✅ New Planned/Due date picker (`DatePickerPanel`): quick choices with day hints, Monday-first month grid
  (follows locale), today dot, selected pill, keyboard (arrows/↩/esc), concentric radii (12 − 4 = 8)
- ✅ Settings is a section: categories in the list column, panel in the card; ⌘, opens it; the separate
  Settings window is gone; settings menus use the product dropdowns
- ✅ Linear-style layout: hidden title bar, switcher next to the traffic lights, the note in a rounded card
  with an 8 pt margin, header moved up; list column resizable (drag its edge, remembered) and hideable
  (⌃⌘S or the button in the card)
- ✅ New Note focus ring only for keyboard focus (it appeared after a click)
- ✅ 188 tests (2 consecutive runs)

**Manual checks pending:** open the Priority, sort, ⋯ and date menus: they should appear right under their
button; hover the switcher icons; drag the list edge; ⌃⌘S; ⌘,.

## Design iteration 4 (your feedback, Oct 17) ✅ automated · 🟡 manual checks pending
- ✅ "Aa" and "⋯" moved to a top bar in the note card; the formatting bar appears there (top center)
- ✅ Responsive formatting bar: full version when it fits, otherwise a compact one with a "more" menu
  (lists, strikethrough, code, font, size); block-type names truncate with an ellipsis, never wrap
- ✅ Motion everywhere (all off with Reduce Motion): spring press on buttons, rows, cards and tiles;
  sliding indicator in the section switcher and size selector; menus pop in; menu icons jiggle on hover;
  checkbox bounce; crossfade between sections and notes; animated list reordering; undo banner slides in
- ✅ Settings redesigned with its own components: theme preview tiles, font "Aa" tiles, segmented size
  selector, note-like preview, rows with tinted organic icons, coral danger zone
- ✅ Tags: no icons, words carry the meaning ("Planned today" vs "Due today"); hand-drawn irregular
  background (fixed shapes per tone, never random) with a slight tilt
- ✅ Hover "⋯" on note rows: Pin/Unpin, Duplicate, Move to Trash (stays visible while its menu is open)
- ✅ 188 tests (2 consecutive runs)

**Manual checks pending:** hover a note row and use its ⋯; select text and check the top formatting bar;
narrow the window to see the compact bar; click around to feel the press/slide animations.

## Design iteration 5 (your feedback, Oct 17) ✅ automated · 🟡 manual checks pending
- ✅ Section switcher replaces the section titles ("Notes", "Today"…); section controls on its right
  (sort for Notes, Empty for Trash)
- ✅ Hiding/showing the list is a smooth spring: the column slides, the note card grows
- ✅ Meaning-based icon motions (`IconMotion`): trash swings, pin drops, sun/gear spin, envelope lifts,
  calendar flips, flags wave, sort arrows turn, lists slide, links wiggle, text styles pulse, warnings
  shake. Played on hover of the whole control (menus, formatting bar, metadata row, toolbar), and on
  selection in the switcher. All off with Reduce Motion.
- ✅ Hand-drawn hover shapes (wobbly rounded rects / capsules) and stronger irregular tag backgrounds
- ✅ **Fixed: tooltips could be covered or clipped** by other views. They now live in their own
  click-through floating panels, centered on the control (placement tests added)
- ✅ 191 tests (2 consecutive runs)

**Manual checks pending:** hover icons in menus, formatting bar and metadata row; toggle the list
(⌃⌘S or the card button); hover anything with a tooltip near the window edges.

## Block drag rework (Oct 17)
- ✅ Blocks reorder with an in-window drag (no system drag-and-drop): grab the grip, the block lifts and
  follows the pointer, an insertion line shows the landing spot, release moves it (⌘Z undoes it)
- ✅ Landing logic (`DropResolver`) unit-tested; the move itself tested at model level
- ✅ Fixed: the invisible position helpers behind menus/tooltips intercepted clicks (`PassthroughView`)
- ⚠️ Synthetic mouse events don't reach SwiftUI in the test runner, so the real drag needs a manual check
- ⚠️ Note-list reordering still uses system drag-and-drop (unverified by hand)

## Plico (Oct 17)
- ✅ Renamed to **Plico** everywhere visible (window, menus, Dock, exports, texts). Bundle ID and data
  location unchanged on purpose, so existing notes and settings carry over.
- ✅ Logo: envelope ("plico") with a note on the yellow cartoon blob. Drawn once as `PlicoLogo`;
  the macOS icon (`Resources/AppIcon.icns`, all sizes) is generated from it by `scripts/make-icon.sh`.
  Also shown on first launch.
- ✅ Roomier hover shapes in the note's metadata row
- ✅ Fixed: the drag grip barely ever appeared (SwiftUI hover doesn't fire over the AppKit text view).
  The text now reports hover itself, and the grip is faintly visible on the block being edited.

## Spec acceptance items already covered by M0 tests
- Formatting persists across relaunch (on-disk container reopen test)
- Duplicate: new IDs, original unaffected
- Trash → Restore keeps prior state; Empty Trash removes notes and their blocks
- Search finds title + body, case/diacritic-insensitive, excludes Trash
- Date-only values stable across timezone/DST
- Second Outlook fetch does not duplicate; removing cached Outlook data never deletes notes
- 500-block note round-trips (performance guard only, not a benchmark)
