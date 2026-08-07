---
id: logical-combinators-sh-and-sh-or
level: task
title: "Logical combinators: sh:and, sh:or, sh:not, sh:xone"
short_code: "SHACL-T-0017"
created_at: 2026-08-06T19:27:15.200590+00:00
updated_at: 2026-08-07T09:50:56.360617+00:00
parent: SHACL-I-0002
blocked_by: [SHACL-T-0011]
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: SHACL-I-0002
---

# Logical combinators: sh:and, sh:or, sh:not, sh:xone

## Parent Initiative

[[SHACL-I-0002]]

## Objective **[REQUIRED]**

The logical combinators — `sh:and`, `sh:or`, `sh:not`, `sh:xone` (§4.6). The first consumers of
suppressed validation, and the task that proves SHACL-T-0011's mechanism against real suite
entries rather than hand-built models.

## Acceptance Criteria

## Acceptance Criteria **[REQUIRED]**

- [x] All four implemented, each taking an RDF list of shapes (`sh:not` takes one shape) and
      evaluating each value node against them through suppressed validation.
- [x] **None of the inner shapes' results reaches the caller.** A `sh:not` whose inner shape
      produced fifty results contributes one result of its own and forty-nine that nobody sees.
      Asserted directly, not inferred from a matching report.
- [x] `sh:xone` is exactly-one, not at-least-one, and the test distinguishes them.
- [x] Result shape per component measured against the suite: which name a `sh:value`, and what
      `sh:sourceShape` points at when the failing shape is a nested blank node.
- [x] Nesting works: a combinator inside a combinator, which is where a suppression mechanism
      that leaks state fails first.
- [x] The recursion behaviour SHACL-A-0002 decided is exercised by a real shapes graph here,
      whichever way it was decided. Shared `on_stack` was the decision, so
      `ex:S sh:not [ sh:node ex:S ]` must report `Failure.Recursive_Shape`.
      *(Adapted: `sh:node` is SHACL-T-0018's, so the graph is `ex:S sh:not ex:S` — the same
      shared-`on_stack` bit, one level shallower.)*
