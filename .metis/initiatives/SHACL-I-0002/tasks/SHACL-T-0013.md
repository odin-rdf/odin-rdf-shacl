---
id: value-range-components-the-four
level: task
title: "Value-range components: the four inclusive and exclusive bounds"
short_code: "SHACL-T-0013"
created_at: 2026-08-06T19:26:57.793476+00:00
updated_at: 2026-08-06T19:26:57.793476+00:00
parent: SHACL-I-0002
blocked_by: [SHACL-T-0012]
archived: false

tags:
  - "#task"
  - "#phase/todo"


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

## Acceptance Criteria **[REQUIRED]**

- [ ] All four implemented through the dispatch seam: a `Constraint_Kind`, a parameter in
      `compile_constraints`, a scope, and a case in `check_value` — **nothing in the
      evaluator**. If the evaluator has to change, that is a finding worth raising.
- [ ] Value-scoped, per the seam's rule: each is asked once per value node and blames it, so
      each result carries `sh:value`.
- [ ] A value node that is not comparable to the bound violates rather than passing. The
      spec's condition is that the comparison holds, and "incomparable" is not "holds".
- [ ] The progress floor from SHACL-T-0009 moves, and the new figure is pinned.
- [ ] Unit tests in `shacl/memstore` covering each component and the incomparable case; tests
      at both widths against both backends.
- [ ] `make test` and `make check` green.

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

*To be added during implementation*
