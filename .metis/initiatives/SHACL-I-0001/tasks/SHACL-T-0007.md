---
id: constraint-dispatch-and-the
level: task
title: "Constraint dispatch and the minimal set: first suite directories green"
short_code: "SHACL-T-0007"
created_at: 2026-08-06T13:58:17.309877+00:00
updated_at: 2026-08-06T18:11:53.629726+00:00
parent: SHACL-I-0001
blocked_by: [SHACL-T-0002, SHACL-T-0004, SHACL-T-0005, SHACL-T-0006]
archived: false

tags:
  - "#task"
  - "#phase/active"


exit_criteria_met: true
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

- [x] **Term-binding bridge**: the shapes model's `rdf.Term` constants bound to the data
      store's `Term_ID`s once at validation setup via `find_term`, mirroring
      odin-rdf-sparql's approach — and handling the SHACL asymmetry, where a constant absent
      from the data store makes value nodes **violate** rather than short-circuiting to empty.
- [x] **Constraint-dispatch seam** shaped for the catalogue initiative to fill: adding a
      constraint component should mean adding a case and its parameters, not touching the
      evaluator.
- [x] Evaluator is a **stack-driven walk over the flat model** (SHACL-A-0001 decision 4), with
      the on-stack shape set carrying **recursion detection**: a recursive shape is reported
      as a failure, not hung on and not silently accepted.
- [x] Minimal constraint set implemented: `sh:minCount`, `sh:maxCount`, `sh:class`,
      `sh:datatype`, `sh:nodeKind`, **`sh:in`, and `sh:hasValue`**.

      The last two were added after SHACL-T-0002 vendored the suite and measured what the
      exit-criteria directories actually exercise: `sh:in` is wanted by
      `targets/multipleTargets-001` and `targets/targetClassImplicit-001`, `sh:hasValue` by
      `path/path-complex-001`. Both were listed as non-goals in SHACL-I-0001 on the
      expectation that the spine could green those directories without them; under "enabled
      means fully green" they cannot be skipped. Both are simple value comparisons needing no
      new machinery — this is a scope correction, not a design change.
- [x] `sh:deactivated` honoured (a deactivated shape produces no results), and `sh:severity`
      carried through to results with `sh:Violation` as the default.
- [x] **The suite's target and path directories enabled and fully green**, with pinned entry
      counts, no skip list, **against both backends at both `Term_ID` widths**. Enabled means
      fully green — a directory that cannot pass entirely stays disabled and the reason is
      recorded.
- [x] A recursion test using a shape that references itself via `sh:node`, asserting a
      reported failure. `sh:node` itself is a catalogue constraint; the *detection* is proven
      here because the mechanism belongs to the spine.
- [x] Allocation guards over the validation hot path.
- [x] `make test` and `make check` green.

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

