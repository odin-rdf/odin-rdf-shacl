---
id: shape-based-constraints-sh-node
level: task
title: "Shape-based constraints: sh:node and the qualified family"
short_code: "SHACL-T-0018"
created_at: 2026-08-06T19:27:19.010123+00:00
updated_at: 2026-08-07T10:10:30.379406+00:00
parent: SHACL-I-0002
blocked_by: [SHACL-T-0011]
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: SHACL-I-0002
---

# Shape-based constraints: sh:node and the qualified family

## Parent Initiative

[[SHACL-I-0002]]

## Objective **[REQUIRED]**

The shape-based constraints — `sh:node`, and the qualified family: `sh:qualifiedValueShape`,
`sh:qualifiedMinCount`, `sh:qualifiedMaxCount`, `sh:qualifiedValueShapesDisjoint` (§4.8).
The last components, and the ones that give the spine's recursion failure its first real
exercise, because `sh:node` is how a user actually writes a recursive shape.

## Acceptance Criteria

## Acceptance Criteria **[REQUIRED]**

- [x] `sh:node`: each value node must conform to the given shape, through suppressed
      validation, with none of the inner results emitted.
- [x] The qualified family: count how many value nodes conform to `sh:qualifiedValueShape` and
      compare against the min and max, with `sh:qualifiedValueShapesDisjoint` excluding nodes
      conforming to a sibling's qualified shape.
- [x] **Qualified parameters without `sh:qualifiedValueShape` are ignored**, which
      `core/node/qualified-001` already asserts and which the engine gets right today by
      accident — keep it right on purpose.
