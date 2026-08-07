---
id: share-one-walk-between-a-property
level: task
title: "Share one walk between a property shape's two qualified bounds"
short_code: "SHACL-T-0026"
created_at: 2026-08-07T13:20:42.675058+00:00
updated_at: 2026-08-07T13:20:42.675058+00:00
parent: 
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/backlog"
  - "#tech-debt"


exit_criteria_met: false
initiative_id: NULL
---

# Share one walk between a property shape's two qualified bounds

## Objective **[REQUIRED]**

A property shape carrying both `sh:qualifiedMinCount` and `sh:qualifiedMaxCount` shares one
`sh:qualifiedValueShape` between them, and `check_qualified` walks its value nodes **once per
bound** — asking the same `(shape, node)` question twice, with an answer that cannot have
changed in between.

Compile the two bounds into a single constraint that **counts once and tests the count
twice**, removing the second walk entirely.

**This is not memoisation, and the distinction is the point.** SHACL-A-0002 considered a
`(shape, node)` conformance cache and SHACL-T-0025 measured it and said no. This removes the
duplicate rather than remembering the first answer, which is why it wins where a cache does
not.

## Backlog Item Details **[CONDITIONAL: Backlog Item]**

### Type
- [x] Tech Debt - Code improvement or refactoring

### Priority
- [x] P2 - Medium (nice to have)

### Technical Debt Impact

- **Current Problems**: Measured at SHACL-T-0025, on a 500-focus-node configuration whose
  only difference from its control is the second bound:

  | | reads | allocations | total bytes | validate |
  | --- | ---: | ---: | ---: | ---: |
  | `qualified-min` | 9003 | 9018 | 2 757 382 | 930 µs |
  | `qualified-minmax` | 10003 | 11018 | 3 973 382 | 1043 µs |
  | **the duplicate** | **+1000** | **+2000** | **+1 216 000** | **+113 µs (11%)** |

  +1000 is exactly the 1000 `ex:q` value nodes, walked a second time.

- **Benefits of Fixing**: All of the above, for no cost anywhere. No hot-path lookup, no
  live memory, no new state. SHACL-A-0002's *As Measured* section has the comparison against
  the cache: there is no axis on which the cache wins, and this dominates it under every
  allocator.

- **Risk Assessment**: Low urgency, and worth saying why it is P2 rather than P1 — it only
  helps shapes graphs that write both bounds, which is a real pattern (exactly N of
  something) but not the common one. **The arena figure is what keeps it from being P3**:
  peak memory does not move, so under a freeing allocator this is 11% of wall clock, but
  under an arena — a natural choice for a validation pass, and one this engine's
  allocator-aware API invites — it is +1.2 MB per validation that never comes back.

## Acceptance Criteria **[REQUIRED]**

- [ ] **Both bounds of one property shape are evaluated from a single walk** of the value
      nodes. One `conformed` count, tested against each bound present.
- [ ] **`qualified-minmax`'s pinned read count falls to `qualified-min`'s — 10003 → 9003.**
      This is the sharpest criterion available and the benchmark predicts it in advance: the
      change is correct exactly when the two configurations become indistinguishable in
      reads, because the only thing between them was the duplicate walk.
- [ ] **`qualified`'s pin (11504) does *not* move.** That configuration is the
      `Disjoint_Pair` form — two separate property shapes with one bound each — so there is
      nothing to share and nothing should change. A pin that moves there means the merge
      caught a case it should not have.
- [ ] **Both bounds can still violate on one focus node, and both results are emitted with
      the right `sh:sourceConstraintComponent`.** `sh:qualifiedMinCount 3` with
      `sh:qualifiedMaxCount 1` and a count of 2 violates both; the merged constraint must
      emit `sh:QualifiedMinCountConstraintComponent` *and*
      `sh:QualifiedMaxCountConstraintComponent`, not one merged result and not the wrong
      component. **A unit test for this specifically**, because no suite entry has that
      shape and the obvious implementation emits one result.
- [ ] **W3C suite still 98 of 98**, both backends, both `Term_ID` widths.
- [ ] `make check` green and **`tests/guards` still net-zero** — a merged constraint changes
      what `check_qualified` allocates and when.
- [ ] **The read-count invariants still hold** — identical across both backends and both
      widths — and the re-pin is explained in the commit message, per `config.odin`'s note
      that a pin may move but must never move unnoticed.

## Implementation Notes **[CONDITIONAL: Technical Task]**

### Technical Approach

The seam is `compile_constraints` (`shacl/constraints.odin`) and `check_qualified`
(`shacl/check.odin`). Today the two bounds compile to two independent `Constraint`s with
kinds `.Qualified_Min_Count` and `.Qualified_Max_Count`, and `check_qualified` runs the whole
counting loop for each.

**Things to check rather than assume:**

- **How many `sh:qualifiedValueShape` values the compiler tolerates.** §4.7.3 gives a
  property shape at most one, so the two bounds share it by definition — but the merge rests
  on that, so confirm the compiler enforces it rather than taking the first of several.
- **`sh:qualifiedValueShapesDisjoint` is part of the count**, not a separate pass, and both
  bounds see the same exclusion. Merging must keep that inside the shared walk.
- **`Constraint` may need a second bound field**, or a small variant. Whatever shape it
  takes, `constraint_scope` and the dispatch switch have to stay coherent — and note the
  fifth seam edit in `check.odin`'s header: a constraint kind missing from `bindings_init`
  reads its parameter as unbound and silently reports nothing.
- **The failure path.** `check_qualified` returns early on `v.failure != .None` in three
  places inside the loop; a merged version has one loop and must still abandon cleanly.

### Dependencies

None. The evidence is already taken — SHACL-A-0002's *As Measured* section and
[[SHACL-T-0025]] — and `bench` already contains the pair that measures it, so the before and
after are one `make bench` apart.

### Risk Considerations

**The obvious implementation emits one result where two are required.** Both bounds can
violate at the same focus node, and no entry in the vendored suite has that shape, so the
suite will not catch it. That is the one place this change can be subtly wrong while looking
entirely right, and it is why a unit test for it is an acceptance criterion rather than a
suggestion.

**Do not let this become the cache.** The temptation, once the walk is shared, is to notice
that other components ask overlapping questions and to generalise. SHACL-A-0002 measured that
and said no; this task removes one specific duplicate and stops there.

## Status Updates **[REQUIRED]**

*To be added during implementation*
