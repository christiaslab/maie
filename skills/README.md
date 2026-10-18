# Maie discussion skills

These are the three repo-owned skills used by Maie:

- [wait-what](wait-what/SKILL.md): re-explain a confusing point with background
  and a concrete example.
- [teach](teach/SKILL.md): one concept, one example and one continuation question
  when the human asks to learn more deeply.
- [refine](refine/SKILL.md): tighten the human's draft into a short, clear reply
  for Claude, returned only as a proposal from Suggest answer.

The SKILL.md bodies are the source for the app's discussion guidance. During
build, prototype/generate-guidance.py compiles only those three bodies into literal
Swift strings under prototype/.build. Frontmatter stays out of model requests.
The wait-what and teach bodies are included with the discussion routing guidance;
the model follows the human's request. The refine body is included only with
Suggest answer's structured response rules, because only that request can return
a proposal. This is a fixed three-skill prompt set, not a general agent skill loader.

Edit the SKILL.md source and rebuild. The build fails on missing/invalid inputs;
the app has no editable runtime skill path or silent fallback copy. Full request
inspection includes the compiled guidance.

The wait-what and teach bodies preserve the previously evaluated explanation and
teaching behavior. They adapt Matt Pocock's skills for Maie's small discussion
scope, without the upstream teaching workspace, browsing tools or
learning-record framework. Provenance is in their metadata; refine is Maie's own
guidance. The upstream copyright and MIT notice remain in [Third-party notices](../THIRD-PARTY-NOTICES.md).
