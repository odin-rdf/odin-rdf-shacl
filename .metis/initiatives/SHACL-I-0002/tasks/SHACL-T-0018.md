---
id: shape-based-constraints-sh-node
level: task
title: "Shape-based constraints: sh:node and the qualified family"
short_code: "SHACL-T-0018"
created_at: 2026-08-06T19:27:19.010123+00:00
updated_at: 2026-08-06T19:27:19.010123+00:00
parent: SHACL-I-0002
blocked_by: [SHACL-T-0011]
archived: false

tags:
  - "#task"
  - "#phase/todo"


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

## Acceptance Criteria **[REQUIRED]**

- [ ] `sh:node`: each value node must conform to the given shape, through suppressed
      validation, with none of the inner results emitted.
- [ ] The qualified family: count how many value nodes conform to `sh:qualifiedValueShape` and
      compare against the min and max, with `sh:qualifiedValueShapesDisjoint` excluding nodes
      conforming to a sibling's qualified shape.
- [ ] **Qualified parameters without `sh:qualifiedValueShape` are ignored**, which
      `core/node/qualified-001` already asserts and which the engine gets right today by
      accident — keep it right on purpose.
- [ ] **A recursive shape written the way a user would write one** — `ex:S sh:node ex:S`, or a
      mutual pair — behaves as SHACL-A-0002 decided, and the test says which. This is the
      criterion SHACL-T-0007 could only approximate through `sh:property`.
- [ ] Result shape per component measured against the suite.
- [ ] The progress floor moves and the new figure is pinned.
- [ ] Tests at both widths against both backends; `make test` and `make check` green.

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

*To be added during implementation*
