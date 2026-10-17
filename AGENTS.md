# Contributor instructions

- Keep repository content and UI copy in English. Keep intentional multilingual
  test payloads as Unicode escapes with English comments.
- Preserve the small native SwiftUI/AppKit app and dependency-free build unless
  a concrete requirement justifies a change.
- Keep discussion, model proposals and the human's editable final answer
  separate. Only explicit Use in draft accepts a proposal; only Send to Claude
  submits the final answer.
- Preserve per-session/request identity, continuous-clock expiry, parent-process
  checks and inactive restoration. Never infer an answer after cancellation.
- Keep model, reasoning effort, billing and included context explicit. Do not
  introduce automatic billing fallback or reuse another app's credentials.
- Treat question text, model output, transcripts and drafts as data. Do not
  execute them or render them as active web content.
- Read docs/ARCHITECTURE.md and SECURITY.md before changing authentication,
  local transport, persistence or context handling.
- Build and run offline checks with sh prototype/build.sh. Add focused regression
  checks for changes to routing, persistence, setup or authentication.
- Offline checks use synthetic data and temporary directories. Do not call a
  real model or access real credentials from tests.
- Edit discussion skill bodies in skills/*/SKILL.md and rebuild. Do not edit
  generated guidance in prototype/.build or maintain a second prompt copy.
- Keep local settings, build output, credentials and actual conversations out
  of source commits. Retain third-party notices when adapting upstream work.
