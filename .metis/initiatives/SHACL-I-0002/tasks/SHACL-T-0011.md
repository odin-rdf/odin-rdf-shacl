---
id: suppressed-validation-and-shacl-a
level: task
title: "Suppressed validation, and SHACL-A-0002"
short_code: "SHACL-T-0011"
created_at: 2026-08-06T19:26:49.177301+00:00
updated_at: 2026-08-06T23:01:18.103910+00:00
parent: SHACL-I-0002
blocked_by: [SHACL-T-0010]
archived: false

tags:
  - "#task"
  - "#phase/completed"


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

## Acceptance Criteria

## Acceptance Criteria **[REQUIRED]**

- [x] A way to ask "does this node conform to this shape?" from inside the evaluator, whose
      results do not reach the caller's `Result_Visitor` and do not affect the outer
      `sh:conforms`.
- [x] **SHACL-A-0002 written alongside the mechanism**, not after it, recording the
      representation chosen, the recursion answer below, and what would reopen either.
- [x] **The recursion question answered explicitly**: whether a suppressed sub-validation
      shares the outer walk's on-stack shape set. Both answers are defensible and they give
      different user-visible behaviour for `ex:S sh:not [ sh:node ex:S ]` — one reports
      `Failure.Recursive_Shape`, the other validates. Decide with the spec and the suite in
      front of you, record the reasoning, and test the case either way.
- [x] Early exit still works and still means what it meant. An inner conformance check wants
      to stop at its first result; the outer traversal must not be stopped by it. Asserted by
      a test, because getting this wrong silently truncates a real validation.
- [x] Memory stays bounded: a suppressed run allocates per branch per value node and must
      return all of it. Allocation guard over nested suppression, including the abnormal exits
      — this is the easiest place in the engine to strand memory.
- [x] No consumer yet. This task adds the mechanism, a guard, and unit tests using a
      hand-built shapes model; `sh:not` and friends arrive in SHACL-T-0017 and SHACL-T-0018.
- [x] Tests at both widths against both backends; `make test` and `make check` green.

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

- **2026-08-06 — Implemented; SHACL-A-0002 decided; awaiting review.** `make test` green at
  both `Term_ID` widths, `make check` green. New: `shacl/suppress.odin` (the mechanism),
  `shacl/suppress_test.odin` (eight tests over a hand-built model and a fake store),
  `.metis/adrs/SHACL-A-0002.md`. Changed: `validate.odin` (`validation_init`/`_destroy` split
  out, `validate_focus` widened to package-private), both instantiation packages
  (`conforms_node`), `tests/guards`, `tests/readme`.

  **The mechanism: swap the visitor on the in-flight `Validation`.** `node_conforms` saves
  `visit`, `visit_data`, and `stopped`, installs a probe that records one bit and returns
  false, runs the ordinary `validate_focus`, and restores the three. Everything else is shared
  by construction — model, bindings, access, allocator, the subclass-closure cache, the
  recursion set, and `failure`.

  **The alternative worth recording is the one that looked safest: copying the `Validation`.**
  It is not merely costlier, it is wrong. `classes` holds dynamic arrays the inner run appends
  to, so the outer's copy would keep stale headers and, after a reallocation, dangling ones —
  corrupted class closures under nesting, surfacing far from the cause. Value semantics on a
  struct of dynamic arrays isolates the headers, not the storage.

  **The recursion question, answered: share the outer walk's `on_stack`.** The argument that
  decided it is not which reading of §3.4 is nicer — both are defensible and the spec leaves
  it undefined — but that the alternative **does not terminate**. With a fresh set per
  suppressed run, `ex:S sh:not [ sh:node ex:S ]` enters `ex:S`, reaches `sh:not`, starts a
  sub-run with an empty set, and enters `ex:S` again, forever. Once a fresh set is out, a
  snapshot copy is behaviourally identical to sharing while adding an allocation and a
  write-back to get wrong. So: sharing, and that graph reports `Failure.Recursive_Shape`.

  Sharing also supplies the memory bound the task asked for, and it is a better one than
  expected: a shape cannot appear twice on the stack, so **nesting depth is bounded by
  `len(s.shapes)`, not by anything about the data**. That is what makes this safe to call per
  value node, which is what `sh:qualifiedValueShape` will do.

  **Testing a mechanism with no consumer — the problem this task actually posed.** The two
  properties that matter (nothing leaks into the caller's stream; an inner stop does not stop
  the outer) are about an in-flight `Validation`, which no public entry point exposes. So the
  tests live in package `shacl` itself, with a fake `Access` — four procedure pointers over a
  hand-built triple list — and a `Shapes` built field by field. A test in that package can
  construct a `Validation` and call `node_conforms` directly, which is the only way to assert
  the save/restore at all. Eight tests: the answer both ways, the nested `sh:property` case,
  no leakage, `stopped` restored, a stopped traversal staying stopped, the recursion case, the
  on-stack set left clean, and suppressed runs nesting inside each other.

  **A public entry point was added, and it is a scope judgement worth flagging.**
  `conforms_node` in the core plus a wrapper per backend. Two reasons: it is a coherent
  primitive (§3.4's own question, which the whole-graph `conforms` cannot express), and
  without it the engine's newest and least-covered capability would go two tasks with **no
  backend-level test at all** — the "both backends, both widths" criterion has nothing to bite
  on otherwise. Reasoning recorded in the ADR rather than only here.

  **Two documentation bugs found while reading, and fixed.** Both instantiation packages
  documented `conforms` as stopping at the first `sh:Violation` with "a warning does not break
  conformance (§3.1.2)" — which contradicts `result.odin`, the spec, and `misc/severity-001`,
  the entry that produces one `sh:Warning` and expects `sh:conforms false`. The code was
  always right; three comments and the README were wrong.

  Also: the README's new `conforms_node` example is compiled by `tests/readme`, per the
  family's README-as-contract rule, and the package doc now lists five caller contracts.

- **2026-08-06 — Review outcome (Greger): defaults taken.** `conforms_node` stays public;
  the hand-built test is scaffolding to be revisited at SHACL-T-0017 (added there as an
  acceptance criterion, with the drift risk named); the `conforms` severity documentation fix
  was split into its own commit ahead of this one.

  **`shape_index_of` added to the core**, taking an `rdf.Term` and returning `(index, found)`.
  The evidence was already in the tree: five places were finding a shape by IRI by hand — two
  `find_shape` helpers and one loop that predate this task, plus two more I had just written,
  plus the README example. All six now go through one implementation. The doc comment states
  why shapes are still named by *index* rather than by term: every `sh:property [ ... ]` is a
  blank node whose label is the parser's business, so the index names all shapes and the term
  lookup serves only the ones an author gave an IRI to.