<img src="assets/maie.svg" width="64" height="64" alt="Maie icon">

# Maie

A small macOS companion for thinking through questions from Claude Code.
Discuss the choices, ask for an explanation, and send your own answer back.

Maie keeps the conversation and final answer separate. **Suggest answer** offers
wording based on your discussion and draft; **Use in draft** accepts it.
Only **Send to Claude** submits the final answer.

This is an early source prototype for local use. It is not a signed, notarized
app distribution. See [validation and limits](docs/VALIDATION.md).

## Get started

Requires macOS 13+, the Swift compiler/macOS SDK, Python 3, and a local Claude
Code installation with AskUserQuestion hooks and onFailure=block support
(validated with Claude Code 2.1.295 or later).

```sh
sh prototype/build.sh
sh prototype/run.sh
```

1. Open **Connection**, choose **Continue with ChatGPT**, then complete sign-in.
2. Choose an available model and effort, then use **Test connection**. Model
   access depends on your account; usage is shared with your ChatGPT plan.
3. Keep Maie open and preview setup for your Claude Code project:

   ```sh
   python3 prototype/setup-hook.py --project /absolute/path/to/your-project
   ```

4. Apply that project-local hook, then start a fresh local Claude Code session:

   ```sh
   python3 prototype/setup-hook.py --project /absolute/path/to/your-project --apply
   ```

Setup preserves unrelated hooks/settings and does not change global settings.
The helper path is absolute; rerun setup after reviewing the old hook if you move
Maie. The app must remain open while a question is waiting.

## Everyday use

- Ask Maie a question in your preferred language. Replies start concise and can
  explain a point or teach one small step when asked.
- The first send per session/app run confirms the connection and included data.
  Later messages and suggestions send directly on your action.
- Model and effort are above the message field. **Include Claude history** adds
  a bounded excerpt from that session; it is off initially.
- Edit **Your answer**, optionally use **Suggest answer**, then **Send to Claude**.
  Old questions remain inactive after a restart; ask Claude for a new question.
- **Sessions** holds separate discussions and lets you delete local history.

ChatGPT sign-in uses Maie's own registration. An optional OpenAI API key requires
explicit activation and separate billing; there is no automatic billing fallback.
Tokens are in Keychain. Discussions and drafts are local JSON, not encrypted by
Maie. Explicit model requests send the selected context to OpenAI.

See the [user guide](prototype/README.md), [architecture](docs/ARCHITECTURE.md),
and [security notes](SECURITY.md).

## Credits and license

[MIT](LICENSE), copyright 2026 Panagiotis Christias.

Maie's explanation and teaching guidance adapts Matt Pocock's
[wait-what](https://github.com/mattpocock/skills/blob/main/skills/productivity/wait-what/SKILL.md)
and [teach](https://github.com/mattpocock/skills/blob/main/skills/productivity/teach/SKILL.md)
from [Skills For Real Engineers](https://github.com/mattpocock/skills).
The adaptation is scoped to short conversations and human-reviewed drafts.
The app's reviewed sources are [skills/wait-what/SKILL.md](skills/wait-what/SKILL.md)
and [skills/teach/SKILL.md](skills/teach/SKILL.md); the build compiles their bodies
into the app. See [how the skills are used](skills/README.md).
The upstream attribution and MIT notice are in [Third-party notices](THIRD-PARTY-NOTICES.md).
