# Prototype validation

Updated October 20, 2026. This summary omits private paths, account information,
conversation content and live session identifiers.

## Completed checks

- Native app/helper compile on the development Mac.
- Offline functional checks: exact Unicode/newline answers, request/session
  isolation, explicit draft acceptance and submission, helper receipts,
  inactive restoration, deletion, bounded context and completed response streams.
- Synthetic identity checks: rejected issuer/audience/nonce/subject changes,
  RSA signature verification and changed-signature rejection.
- Focused regressions: captured deletion target, history size limit/recovery,
  complete sign-in cancellation, model/effort snapshots, supported efforts,
  scope confirmation and connection-change guards.
- User-operated live checks: Maie's own ChatGPT authorization and completed
  inference; Claude Desktop question/discussion/suggestion/final answer with
  exact Claude receipt; next-question continuity, context inspection and quit
  interruption; proposal acceptance and clarification routing.
- Latest UI checks: simplified Suggest answer, short explanation and small-step
  teaching, Stop without a raw cancellation error, High effort after restart,
  retained draft and corrected automatic scrolling on a new message.
- User-operated deletion removed the evaluation session and the app remained
  empty after Quit/reopen, as explicitly confirmed.
- A clean allowlisted source artifact built successfully with its included
  dependencies and passed offline app/helper/process checks. Fresh-project setup
  passed synthetic preservation/conflict tests and CLI dry-run/install/repeat
  checks in temporary directories, without touching real settings.
- The two adapted SKILL.md bodies and the project's refine skill are included
  in source and compiled at build time. A before/after check confirmed unchanged discussion instructions. Skill
  checks cover missing/invalid inputs and literal Unicode/quote/control text,
  including interpolation-like content remaining plain text. The functional
  checks compare compiled bodies with the reviewed files and actual request.

The hook core also has earlier local tests covering terminal and IDE submission,
cancellation, concurrent routing, timeout, sleep/wake, parent interruption and a
competing denying hook. They are historical evidence for the shared primitives;
they do not establish every combination for the native prototype.

The final source review identified and corrected stale token-refresh installation
after sign-out and duplicate setup when an existing Maie command has arguments.
Focused offline regressions now cover deletion followed by sign-out while refresh
is suspended, late refresh rejection, newer shared refresh preservation, and
parameterized helper conflicts without settings changes. Related task ownership
checks ensure a deleted session's old cancellation cannot clear a replacement
request or disable Stop. These use synthetic credentials and transport only.

## Question-set update

The question-set, new-question presentation and simplified Connection changes
follow the initial source release review. New offline checks cover one to four
questions, an omitted/default or strict-boolean multiSelect, exact complete
answer sets, duplicate-key rejection, multi-select/custom text, isolated page
drafts/discussions, late proposal routing to its original page, final-review
submission, whole-set cancellation and inactive restoration. Process checks
exercise simultaneous four-question calls, preserved original inputs, decisions
larger than the previous 32 KiB packet limit, receipts and partial-set rejection.

The preceding user-operated cross-project Desktop evaluation verified a real
question from another repository, discussion, clarification, proposal acceptance
and displayed Claude receipt. That evaluation preceded the question-set update.
A subsequent user-operated Desktop call containing four questions passed on
October 17: Question 1 of 4 and Question 2 of 4 opened at their question/options;
a discussion on the first page stayed separate from the empty second page;
multi-select, a custom-text answer and the complete four-answer review worked.
Claude's displayed received JSON matched all four reviewed answers exactly.
The user also inspected and approved the simplified Connection layout. No new
sign-in or historical host matrix was repeated. Detailed notification timing,
keyboard focus during concurrent work and reduced-motion behavior remain live
validation limits. No new independent source/security review of this update is
claimed.

## Pending or limited

- Fresh-account/clean-Mac OAuth, refresh expiry, revocation failures and optional
  paid API-key inference have not been fully evaluated live.
- Full 30-minute host waits and every host/plugin combination are unverified.
- Cloud/SSH, Windows/Linux and parent/child session
  discovery are unsupported.
- Model discussion replies support native inline Markdown. Tables and block
  formatting can still appear literally. Provider response quality can vary.

Offline checks do not call OpenAI or Claude, inspect real credentials or operate
the GUI. Live tests consume the connected account's normal usage.

## Quiet menu-bar arrival update

Focused synthetic checks cover pending-set counts across sessions, preserved
selection/draft, notice dismissal, mismatched session targets, stale heartbeat
targets, cancellation and inactive restoration. The offline build and app/helper
checks passed again on October 18. The restricted sandbox could not create the
temporary synthetic RSA key; the complete build passed outside that sandbox,
without real credentials or model calls. Hidden-panel visibility, menu interaction, keyboard focus during
concurrent typing and reduced motion still require user-operated validation.

## October 18 user-operated follow-up and refinement

The owner confirmed quiet arrival, correct opening, concurrent sessions with
preserved draft, cancellation removing a pending menu entry while retaining
history, explanation/teaching behavior, explicit proposal acceptance, Claude
receipt and the pending dot clearing. Notice dismissal, expiry and reduced
motion were not independently confirmed in this follow-up.

