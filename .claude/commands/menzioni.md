---
description: Read the emails that @mention me in Outlook on the web and hand them to Plico's Mentions
---

Read the emails where someone @mentioned me in Outlook on the web, in my Chrome
(Claude in Chrome), and hand them to Plico through its mentions folder. Read only:
never open, reply to, move, flag, delete or mark anything in Outlook.

1. Load the Claude in Chrome tools, call `tabs_context_mcp`, open a new tab on
   `https://outlook.office.com/mail/` (I'm already signed in; if a sign-in page
   shows, stop and tell me: never type a password).
2. Inbox ▸ Focused: open the filter menu (the lines icon above the list) and pick
   **Mentions me**. Read the rows with `javascript_tool`:
   `document.querySelectorAll('[role="option"]')`: sender name (row text), sender
   address and full date (the `title` attributes, e.g. "Fri 6/27/2025 2:28 PM",
   local time Europe/Rome), subject, preview (`aria-label` / row text).
   Then the **Other** tab: switching tabs clears the filter, so pick Mentions me again.
   Scroll if `aria-setsize` is larger than the rows shown.
3. Write one file to `~/Library/Application Support/SmartNotes/Mentions Inbox/`,
   first as `.outlook-web-run.tmp`, check it is valid JSON, then rename it to
   `outlook-web-<yyyyMMdd-HHmm>.json` (Plico watches the folder, imports and deletes it):

   ```json
   {"source": "outlook-web", "checkedAt": "<now, ISO 8601 with offset>",
    "messages": [{"subject": "…", "from": {"name": "…", "address": "…"},
                  "receivedAt": "<ISO 8601 with offset>", "preview": "…",
                  "webLink": "https://outlook.office.com/mail/"}]}
   ```

   Write every mention found, even ones sent before: Plico skips duplicates and
   keeps the ones I dismissed hidden. Format and fields: `MentionsFolder.swift`.
4. Close the tab and tell me in Italian how many mentions there are and which are new.
