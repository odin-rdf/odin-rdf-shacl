---
id: constraint-dispatch-and-the
level: task
title: "Constraint dispatch and the minimal set: first suite directories green"
short_code: "SHACL-T-0007"
created_at: 2026-08-06T13:58:17.309877+00:00
updated_at: 2026-08-06T13:58:17.309877+00:00
parent: SHACL-I-0001
blocked_by: ["SHACL-T-0002", "SHACL-T-0004", "SHACL-T-0005", "SHACL-T-0006"]
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: SHACL-I-0001
---

# Constraint dispatch and the minimal set: first suite directories green

## Parent Initiative

[[SHACL-I-0001]]

## Objective **[REQUIRED]**

Join the spine into a working validator: the constraint-dispatch seam, the term-binding bridge
from shapes model to data store, the evaluator's explicit stack with recursion detection, and
the minimum constraint set needed to turn whole suite directories green. This task is where
the initiative's exit criteria are met, and where the seam that the catalogue initiative fills
gets its shape.

## Acceptance Criteria **[REQUIRED]**

- [ ] **Term-binding bridge**: the shapes model's `rdf.Term` constants bound to the data
      store's `Term_ID`s once at validation setup via `find_term`, mirroring
      odin-rdf-sparql's approach — and handling the SHACL asymmetry, where a constant absent
      from the data store makes value nodes **violate** rather than short-circuiting to empty.
- [ ] **Constraint-dispatch seam** shaped for the catalogue initiative to fill: adding a
      constraint component should mean adding a case and its parameters, not touching the
      evaluator.
- [ ] Evaluator is a **stack-driven walk over the flat model** (SHACL-A-0001 decision 4), with
      the on-stack shape set carrying **recursion detection**: a recursive shape is reported
      as a failure, not hung on and not silently accepted.
- [ ] Minimal constraint set implemented: `sh:minCount`, `sh:maxCount`, `sh:class`,
      `sh:datatype`, `sh:nodeKind`, **`sh:in`, and `sh:hasValue`**.

      The last two were added after SHACL-T-0002 vendored the suite and measured what the
      exit-criteria directories actually exercise: `sh:in` is wanted by
      `targets/multipleTargets-001` and `targets/targetClassImplicit-001`, `sh:hasValue` by
      `path/path-complex-001`. Both were listed as non-goals in SHACL-I-0001 on the
      expectation that the spine could green those directories without them; under "enabled
      means fully green" they cannot be skipped. Both are simple value comparisons needing no
      new machinery — this is a scope correction, not a design change.
- [ ] `sh:deactivated` honoured (a deactivated shape produces no results), and `sh:severity`
      carried through to results with `sh:Violation` as the default.
- [ ] **The suite's target and path directories enabled and fully green**, with pinned entry
      counts, no skip list, **against both backends at both `Term_ID` widths**. Enabled means
      fully green — a directory that cannot pass entirely stays disabled and the reason is
      recorded.
- [ ] A recursion test using a shape that references itself via `sh:node`, asserting a
      reported failure. `sh:node` itself is a catalogue constraint; the *detection* is proven
      here because the mechanism belongs to the spine.
- [ ] Allocation guards over the validation hot path.
- [ ] `make test` and `make check` green.

## Implementation Notes

### Technical Approach

Dispatch is a switch over the constraint component in the flat model, executed by the stack
walk. Keeping it a switch rather than a table of procedure pointers is consistent with
SPARQL-T-0011's finding that the family's no-dynamic-dispatch default is free here — and with
its counterweight, that procedure pointers measured as noise if the constraint ever costs more
than it saves.

The minimal constraint set is chosen by what the target and path directories actually
exercise, not by what looks foundational. If vendoring (SHACL-T-0002) shows those directories
need a constraint outside this list, add it here and say so — the alternative is a directory
held out of the exit criteria for one missing component.

### Dependencies

SHACL-T-0002 (suite and harness), SHACL-T-0004 (value nodes), SHACL-T-0005 (focus nodes),
SHACL-T-0006 (results and report). This is the join point — all four must be in.

### Risk Considerations

This is the task where the initiative's exit criteria are actually tested, so it is where
surprises surface. Two to expect:

- **The suite directories may not partition as cleanly as assumed.** If the target and path
  directories turn out to require large parts of the catalogue, the exit criteria need
  restating rather than the catalogue being smuggled in here. Raise it; do not absorb it.
- **The language-tag trigger could fire.** SHACL-I-0001's analysis says it cannot — the
  exposed constraints (`sh:uniqueLang`, `sh:hasValue`, `sh:in`) are all catalogue, and
  `sh:languageIn` is immune by BCP 47 basic filtering. If an entry in an enabled directory
  fails on language-tag case anyway, that analysis was wrong: stop, and take the
  odin-rdf-parser fix to review per the trigger.

## Status Updates **[REQUIRED]**

*To be added during implementation*
