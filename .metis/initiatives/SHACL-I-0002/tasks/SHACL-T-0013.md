---
id: value-range-components-the-four
level: task
title: "Value-range components: the four inclusive and exclusive bounds"
short_code: "SHACL-T-0013"
created_at: 2026-08-06T19:26:57.793476+00:00
updated_at: 2026-08-07T05:56:26.621183+00:00
parent: SHACL-I-0002
blocked_by: [SHACL-T-0012]
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: SHACL-I-0002
---

# Value-range components: the four inclusive and exclusive bounds

## Parent Initiative

[[SHACL-I-0002]]

## Objective **[REQUIRED]**

The four value-range components — `sh:minInclusive`, `sh:maxInclusive`, `sh:minExclusive`,
`sh:maxExclusive` (§4.6.2–4.6.5). The first components to consume the value machinery, and the
first real exercise of the four-edit seam by something that is not a term comparison.

## Acceptance Criteria

## Acceptance Criteria **[REQUIRED]**

- [x] All four implemented through the dispatch seam: a `Constraint_Kind`, a parameter in
      `compile_constraints`, a scope, and a case in `check_value` — **nothing in the
      evaluator**. If the evaluator has to change, that is a finding worth raising.
- [x] Value-scoped, per the seam's rule: each is asked once per value node and blames it, so
      each result carries `sh:value`.
- [x] A value node that is not comparable to the bound violates rather than passing. The
      spec's condition is that the comparison holds, and "incomparable" is not "holds".
- [x] The progress floor from SHACL-T-0009 moves, and the new figure is pinned.
- [x] Unit tests in `shacl/memstore` covering each component and the incomparable case; tests
      at both widths against both backends.
- [x] `make test` and `make check` green.

## Implementation Notes

### Technical Approach

Mechanically similar to `sh:datatype` in shape — read a term parameter, compare per value node
— with the comparison coming from SHACL-T-0012 rather than from term equality. If these four
take meaningfully more than "a case each", the seam is not doing its job and that is worth
recording.

### Dependencies

SHACL-T-0012 (the value comparison). Independent of everything else.

### Risk Considerations

Low. The main thing to watch is the boundary between "the comparison says false" and "the
comparison could not be made", which is a single `if` written the wrong way round.

## Status Updates **[REQUIRED]**

- **2026-08-07 — Implemented; awaiting review.** `make test` and `make check` green at
  both `Term_ID` widths. **Progress floor 21 → 31**: `core/node` 9 → 15,
  `core/property` 12 → 16 — **all ten value-range entries in the corpus, and nothing
  else**, on the first run against both backends. The catalogue's remaining work is 38
  entries of the original 51.

  **The seam held, and that is the finding.** The task said to record it if these took
  meaningfully more than a case each; they did not. Four `Constraint_Kind`s, four lines in
  `compile_constraints`'s existing single-term table (which went from 3 entries to 7 and
  changed in no other way), four names on the value arm of `constraint_scope`, one line in
  `check_value`, plus vocabulary and `component_iri`. **The evaluator was not touched** —
  no edit to `validate.odin`, `path_eval.odin`, `target.odin`, or `report.odin`.

  The one procedure that is new is `check_range`, and it is one rather than four because
  the components differ only in which of `compare_values`'s four answers they accept.

  **Incomparable violates structurally rather than by a test.** The risk note called out
  the single `if` written the wrong way round; the way to not write it wrong is to not
  write it. `#partial switch c.kind` has an arm per component, each accepting one or two
  of `.Less/.Equal/.Greater`, and `.Incomparable` simply matches nothing and falls through
  to false. An explicit `if order == .Incomparable { return false }` would be identical
  behaviour with a place for a later component to invert it. Said so in the doc comment,
  since it reads as an omission otherwise.

  **What the unit tests cover that the suite does not.** `test_value_range_boundaries` puts
  all four bounds against the same three nodes so inclusive-versus-exclusive is one column
  of the expectation. `test_value_range_incomparable_violates` pins cross-datatype
  conformance (`"4.0"^^xsd:decimal` and `"12"^^xsd:byte` both satisfy `sh:minInclusive 4`,
  where term equality fails both) and, more usefully, **a bound that is itself not a
  value** — `sh:minInclusive ex:NotANumber`, where nothing can be shown to be in range so
  nothing is. No suite entry has that.

  Both fixtures also exercise the **unbound** focus-node path, which the suite structurally
  cannot: an entry's shapes and data are the same document, so every node in it is bound
  and reaches `check_range` through the store's dictionary. Here they are named only by
  `sh:targetNode` and reach it as terms. That is why the expectations read `?"3"` rather
  than `"3"`, and it is noted in the test so the `?` is not mistaken for noise.

  **Two existing tests had to move, and they moved in the right direction.**
  `test_ignored_parameters_are_recorded` (memstore) and
  `test_shape_expecting_parameters_are_recorded_as_unimplemented` (kvstore) both used
  `sh:minInclusive` as their example of a component the engine reads and does not enforce.
  It is enforced now, so both switch to `sh:pattern` and `sh:minInclusive` joins the
  *not*-recorded list in the memstore one. That assertion now earns its place twice over:
  it would catch a future component wired into the evaluator without being declared in
  `IMPLEMENTED_PARAMETERS`, which is the failure that would make `shapes_ignored` lie.

  README's component list updated: eleven validate, and value-range is out of the
  "missing" sentence.

  Nothing under the upstream repos was touched, and nothing new was asked of the store.
  Not committed — awaiting review.