- [x] **`shacl/suppress_test.odin`'s hand-built model reviewed once the real consumers exist**
      (Greger, 2026-08-06). It was written as scaffolding: the leakage and stop-restoration
      properties were unreachable through any public entry point at SHACL-T-0011, so they are
      asserted against a `Shapes` built field by field and a fake `Access`. Re-assert both
      through `sh:not` on a real shapes graph here, then decide whether the hand-built version
      still earns its place or is deleted. The risk it carries is drift: nothing checks that
      hand-built model against what `compile` actually produces.
      *(Kept. Reasoning written into that file's header.)*
- [x] The progress floor moves substantially and the new figure is pinned. *(51 → 63.)*
- [x] Tests at both widths against both backends; `make test` and `make check` green.

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

- **2026-08-07 — Started; corpus read first.** Eleven entries: `core/node`'s and-001,
  and-002, not-001, not-002, or-001, xone-001, xone-duplicate; `core/property`'s and-001,
  not-001, or-001, or-datatypes-001.

  **All four are value-scoped and uniform**, which is the good news and unusual for this
  initiative: one result per failing value node, naming it in `sh:value`, with the shape's
  own path as `sh:resultPath` and `sh:sourceShape` the shape *carrying* the combinator —
  never the branch that failed. `property/and-001` and `or-datatypes-001` pin the property
  case; `node/*` pin the node case where value node and focus node coincide.

  **`xone-duplicate` is the entry that earns its name**: `sh:xone ( ex:s2 ex:s2 )` over
  `ex:i` (conforms to neither copy) and `ex:j` (conforms to both). Both report. An
  at-least-one reading passes `ex:i` and fails `ex:j`; a count-distinct reading passes both.

  Plan: a `Constraint.shapes` span into `Shapes.shape_children`, filled in a pass after the
  `sh:property` fixup — the same shape SHACL-T-0016 needed, and for the same reason: shape
  indices do not exist until every shape is compiled. Evaluation is four cases over
  `node_conforms`, which is SHACL-T-0011's mechanism used rather than changed.

  Two decisions this task inherits and must now make:

  - **A malformed `sh:and` / `sh:or` / `sh:xone` list.** `compile.odin`'s discovery skips
    one today with a comment saying the question belongs to this task. Answer: an error,
    consistent with `sh:in`, `sh:languageIn`, and `sh:ignoredProperties`. One error kind for
    all three, since the `Error` names the parameter.
  - **`shacl/suppress_test.odin`'s hand-built model** — reviewed here per the acceptance
    criterion.

- **2026-08-07 — Found while reading §4: the repository's spec section numbers are wrong,
  and not only here.** Confirmed against the Recommendation's table of contents. The real
  numbering is 4.1 value type, 4.2 cardinality, 4.3 value range, 4.4 string-based, 4.5
  property pair, 4.6 logical, 4.7 shape-based, 4.8 other (4.8.1 `sh:closed`, 4.8.2
  `sh:hasValue`, 4.8.3 `sh:in`). About thirty citations across `shacl/`, plus SHACL-A-0002
  and this initiative, name a different section — `sh:class` as §4.4.1 rather than §4.1.1,
  `sh:in` as §4.6.1 rather than §4.8.3, the string family as §4.5 rather than §4.4, and so
  on. Only cardinality, `sh:closed`, `sh:or` and `sh:xone` happen to be right.

  It is a documentation defect, not a behavioural one, but the numbers are cited as
  authority — several are in `error_message`, which is public API text. Handled as a
  separate, clearly-delimited sweep after this task's implementation, so it can be dropped
  without touching the component work.

- **2026-08-07 — Implemented; awaiting review.** All four combinators validate. Progress
  floor **51 → 63**, the largest single move of the initiative: `core/node` 24 → **31 of
  32**, `core/property` 27 → **32 of 38**. `make test` green at both widths against both
  backends; `make check` and the purity check green.

  **Twelve entries, not the eleven predicted.** `property/datatype-003` is an `sh:or`
  entry named after what its branches contain, so counting the family by filename
  undercounts it by one. Recorded because the same trap applies to SHACL-T-0018's count.

  **SHACL-T-0011's mechanism needed no change**, which was this task's stated success
  condition — "if it does, that is the signal that the ADR's design was shaped by too
  little contact with its consumers". `suppress.odin` is untouched; `check_logical` is
  sixty lines of `node_conforms` and boolean combination.

  **One thing did change, in `check_shape`, and it is worth stating rather than
  absorbing.** The constraint loop checked `v.stopped` and not `v.failure`. That was sound
  for the whole spine: the only failure is shape recursion, which `push_frame` raises
  *after* `check_shape` has run, so nothing there could ever observe one. A suppressed run
  raises it from *inside* a constraint check, and the constraints after it would have kept
  reporting into a report the caller must already discard. One clause — a latent assumption
  a new capability exposed, rather than a bug the combinators introduced.

  **Compilation needed the same second pass `sh:closed` did, for a sharper reason.** A
  combinator's operands are *other shapes*, and a shape's index does not exist until the
  worklist has drained — `sh:and ( ex:A ex:B )` may name shapes compiled later, or itself.
  So `compile_constraints` creates the constraint (it must: `Shape.constraints` is a
  contiguous span) and `compile_shape_operands` fills `Constraint.shapes` after the
  `sh:property` fixup. The two halves pair by ordinal — the k-th `.And` constraint on a
  shape is the k-th value of `sh:and` on its node — which holds because both read the same
  parameter of the same shape from the same store, and is stated at the procedure because
  it is the one coupling between them.

  **The inherited decision, answered.** A malformed `sh:and`/`sh:or`/`sh:xone` list is an
  ill-formed shapes graph (`Error_Kind.Shape_List_Not_A_List`), consistent with `sh:in`,
  `sh:languageIn` and `sh:ignoredProperties`. One kind for the three, since the `Error`
  already names the parameter. Discovery keeps skipping a list it cannot walk and the
  operand pass errors on it, so the decision lives in one place rather than two.

  **Empty lists**, which no corpus entry writes: the conjunction of nothing holds, the
  disjunction of nothing does not, exactly-one of nothing does not. All three fall out of
  the loops rather than being special-cased, and are recorded at the procedure.

  **Tests, and a check that they bite.** Six unit tests in `shacl/memstore`, and the
  implementation was broken three ways to confirm they are not decorative: weakening
  `sh:xone` to at-least-one fails `test_xone_is_exactly_one` and drops `core/node` from 31
  to 29; making `node_conforms` leak the caller's visitor fails **seven** tests; dropping
  the `stopped` restore fails five. The leakage test was rewritten after the first pass —
  it originally expected zero results, which an engine where `sh:not` did nothing would
  also produce, so it now expects exactly one from a second `sh:not` that genuinely fires.

  **`shacl/suppress_test.odin` reviewed, and kept.** The drift risk it carried is now
  covered from the other side: two of the new memstore tests assert the same properties
  through a compiled shapes graph on a real backend. What is left there is genuinely
  unreachable from outside — the assertions name `v.visit`, `v.visit_data`, `v.stopped`,
  `v.on_stack` and `Suppressed_Probe` directly, and SHACL-A-0002 records the save/restore
  as a discipline rather than a type, so those are what would notice a field added to the
  caller's stream and not to `node_conforms`. Reasoning written into that file's header
  rather than left here.

  **A finding for SHACL-T-0018 and SHACL-T-0019, pinned in `suite.odin`.** Six entries
  remain and only five are SHACL-T-0018's. **`core/property/nodeKind-001` uses nothing
  beyond the spine** — six plain `sh:nodeKind` property shapes — and has been red since the
  floor was first measured. Enabling `core/property` therefore needs it diagnosed as well
  as the shape-based constraints landed, and SHACL-T-0019 must not assume the catalogue
  closing is enough. Not chased here: it is outside this task, and the first place to look
  is report comparison rather than the engine — its expected report carries eighteen
  results whose `sh:sourceShape` are shapes-graph blank nodes and whose `sh:value` are
  *data*-graph blank nodes, which is the hardest isomorphism case in the corpus and the
  shape of the harness defect SHACL-T-0012 already found once.

  **Store evidence: nothing new asked, but the read volume changed.** A suppressed run
  makes only reads the engine already made, so no capability is wanted. What is new is the
  multiplier — a whole sub-walk per branch per value node, nesting — so a validation's read
  count is now proportional to the shapes graph times the data. Recorded under STORE-T-0019
  in `docs/store-evidence.md`, with the note that the likelier answer is memoisation here
  than a snapshot verb upstream.