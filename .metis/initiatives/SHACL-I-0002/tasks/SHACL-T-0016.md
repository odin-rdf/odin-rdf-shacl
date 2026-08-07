---
id: sh-closed-and-sh-ignoredproperties
level: task
title: "sh:closed and sh:ignoredProperties, and the store evidence it produces"
short_code: "SHACL-T-0016"
created_at: 2026-08-06T19:27:10.389847+00:00
updated_at: 2026-08-07T09:28:49.502666+00:00
parent: SHACL-I-0002
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: SHACL-I-0002
---

# sh:closed and sh:ignoredProperties, and the store evidence it produces

## Parent Initiative

[[SHACL-I-0002]]

## Objective **[REQUIRED]**

`sh:closed` and `sh:ignoredProperties` (§4.8.1) — the component that asks the store a question
the spine never asked: which predicates a focus node actually *uses*. Small by entry count and
disproportionately interesting, because it is the likeliest source of new store evidence in
this initiative.

## Acceptance Criteria

## Acceptance Criteria **[REQUIRED]**

- [x] `sh:closed true` violates for every triple whose predicate is neither declared by one of
      the shape's property shapes nor listed in `sh:ignoredProperties`.
- [x] The result names the offending predicate and value the way the suite expects — measured
      against `core/node`'s entries, not assumed.
- [x] The "predicates in use" read is a wildcard-predicate match from the focus node through
      the published interface, with the graph bound. **If it wants something the interface
      cannot answer, that goes in `docs/store-evidence.md` with the shape that wants it** — and
      it is a proposal for review, never a backend-specific workaround.
- [x] `sh:ignoredProperties` compiles as an RDF list of predicate IRIs, like `sh:in`'s members.
- [x] The set of declared predicates comes from the shape's property shapes whose path is a
      **predicate path**; a shape whose path is a sequence or an inverse declares no single
      predicate, and what the spec says about that is checked rather than guessed.
- [x] The progress floor moves and the new figure is pinned.
- [x] Tests at both widths against both backends; `make test` and `make check` green.

## Implementation Notes

### Technical Approach

Set-scoped: asked once per focus node about everything the node asserts, not once per value
node. The interesting part is the model question — "which predicates does this shape declare"
is a property of the shape's children, which the flat model can answer at compile time and
cache rather than recompute per focus node.

### Dependencies

None. Independent; can run in parallel with the other mechanical families.

### Risk Considerations

**This is the store-evidence task.** Its risk is not failure but silence: doing the work, using
the interface, and forgetting to record what the experience was. The evidence log has been
open since SHACL-T-0005 and has found nothing; a genuine finding here would be the first, and
a genuine non-finding is also a result worth writing down.

## Status Updates **[REQUIRED]**

- **2026-08-07 — Started; corpus read first, and it settled the shape of the work.**
  `node/closed-001` and `closed-002` are the only two entries in `core/node` and
  `core/property`; `core/complex`'s `personexample.ttl` and `shacl-shacl-data-shapes.ttl`
  use the component too and are not enabled.

  **The detail the corpus supplied, and it is a `Result` change rather than a component
  detail.** A `sh:closed` result carries `sh:resultPath <the offending predicate>` and
  `sh:value <the offending object>`. `Result.path` is an index into `Shapes.paths`, so it
  cannot say that: the predicate is a term of the **data** graph and not a compiled path at
  all. `closed-001` is on a node shape, whose `path` is -1, so a report that omitted
  `sh:resultPath` entirely would be wrong in a way nothing else in the engine is.

  Plan, in the seam's order plus the two edits it does not cover:

  1. Vocabulary: `sh:closed`, `sh:ignoredProperties`, `sh:ClosedConstraintComponent`.
  2. `Constraint_Kind.Closed`, scope `.Value` — §4.8.1 is per *value node* as the subject.
  3. Compilation in two halves: the boolean in `compile_constraints`, and the **allowed
     predicate set** in a pass after the `sh:property` fixup, because a shape's children
     are not linked when its own constraints are compiled. The set is
     `sh:ignoredProperties` ∪ the IRI predicate paths of the shape's property shapes,
     appended contiguously to `Shapes.values` so `bindings_init` binds it like `sh:in`'s.
  4. `Result.path_predicate` / `has_path_predicate`, and `report_add` preferring it.
  5. **A fifth `Access` verb.** `Scan` yields one quad position and `Step` yields nodes;
     `sh:closed` wants (predicate, object) *pairs* for one subject, which neither can
     express. This is the store-evidence question, and the answer looks like it will be
     that the gap is in this package's own adapter rather than in the store — the
     published `match` returns whole quads.

