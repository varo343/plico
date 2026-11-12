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

## Markdown paste & nested text (Oct 27)
- ✅ Pasted Markdown is converted: `**bold**`, `*italic*`, `~~strike~~`, `` `code` ``, `[links](…)`, headings,
  bullet/numbered lists, `- [ ]` checklists, quotes, fenced code; `\*` escapes and `&amp;`-style entities
  become plain characters. Also applied to RTF/HTML without formatting of its own (code editors, Terminal).
  Paste and Match Style (⌥⇧⌘V) keeps the symbols. Unsafe links keep their text only.
- ✅ Nested text under any block, hidden until expanded (chevron at the end of the row, `/nested`, ⌥⌘N,
  context menu). Return adds a line; ↑/↓ move between the block and its nested text; Backspace in empty
  nested text closes it; trash button deletes it (undoable). Bold/italic/links/size work inside it.
  Merging, splitting, multi-block delete, copy/paste keep it. Schema V3 (lightweight from V2, migration test).
- ✅ Drag a row onto the middle of another row: it becomes the last line of that row's nested text (row
  stays collapsed; marker, tag and its own nested text come along; one undo step). The target row
  highlights with "Nest inside"; near a row's top/bottom edge (≤10 pt) the drag still reorders.
- ✅ Each row of nested text has a grip in the margin (on hover): drag it between rows → it becomes a row
  again (kind, checked state, tag, formatting and its indented lines come back); onto another row → it
  moves into that row's nested text. Context menu / VoiceOver: "Move Out as a Row". One undo step each.
  Nesting now indents every line of a dragged row's own nested text, so it reads back intact.
