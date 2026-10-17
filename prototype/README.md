# Maie user guide

## Build and open

From the source directory:

```sh
sh prototype/build.sh
sh prototype/run.sh
```

The build uses the installed Swift compiler, macOS SDK and Python 3. It compiles
app/helper and runs offline checks with synthetic data and temporary storage.
No third-party packages, model requests or real credentials are needed for checks.
Output is `prototype/.build/Maie Prototype.app` and `.build/maie-hook`.
The run script builds only if the app is missing. After rebuilding, choose the
menu bar leaf → **Quit Maie**, then reopen.

The window moves, resizes, follows system appearance and remembers placement.
The minus button hides it. Hiding does not cancel requests or pause deadlines.
**⌘J** focuses discussion. Return in Your answer inserts a newline; final
submission has no default keyboard shortcut.

## Connection and model

Use **Continue with ChatGPT** in Connection and finish authorization in the system
browser. Maie uses its own registration and Keychain entries, never another
app's private tokens. Choose an account-available model and use **Connection check → Check connection**.
The test sends only the disclosed verification prompt; success requires a
completed response. A catalog entry alone does not establish inference access.
Eligibility, credits and limits depend on the account. **Manage usage** opens
ChatGPT settings. Maie does not display a numeric remaining quota.

The model/thinking-time menu is above Ask Maie and also in Connection. Supported effort
choices are explicit for known model IDs; unknown models keep Model default.
The chosen value is sent as reasoning.effort. The selected model restores only
if it is still in the connected account's catalog; effort is saved per model.
Changing model/effort invalidates an open confirmation.

Saved accounts have separate registrations. Tokens and the optional API key use
Keychain service `local.maie.prototype.openai`. A Keychain permission prompt can
appear after rebuilding this development app. Enter your Mac password only in
the system dialog. Sign out attempts remote revocation, then clears local tokens;
unconfirmed revocation is reported. Registrations remain available for re-login.

The optional API-key controls require explicit activation and separate API
billing. Errors never switch to API billing. Restart returns to the ChatGPT
route and reloads its account's catalog. Remove saved API key is available in
Connection. Never paste OAuth tokens into the API-key field.

## Claude Code setup

After a completed connection test, keep Maie open. From the source directory:

```sh
python3 prototype/setup-hook.py --project /absolute/path/to/your-project
python3 prototype/setup-hook.py --project /absolute/path/to/your-project --apply
```

The first command previews only; the second installs one synchronous
AskUserQuestion handler in that project's `.claude/settings.local.json`.
Unrelated settings/hooks are preserved. Repeating setup is idempotent. Invalid,
linked or conflicting settings stop setup without overwriting them. Another
Maie installation needs manual review to avoid duplicate helpers. Moving the
source/build requires reviewing and replacing its old absolute helper path.
Start a fresh local Claude Code session after setup.

To disable Maie, remove only its matching helper entry from the project's
`.claude/settings.local.json`; leave unrelated hooks intact. Start a fresh session.

The helper waits up to 30 minutes with a continuous-clock deadline. Host timeout
is 1,830 seconds and onFailure is block. Host interruptions can happen earlier.
Missing app, heartbeat loss, quit/restart, cancellation and expiry return no
approved answer. Another hook can still deny the tool call. Maie handles one to
four questions per call, each with two to four options.
Multiple selections are available when the question requests them. Your answer
also accepts custom text, including an answer outside the listed options.
A missing multiSelect flag uses single selection; a supplied flag must be a
JSON boolean.

## Discussion and answer

Ask a question in your preferred language. Maie starts concise, re-explains
unfamiliar points with examples, and teaches one concept/example/question at a
time when asked. It cannot browse, run commands or access project files.
Restored conversations open at the end. New questions and question-page changes
open at the question/options; sent messages and model responses follow the end
of the discussion. Manual scrolling remains available. A small new-question
notice offers Show when another session or editor is in use. The panel can
appear without taking keyboard focus from the current app; reduced-motion
preferences are respected.

The first model action per Claude session per app run shows a confirmation of
connection/data. **View everything sent to OpenAI** expands the exact text.
After confirmation, the arrow, Return in Ask Maie and **Suggest answer** send
directly on your explicit action. Changing account/billing/session or including a
new transcript source requires confirmation. Removing extra context does not.
Approval stays in memory and resets on quit/deletion. Typing, changing settings
and receiving a Claude question never send by themselves.

**Suggest answer** works from a draft or the discussion. The current draft takes
precedence over earlier preferences. A usable proposal appears once with
**Use in draft / Dismiss**. If human intent is missing, a clarification stays in
discussion. Only Use in draft changes the draft; only **Send to Claude** returns
its exact contents to the originating question. Inspect the actual Claude result
when verifying delivery; a helper receipt alone cannot prove another hook allowed it.

For a question set, Question 1 of 4 and Previous / Next navigate one page at a
time. Each page retains its own discussion, draft and proposal. Next never sends
an answer to Claude. The final Review answers page displays the entire set with
Edit links. Send to Claude becomes available there only when every answer is
nonempty and within its size limit. Cancel cancels the complete pending set;
partial answer sets are never returned to Claude.

Each Claude session retains its history. Every question has its own
draft/composer/proposal/status. Project names label sessions; Details holds full
identifiers and paths. Incoming questions do not steal a waiting/sending editor.
Restored questions are inactive and cannot be submitted again.

## Context and storage

**Include Claude history** starts off per session. It reads at most the last
256 KiB of the hook-indicated transcript and selects matching canonical user/
assistant text, excluding tools, thinking and other sessions. The excerpt has at
most 12 messages and 12,000 characters. View shows provenance and unavailable
states. Transcript writes can lag; the current hook question is authoritative.

Requests include the current question/options, draft, optional excerpt, up to
24 recent Maie messages and three earlier explicitly submitted answers. There is
no full-repository ingestion, clipboard access, adaptive memory or chat import.
OpenAI requests use store=false, which does not guarantee zero provider retention.

App data is in `~/Library/Application Support/Maie/`: sessions.json contains
history/drafts/context, accounts.json contains non-token account labels,
host.json contains an opaque host ID, and bridge/ contains temporary packets.
Tokens/API keys are in Keychain. Directory/file permissions are 0700/0600;
conversation JSON is not encrypted by Maie. Disk encryption/backups follow the Mac.
Window/model/effort preferences use macOS preferences.

History has an 8,000,000-byte read/write bound. If a save is too large, the previous
file remains and a warning reports unsaved edits. Shorten drafts or delete old
sessions while Maie is open, then verify the warning clears. Old oversized files
require recovery outside the app; unreadable history is preserved and blocks startup.

**Sessions → Delete this session…** deletes Maie's saved discussion/drafts/context
and cancels pending questions. It does not delete Claude transcripts, remote
provider data or external backups. Confirmation is bound to the selected session.

`MAIE_DATA_DIR` is an absolute-path override for isolated checks; app/helper must
use the same value. Normal launch does not set it.

## Limits and credits

This source preview has no Developer ID/notarized installer, multi-provider
routing, Cloud/SSH support, personal learning memory or
automatic parent/child discovery. Plain-text model replies can show literal
Markdown. See [validation](../docs/VALIDATION.md) and [security](../SECURITY.md).

Discussion guidance adapts Matt Pocock's wait-what/teach skills. Sources and the
upstream MIT notice are in [Third-party notices](../THIRD-PARTY-NOTICES.md).
The two adapted [SKILL.md sources](../skills/README.md) are included in the repo
and compiled into the app at build time. Editing them requires a rebuild.
Maie's own code is [MIT licensed](../LICENSE).