- [x] **A recursive shape written the way a user would write one** — `ex:S sh:node ex:S`, or a
      mutual pair — behaves as SHACL-A-0002 decided, and the test says which. This is the
      criterion SHACL-T-0007 could only approximate through `sh:property`.
      *(All three forms tested, including SHACL-A-0002's own worked example.)*
- [x] Result shape per component measured against the suite.
- [x] The progress floor moves and the new figure is pinned. *(And `core/node` is enabled.)*
- [x] Tests at both widths against both backends; `make test` and `make check` green.

## Implementation Notes

### Technical Approach

`sh:node` is value-scoped and straightforward once suppression exists. The qualified family is
the harder one: it is set-scoped, it counts rather than tests, and
`sh:qualifiedValueShapesDisjoint` needs to see its *sibling* property shapes' qualified shapes
— which is a read across the model rather than down it, and the flat representation makes that
an index walk rather than a pointer chase.

### Dependencies

SHACL-T-0011 (suppressed validation and SHACL-A-0002) and, through it, SHACL-T-0010.

### Risk Considerations

**Recursion stops being theoretical here.** SHACL-I-0001 predicted this: users with
asset-points-at-asset data reach for `sh:node`, and a reported failure is what they get. If the
suite or a consumer shows that recursive shapes are common rather than a corner case, that is
a recorded review trigger on SHACL-A-0001 and the moment to raise it — not to quietly add
cycle-breaking.

**`sh:qualifiedValueShapesDisjoint` is the most intricate thing in SHACL Core.** Budget for it
separately from the other four, and if it turns out to want its own task, split it rather than
letting it swallow this one.

## Status Updates **[REQUIRED]**

- **2026-08-07 — Started; corpus read first, and it settled the design.** Six entries:
  `core/node`'s node-001 and qualified-001; `core/property`'s node-001, node-002,
  qualifiedValueShape-001, qualifiedMinCountDisjoint-001, qualifiedValueShapesDisjoint-001.
  (Five of `core/property`'s six remaining — the sixth is `nodeKind-001`, which
  SHACL-T-0017 flagged as needing nothing this task adds.)

  **`sh:node` is `sh:not` without the inversion.** Value-scoped, one result per failing
  value node naming it in `sh:value`, `sh:sourceShape` the carrying shape. Nothing new.

  **The qualified family is set-scoped and carries no `sh:value`** —
  `qualifiedValueShape-001` expects one result with `sh:resultPath` and no value, because
  the fault is a count over the whole value-node set. Two components, not one:
  `sh:QualifiedMinCountConstraintComponent` and `sh:QualifiedMaxCountConstraintComponent`.
  `sh:qualifiedValueShapesDisjoint` names no component of its own, like `sh:flags`.

  **`sh:qualifiedValueShapesDisjoint` needs a read the model has never made: upward.**
  §4.7.3 defines a shape's *siblings* as the other `sh:property` values of the shapes that
  have it as a `sh:property` value, and a value node is excluded when it conforms to any
  sibling's `sh:qualifiedValueShape`. The model has children and no parents. Computed at
  compile time in a pass over parents, so validation still walks downward only.

  `qualifiedValueShapesDisjoint-001` is what pins it: two property shapes on the same path,
  one qualifying on `ex:Thumb` and one on `ex:Finger`, and `ex:FingerAndThumb` is excluded
  from **both** counts, so both violate their minimums.

  Plan:

  1. `Constraint_Kind.Node`, `.Qualified_Min_Count`, `.Qualified_Max_Count`; vocabulary and
     the three component IRIs.
  2. `Constraint.siblings`, a second span into `Shapes.shape_children`. **An empty siblings
     span is how `sh:qualifiedValueShapesDisjoint false` is represented** — a disjointness
     with nothing to be disjoint from behaves identically, so no boolean is stored.
  3. `sh:node` joins the operand table SHACL-T-0017 built; the qualified shape and the
     siblings resolve in the same post-fixup region, siblings second because they read the
     qualified shapes.
  4. Evaluation: `sh:node` a one-line `node_conforms`; the qualified pair a count.

  **Qualified counts compile only when `sh:qualifiedValueShape` is present**, which is what
  `node/qualified-001` asserts — the engine gets it right today by doing nothing, and the
  criterion is to keep it right on purpose.

  **Recursion stops being theoretical here**, per the task's risk note: `ex:S sh:node ex:S`
  is how a user writes a recursive shape, and SHACL-A-0002's own worked example
  (`ex:S sh:not [ sh:node ex:S ]`) becomes writable for the first time.

- **2026-08-07 — Implemented; awaiting review. SHACL Core's constraint catalogue is
  complete.** All five entries went green, and with them the directory:

  - **`core/node` is 32 of 32 and is now ENABLED** — see below, this is a judgement call.
  - `core/property` is 37 of 38, the one gap being `nodeKind-001`.
  - Every §4 component that does not need SPARQL is implemented: twenty-nine of them.

  `make test` green at both widths against both backends; `make check` and purity green.

  **I enabled `core/node`, which the Implementation Plan assigns to SHACL-T-0019.** The
  rule the family states is "enabled means fully green", and `suite.odin` has said since
  SHACL-T-0008 that "leaving a green directory disabled would misstate the position as
  surely as enabling a broken one". Holding a 32-of-32 directory off for one more task
  would have done exactly that. Flagged rather than assumed: if the intent was that
  SHACL-T-0019 owns every enablement, reverting is three lines in `suite.odin` plus the
  pinned counts. It also renamed
  `test_exactly_the_spine_directories_are_enabled` to
  `test_exactly_the_green_directories_are_enabled`, since "the spine's four" stopped being
  the rule.

  **The progress floor reads 37, and it went *down* from 63.** That is the mechanism, not a
  regression: an enabled directory carries no floor, so `core/node`'s 31 left the sum and
  became part of `ENABLED_ENTRIES` (26 → 58), where they are a conformance claim rather
  than a direction of travel. The arithmetic is written into `suite.odin` so nobody has to
  reconstruct it. Of the catalogue's original 51 entries of work, 50 are done.

  **`sh:node` needed no evaluator of its own.** It is `sh:and` over a one-shape span —
  every named shape must be conformed to — so it shares `check_logical`'s case rather than
  getting a copy that would read identically. Only the component IRI differs.

  **The qualified family, and the one genuinely new thing in it.**
  `sh:qualifiedValueShapesDisjoint` is the only place this engine reads the shapes model
  **upward**: §4.7.3's siblings are the other `sh:property` values of the shapes that
  declare this one, and the model has children and no parents. Inverted once at compile
  time (`compile_qualified_siblings`), so validation still walks downward only. This is the
  third consecutive task needing a post-fixup pass, and for the third distinct reason.

  Two representation choices worth reviewing:

  - **`sh:qualifiedValueShapesDisjoint false` is an empty siblings span**, and so is
    `true` with no siblings — no boolean is stored, because the two are the same thing to
    the evaluator. The test fixture pairs a disjoint shape with an identical non-disjoint
    one over the same data so the difference is attributable.
  - **The disjoint reading follows `sh:closed` and `sh:uniqueLang`**: the term
    `"true"^^xsd:boolean` and nothing else. Both corpus entries write it that way, so
    nothing measures the alternative; this is consistency, recorded as such.

  **Tests, checked against a broken engine.** Five new unit tests. Disabling the disjoint
  exclusion fails `test_qualified_value_shapes_disjoint` and drops `core/property` to 35;
  making `sh:node` a no-op fails two unit tests, drops `core/property` to 34, and breaks
  two enabled entries.

  **One test was too weak and the check is why I know.** The inert-parameters test — the
  `node/qualified-001` criterion — passed with *both* of its guards removed, because my
  fixture never put `sh:qualifiedValueShape` in the shapes store at all, so the compiler
  skipped every read of it on a `v.found` check. **The corpus entry has the same weakness**:
  its shapes graph never mentions the parameter either, so it passes on an absent
  dictionary term rather than on the rule it was written for. The fixture now carries a
  second shape that uses the parameter for real. Also recorded at the test: the behaviour
  is guarded in two places, removing either alone still passes, and that redundancy is
  deliberate rather than dead code.

  **Recursion, the criterion SHACL-T-0007 could only approximate.** Three shapes, all
  reporting `Failure.Recursive_Shape`: `ex:S sh:node ex:S`, a mutual `ex:S`/`ex:T` pair,
  and **SHACL-A-0002's own worked example `ex:S sh:not [ sh:node ex:S ]`**, writable for
  the first time. No suite entry exercises recursion, so the ADR's decision now has a real
  shapes graph behind it rather than a hand-set bit. The SHACL-A-0001 review trigger is
  untouched — nothing here suggests recursive shapes are common — and is restated in the
  test so the next person to hit one finds the reasoning.

  **Store evidence: still no gap, but the first concrete argument for memoisation.** A
  qualified shape with both a minimum and a maximum walks the same value nodes against the
  same shape twice — the same question with an answer that cannot have changed — and
  disjointness multiplies it by the sibling count. Recorded under STORE-T-0019 in
  `docs/store-evidence.md` as structural rather than incidental. Deliberately not fixed:
  SHACL-A-0002's review trigger is *measured* cost and there is no benchmark yet.

  **Handover to SHACL-T-0019.** Its remaining work is not a component. `core/property`'s
  `nodeKind-001` uses only what the spine shipped and is the single entry between this
  repository and both catalogue directories green; the diagnosis pointer is pinned in
  `suite.odin`. Beyond that: the docs and write-up refresh, and the SHACL-SPARQL handover.