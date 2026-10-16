# Smart Notes — UX/UI Design Specification

**Version:** 1.0 · **Platform:** macOS native · **Status:** Implementation handoff  
**Companion:** `Smart_Notes_Technical_Spec.md` v1.1  
**Design direction:** Modern Cartoon Productivity — playful, expressive, calm, and professional.

---

## 1. Product experience

Smart Notes replaces Apple Notes on Mac. It is primarily a fast, pleasant writing environment with two supporting destinations: **Today** (scheduled/due notes) and **Mentions** (Outlook items that may require attention). The interface should feel warm and distinctive, never childish or visually noisy. There is no AI chat, agent dashboard, or project-management layer.

**Design principles**
1. **Writing is primary.** The app must feel effortless during long writing sessions.
2. **One obvious action.** The **New Note** floating button is the most visually prominent action.
3. **Expressive edges, disciplined layout.** Cartoon irregularity belongs to select controls and illustrations, not text baselines, grids, or dense data.
4. **A calm canvas.** Plenty of whitespace, restrained color, highly readable editor.
5. **Discoverable and accessible.** Drag operations always have keyboard/menu equivalents; no meaning conveyed only by color.

## 2. Navigation and information architecture

**Exactly four primary destinations:**
- **Notes** — default; active note collection and editor.
- **Today** — notes planned for today, due today, or overdue.
- **Mentions** — Outlook-backed inbox of imported email cards.
- **Trash** — deleted notes, restore and permanent delete.

**No Archive in MVP.** No separate Tasks, Calendar, Dashboard, AI, Projects or Connectors pages. Settings lives in the app menu and optionally a compact sidebar footer control, not as a fifth main section.

### Desktop window anatomy
- Default three-column structure: **navigation sidebar (approx. 200–230 pt)**, **note list (approx. 260–330 pt)**, **editor (flexible, min approx. 440 pt)**. Values are initial design targets, not rigid constraints.
- macOS title bar and window controls stay native. Respect traffic-light controls and safe-area insets.
- Sidebar collapsible; note list collapsible to give editor room.
- Window minimum width proposed ~820 pt; at narrow widths transition to sidebar + content or list + editor, with back navigation. Never compress the editor until text is unusable.
- Main editor background: warm off-white in light mode; deep warm charcoal in dark mode.

### Notes screen
- Sidebar left, note list center, editor right.
- List header: “Notes”, compact search field, sorting menu.
- Note row: title, 1–2 line preview, relative updated time, optional pin/priority/date indicators. Selected state clearly visible.
- Drag to reorder notes **only when sort mode is Manual**; in other sort modes disable the drag affordance and explain via tooltip.
- New Note floating action is anchored to the **bottom-right of the app content area** (not to a scrolling row). It remains visible in Notes and other primary destinations where creation is appropriate.

### Today screen
- Heading “Today” with localized date.
- Three logical groups: **Overdue**, **Due today**, **Planned today**; do not show the same note twice. Empty groups may be hidden.
- Each item is a compact note card with title, priority if present, date label, and direct open action.
- Notes appear because of explicit planned/due dates, **not AI-generated urgency**.
- A note is not a task by default; avoid misleading completion toggles on note cards. Checklist items are completed in the editor.

### Mentions screen
- Heading “Mentions”; subtitle “From Outlook” and last successful refresh timestamp.
- Toolbar: Connect/Reconnect account, Refresh, filter dropdown (Flagged, All Inbox, configured rules).
- Read-only cards: sender, subject, snippet, received time, source indicator, action **Open in Outlook**, secondary action **Create Note**, dismiss locally.
- **Terminology:** “Mentions” is the product navigation label, not a claim that every email is a true @mention. Display filter explanations prominently. The MVP Outlook connector cannot reliably detect every cross-product @mention.
- Email items are **not** silently converted to editable notes; the user explicitly chooses Create Note.
- Azure DevOps direct integration is **future scope**; do not imply that comments or work-item mentions are available in v1 unless they arrive as filtered Outlook emails.

### Trash screen
- List of deleted notes with deleted timestamp.
- Restore action on each note; permanent delete behind explicit confirmation.
- No Archive section or archive action anywhere in MVP.

## 3. Signature visual language

### Modern cartoon, not children's software
- Mostly crisp typography and straight content alignment.
- Small number of organic shapes, asymmetrical corners and hand-drawn-feeling outlines.
- Subtle dimensionality: soft offset shadow or restrained border; avoid heavy skeuomorphism.
- Irregularity is intentional and repeatable; **do not randomize shape paths at runtime**. Ship a small stable library of vector shapes.
- Avoid excessive decorative stickers, wobbly text, saturated backgrounds, or animation during writing.

