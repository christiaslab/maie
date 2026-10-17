# Prototype validation

Updated October 17, 2026. This summary omits private paths, account information,
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
- The two adapted SKILL.md bodies are included in source and compiled at build
  time. A before/after check confirmed unchanged discussion instructions. Skill
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

## Pending or limited

- Fresh-account/clean-Mac OAuth, refresh expiry, revocation failures and optional
  paid API-key inference have not been fully evaluated live.
- Full 30-minute host waits and every host/plugin combination are unverified.
- Cloud/SSH, multiple-choice questions, Windows/Linux and parent/child session
  discovery are unsupported.
- The UI displays model replies as plain text; Markdown tables and formatting
  can appear literally. Provider behavior and model response quality can vary.

Offline checks do not call OpenAI or Claude, inspect real credentials or operate
the GUI. Live tests consume the connected account's normal usage.
