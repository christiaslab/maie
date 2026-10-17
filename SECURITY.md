# Security

Maie is an early local macOS prototype. The current source preview is the
supported version. Review changes before building or enabling its hook.

## Data and trust boundaries

- OAuth belongs to Maie's own registration. The callback listens on IPv4 loopback
  only and validates state, PKCE and nonce. Identity uses the issuer's RS256 JWKS
  and checks issuer, audience, subject and expiry.
- Connection changes invalidate pending refreshes. A late result cannot install
  credentials after sign-out or replace a newer connection.
- Tokens and optional API keys are in macOS Keychain. No other app's credentials
  are read. Requests use the fixed OpenAI HTTPS endpoints.
- Project text is sent only after an explicit model action. The initial
  confirmation shows connection and data scope. New scope requires confirmation.
  Model/effort are visible; API billing never activates as a fallback.
- Questions, transcripts and model replies are untrusted text. Maie offers no
  model tools, command execution or active web rendering.
- The two reviewed skills are compiled from fixed repo paths during build.
  Their bodies are escaped as literal strings, with no runtime skill execution
  or loading of external agent configuration.
- The helper binds decisions to the originating session/request, validates the
  original tool input and rechecks lifetime before returning an approved answer.
  Cancellation, transport loss and expiry do not synthesize an answer.
- Local JSON uses a private directory and restricted files, bounded reads and
  atomic replacement. Restored pending requests are inactive.

## Practical limits

This is a development build, without an App Sandbox entitlement, Developer ID
distribution signing or notarization. Build it from reviewed source; this release
does not provide a supported downloadable application installer.

Maie trusts the logged-in macOS user and their project settings. Malware running
as that user, a compromised OS, malicious changes to the installed helper, and
external backup retention are outside its protection boundary.

Conversation JSON is not encrypted by Maie. Context, questions and drafts can
contain sensitive material; inspect what is included before sending. OpenAI
requests set store=false, which is not a promise of zero provider-side retention.
Deleting a session removes Maie's local record, not remote data or backups.

ChatGPT eligibility and limits depend on the account. Optional API-key billing
is separate. Remote revocation can fail; the app reports an unconfirmed result
and points to provider settings. Old oversized local history requires manual
recovery rather than silent truncation.

## Reporting a vulnerability

Do not include credentials, real conversations or exploit details in a public
issue. Use the repository's private vulnerability reporting if it is enabled;
otherwise ask the maintainer for a private reporting channel without disclosing
the vulnerability publicly.

## Validation scope

Offline checks exercise identity claim rejection and synthetic RSA verification,
session isolation, stale-snapshot rejection, exact answers, incomplete streams,
storage limits, cancellation and setup preservation. Local live evaluations also
covered ChatGPT inference and the Claude question/answer loop. See
docs/VALIDATION.md for the distinction between checked and untested paths.
These checks are not a comprehensive security audit.
