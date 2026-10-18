# Architecture

Maie is a local macOS app with a small command hook helper. It uses SwiftUI,
AppKit, Foundation, Security, CryptoKit and Network; Python is used for setup
and offline checks. There are no third-party runtime packages.

## Request flow

1. Claude Code invokes the helper before AskUserQuestion.
2. The helper validates one to four questions and creates a per-request
   packet in Maie's private application-support directory.
3. The app shows the question and maintains a separate discussion and draft.
4. A human may explicitly request an OpenAI explanation or answer suggestion.
5. Only Send to Claude returns the complete set of exact human-approved answers
   to that helper. Previous / Next retains answers locally. Multi-question calls
   require a final review; a single question keeps its direct explicit send.

The helper owns its stdin/stdout and final decision. Session ID, request ID,
tool-use ID, app run ID and a continuous-clock deadline bind the response.
Heartbeat loss, cancellation, quit or expiry produces no approved answer.
Pages in a question set share one bridge request, tool-use identity, lifetime
and receipt. Each page has its own stable local ID, draft, composer, proposal and
discussion. The helper validates that answer keys match every original question
exactly; duplicate question texts are rejected because Claude keys answers by
question text. Multi-select labels are joined with commas; the editable final
text remains authoritative. Omitted multiSelect means false; numeric booleans
are rejected. Unknown original tool-input fields are preserved.
An app restart retains history but makes all pages of old pending sets inactive.
Optional group fields allow existing single-question history to decode unchanged.
The helper waits up to 30 minutes; the configured host timeout is 1,830 seconds.
Another host hook can still block a returned answer.

## Source map

- prototype/PrototypeApp.swift: app lifecycle, panel and menu bar.
- prototype/PrototypeView.swift: discussion, draft and explicit controls.
- prototype/SessionModel.swift: per-session state, context, model snapshots,
  proposal/clarification routing and final submission.
- prototype/OpenAIConnection.swift: this app's OAuth registration, Keychain-backed
  connection, model catalog, reasoning effort and Responses API transport.
- skills/wait-what/SKILL.md and skills/teach/SKILL.md: reviewed explanation and
  teaching guidance. prototype/generate-guidance.py compiles their bodies to
  literal Swift strings during build; metadata is not sent to the model.
- prototype/DiscussionGuidance.swift: discussion routing around those skill bodies.
- prototype/HookTransport.swift and HookMain.swift: local helper transport.
- prototype/LocalStorage.swift: bounded persistence and Keychain storage.
- spike/HookCore.swift: shared request validation and lifetime primitives,
  retained at its original path because the build imports it directly.
- prototype/setup-hook.py: fresh project-local setup, previewed before --apply.

## Model requests

The first explicit request per Claude session per app run confirms the connection
and included data. Later explicit sends use fresh snapshots. A different account,
billing route, session or newly included transcript source requires confirmation.
Changing settings or receiving a question never starts inference by itself.
Model and effort changes invalidate an open confirmation; sending checks the
snapshot again and checks the connection revision around token refresh.
Connection changes cancel pending refreshes; late results must still match the
active revision and account before saving credentials. Sign-out invalidates this
revision before revocation begins. Cleanup is bound to each refresh/model task,
so an old cancelled operation cannot clear its replacement.

Discussion uses concise explanations and optional small teaching steps.
Suggest answer uses structured proposal/clarification output. A proposal never
changes the draft until Use in draft. A clarification stays in discussion.
The most recent draft takes precedence over older discussion preferences.

Requests contain the current question/options, draft, up to 24 recent Maie
messages, three earlier explicitly submitted answers, and optional Claude context.
Context reads at most the last 256 KiB of the indicated transcript, selecting
matching canonical user/assistant text with a total 12,000-character excerpt.
There is no repository ingestion, adaptive memory or browser/tool execution.

## State and limits

Keychain stores tokens and optional API keys. Application-support JSON stores
account labels, host ID, discussions and drafts; it is not encrypted by Maie.
Directory/file permissions are 0700/0600. History reads/writes share an
8,000,000-byte bound and preserve the previous saved file if a write is too large.
Old oversized files need manual recovery. Model text is bounded to 256 KiB;
each answer sent to Claude is bounded to 8 KiB. Helper decision packets have a
512 KiB bound to allow JSON escaping of four answers and their question keys;
the original input retains its 64 KiB bound.

The API-key route requires explicit activation and separate billing. Errors
never switch routes automatically. Quota totals are not imported; Manage usage
opens the provider's settings. Future providers, plugins and MCP are outside
this prototype's implementation.

## Presentation

Incoming questions publish a small notice. An existing waiting editor, model
response or another active session keeps its selection; Show explicitly opens
the new set. Automatically selected questions and page navigation scroll to the
question, while discussion changes scroll to the conversation end. Arrivals do
not order the panel forward or activate the app. A menu-bar dot marks live waiting
sets, and the menu lists each set separately. Opening a menu target rechecks its
session/request identity and liveness; notice dismissal leaves pending sets
available. Sending, cancellation and expiry remove sets from this list. Motion
respects the system reduced-motion preference. Notices and review state are
presentation state, not persisted approvals or automatic model requests.

Maie uses a normal-level native window with integrated close/minimize/zoom controls
and Dock switching. Closing hides the window without stopping pending requests;
Quit stops the bridge. Model discussion text uses native inline Markdown styling,
preserving whitespace and removing link actions. No web view or remote content
loading is involved. Stored text, proposals and drafts are unchanged.
