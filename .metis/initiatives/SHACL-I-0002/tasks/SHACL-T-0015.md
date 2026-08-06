---
id: property-pair-components-equals
level: task
title: "Property-pair components: equals, disjoint, lessThan, lessThanOrEquals"
short_code: "SHACL-T-0015"
created_at: 2026-08-06T19:27:06.698646+00:00
updated_at: 2026-08-06T19:27:06.698646+00:00
parent: SHACL-I-0002
blocked_by: [SHACL-T-0012]
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: SHACL-I-0002
---

# Property-pair components: equals, disjoint, lessThan, lessThanOrEquals

## Parent Initiative

[[SHACL-I-0002]]

## Objective **[REQUIRED]**

The property-pair components — `sh:equals`, `sh:disjoint`, `sh:lessThan`,
`sh:lessThanOrEquals` (§4.7). The first components that read the data graph a *second* time
from the focus node, comparing a shape's value nodes against the values of another predicate.

## Acceptance Criteria **[REQUIRED]**

- [ ] All four implemented, each comparing the shape's value nodes against the values of the
      parameter's predicate at the same focus node.
- [ ] The second read goes through the **same match interface** as everything else, with the
      graph position bound. No new store capability, or if one is genuinely wanted, it is
      recorded in `docs/store-evidence.md` rather than worked around.
- [ ] `sh:lessThan` and `sh:lessThanOrEquals` use SHACL-T-0012's value comparison, and both are
      restricted to property shapes per the spec.
- [ ] Result shape correct per component: which of them name a `sh:value` and which blame the
      focus node is measured against the suite, not assumed.
- [ ] The progress floor moves and the new figure is pinned.
- [ ] Tests at both widths against both backends; `make test` and `make check` green.

## Implementation Notes

### Technical Approach

The parameter is a predicate IRI, so it binds like any other model term and the second read is
a single `match` from the focus node — which the `Scan` adapter already serves. The comparison
is set-against-set for `sh:equals` and `sh:disjoint`, pairwise for the ordering pair.

Worth noticing: this is the first component group whose result does not depend only on the
value nodes, so it may not fit either existing scope cleanly. If it does not, extend the scope
vocabulary deliberately rather than special-casing inside a check.

### Dependencies

SHACL-T-0012 for `sh:lessThan` and `sh:lessThanOrEquals`. `sh:equals` and `sh:disjoint` need
only term equality and could land first.

### Risk Considerations

**The scope question above is the real risk.** If property-pair components need a third scope,
that is a change to the seam the catalogue initiative is supposed to be filling rather than
reshaping — so it wants a moment's thought and a note, not a quiet edit.

## Status Updates **[REQUIRED]**

*To be added during implementation*
