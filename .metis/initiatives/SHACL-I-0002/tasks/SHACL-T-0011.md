---
id: suppressed-validation-and-shacl-a
level: task
title: "Suppressed validation, and SHACL-A-0002"
short_code: "SHACL-T-0011"
created_at: 2026-08-06T19:26:49.177301+00:00
updated_at: 2026-08-06T19:26:49.177301+00:00
parent: SHACL-I-0002
blocked_by: [SHACL-T-0010]
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: SHACL-I-0002
---

# Suppressed validation, and SHACL-A-0002

## Parent Initiative

[[SHACL-I-0002]]

## Objective **[REQUIRED]**

Give the engine the one capability it does not have: validating a node against a shape and
learning whether it conformed **without emitting that shape's results**. Six components need
it — `sh:not`, `sh:or`, `sh:xone`, and the three qualified parameters — and the whole reason
this task comes third rather than eighth is that shaping the mechanism around whichever of
them lands first is how it goes wrong. Carries **SHACL-A-0002**.

## Acceptance Criteria **[REQUIRED]**

- [ ] A way to ask "does this node conform to this shape?" from inside the evaluator, whose
      results do not reach the caller's `Result_Visitor` and do not affect the outer
      `sh:conforms`.
- [ ] **SHACL-A-0002 written alongside the mechanism**, not after it, recording the
      representation chosen, the recursion answer below, and what would reopen either.
- [ ] **The recursion question answered explicitly**: whether a suppressed sub-validation
      shares the outer walk's on-stack shape set. Both answers are defensible and they give
      different user-visible behaviour for `ex:S sh:not [ sh:node ex:S ]` — one reports
      `Failure.Recursive_Shape`, the other validates. Decide with the spec and the suite in
      front of you, record the reasoning, and test the case either way.
- [ ] Early exit still works and still means what it meant. An inner conformance check wants
      to stop at its first result; the outer traversal must not be stopped by it. Asserted by
      a test, because getting this wrong silently truncates a real validation.
- [ ] Memory stays bounded: a suppressed run allocates per branch per value node and must
      return all of it. Allocation guard over nested suppression, including the abnormal exits
      — this is the easiest place in the engine to strand memory.
- [ ] No consumer yet. This task adds the mechanism, a guard, and unit tests using a
      hand-built shapes model; `sh:not` and friends arrive in SHACL-T-0017 and SHACL-T-0018.
- [ ] Tests at both widths against both backends; `make test` and `make check` green.

## Implementation Notes

### Technical Approach

The candidates, to be weighed in the ADR rather than assumed here: a nested `validate` with a
counting visitor and a null sink; a `Conformance` sub-run that shares the outer walk's stack;
or a flag on the frame that suppresses emission for a subtree. The third is cheapest and the
most likely to leak state; the first is cleanest and duplicates the walk.

Whatever is chosen, it has to survive the constraint that made the evaluator what it is: this
is non-generic code reached through procedure pointers, so ordinary recursion is available —
but the flat model and the explicit stack are not optional (SHACL-A-0001 decision 4).

### Dependencies

SHACL-T-0010 — nesting is only reachable once shape discovery recognises the parameters that
nest.

### Risk Considerations

**This is the task most likely to be got subtly wrong and not noticed**, because no suite entry
exercises it until SHACL-T-0017 lands. Its tests are therefore unit tests over hand-built
models, and they carry more weight than usual. Write the case where a suppressed run *would*
have produced results and assert the caller saw none — the failure mode is silent leakage into
someone's report.

**The recursion answer may turn out to be a spec question with no clean answer.** If both
readings are defensible and the suite does not settle it, record that plainly in the ADR and
pick the one that fails loudly rather than the one that guesses.

## Status Updates **[REQUIRED]**

*To be added during implementation*
