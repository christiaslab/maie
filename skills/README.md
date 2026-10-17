# Maie discussion skills

These are the two repo-owned adaptations used by Maie:

- [wait-what](wait-what/SKILL.md): re-explain a confusing point with background
  and a concrete example.
- [teach](teach/SKILL.md): one concept, one example and one continuation question
  when the human asks to learn more deeply.

The SKILL.md bodies are the source for the app's discussion guidance. During
build, prototype/generate-guidance.py compiles only those two bodies into literal
Swift strings under prototype/.build. Frontmatter stays out of model requests.
Both bodies are included with the discussion routing guidance; the model follows
the human's request. This is a fixed two-skill prompt adaptation, not a general
agent skill loader. Suggest answer keeps its separate structured response rules.

Edit the SKILL.md source and rebuild. The build fails on missing/invalid inputs;
the app has no editable runtime skill path or silent fallback copy. Full request
inspection includes the compiled guidance.

The bodies preserve the previously evaluated explanation and teaching behavior.
They adapt Matt Pocock's skills for Maie's small discussion scope, without the
upstream teaching workspace, browsing tools or learning-record framework.
Provenance is in each file's metadata. The upstream copyright and MIT notice
remain in [Third-party notices](../THIRD-PARTY-NOTICES.md).
