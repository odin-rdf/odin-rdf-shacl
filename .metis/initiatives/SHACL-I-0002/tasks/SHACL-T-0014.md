---
id: string-components-length-pattern
level: task
title: "String components: length, pattern, and the language pair"
short_code: "SHACL-T-0014"
created_at: 2026-08-06T19:27:01.855781+00:00
updated_at: 2026-08-06T19:27:01.855781+00:00
parent: SHACL-I-0002
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: SHACL-I-0002
---

# String components: length, pattern, and the language pair

## Parent Initiative

[[SHACL-I-0002]]

## Objective **[REQUIRED]**

The string-based components — `sh:minLength`, `sh:maxLength`, `sh:pattern` with `sh:flags`,
`sh:languageIn`, `sh:uniqueLang` (§4.5). The group that brings in a regex engine, and the one
where the language-tag question this family has been carrying since the vision could finally
become real.

## Acceptance Criteria **[REQUIRED]**

- [ ] `sh:minLength` and `sh:maxLength` over the value node's lexical form, with the spec's
      rule that they do not apply to blank nodes.
- [ ] `sh:pattern` and `sh:flags` via **`core:text/regex`**, keeping the family's
      no-external-dependencies constraint. Decided at design (2026-08-06) on the measurement
      that the corpus's four patterns are `^[2-8][0-9]*$`, `Aldi`, `joh`, `Joh` and one flag
      `i` — all in any engine's common subset.
- [ ] **The dialect divergence documented explicitly** where a user will meet it: SHACL defines
      `sh:pattern` by XPath `fn:matches` (XML Schema regex) with flags `i s m x q`; Odin's
      package offers `m i x u`. Say which flags are unsupported and what happens when one is
      given, rather than silently ignoring it.
- [ ] `sh:languageIn` by **BCP 47 basic filtering** (RFC 4647) — case-insensitive and
      prefix-based, so `@en-NZ` matches `en`. This is why it is immune to the language-tag
      folding question, and the test should say so.
- [ ] `sh:uniqueLang`, which is set-scoped: it is asked once about the whole value-node set.
- [ ] **The language-tag trigger is live here.** If any entry fails on tag case, work stops and
      the fix goes to odin-rdf-parser with review and bench numbers, per the standing trigger.
      The corpus survey says it cannot fire; if it does, that survey was wrong.
- [ ] The progress floor moves and the new figure is pinned.
- [ ] Tests at both widths against both backends; `make test` and `make check` green.

## Implementation Notes

### Technical Approach

Four of the five are ordinary seam work. `sh:pattern` is the one with a decision already taken
and a limit to document; `sh:uniqueLang` is the one whose scope is easy to get wrong, because
it reads like a per-value check and is not.

An unsupported `sh:flags` letter should be an ill-formed-shapes error rather than a silent
ignore — the whole point of documenting the divergence is that a user finds out.

### Dependencies

None. Independent; can run in parallel with SHACL-T-0011 through SHACL-T-0013.

### Risk Considerations

**The regex decision was taken on four patterns.** That is enough evidence to start and not
enough to be smug about. If an entry needs something outside `core:text/regex`, the decision
reopens with real evidence, which is the point of having recorded how it was made.

**This is the only task in the initiative that can fire the language-tag trigger.** It is
listed as an acceptance criterion rather than a note so it cannot be absorbed quietly.

## Status Updates **[REQUIRED]**

*To be added during implementation*