- ✅ ⌘C / ⌘X / Delete enabled for a multi-block selection (were disabled by NSTextView's validation).
- ✅ 305 tests (5 consecutive runs; a caret race found by them fixed — grips no longer redraw the text view)

**Manual checks pending:** drag a row onto another and a nested row back out (highlight, insertion line,
drop, ⌘Z) — synthetic mouse events don't reach
SwiftUI in tests; paste a ChatGPT/Claude answer as plain text; open, edit and hide nested text on a
real note; ⌥⌘N from the block and from inside the nested text.

## Sorting rows (Oct 28)
- ✅ Sort button in the note's metadata strip and Format ▸ Sort Rows by Severity (⌥⌘S) / by Completion.
  Only lists move (runs of list items or tagged rows); headings and plain text stay and separate lists.
  Indented rows travel with their row and are sorted too; a multi-block selection limits the sort. Stable.
- ✅ Move Checked Rows Down (default on, saved in settings, toggle in the Sort menu and Format menu):
  checking moves the row below its siblings; unchecking moves it back above the first completed row.
  Check + move is one undo step. Today's checklist preview follows the new order.
- ✅ Both directions: Severity High → Low (⌥⌘S) / Low → High (⇧⌥⌘S, completed still last); Completion
  Open First / Completed First. Sort menu and Format ▸ Sort Rows submenu.
- ✅ Expanding nested text: it used to slide in from above, across the row's own text, while the rows
  below jumped. Now it fades in under the row and the rows below slide (list-level animation keyed on
  `expandedDetails`); measured frame by frame in a probe.
- ✅ Tag picker hosting test waits for the picker instead of a fixed 200 ms (failed ~2/5 under load).
- ✅ 318 tests (6 consecutive runs)

**Manual checks pending:** expand/collapse nested text (smoothness), click a checkbox in a real list (animation, caret), Sort menu in light and dark.

## Two columns & pictures (Nov 3)
- ✅ Two columns: `NoteBlock.column` (0 left, 1 right). Blocks stay in reading order (left, then right) and
  ranks rise that way (`Note.ordered` renumbers when they don't), so every "insert between neighbours"
  path keeps working. Return continues in the same column; Backspace never joins the columns (an empty
  first line of the right column goes instead); Move Up/Down stays in the column; sorting and numbered
  lists end at a column's edge. An empty left column makes the right one the only one.
- ✅ Making a column: drag a block's grip past the note's right edge ("New column" outline), Format ▸
  Move to Right / Left Column (⌃⌘→ / ⌃⌘←, also for a multi-block selection), or "/column". Dragging onto
  a row of the other column moves it there (a line shows where).
- ✅ Pictures: `.image` blocks (`NoteBlock.image`, the text is the caption). Drag from Finder or another
  app onto the text, between rows, below the note or beside it (starts the right column); paste a
  screenshot or copied image (⌘V; image data that comes with text is ignored); Format ▸ Insert Image…
  (⌥⌘I) or "/image". Large or non-compact pictures (TIFF) are scaled/re-encoded (`NoteImage.importing`).
  Hover shows a delete button; Backspace in an empty caption removes the picture; Backspace after it goes
  to the caption. JSON export keeps pictures (Base64) and columns; Markdown names them.
- ✅ Schema V4 (lightweight from V3): `columnIndex`, `imageData` (external storage), `imageID` (saves skip
  unchanged pictures without reading them back). Migration test from a V3 store.
- ✅ Columns use a custom single-pass `ColumnsLayout`: an HStack measured every text view several times
  and slowed typing in a 150-block note from ~1.3 s to ~3.7 s per 10 keystrokes.
- ✅ Tag picker test retries a missed click (still failed ~1/13 under load). 356 tests, 8 consecutive runs

**Manual checks pending:** drag a block to the right edge / across columns, drop a picture from Finder
and from a browser (file promises from some browsers aren't read), paste a screenshot, light and dark.

## Pictures and column drops, round 2 (Nov 3)
- ✅ Tiny picture: the drop stored the drag's preview (66×58 px TIFF), not the file. Drags from the
  screenshot thumbnail and browsers carry the file as a promise; promises are now received
  (`NSFilePromiseReceiver`, 10 s timeout) and files/promises always win over image data. SwiftUI drops
  prefer a non-TIFF type's file representation. The already stored thumbnail stays as it is.
- ✅ Resize: drag the picture's corner (live "W × H" label); double-click the corner or "Actual Size" in
  its menu resets it. One undo step per drag. Schema V5 (lightweight) adds `imageWidth`.
- ✅ Preview: click a picture to open it over the note (up to 3× its size), Esc / click outside / ✕ to
  close, or open it in the Preview app.
- ✅ Drop zones from the start of a block drag (and of a picture drag from outside): a one-column note
  shows a quiet "New column" zone beside it (over its right edge when the window has no room), lit up
  under the pointer; a two-column note outlines the other column. Rows fade/scale in when inserted
  and glide across when they change column (`matchedGeometryEffect`).
- ✅ 360 tests, 5 consecutive runs

**Manual checks pending:** drag the screenshot thumbnail and a browser image in, resize, preview,
block drag to the new-column zone in a narrow and a wide window.

## Pictures and column drops, round 3 (Nov 3, from a screen recording)
- ✅ Delete button: hover was tracked on the picture only, so moving onto the button "left" the picture
  and hid the button just before the click. Hover now covers the picture and its buttons.
- ✅ Resize stutter: every pointer move re-measured every text view (a scratch TextKit layout each).
  `BlockNSTextView.height(forWidth:)` keeps its answers until the text changes; live resize uses
  cheaper filtering and no animation. Also faster note opening (150 blocks: ~1.2 s → ~0.75 s).
- ✅ Pictures on rows: drag a picture (or its block's grip) onto a row → attached under its text ("Attach
  picture"); the caption joins the row's nested text. Drag it to another row, or out between rows to
  make it an image block again (also "Move Out as an Image Block"). One picture per row; joining two
  rows that both have one is refused. Saved with the row, exported in JSON.
- ✅ Drop zones, consistent: highlights come from the column layout, not from row frames (frames are
  also frozen during a drag: they included the drag offsets, which put the left highlight over the text).
  One column: a rail at the right edge from the start of a drag; past 65% of the width the rows make room
  and the right half shows "Release for a new column". Two columns: the other column is outlined.
- ✅ Same note width with one or two columns (760): the note no longer jumps when a column appears,
  and the right column sits next to the left. `matchedGeometryEffect` removed (it left a ghost copy).
- ✅ 365 tests, 3 consecutive runs. Drag states checked in renders (simulated mouse drags don't reach
  SwiftUI gestures offscreen).

**Manual checks pending:** delete/resize a picture, drag a picture onto a row and back out, drag a row
to the right edge, resize the window with two columns.

## Row tools (Nov 3)
- ✅ ⌥-drag a row's grip: drops a copy (between rows, in the other column, or in the new-column zone);
  the row stays put, a card with a "+" follows the pointer, the cursor is the copy cursor. ⌥ can be
  pressed or released during the drag.
- ✅ Right click on a row (text, grip or picture; ⌃-click too): the row shows selected and a menu offers
  Duplicate (⇧⌘D, also in Format), Copy Row (lossless + plain text), Move to Right/Left Column, Move
  Up/Down, nested text, picture tools (Open, Copy, Actual Size, Move Out, Delete Image) and Delete Row.
  Cut/Copy/Paste appear when text is selected; the standard text menu (spelling, Look Up…) is under "Text".
  Grip and picture use `RowMenuCatcher`, which only takes menu clicks so drags and clicks pass through.
- ✅ Row menu in Plico style (feedback): no NSMenu any more — `SNMenuList` in a floating panel at the
  pointer, icons in tiles like the slash menu, with Plico icon motions (new ones for the row tools) and
  shortcuts shown. The right-clicked row is grey (the menu's hover colour), not yellow. Nested text keeps
  the standard text menu.
- ✅ 373 tests, 3 consecutive runs

**Manual checks pending:** ⌥-drag with the real cursor, right click on text/grip/picture.

## Wider two-column notes (Nov 4)
- ✅ Two columns at 760 pt left ~300 pt each and wrapped every line (feedback). Two-column notes are now
  up to 1200 pt wide (~540 pt per column). Title and blocks widen together in one animation, also while
  a drag previews the new column, so the earlier jump (title first, rows after) doesn't come back.

## Note list selection (Nov 4)
- ✅ Sometimes two notes looked selected (feedback). The selection card was inserted and removed with a
  transition, which the lazy list could leave behind when it reloaded mid-animation; it is now always
  there and only fades (same for the dragged-row card).

## Smoother animations (Nov 5)
Measured in release with the full app (60 notes, one of 150 rows in two columns), then profiled:
- ✅ Every block text view (an NSTextView with a superview) observed the frame changes of *every* view,
  waiting for a clip view to adopt it, so each layout pass cost rows × views. `BlockNSTextView` turns
  that off (`_setWatchingSuperviewClipView:`, with a public fallback in `viewDidMoveToWindow`); guarded
  by `EditorPerformanceTests`.
- ✅ Row frames and the blocks area are no longer SwiftUI state (every layout change re-rendered the whole
  editor and list): `EditorGeometry` / `RowFrames`, each row reporting with `onGeometryChange`, frozen
  during drags.
- ✅ Editor rows and list rows are `Equatable`: a change re-renders only the rows it concerns (the caret
  request and the drag are passed only to their row). Pictures compare by ID, not byte by byte.
- ✅ Per-row AppKit helper views (tooltip and tag anchors, the right-click catcher) exist only while the
  row is hovered or active; the tag picker adds its anchor on demand when opened without hovering.
- ✅ The note card's shadow is drawn by its shape, not recomputed from the whole note on every frame.
- ✅ Rows aren't laid out again for SwiftUI's "how wide could it grow" question (half the measurements
  while typing).
- Results (before → after): open a 20-row note 210 → 125 ms, a 150-row note 1090 → 560 ms, a keystroke in
  the 150-row note 55 → 20 ms, a list show/hide frame 48 → 32 ms (150 rows).
- ✅ 375 tests, 3 consecutive runs

**Still costly:** a width change re-lays out every row's text (window resize, list toggle in narrow
windows); scrolling a 150-row note costs ~9 ms a frame, mostly SwiftUI's own layout.

## Gliding menu highlight (Nov 5)
- ✅ Menus (row menu, sort, note actions, every `SNMenuList`) and the "/" menu have one highlight that
  glides from row to row with a spring (`menuHighlight(on:)` / `menuHighlightRow(_:)`, `SNMotion.glide`),
  following the pointer and ↑/↓, instead of each row lighting up on its own (feedback, from a reference video).
- ✅ Timing measured frame by frame on the reference video: there in ~0.1 s with no bounce (critically
  damped spring, `SNMotion.glide`); it hides on the spot when the pointer leaves the menu and, coming back,
  appears on the row under the pointer instead of gliding from the old one (`SNMotion.highlightFade`).
- ✅ The note list (what the reference was about): one hover highlight glides from note to note with the
  same timing, beneath the selected note's card; hidden while dragging a note and when the pointer leaves.
- ✅ Every list in the left column shares it (`glidingHover()` / `glidingHoverRow(_:)`, Shared/UI/GlidingHover.swift):
  Notes, Today (the hovered card clears so the highlight shows through, across sections), Mentions, Trash
  (its row actions still appear on hover) and the Settings panes.

## Drag selection in a column (Nov 5)
- ✅ Dragging across rows of one column selected both columns (feedback): the tracker matched the left
  column's rows at the same height first. A drag now stays in the column it started in (above or below
  it: that column's first or last row). Shift-click into the other column still selects in reading order.
  Test: `dragInOneColumnSelectsOnlyThatColumn`.

## Named links (Nov 5)
- ✅ A web address pasted or dropped on its own (address bar, "Copy Link", a link dragged from a browser)
  becomes a link named instead of the whole address (feedback): the title that came with it (Safari's
  `public.url-name`, the link text in Chrome/Edge HTML), else a readable name from the address
  ("github.com › pull/12", `LinkNaming.readableName`), then the page's title once it arrives
  (`WebLinkTitleFetcher`: og:title or `<title>`). Paste and Match Style keeps the whole address.
- ✅ Loading the title: no cookies, nothing cached, only the head of the page (256 KB at most), and only if
  the page answers itself (a redirect to another site, e.g. a sign-in, or a "Sign in"/"Just a moment" title
  keeps the readable name). Not for addresses that look single-use (reset, verify, unsubscribe, tokens or
  codes in the query) nor for localhost, IP addresses and `.local`. Tests and in-memory stores never go online.
- ✅ The title replaces the name only while the link's text is still the name; the caret stays where it was,
  and undoing the paste removes the link. Tests: `LinkNamingTests`, `LinkPasteTests`.

## Mentions from a folder (Nov 6)
- ✅ Without Graph access (the tenant needs admin consent): mentions can arrive as JSON files in
  `~/Library/Application Support/SmartNotes/Mentions Inbox` (`MentionsFolder`). Plico imports a file as soon
  as it lands (folder watch), on launch and on activation, then deletes it; unreadable files stay. Same
  dedupe and dismissed state as synced mail (account `outlook-web`); shown in Mentions without an account,
  "From Outlook on the web · checked …". Graph-style names (`receivedDateTime`, `bodyPreview`,
  `from.emailAddress`) are read too, for a Power Automate flow later.
- ✅ Filled by an agent reading Outlook on the web in Chrome (filter "Mentions me", Focused and Other):
  `/menzioni` (`.claude/commands/menzioni.md`). Read only. Outlook on the web hides message IDs from the
  agent, so "Open in Outlook" opens the mailbox, not the message. Tests: `MentionsFolderTests`.
- New Outlook for Mac doesn't answer AppleScript (0 accounts, 0 messages), so reading it locally isn't possible.

## Spec acceptance items already covered by M0 tests
- Formatting persists across relaunch (on-disk container reopen test)
- Duplicate: new IDs, original unaffected
- Trash → Restore keeps prior state; Empty Trash removes notes and their blocks
- Search finds title + body, case/diacritic-insensitive, excludes Trash
- Date-only values stable across timezone/DST
- Second Outlook fetch does not duplicate; removing cached Outlook data never deletes notes
- 500-block note round-trips (performance guard only, not a benchmark)