### Primary New Note FAB — highest visual priority
- **Position:** bottom-right of the active content region, floating above content with at least 20–24 pt inset from bottom and right safe edges.
- **Size:** approximately 60–68 pt diameter bounding box, generous clickable area (minimum 44×44 pt).
- **Shape:** intentionally imperfect organic blob, not a mathematically perfect circle; mildly asymmetric contour, dark expressive outline (~2–3 pt).
- **Color:** warm yellow accent, near-black plus icon; enough contrast in both themes.
- **Icon:** large centered `+` with rounded strokes. Accessible name “New Note”.
- **Behavior:** click creates note and focuses editor immediately; keyboard shortcut **⌘N** does exactly the same.
- **Hover:** subtle lift/scale (~1.03), shadow change; **pressed:** gentle squash (~0.97) with brief spring. Respect Reduce Motion by removing movement.
- **Focus:** visible keyboard focus ring, no ambiguous hit area.
- **Overlap rule:** provide bottom padding to scrollable content so FAB never obscures last note, last editor line, or important buttons. If text selection/editor is active, preserve keyboard focus on hover; clicking intentionally creates a new note.
- **Important:** The FAB should be the most prominent **action**, not the most distracting element. No pulsing or looping animations.

### Other organic UI accents
- Selected nav background can have a very subtle asymmetrical pill.
- Priority chips and empty-state illustration shapes may be organic.
- Editor text fields, paragraphs, list separators, date picker and data cards should remain regular and aligned.
- Only one strong yellow primary accent per screen wherever possible.

## 4. Design tokens — initial proposal

Tokens are implementation defaults; tune visually after a real macOS prototype. Support light/dark through **semantic** colors, not hard-coded foregrounds in views.

### Color tokens
| Token | Light | Dark | Use |
|---|---|---|---|
| `surface.canvas` | `#F8F5ED` | `#211F1C` | Editor/main canvas |
| `surface.sidebar` | `#F0ECE3` | `#292622` | Sidebar |
| `surface.card` | `#FFFEFA` | `#302C28` | List/cards |
| `text.primary` | `#292929` | `#F5F1E9` | Body and headings |
| `text.secondary` | `#77736C` | `#B5ADA3` | Supporting text |
| `border.subtle` | `#DED8CE` | `#48413A` | Dividers |
| `accent.yellow` | `#F6C65B` | `#F6C65B` | New Note FAB, rare primary highlights |
| `accent.mint` | `#D5E9D3` | `#3A5645` | Soft positive labels |
| `accent.coral` | `#F4B9A8` | `#6A4038` | Attention/overdue accents |
| `focus.ring` | `#755B21` | `#F6D780` | Keyboard focus |

Use contrast-checked text on accent fills. Never use pastel colors alone to communicate priority. High priority = label + icon + color.

### Typography
- Default app/editor family: **SF Pro / system sans** for macOS fidelity and readability.
- Optional editorial display font can be explored **later**; no bundled licensed font is required for MVP.
- Suggested scale: title 26/32 semibold; section 18/24 semibold; row title 14/20 medium; body editor 16/25 regular; secondary 12–13/18.
- Rich editor supports headings H1/H2/H3, bold, italic, underline, strikethrough, links, bullet/numbered lists, checklists, font family presets, and text-size presets as described in technical spec.
- **Do not use cartoon letterforms for long-form notes.**

### Spacing and geometry
- Base spacing scale: 4, 8, 12, 16, 24, 32 pt.
- Card padding 12–16 pt; section gap 20–24 pt.
- Standard corner radii 10–14 pt; expressive shapes are dedicated vector assets, not arbitrary oversized radii.
- Border thickness standard 1 pt; expressive controls 2–3 pt.
- Avoid shadows on every row; reserve subtle depth for FAB and occasional floating surfaces.

## 5. Notes editor UX

### Editor anatomy
- Editable note title, then note body with minimal chrome.
- Metadata strip (priority, planned date, due date, pin) placed unobtrusively above body or in compact inspector; no persistent giant toolbar.
- Formatting toolbar appears on text selection or via compact toolbar button. Essential formatting also available through shortcuts.
- Hovering over a logical block reveals a drag handle at its left edge. On drag, show a clear insertion marker and preserve formatting.
- A **block** means paragraph/heading/list/checklist item, not a visual wrapped line. Explain this in UI help only when necessary.
- Keyboard move-block-up/down action via menu/context menu; avoid stealing standard text navigation shortcuts.
- Autosave silently. No disruptive save banners; optional subtle “Saved” status only where useful.

### Rich text rules
- Enter splits block; Shift+Enter adds soft break; Backspace at start merges where valid.
- Selected text formatting never alters unrelated blocks.
- Checklist checkbox is clickable and keyboard accessible.
- Link styling is distinguishable without relying only on color (e.g. underline on hover/focus).
- Font sizes should be chosen from stable presets initially (e.g. 12, 14, 16, 18, 22, 28 pt), not a free-form typographic control in v1.
- Prevent accidental drag while selecting text: handle is separate from body content.

### Note metadata
- Priority: None / Low / Medium / High; clear text labels.
- Planned date: when user intends to work on note. Due date: actual deadline.
- Pin: places note in pinned group; does not change due date or priority.
- Delete moves note to Trash with undo opportunity and explicit Restore.
- No archive control.

