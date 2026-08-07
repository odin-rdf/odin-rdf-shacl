---
id: the-memoisation-decision-and-shacl
level: task
title: "The memoisation decision, and SHACL-A-0002's amendment"
short_code: "SHACL-T-0025"
created_at: 2026-08-07T11:34:44.535089+00:00
updated_at: 2026-08-07T11:34:44.535089+00:00
parent: SHACL-I-0003
blocked_by: [SHACL-T-0023]
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: SHACL-I-0003
---

# The memoisation decision, and SHACL-A-0002's amendment

## Parent Initiative

[[SHACL-I-0003]]

## Objective **[REQUIRED]**

Pull the review trigger SHACL-A-0002 left. Measure the duplicated conformance work, decide
whether a `(shape, node)` cache is justified, implement it **only if the numbers say so**,
and write the outcome back into the ADR either way.

**Either answer is a deliverable.** "The trigger was pulled, here are the numbers, no cache
was warranted" closes the question as firmly as the opposite, and it is the answer the
design phase went to some trouble to keep reachable.

## Acceptance Criteria **[REQUIRED]**

- [ ] **The duplicate is measured, not argued.** Reads and wall clock for a configuration
      that exercises the qualified family, against the same configuration with it absent —
      the knob [[SHACL-T-0023]] was required to expose.
- [ ] **The decision is made on the numbers**, with the reasoning recorded: how many reads
      a cache would avoid, on what shape of workload, and at what hot-path cost.
- [ ] **SHACL-A-0002 is amended with the outcome**, in the shape of SHACL-A-0001's "As
      Built" sections — the numbers, the decision, and the date. The ADR currently carries
      a review trigger with nothing behind it; after this it carries an answer.
- [ ] **If and only if the cache is justified**: implemented as a `(shape, node)` cache in
      `Validation`, with the W3C suite still **98 of 98** against both backends at both
      `Term_ID` widths, `make check` green, and `tests/guards` still net-zero — a cache is
      exactly the sort of thing that strands memory on an abnormal exit.
- [ ] **If the cache lands, the read-count invariants are re-established.** A cache changes
      how many reads a validation makes; it must change them *identically* on both backends
      and at both widths, or the invariant [[SHACL-T-0023]] asserts has become a bug report.
- [ ] **If the cache does not land**, `docs/store-evidence.md`'s standing note about the
      structural duplicate is updated to say it was measured and found not to matter,
      rather than left reading as an open concern.

## Implementation Notes **[CONDITIONAL: Technical Task]**

### Technical Approach

The duplicate is structural and provable from the code without measuring anything: a
qualified property shape carrying both `sh:qualifiedMinCount` and `sh:qualifiedMaxCount`
shares one `sh:qualifiedValueShape`, and the two constraints walk the same value nodes
against the same shape independently. `sh:qualifiedValueShapesDisjoint` multiplies it by
the sibling count. SHACL-T-0018 found it; `docs/store-evidence.md` records it.

What is *not* provable from the code is whether it matters, which is the whole reason
SHACL-A-0002 said measured.

### Dependencies

[[SHACL-T-0023]] for the instrument. [[SHACL-T-0024]]'s baselines are what a cached run
would be compared against.

### Risk Considerations

**The measurement must be able to say no, and the easiest way to fail this task is to
build a workload that cannot.** A configuration tuned to stress the qualified family will
endorse the cache whatever the truth is. The qualified family is the least-used corner of
SHACL Core; a cache costs a map lookup on the engine's hot path, on *every* suppressed
check, to save work that may be rare in the shapes graphs people actually write. The
configuration without it is the control, and the decision is not defensible without it.

**This is the class of optimisation that sounds obviously right.** The duplicate is real,
provable, and visible in the source — which is exactly why SHACL-A-0002 declined to act on
it and why acting on it now without numbers would be repeating the mistake the ADR
avoided.

**A cache interacts with the abnormal exits.** Early stop and recursion failure unwind by
hand, and anything added to `Validation` has to unwind with them. `tests/guards`'
`test_early_exit_and_recursion_unwind_cleanly` is the guard that would catch it, and it
should be checked deliberately rather than assumed from a green run.

## Status Updates **[REQUIRED]**

*To be added during implementation*
