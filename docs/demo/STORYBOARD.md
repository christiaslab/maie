# Demo storyboard

A clip of about 45 seconds showing one Claude Code question answered through
Maie. The story is about understanding the question and keeping the final
answer human-owned: a proposal never changes the draft until **Use in draft**,
and only **Send to Claude** submits it.

## Status of the current recording

The current clip (`prototype/.build/demo/maie-demo-synthetic.mp4`, 44.3 s,
1920x1080, dark appearance, produced by the gitignored UI harness under
`prototype/.build/ui-harness/`) is **synthetic** and is labeled as such on
screen:

- Model replies (explanation and proposal) are scripted. No model is called.
- Claude Code is simulated: a synthetic AskUserQuestion payload is passed to
  Maie's real hook helper. No Claude Code session is recorded.
- The app views, button presses, draft editing and the helper's returned answer
  are real for that run. The closing scene shows the helper output and whether
  it exactly matches the edited draft.
- All content is fictional: project "trailmap", no real names, accounts,
  paths or conversations.

On-screen footer label: "Synthetic demo · fictional project · scripted model
replies · simulated Claude Code".

Music: "First Light Particles" by Yoiyami, CC0 1.0 (public domain, no
attribution required), from opengameart.org/node/182244. About 44 s of the
track are mixed under the clip at a low level with a 1.5 s fade in and a 3 s
fade out. The media and the track stay out of Git; the file, checksum and
license are recorded in `prototype/.build/demo/music/SOURCE.md`.

## Scenario

Fictional project **trailmap**. Claude asks:

> Where should Trailmap store saved routes for the first release?
> 1. SQLite file — One local database file
> 2. Postgres service — Shared server database
> 3. JSON files — One file per route

## Shot list

The window (470 pt wide) sits on the left; a step label and one short caption
sit on the right. The opening and closing scenes are a mock terminal pane
("claude · trailmap"), not a recording of Claude Code.

| Scene | On screen | Caption |
| --- | --- | --- |
| Intro (~3 s) | Terminal pane: the AskUserQuestion with its three options and a "waiting…" cursor. | — |
| 1 · OPEN | Maie opened from the menu-bar leaf; the question, options and empty **Your answer**. | "The question waits in Maie until you open it." |
| 2 · UNDERSTAND | "Explain the difference briefly." typed in **Ask Maie**; first-send confirmation; the explanation appears while **Your answer** stays empty. | "Ask what the options mean." / "You confirm the first request before it is sent." |
| 3 · DECIDE | Rough intent typed in **Your answer**; **Suggest answer**; a **Proposed answer** with **Use in draft / Dismiss** while the draft below is unchanged. | "Write your intent, then ask for a suggested answer." / "The suggestion stays separate. Your answer is unchanged." |
| 4 · ACCEPT | **Use in draft**; the draft now holds the proposal text. | "Use in draft copies it into your answer." |
| 5 · EDIT | " Revisit after the beta." appended to the draft. | "Edit the answer in your own words." |
| 6 · SEND | **Send to Claude**; status shows the answer was sent. | "Only Send to Claude submits it." |
| Outro (~6 s) | Terminal pane: the received answer typed after "›", then "exactly the edited text ✓" from the real helper output; closing frame with the leaf and the "maie" wordmark. | — |

Do not cut the unchanged-draft moment in step 3.

## Points to keep visible

- **Your answer** is empty or unchanged while the proposal is shown.
- **Dismiss** is visible next to **Use in draft**, even though it is not pressed.
- The edit after Use in draft appears in the final received text.
- Model and thinking time are visible above the message field.
- The real window controls are colored (the window is key while recording).

## Capture checklist for a future live recording

Before recording:

- [ ] Use a fresh throwaway project (for example, a new empty `trailmap`
      folder) with the project-local hook applied; no real repositories.
- [ ] Use a throwaway or clearly non-identifying macOS user if possible. No
      account names, email addresses, avatars or home-folder paths visible in
      Maie, Claude Code, the terminal prompt or window titles.
- [ ] Keep **Details** (session IDs, request IDs, paths) closed, or confirm the
      shown values are throwaway.
- [ ] Hide menu bar clutter; keep only the clock (optional) and Maie's leaf.
- [ ] Turn on Do Not Disturb / Focus; quit messaging and mail apps.
- [ ] Close unrelated windows; use a plain desktop background.
- [ ] Set a fixed window size (the synthetic clip uses a 470 pt wide window) and
      the same position for each take.
- [ ] Choose light or dark appearance and keep it for the whole clip.
- [ ] Leave **Include Claude history** off unless the transcript is synthetic.
- [ ] Review the first-send confirmation, including **View everything sent to
      OpenAI** if expanded; confirm every line is OK to show.
- [ ] Check that the Connection view shows no account label you do not want to
      publish.
- [ ] Use only music whose license you have recorded (source, file, license).

During and after recording:

- [ ] Verify Claude's displayed received answer matches the sent draft exactly
      (inspect the actual Claude result, not only Maie's status).
- [ ] Label what is live and what is scripted (for example, "live model reply,
      live Claude Code session" or "scripted model reply").
- [ ] Review every frame for notifications, private text or identifiers before
      publishing.
- [ ] Keep video, stills and raw captures out of Git. Host media externally and
      link to it.