## 6. Key interactions and states

### Primary flows
1. **Create:** FAB or ⌘N → blank note selected → cursor in title/body → type → autosave.
2. **Organize:** pin/priority/date → list metadata updates immediately → Today updates when date applies.
3. **Reorder notes:** switch sort to Manual → drag list row → persistent ordering; otherwise sorting remains deterministic.
4. **Reorder blocks:** hover grip → drag to insertion line → preserve content and inline marks; keyboard alternative.
5. **Delete/restore:** move to Trash → restore from Trash; permanent delete requires confirmation.
6. **Outlook:** Connect → consent or permission error → Refresh → card list → Open in Outlook or Create Note.

### States to design explicitly
- First launch: warm empty state with prominent FAB and brief “Write your first note”.
- Empty Today: “Nothing scheduled for today” with link to Notes, no fabricated recommendations.
- Mentions disconnected: concise explanation and Connect Outlook action.
- Mentions loading: lightweight skeleton rows; no endless spinner.
- Mentions empty: explain active filter and offer switch to All Inbox.
- Offline: notes fully editable; Mentions displays cached data and clear last-sync time.
- Outlook permission denied/expired: specific reconnect guidance, no false success state.
- Empty Trash: simple reassuring state.
- Search no results: helpful zero-state, clear query action.
- Save/persistence failure: non-dismissable recoverable error with retry/export option; never pretend data saved.

## 7. Accessibility and platform behavior

- Full keyboard navigation; ⌘N create, ⌘F search, ⌘B/I/U formatting, ⌘Z undo.
- Native VoiceOver labels for FAB, note rows, priority controls, drag handles, dates, email actions.
- Use accessible descriptions for organic icons; decorative shapes hidden from accessibility tree.
- Provide Move Up / Move Down context-menu actions as alternative to drag-and-drop.
- Respect system light/dark mode, increased contrast, Reduce Motion, text scaling where supported.
- Use standard macOS context menus, date pickers, focus rings and title-bar behavior where practical.
- Avoid forced animations while typing and avoid moving content when hover states appear.
- Maintain at least WCAG AA-equivalent contrast targets for body text and actionable controls.

## 8. Component inventory

**Required reusable components:**
- `OrganicNewNoteButton` (signature FAB)
- `SidebarDestinationRow`
- `NoteListRow`
- `PriorityBadge`
- `DateMetadataChip`
- `NoteEditorToolbar`
- `BlockDragHandle`
- `BlockInsertionIndicator`
- `MentionCard`
- `EmptyState`
- `ConnectionStatus`
- `ConfirmDestructiveAction`

All components use semantic tokens and support hover, active, selected, focused, disabled, loading (where relevant), and error states. Avoid one-off styling within feature screens.

## 9. Screens to implement and review

1. Notes — populated, selected note, editor idle.
2. Notes — editing and selected text formatting toolbar.
3. Notes — dragging a block and note row.
4. Notes — empty first-launch state.
5. Today — populated, overdue, empty.
6. Mentions — disconnected, loading, populated, permission error, empty filter.
7. Trash — populated and empty, restore confirmation where needed.
8. Settings — appearance, editor defaults, Outlook connection, export.
9. Narrow window layout, dark mode, keyboard focus, Reduce Motion.

## 10. Handoff to coding model

- Read **both** specifications before coding.
- Treat this document as authoritative for layout, navigation, interaction design and visual tokens; treat technical spec as authoritative for persistence, security and API integration.
- Do not invent extra navigation destinations, especially **Archive**.
- Implement the FAB as a stable custom SwiftUI `Shape` or vector path; do not use a default perfect Circle for its final silhouette.
- Make the editor functional before polishing decorative elements; never sacrifice text editing reliability for style.
- Provide screenshots for Notes, Today, Mentions, Trash, and dark mode; compare against this spec and iterate.
- If any interaction is technically infeasible in current architecture, document the tradeoff and propose the least disruptive alternative rather than silently removing it.
- Avoid external paid UI libraries and copyrighted font dependencies.

### Design acceptance criteria
- [ ] New Note FAB is visually dominant, organic, bottom-right, keyboard accessible, always clickable.
- [ ] Navigation has exactly Notes, Today, Mentions, Trash; no Archive.
- [ ] App feels modern and playful without compromising long-form writing readability.
- [ ] All note CRUD, formatting, dates, priorities and drag reordering affordances are understandable.
- [ ] Today shows only explicit planned/due notes and avoids duplicate cards.
- [ ] Mentions makes Outlook source and last sync clear, and never implies all messages are @mentions.
- [ ] Light/dark, reduced motion, keyboard navigation and VoiceOver are addressed.
- [ ] FAB does not cover editable text or row controls at minimum window size.

---

**Scope rule:** Make four screens exceptional before adding a fifth. The design goal is an app the user enjoys opening every day, not a generic productivity dashboard.
