---
id: logical-combinators-sh-and-sh-or
level: task
title: "Logical combinators: sh:and, sh:or, sh:not, sh:xone"
short_code: "SHACL-T-0017"
created_at: 2026-08-06T19:27:15.200590+00:00
updated_at: 2026-08-06T19:27:15.200590+00:00
parent: SHACL-I-0002
blocked_by: [SHACL-T-0011]
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: SHACL-I-0002
---

# Logical combinators: sh:and, sh:or, sh:not, sh:xone

## Parent Initiative

[[SHACL-I-0002]]

## Objective **[REQUIRED]**

The logical combinators — `sh:and`, `sh:or`, `sh:not`, `sh:xone` (§4.9). The first consumers of
suppressed validation, and the task that proves SHACL-T-0011's mechanism against real suite
entries rather than hand-built models.

## Acceptance Criteria **[REQUIRED]**

- [ ] All four implemented, each taking an RDF list of shapes (`sh:not` takes one shape) and
      evaluating each value node against them through suppressed validation.
- [ ] **None of the inner shapes' results reaches the caller.** A `sh:not` whose inner shape
      produced fifty results contributes one result of its own and forty-nine that nobody sees.
      Asserted directly, not inferred from a matching report.
- [ ] `sh:xone` is exactly-one, not at-least-one, and the test distinguishes them.
- [ ] Result shape per component measured against the suite: which name a `sh:value`, and what
      `sh:sourceShape` points at when the failing shape is a nested blank node.
- [ ] Nesting works: a combinator inside a combinator, which is where a suppression mechanism
      that leaks state fails first.
- [ ] The recursion behaviour SHACL-A-0002 decided is exercised by a real shapes graph here,
      whichever way it was decided.
- [ ] The progress floor moves substantially and the new figure is pinned.
- [ ] Tests at both widths against both backends; `make test` and `make check` green.

## Implementation Notes

### Technical Approach

Each combinator is a case in `check_value` that runs suppressed validations and combines
booleans; the machinery is SHACL-T-0011's and this task should not need to change it. If it
does, that is the signal that the ADR's design was shaped by too little contact with its
consumers — record it rather than patching around it.

### Dependencies

SHACL-T-0011 (suppressed validation and SHACL-A-0002) and, through it, SHACL-T-0010 (widened
discovery, without which the nested shapes are not shapes).

### Risk Considerations

**This is where SHACL-T-0011 gets its real test.** If suppression leaks — into the caller's
report, into `sh:conforms`, or across nested runs — this is the task that finds out, and the
fix belongs in the mechanism rather than in the combinators.

## Status Updates **[REQUIRED]**

*To be added during implementation*
