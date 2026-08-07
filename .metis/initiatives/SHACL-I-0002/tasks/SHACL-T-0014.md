---
id: string-components-length-pattern
level: task
title: "String components: length, pattern, and the language pair"
short_code: "SHACL-T-0014"
created_at: 2026-08-06T19:27:01.855781+00:00
updated_at: 2026-08-07T06:15:02.989376+00:00
parent: SHACL-I-0002
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


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

## Acceptance Criteria

## Acceptance Criteria **[REQUIRED]**

- [x] `sh:minLength` and `sh:maxLength` over the value node's lexical form, with the spec's
      rule that they do not apply to blank nodes.
- [x] `sh:pattern` and `sh:flags` via **`core:text/regex`**, keeping the family's
      no-external-dependencies constraint. Decided at design (2026-08-06) on the measurement
      that the corpus's four patterns are `^[2-8][0-9]*$`, `Aldi`, `joh`, `Joh` and one flag
      `i` — all in any engine's common subset.
- [x] **The dialect divergence documented explicitly** where a user will meet it: SHACL defines
      `sh:pattern` by XPath `fn:matches` (XML Schema regex) with flags `i s m x q`; Odin's
      package offers `m i x u`. Say which flags are unsupported and what happens when one is
      given, rather than silently ignoring it.
- [x] `sh:languageIn` by **BCP 47 basic filtering** (RFC 4647) — case-insensitive and
      prefix-based, so `@en-NZ` matches `en`. This is why it is immune to the language-tag
      folding question, and the test should say so.
- [x] `sh:uniqueLang`, which is set-scoped: it is asked once about the whole value-node set.
- [x] **The language-tag trigger is live here.** If any entry fails on tag case, work stops and
      the fix goes to odin-rdf-parser with review and bench numbers, per the standing trigger.
      The corpus survey says it cannot fire; if it does, that survey was wrong.
      **It did not fire** — see the status update for why it structurally could not.
- [x] The progress floor moves and the new figure is pinned.
- [x] Tests at both widths against both backends; `make test` and `make check` green.

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

- **2026-08-07 — Implemented; awaiting review.** `make test` and `make check` green at
  both `Term_ID` widths. **Progress floor 31 → 42**: `core/node` 15 → 20,
  `core/property` 16 → 22 — the eleven remaining string entries, first run, both
  backends. The catalogue's remaining work is 27 entries of the original 51.

  **The regex decision held, and it was checked before anything was written.** The four
  corpus patterns (`^[2-8][0-9]*$`, `Aldi`, `Joh`, `joh`, one `sh:flags "i"`) were run
  through `core:text/regex` as a scratch program first, including the anchoring and the
  case-insensitive pair. All correct, so the design-phase measurement stands and no
  reopening was needed.

  One thing that measurement had not established: **`regex.match` searches rather than
  matching the whole string**, which is what XPath `fn:matches` does and what
  `property/pattern-001` depends on — `sh:pattern "Joh"` must match `"John Doe"`. It is
  right by default, and there is a unit test saying so rather than a comment hoping.

  **The corpus contradicted the obvious implementation once, and it matters.**
  `property/uniqueLang-002` declares `sh:uniqueLang "1"^^xsd:boolean` over two `@en`
  literals and expects `sh:conforms true`, with a comment in the fixture explaining that
  only `true` activates the component. So `sh:uniqueLang` is switched on by the **term**
  `"true"^^xsd:boolean` and not by its value — "1" is the same value and a different term.
  This is the one place in the engine where a boolean parameter is read as a term, three
  tasks after learning to compare values, so it is commented at the compile site and has
  its own unit test.

  **The reading is arguable and the comment now says so.** The entry's justification is a
  judgement about §4.5.5's prose, and it cuts against the spec's own normative validator,
  which tests the parameter with SPARQL `=` — under which `"1"^^xsd:boolean = true` is
  true by value. The entry is `sht:approved` and the family's rule is that the suite
  defines done, so the suite wins; but this is an interpretation the corpus made, not a
  fact the specification states, and it is recorded as such. That entry was already in the floor because nothing implemented
  `sh:uniqueLang`; it is now the only entry in the tree that went from passing-by-inaction
  to passing-by-validation.

  **The language-tag trigger did not fire, and could not have.** Both components that read
  a tag compare case-insensitively *by specification* — RFC 4647 basic filtering for
  `sh:languageIn`, RDF Concepts' tag identity for `sh:uniqueLang` — so neither ever asks a
  question whose answer depends on whether the parser folded a tag's case. The corpus
  survey was right, and the reason is structural rather than lucky. The fixture
  demonstrates it rather than asserting it in prose: `@EN` appears on both sides, matched
  against the range `en` and counted as a duplicate of `@en`.

  **What §4.5 means by "the value node's string" is the part worth reviewing.** It is not
  the lexical form: a literal gives its lexical form, **an IRI gives the IRI itself**, and a
  blank node gives nothing and therefore violates all three of `sh:minLength`,
  `sh:maxLength`, and `sh:pattern`. `node/minLength-001` pins it — `<a:b>` is three
  characters and violates `sh:minLength 4`. The unit test includes a blank node against
  `sh:minLength 0`, which is the assertion an implementation defaulting to `""` would fail
  and every other assertion would let through. Length counts **code points**, per
  `fn:string-length`; no corpus entry is non-ASCII, so that is the spec followed rather
  than a test passed, and there is a test for it.

  **`sh:flags` refuses rather than downgrades.** `s` and `q` are legal XPath flags with no
  equivalent in `core:text/regex`, so they are `Error_Kind.Flags_Unsupported` at compile
  time; a pattern that will not compile is `Error_Kind.Pattern_Ill_Formed`. Silently
  dropping a flag would validate against a pattern nobody wrote and then report
  conformance. Documented in the README, the package doc (now seven contracts), and at the
  code. Six new `Error_Kind`s in all — the string family cites §4.5 where the existing
  cardinality errors cite §4.2, and an error message naming the wrong section is worse
  than a longer enum.

  **The model owns an allocation for the first time.** `Constraint.pattern` is a compiled
  `regex.Regular_Expression`, built once at compile time and freed by `shapes_destroy` —
  which now has a loop over constraints, and runs on the failed-compile path too.
  `tests/guards` is green, so nothing strands.

  **The ignored-parameter tests moved for the third task running, and this time
  permanently.** They had used whichever component was next on the catalogue's list —
  `sh:minInclusive`, then `sh:pattern` — so each landing task had to come back and pick
  another. They now use `sh:sparql` and `sh:entailment`, which belong to a phase this
  initiative is explicitly not part of and will still be unimplemented when it closes.

  Nothing under the upstream repos was touched, and nothing new was asked of the store.
  Not committed — awaiting review.