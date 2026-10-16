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

## Milestone 1 — Notes foundation ⬜
Sidebar / list / editor shell, CRUD, autosave (debounce + flush on focus loss and quit), Trash, search,
sort modes + manual drag reorder, pinning, OrganicNewNoteButton FAB + ⌘N, empty states, custom sidebar styling.
Editor in M1 is a plain-text placeholder; the rich block editor is M2.

## Milestone 2 — Block editor ⬜ (highest technical risk)
Spike first: NSTextView-per-block vs. a single NSTextView. Show drag reorder, formatting preservation and undo
working before building on top.

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
