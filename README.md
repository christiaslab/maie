<img src="assets/maie.svg" width="64" height="64" alt="Maie icon">

# Maie

A small macOS companion for thinking through questions from Claude Code.
Discuss the choices, ask for an explanation, and send your own answer back.

The name Maie draws on Socratic maieutics: helping someone bring their own
thinking into words through questions and dialogue. You work through the
choices, and the final answer remains yours.

Maie keeps the discussion and your final answer separate. **Suggest answer**
proposes wording, **Use in draft** accepts it, and only **Send to Claude**
submits. A set of up to four questions appears one at a time, each with its own
discussion and draft, and you review the whole set before sending.

This is an early source prototype for local use. It is not a signed, notarized
app distribution. See [validation and limits](docs/VALIDATION.md).

## Get started

Requires macOS 13+, the Swift compiler and macOS SDK, Python 3, and a local
Claude Code installation that supports AskUserQuestion hooks with
onFailure=block.

```sh
sh prototype/build.sh
sh prototype/run.sh
```

After building, you can also open `prototype/.build/Maie Prototype.app` from
Finder.

1. Open **Connection**, choose **Continue with ChatGPT**, then complete sign-in.
2. Choose a model and thinking time, then use **Connection check → Check
   connection**. Model access depends on your account, and usage counts
   against your ChatGPT plan.
3. Keep Maie open and preview setup for your Claude Code project:

   ```sh
   python3 prototype/setup-hook.py --project /absolute/path/to/your-project
   ```

4. Apply that project-local hook, then start a fresh local Claude Code session:

   ```sh
   python3 prototype/setup-hook.py --project /absolute/path/to/your-project --apply
   ```

Setup keeps unrelated hooks and settings and never changes global settings.
The helper path is absolute, so rerun setup if you move Maie. Keep the app open
while a question is waiting.

## Everyday use

- Ask Maie a question in your preferred language. Replies start concise and can
  explain a point or teach one small step when asked.
- The first send in each session and app run asks you to confirm the
  connection and included data. Later sends go directly on your action.
- Model and thinking time are above the message field. **Include Claude history**
  adds a bounded excerpt from that session; it is off initially.
- Edit **Your answer**, optionally use **Suggest answer**, then **Send to Claude**.
  In a question set, **Previous / Next** keeps each answer locally and the last
  page opens **Review answers** before the single submission. Pick several
  options when allowed, or type a custom answer.
- After a restart, old questions stay inactive; ask Claude to ask again.
- New questions appear with a small notice. If you are busy elsewhere, **Show**
  opens the question when you are ready. A hidden Maie stays hidden: the
  menu-bar leaf shows a dot while questions are pending, and its menu lists them.
- Maie also posts one macOS notification per new question set when it is not in
  front. The first run asks for permission (System Settings > Notifications);
  it is a banner only, without sound, and clicking it opens that question.
- **Sessions** holds separate discussions and lets you delete local history.

ChatGPT sign-in uses Maie's own registration. An optional OpenAI API key needs
explicit activation and is billed separately; there is no automatic billing
fallback. Tokens are stored in Keychain. Discussions and drafts are local JSON
files that Maie does not encrypt. Only your explicit requests send the selected
context to OpenAI.

See the [user guide](prototype/README.md), [architecture](docs/ARCHITECTURE.md),
and [security notes](SECURITY.md).

## Credits and license

[MIT](LICENSE), copyright 2026 Panagiotis Christias.

The explanation and teaching guidance adapts Matt Pocock's
[wait-what](https://github.com/mattpocock/skills/blob/main/skills/productivity/wait-what/SKILL.md)
and [teach](https://github.com/mattpocock/skills/blob/main/skills/productivity/teach/SKILL.md)
from [Skills For Real Engineers](https://github.com/mattpocock/skills).
See [how the skills are used](skills/README.md) and the
[third-party notices](docs/THIRD-PARTY-NOTICES.md) for the upstream MIT notice.