The subsequent window/session refinement requires new live checks: normal
window stacking, native close/minimize/zoom, Dock switching, session contrast
and inline Markdown appearance. Synthetic formatting checks cover preserved
paragraphs, emphasis, inert links and literal script-like text. No live model
calls or real credentials are used by these checks.

The complete build and offline app/helper checks passed after this refinement.

The final unified-header correction uses the original native macOS window
buttons. An isolated synthetic app rendered the real view at 480x780 and
720x900; both active-window images were inspected. It checked visible/enabled
native controls and minimize/restore without starting the bridge or accessing
real credentials. The complete build passed. Manual pointer interaction and
owner evaluation of this final native header remain pending.

The rounded-outline follow-up was inspected in the synthetic preview; the full
offline build passed again.

## October 18 isolated UI validation and fixes

An isolated harness compiled the real app sources with a temporary
MAIE_DATA_DIR, a throwaway preferences suite, in-memory synthetic credentials,
a stubbed network and scripted model replies. The real hook helper received a
synthetic AskUserQuestion payload. No real model, credentials, Keychain entries
or Claude settings were used. It drove native AppKit events and passed 28 checks
in dark and light appearance: visible/enabled native controls, quiet arrival,
menu opening, status dot, first-send confirmation, Use in draft, a second arrival
not stealing the editor, cancellation, minimize/restore, close and Cmd-W hiding
with the request live, zoom, and a helper receipt equal to the exact draft.

Fixes from this pass: Discuss/Collapse no longer override a size the person
chose; the pending menu, header and Sessions list share one session label (new
offline regression); the send arrow, Connection button and Ask Maie field have
accessible labels. The complete offline build passed afterwards.

Not covered: the bundled app itself (the harness reuses its sources), real
pointer interaction, reduced motion, live notice dismissal timing, live Claude
Code and live model calls. The proposal box was intermittently clipped behind
the composer after appearing; the fix below resolved it.

## October 18 evening fixes and checks

Offline regressions in `sh prototype/build.sh` now cover: zoom clamped to the
1200x1600 maximum; one shared session label; choosing an option keeping typed
text aside with explicit restore; and the refine skill (Suggest answer with
text in the draft tightens that draft and returns a proposal, an empty draft
behaves as before). Discuss growing a compact window only when it is smaller,
and Collapse undoing only that growth, were checked in the local UI harness,
not in the offline build. The harness reproduced the clipped proposal box 25 of
25 times before the `ConversationEnd` change and 0 of 25 after it. Windows under 640 points tighten the composer, draft and
action bar. GitHub Actions runs the same offline build on every push and
pull request; the first two runs passed.

Not tested live: the compact layout at the 400x520 minimum, the scroll fix in
the bundled app, the refine skill with a real model, reduced motion and
notice dismissal timing.

## October 20 fail-safe wording

Incident class: Maie was not running, the helper denied the AskUserQuestion
call and the turn stopped. The human never saw the question and later typed a
generic "continue", which Claude read as approval of its own "(Recommended)"
option. The three deny reasons (not running; cancelled, disconnected or
expired; unsupported or invalid request) now share one fail-safe text: the
human did not see or answer the question, no option including a recommended
one is chosen, a later generic reply such as "continue", "ok" or "go on" is not
an answer or an authorization, and Claude must ask again with AskUserQuestion
once Maie is open or in chat with an explicit answer naming the option. The
decision, exit code and `"continue": false` are unchanged.

`BridgeChecks.py` now asserts, for every deny (timeout, wrong session, service
restart, cancellation, partial set, app offline), the key phrases above, no
`updatedInput` or `answers` key anywhere, `permissionDecision` equal to deny
and `stopReason` equal to `permissionDecisionReason`. A new case sends a
zero-question payload and a non-JSON body: both return the same deny on one
stdout line with exit code 0 and create no bridge packet. The complete offline
build passed.

The same build adds the question notifier check: one banner per new live set,
no repeat, removal when the set disappears or the app quits, and no banner
while Maie is active and showing. A throwaway probe bundle confirmed that
UNUserNotificationCenter works in an unsigned swiftc bundle and aborts outside
one, so the adapter lives only in the app. The authorization prompt, banner
delivery and click-to-open are not yet confirmed live; the discussion
guidance's plain-Greek rule is not covered by an offline check.

## October 20 pass-through when Maie is closed

The "Maie is not running" deny is gone. Without a recent service lease the
helper now returns an empty JSON object, so Claude Code falls through to its
own AskUserQuestion prompt in the chat. Denies remain for cancellation, expiry,
disconnection (heartbeat loss, quit or restart) and unsupported or invalid
requests, with the fail-safe wording above unchanged. `BridgeChecks.py` now
asserts that the app-offline case returns `{}` on one stdout line with exit
code 0, no stderr and no new bridge packet; the deny assertions cover the
remaining cases. The banner now requests alert and sound authorization and
plays the default notification sound, which can be switched off in System
Settings > Notifications > Maie. The complete offline build passed.

Not yet confirmed live: that Claude Code shows its own prompt when Maie is
closed, and that the banner plays a sound and opens the set when clicked.
