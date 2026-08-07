---
id: property-pair-components-equals
level: task
title: "Property-pair components: equals, disjoint, lessThan, lessThanOrEquals"
short_code: "SHACL-T-0015"
created_at: 2026-08-06T19:27:06.698646+00:00
updated_at: 2026-08-07T06:24:07.727223+00:00
parent: SHACL-I-0002
blocked_by: [SHACL-T-0012]
archived: false

tags:
  - "#task"
  - "#phase/completed"


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

## Acceptance Criteria

## Acceptance Criteria **[REQUIRED]**

- [x] All four implemented, each comparing the shape's value nodes against the values of the
      parameter's predicate at the same focus node.
- [x] The second read goes through the **same match interface** as everything else, with the
      graph position bound. No new store capability, or if one is genuinely wanted, it is
      recorded in `docs/store-evidence.md` rather than worked around.
- [x] `sh:lessThan` and `sh:lessThanOrEquals` use SHACL-T-0012's value comparison, and both are
      restricted to property shapes per the spec.
- [x] Result shape correct per component: which of them name a `sh:value` and which blame the
      focus node is measured against the suite, not assumed.
- [x] The progress floor moves and the new figure is pinned.
- [x] Tests at both widths against both backends; `make test` and `make check` green.

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

- **2026-08-07 — Implemented; awaiting review.** `make test` and `make check` green at
  both `Term_ID` widths. **Progress floor 42 → 49**: `core/node` 20 → 22,
  `core/property` 22 → 27 — the seven property-pair entries. Twenty entries of the
  original 51 remain.

  **The scope question resolved against adding a scope, and the seam's documentation was
  what needed fixing.** These four are set-scoped — `sh:equals` and `sh:disjoint` compare
  set against set and could not be answered from one node, and the ordering pair could be
  but would repeat the second store read once per value node. What broke is not the enum
  but the *invariant written beside it*: the header claimed a set-scoped component "has no
  single node to blame, so its result carries none". `sh:equals` is set-scoped and its
  results carry `sh:value` — **including nodes that are not value nodes at all**, because
  the symmetric difference runs in both directions and `node/equals-001` expects a result
  naming a member of the other predicate's set. So scope decides how often the component
  is called; `emit_result`'s `has_value` decides what it blames. The two were correlated
  across the spine's seven and that was a coincidence, now written down as one.

  **The floor moved by zero on the first run, and the cause is worth more than the fix.**
  `bindings_init` resolves a constraint's parameter term to a data-store `Term_ID` from a
  kind-switch that listed `Class`, `Datatype`, and `Has_Value`. A component missing from
  it does not error — it reads `constraint_bound` as false, concludes the store has never
  seen its parameter, and reports **nothing**. All four components compiled, dispatched,
  ran, and found an empty second set on every focus node, and every test passed.

  That makes it a **fifth edit the seam's documentation did not mention, and it is in the
  evaluator** — so the initiative's "four edits per component and none of them is in the
  evaluator" held for the spine's seven and does not hold in general. Corrected in
  `check.odin`'s header and at the switch itself, both naming this failure, because the
  next component that compares a parameter by ID will hit it identically and silently.

  **One corpus detail that only the corpus could have told us.** `sh:lessThan` emits a
  result **per failing pair**, not per failing value node: `property/lessThan-002` puts two
  integers against two strings — every pair incomparable — and expects *four* results with
  each `sh:value` repeated twice. A per-value-node loop with a break produces two and
  looks entirely reasonable. Pinned in a unit test built on the same shape.

  **No new store capability.** The second read is `Access.step`, the same procedure a
  predicate path uses, with the graph bound by the instantiation package —
  `docs/store-evidence.md` gains nothing from this task. Absence stays emptiness on that
  read: an unbound focus node or an unseen predicate gives an empty second set, which is a
  real answer rather than a missing one (`sh:equals` then reports every value node,
  `sh:lessThan` reports nothing, and the corpus expects both).

  The ordering pair compares by value through SHACL-T-0012, so `.Incomparable` fails for
  the same reason it fails in the value-range components; the pair is restricted to
  property shapes per §4.7.3–4.7.4, and there is a test that a node shape using it asks
  nothing.

  Nothing under the upstream repos was touched. Not committed — awaiting review.