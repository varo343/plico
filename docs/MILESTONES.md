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

## Milestone 2 — Block editor ⬜ (highest technical risk)
Approach is settled: one NSTextView per block, already working in M1.
Remaining: formatting commands and toolbar, links (⌘K), block type changes, Tab indent,
block drag with insertion indicator, Move Up/Down, note-level undo/redo across blocks, rich paste mapping.

## Milestone 3 — Priority, dates, Today ⬜
## Milestone 4 — Outlook (mock fixtures first) ⬜
## Milestone 5 — Polish, accessibility, export ⬜

## Spec acceptance items already covered by M0 tests
- Formatting persists across relaunch (on-disk container reopen test)
- Duplicate: new IDs, original unaffected
- Trash → Restore keeps prior state; Empty Trash removes notes and their blocks
- Search finds title + body, case/diacritic-insensitive, excludes Trash
- Date-only values stable across timezone/DST
- Second Outlook fetch does not duplicate; removing cached Outlook data never deletes notes
- 500-block note round-trips (performance guard only, not a benchmark)