- **2026-08-07 — Implemented; awaiting review.** `sh:closed` and `sh:ignoredProperties`
  validate. `node/closed-001` and `closed-002` go green: `core/node` 22 → 24, progress
  floor **49 → 51**. `core/complex` unchanged at 1 of 2, still pinned at 0. `make test`
  green at both widths against both backends; `make check` and the purity check green.
  Eighteen entries of the original fifty-one remain, all behind SHACL-T-0017 and
  SHACL-T-0018.

  **The store evidence, which is the point of this task.** Written up in
  `docs/store-evidence.md`. The prediction held and the question underneath it did not.
  The store was asked for the outgoing triples of one node — `(node, *, *, graph)`, two
  positions bound — and `match` served it unchanged on both backends, returning whole
  `Encoded_Quad`s so the predicate and the object arrive together. No new store
  capability was wanted, none is used, and **STORE-T-0016 is now retired rather than
  merely unexercised**: `sh:closed` was the last thing the vision predicted would want
  graph introspection, and it does not.

  **What did not serve it was `Access`, which is ours.** Its three read verbs each yield
  *one* position of a matched quad, and this component needs two of the same quad; no
  composition of `Scan` and `Step` gives a pair. So `Access` gained a fourth verb,
  `Outgoing`, and each instantiation package an eight-line adapter around the `match` it
  already calls. That is the first real finding this log has produced in twelve tasks,
  and it is a narrowing **we** wrote — one that predated any consumer that strained it,
  which is how a narrowing quietly becomes the constraint. Recorded because a less
  careful engine would have found `Access` insufficient and filed it upstream as a store
  gap.

  **Three things the corpus decided that the obvious implementation gets wrong.**

  1. **The result path is a data-graph term.** `sh:resultPath` is the offending triple's
     predicate and `sh:value` its object. `Result.path` is an index into `Shapes.paths`
     and cannot say that, and `closed-001` puts it on a *node* shape whose path is -1 —
     so a report that fell back on `path` would omit `sh:resultPath` entirely. `Result`
     gained `path_predicate` / `has_path_predicate`, `emit_result` two defaulted
     parameters, and `report_add` a branch. It is the first `Result` change since the
     spine and it is now a documented caller contract.
  2. **`rdf:type` is not ignored by default.** `closed-001` reports it; `closed-002` is
     the same data with `sh:ignoredProperties ( rdf:type )` and one result instead of
     two. Assuming the default would still pass `closed-002`.
  3. **A result per offending *triple***, not per offending predicate.

  **The model question resolved as the task predicted, but not where.** The allowed set
  is a property of the shape's children, so it is computed once at compile time — and it
  cannot be computed where every other constraint parameter is, because a shape's
  `sh:property` children are linked by index in a fixup pass *after* every shape is
  compiled. So the component compiles in two halves: the boolean in
  `compile_constraints`, the set in `compile_closed_sets` after the fixup, appended
  contiguously to `Shapes.values` so `bindings_init` resolves it to data-store IDs with
  no case of its own. It is the only compile error raised away from where its parameter
  is read, which is why `Ignored_Properties_Not_A_List` has a test.

  **The predicate-path question, checked rather than guessed.** A property shape declares
  a predicate only when its path is a bare predicate IRI. A sequence or an inverse is a
  blank node in the shapes graph and a triple's predicate is always an IRI, so such a
  path can never name one — the spec defines the allowed set through
  `sh:property/sh:path` and the behaviour falls out rather than needing a rule. The case
  is real: `core/complex`'s `personexample.ttl` closes a shape one of whose property
  shapes has `sh:path [ sh:inversePath ex:worksFor ]`. Pinned in a unit test, since no
  enabled entry reaches it.

  **Two judgement calls, flagged rather than absorbed.**

  - **Scope is `.Value`, not `.Node_Set`** — which contradicts this task's own Technical
    Approach note ("set-scoped: asked once per focus node"). §4.8.1's textual definition
    is per *value node*: the value node is the subject whose triples are inspected. The
    two readings are indistinguishable on a node shape, which is every entry in the
    corpus, so nothing measures it. I could not obtain a reliable verbatim read of the
    textual definition — three fetches of the Recommendation returned paraphrases, one of
    them self-contradictory — so this follows the value-node reading and pins it in a
    unit test that puts `sh:closed` on a property shape. **Worth a second opinion.**
  - **`sh:closed` is switched on by the term `"true"^^xsd:boolean` and nothing else**,
    which is `sh:uniqueLang`'s reading extended to identical wording. Nothing in the
    corpus measures it here, and the tension is the one already recorded at
    `sh:uniqueLang`: §4.8.1's prose says "if sh:closed is true", the spec's normative
    SPARQL says `FILTER ($closed)`, and the two disagree about `"1"^^xsd:boolean`. Chose
    engine-internal consistency over a coin flip, since one of the two readings already
    has a suite entry behind it.

  **Files touched.** `shacl/`: vocab, model, error, constraints, compile, check, validate,
  result, report; `shacl/memstore/` and `shacl/kvstore/`: eval (the adapter) and validate
  (the wiring). Tests: `memstore/compile_test.odin` (two ill-formed cases),
  `memstore/validate_test.odin` (`test_closed`, and a fifth field in `record` written only
  where there is one). Docs: `docs/store-evidence.md`, `README.md`, the package doc's
  contract list, `tests/w3c/harness/suite.odin`. Nothing upstream was touched.