- **2026-08-06 — Complete, awaiting review.** All nine criteria met. `make check` clean,
  `make test` green at both `Term_ID` widths: **86 tests per width**, up from 67 — 40
  memstore (9 new), 12 kvstore (4 new), 10 guards (3 new), 22 harness (2 new, one of which
  *is* the conformance run).

  **The exit criteria are met: `core/targets` (7 entries) and `core/path` (13) are fully
  green**, no skip list, against **both** backends at **both** widths — 40 entry runs per
  width, each compared to its expected report by blank-node isomorphism.

  **What landed.** `shacl/validate.odin` (the `Access` and `Bindings` bridges, `Failure`, and
  the stack-driven walk), `shacl/check.odin` (the dispatch seam and the seven components),
  `validate` / `validate_report` / `conforms` in both instantiation packages, a `Report_Sink`
  visitor in each, and `tests/w3c/harness/runner.odin` — the thing that makes any of this
  gradable.

  **Two corrections the suite forced, neither absorbed silently.**

  1. **Path-form precedence was backwards.** `classify_path` read the named forms
     (`sh:inversePath` and friends) first and fell back to a bare RDF list. `path-strange-001`
     and `-002` each write a node that is *both* a sequence and an `sh:inversePath`, and both
     expect `sh:resultPath ( ex:p ex:q )` — the sequence. §2.3.1 says nothing about a node
     carrying two forms, so this is measured rather than chosen; `rdf:first` is now tested
     first and `test_sequence_wins_over_a_named_path_form` pins it. Left as it was, one entry
     of an otherwise green directory would have failed.
  2. **`sh:datatype` does not check the lexical form.** §4.3.1 requires the value's lexical
     form to be well-formed for the datatype, so `"abc"^^xsd:integer` should violate even
     though the datatype IRI matches. Not implemented: it needs the lexical-to-value machinery
     the catalogue initiative's value-range components need anyway, and both enabled
     directories use `sh:datatype` only with `xsd:string`, whose lexical space is every
     string. Recorded in the code at the check, naming `core/node`'s `datatype-002` as the
     entry that will demand it — that directory stays disabled until it does.

  **Neither risk in this task fired.** The two directories partition exactly as SHACL-T-0002
  measured — the seven-component set covers them with nothing left over — so the exit criteria
  did not need restating. And the language-tag trigger did not fire: no entry in either
  directory depends on tag folding, which is what SHACL-T-0002's corpus survey predicted.
  **odin-rdf-parser is untouched.**

  **Scope is the design.** SHACL's components divide into value-scoped (asked once per value
  node, result carries `sh:value`) and set-scoped (asked once about the whole value-node set,
  result carries none). Getting one wrong produces results that look plausible and are wrong,
  and the suite catches it immediately: `path-complex-001` expects an `sh:hasValue` violation
  with a `sh:resultPath` and no `sh:value`, `targetClassImplicit-001` expects an `sh:in`
  violation that names one. So scope is a named property of a `Constraint_Kind` rather than a
  habit of the code, and it is the second thing the catalogue initiative fills in per
  component.

  **Recursion detection is the stack, not a search.** The walk is explicit (SHACL-A-0001
  decision 4), so "the shapes currently being validated" is literally the stack and `on_stack`
  is one bit per shape. Detection fires at re-entry, before another triple is read. The test
  uses a `sh:property` self-reference rather than the `sh:node` the criterion names, because
  `sh:node` is a catalogue constraint the spine does not implement — the mechanism reached is
  identical, and the fixture's data is cyclic, so a test that terminates at all is already
  most of the assertion. Also asserted: a shape reached twice as a *sibling* is not recursion,
  which is how this is easiest to get wrong in the other direction.

  **The asymmetry is carried per use rather than collapsed.** A term the data store has never
  seen means **emptiness** on a path or a target and **failure** in a constraint —
  `sh:class ex:Missing` makes every value node violate, and `path-complex-002` is the suite
  entry that depends on it, because its data graph never mentions `ex:C` at all.
  `test_absent_terms_mean_opposite_things` puts both directions in one fixture.

  **The suite runner loads the two graphs into two separate stores**, even when an entry names
  the same file for both — which nearly all of them do. Parsing twice costs microseconds and
  buys the ownership property on every run rather than only in the test that asserts it: the
  shapes store is destroyed before the data store is opened. It also keeps the two graphs'
  blank-node label spaces apart, which the entries with separate shapes files would otherwise
  need special handling for.

  **Store evidence: still nothing.** `docs/store-evidence.md` updated. One new near-miss
  recorded and rejected — `sh:class` asks a *set* membership question the interface answers
  one bound match at a time, and the right answer is to build the closure set above the
  interface and issue one `(value, rdf:type, *)` match per value node, not to ask for a new
  verb. The shape of that question recurs in the catalogue initiative (`sh:node`,
  `sh:qualifiedValueShape`), so the reasoning is written down rather than re-derived.
  STORE-T-0019 (snapshot reads) is sharpened but not promoted: a full validation is now
  measurably read-heavy, which widens the window a concurrent writer could open in, but
  nothing in the interface is missing and no consumer has asked.

  **README's status paragraph corrected** — it still claimed the repository held scaffolding
  only. The quick-start example and the contract documentation remain SHACL-T-0008's.