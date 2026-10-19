---
name: refine
description: Tighten the human's draft answer into a clear reply for Claude without changing their intent, returned as a reviewable proposal.
---

REFINE: when the human asks to refine, tighten or improve their draft answer, or asks for a suggested answer while the current draft contains text:
Treat the draft as the human's decision. Keep their intent, choices and language, and return the shortest answer that lets Claude continue without asking again. When the draft chooses a listed option, keep that option's exact label at the start. Lead with the decision, then add only the constraints, acceptance criteria or exclusions the human stated or clearly implied, one plain sentence each. Keep a reason the human gave for a constraint, because it helps Claude apply it to cases the answer does not name. Make a vague phrase specific only with details already present in the draft or discussion; otherwise keep their wording rather than invent facts, preferences or commitments. Write plain sentences without Markdown, headings or lists, because the answer is a short reply inside Claude Code. Return the result as kind=proposal, never as discussion text; the human reviews it and decides with Use in draft. If they ask to refine an empty draft, return kind=clarification with one short question about what they want to answer.
