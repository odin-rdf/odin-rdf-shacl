---
id: close-the-catalogue-core-node-and
level: task
title: "Close the catalogue: core/node and core/property green, docs, and the write-ups"
short_code: "SHACL-T-0019"
created_at: 2026-08-06T19:27:22.833772+00:00
updated_at: 2026-08-07T10:38:44.642977+00:00
parent: SHACL-I-0002
blocked_by: [SHACL-T-0013, SHACL-T-0014, SHACL-T-0015, SHACL-T-0016, SHACL-T-0017, SHACL-T-0018]
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: true
initiative_id: SHACL-I-0002
---

# Close the catalogue: core/node and core/property green, docs, and the write-ups

## Parent Initiative

[[SHACL-I-0002]]

## Objective **[REQUIRED]**

Close the initiative: enable `core/node` and `core/property`, verify each exit criterion by a
run rather than an assertion, document the components to the family contract standard, and
refresh the two standing write-ups for review. The spine's SHACL-T-0008 is the model, including
its finding that verification is not a formality — it found three shipped bugs.

## Acceptance Criteria **[REQUIRED]**

- [x] **`core/node` (32) and `core/property` (38) enabled and fully green**, pinned counts, no
      skip list, both backends, both `Term_ID` widths. A directory that cannot pass entirely
      stays disabled and the reason is recorded.
- [x] The progress floor from SHACL-T-0009 is **retired or reduced to the directories still
      disabled** — a floor over a green directory is noise.
- [x] Every new exported symbol documented; the `shacl` package doc's memory contract updated
      for whatever suppressed validation added; the constraint-component list in the README and
      the package doc brought up to date.
- [x] The ignored-parameter record is **empty for every enabled directory**, asserted — the
      check SHACL-T-0010 added, now meaning what it was built to mean.
- [x] `tests/readme` still compiles and still asserts; if the API changed, the README changed.
- [x] **Store-evidence write-up refreshed for review.** The log has been open since
      SHACL-T-0005 and found nothing through the spine; `sh:closed` and the shape-based
      constraints are the likeliest places for a first finding. Empty is a fine answer if it is
      said plainly.
- [x] **Language-tag status refreshed.** Whether the trigger fired in SHACL-T-0014, and if not,
      where the exposure now sits.
- [x] **Exit criteria verified by a run**: `make test` at both widths and `make check`, with
      per-package test counts and enabled directories recorded in the task log.
- [x] Handover notes for the SHACL-SPARQL phase, in the shape of
      `docs/handover-catalogue.md` — what `core/complex` needs, where the `sparql:` collection
      goes, and what this initiative left open.

## Implementation Notes

### Technical Approach

Follow SHACL-T-0008's closing pattern: verify each exit criterion individually, record the
evidence, and where one is not met in full, say so and propose either a re-scope or holding
the initiative open rather than declaring victory.

Expect the verification pass to find things. It did last time, in code that had shipped and
been reviewed, because the newly-enabled directories test corners the earlier ones never
reached.

### Dependencies

Everything: SHACL-T-0013 through SHACL-T-0018. SHACL-T-0009 through SHACL-T-0012 are transitive
dependencies through those.

### Risk Considerations

**The two write-ups are the easiest thing to shortchange at the end of a build**, which is why
they are acceptance criteria rather than closing notes — the same reason SHACL-T-0008 gave.

**If the exit criteria are not fully met**, the honest options are a recorded re-scope with
reasons or holding the initiative open. Both go to review. Neither is "mark it done and file
the rest as backlog" without saying so.

## Status Updates **[REQUIRED]**

- **2026-08-07 — Entering state, left by SHACL-T-0018. Not started.**

  **SHACL Core's constraint catalogue is complete** — every §4 component that does not need
  SPARQL, twenty-nine of them. Two of this task's criteria are therefore already part-met
  and one piece of work is not a component at all:

  - **`core/node` is enabled and green** (32 of 32). SHACL-T-0018 did this rather than
    leaving it here, because "enabled means fully green" and holding a green directory off
    would have misstated the position. Flagged there for review; if it should have waited,
    reverting is `suite.odin` plus the pinned counts.
  - **`core/property` is 37 of 38 and still disabled.** The progress floor is reduced to it
    alone (`PROGRESS_FLOOR :: 37`), `ENABLED_ENTRIES :: 58`.
  - **The single remaining entry is `core/property/nodeKind-001`, and it needs no
    component.** Six plain `sh:nodeKind` property shapes, red since the floor was first
    measured. Diagnosing it is this task's one piece of engineering.

  **How to find which entries fail — the technique, written down because it is a throwaway
  each time.** The floor prints counts, not names, deliberately (a per-entry list would be
  a skip list by another name). To get names, instrument `count_passing` in
  `tests/w3c/harness/floor_test.odin` temporarily:

  ```odin
  ran += 1
  if entry_matches(suite.dir, backend, &tf, e) {
      passed += 1
      if backend == .Memstore { log.infof("PASS %s/%s", suite.dir, e.id) }
  }
  ```

  then diff against the directory listing:

  ```
  odin test tests/w3c/harness -collection:rdf=../odin-rdf-parser \
      -collection:store=../odin-rdf-store \
      -define:ODIN_TEST_NAMES=w3c.test_disabled_suites_meet_their_progress_floor \
    | grep -o "PASS core/property/[a-zA-Z0-9-]*" | sort > /tmp/pass.txt

  ls tests/w3c/core/property/*.ttl | xargs -n1 basename | sed 's/\.ttl$//' \
    | grep -v -- "-data$\|-shapes$\|^manifest$" \
    | sed 's|^|PASS core/property/|' | sort > /tmp/all.txt

  comm -23 /tmp/all.txt /tmp/pass.txt
  ```

  **Revert the instrumentation afterwards.** It must not land: the floor test's own header
  explains why a per-entry list is the thing the family's rule exists to avoid.

  For an *enabled* directory this is unnecessary — `run_suite` fails on the first mismatch
  and names the entry.

  **Where to look first for `nodeKind-001`, and it is probably not the engine.** Its
  expected report carries eighteen results whose `sh:sourceShape` are shapes-graph blank
  nodes and whose `sh:value` are *data*-graph blank nodes. That is the hardest isomorphism
  case in the corpus, and it is the shape of the harness defect SHACL-T-0012 already found
  once — `expected_report` following `sh:focusNode` into the data graph when the focus node
  was a blank node. Rule the harness out before touching `sh:nodeKind`, which is spine code
  that four green directories exercise.

  **One habit worth keeping from SHACL-T-0016 to SHACL-T-0018**, since this task writes the
  handover: every component task confirmed its tests bite by *breaking the implementation*
  and checking the right tests failed. It found a genuinely weak test in SHACL-T-0018 — one
  that passed with both of its guards removed — and the corpus entry it was modelled on
  turned out to share the weakness. Worth stating in the handover notes as a practice, not
  just a result.

- **2026-08-07 — Implemented and awaiting review. The suite is 98 of 98: every directory
  enabled, including two the initiative did not expect to close.**

  Two things happened that the entering note did not predict, and both are scope
  decisions rather than mechanics, so they are first.

  ### One defect, two halves, and it blocked both remaining directories

  `nodeKind-001` was diagnosed in the first ten minutes and it was **not** the harness.
  It was the report emitter, and the entering note's prediction ("probably not the
  engine") was wrong for a reason worth recording: a report merges blank nodes from
  **three** graphs — its own, the data graph's, and the shapes graph's — and both stores
  label loaded blank nodes `b0`, `b1`, … densely from zero, *per store*. Merging graphs
  without standardising blank nodes apart is the oldest mistake in RDF, and the engine
  was making it twice.

  1. **The report's own labels collided with the data graph's.** `fresh_blank` minted
     `b0`, `b1`, … — the same pattern the store generates. In `nodeKind-001` the produced
     report asserted `_:b3 sh:sourceShape _:b3`: a result node and the shape it blamed,
     collapsed into one node. **The suite caught this one**, as an isomorphism failure,
     which is what an isomorphism check is for.
  2. **The shapes graph's labels collided with the data graph's**, and this half the suite
     **could not** catch. Every `core/` entry names one file as both graphs, so the two
     loads assign identical labels and conflating them is accidentally correct. With
     separate files — which is what a real consumer has — a report says
     `sh:sourceShape _:b0 ; sh:value _:b0` and means the shape and the value it blamed are
     the same node. Found by writing the fixture the corpus does not contain.

  Fixed in `shacl/report.odin`: the data graph keeps its labels (they are the ones a
  consumer can act on — `sh:value _:b0` is how a result says *which* unnamed node failed),
  the shapes graph's are prefixed with `s`, and the report's own are minted as `r0`, `r1`,
  ….

  **Half-fixing was considered and rejected.** Only the first half is measurable by the
  suite, and stopping there would have greened `core/property` while leaving a known-wrong
  report shipped — which is the "declare victory" move this task's Risk Considerations
  name. The residual contract is stated rather than proved: borrowed blank-node labels
  must not begin with `r` or `s`. Both backends generate `b`+digits and nothing else, so
  it holds by construction; a caller writing its own `Term_Loader` is the one case that
  has to know, and the package doc says so.

  `tests/w3c/harness/report_test.odin` gains
  `test_report_blank_nodes_are_standardised_apart`, with the two graphs in separate files.
  **It bites in both directions, confirmed by breaking each half in turn**: reverting
  `fresh_blank`'s prefix fails it on the data-graph clause, dropping `shape_term`'s fails
  it on the two-borrowed-graphs clause, with distinct messages.

  ### `core/complex` is green, and the initiative was wrong about it — needs review

  **This is the decision most worth a second opinion.** `core/complex` is an explicit
  non-goal in SHACL-I-0002 ("SHACL-SPARQL … and with them `core/complex`, whose two
  entries need `sh:sparql`, `sh:shapesGraph`, and `sh:entailment`"). It is now enabled.

  The premise turns out to be false, and reading the file is what says so. `sh:sparql`
  occurs **once** in `shacl-shacl-data-shapes.ttl`, as an object of
  `sh:targetSubjectsOf`; `sh:shapesGraph` and `sh:entailment` occur as objects of
  `sh:targetObjectsOf`. All three are *targeted vocabulary* — SHACL's own shapes saying
  "anything that is the subject of a `sh:sparql` triple is a shape" — not constraint
  parameters. Nothing in that file asks for a query engine.

  `personexample` was the red entry, and the blank-node fix greened it: its expected report
  carries blank-node `sh:sourceShape`s. `shacl-shacl` was the one long suspected of
  passing by inaction, and **that is now measured rather than argued**:

  - the ignored-parameter record is **empty** for both entries, asserted by
    `test_enabled_suites_are_green` — the SHACL-T-0010 mechanism doing exactly the job it
    was built for; and
  - breaking `sh:datatype` or `sh:nodeKind` in the evaluator turns **both** entries red.
    An engine that was doing nothing would leave `shacl-shacl` green under any breakage.

  Under "enabled means fully green — leaving a green directory off misstates the position
  as surely as enabling a broken one", it goes on. **Reverting is one line in `suite.odin`
  plus `ENABLED_ENTRIES :: 96`.**

  The general lesson, which the handover carries: the false premise survived a discovery
  phase, a design phase, a decomposition, and ten task write-ups, because every one of them
  was reading the previous one. Nobody read the file until the closing task.

  ### The progress floor: retired, not reduced — also a deletion worth review

  With every directory enabled there are no disabled directories left, so the criterion's
  "reduced to the directories still disabled" has an empty answer. Kept as-is it would be a
  test iterating an empty set and asserting `0 == 0` — a green that means nothing, which is
  the exact failure the floor's own header spent a page warning about. So
  `floor_test.odin` (248 lines), the `floor` field on `Suite`, and `PROGRESS_FLOOR` are
  gone.

  It is recoverable and both `suite.odin` and the two READMEs say how:
  `git show SHACL-T-0019~1 -- tests/w3c/harness/floor_test.odin`. The SHACL-SPARQL phase
  will want it back the day it vendors `sparql/`, and the caveat it printed must come back
  with it.

  ### The verification pass found things, as SHACL-T-0008 said it would

  Two of them were in `tests/guards`, and both were **silent coverage loss** rather than
  wrong code:

  - **The validation guard's fixture had no nesting at all.** `VALIDATION_SHAPES` contained
    not one of the six shape-expecting parameters, so the allocation path the initiative's
    own Testing Strategy singled out — "suppressed validation, which allocates a nested
    walk per branch per value node and is the easiest place in the engine to strand
    memory" — was never walked under a tracking allocator during a validation. Only
    `conforms_node` at top level was. Fixed: all six are in the fixture now, with two
    sibling qualified shapes so `sh:qualifiedValueShapesDisjoint` has a sibling to walk.
  - **`track` hands its body an allocator and no `testing.T`**, so a validation that ended
    two shapes in — `Failure.Recursive_Shape` abandons the traversal — would shrink the
    guard's coverage to nothing while leaving it green. Added
    `test_the_validation_guard_fixture_is_fully_walked`, which walks the same fixture
    outside the tracker and asserts the walk completed and produced results.
  - **The compile guard's ignored-parameter coverage had lapsed.** It used
    `sh:minInclusive` as its unimplemented parameter; SHACL-T-0013 implemented it, so for
    six tasks that guard has been covering an empty record. Now `sh:sparql` — a parameter
    this project has decided not to implement, so it cannot lapse the same way.

  ### Exit criteria, each verified by a run

  `make test` — **145 tests per width, all successful, at 64- and 32-bit**:
  `shacl` 21, `shacl/memstore` 71, `shacl/kvstore` 14, `tests/guards` 12 (was 11),
  `tests/readme` 4, `tests/w3c/harness` 23 (was 24 — the floor file's two tests removed,
  one report test added). `make check` green including the purity check (no LMDB in a
  core+memstore consumer).

  | Criterion | Status |
  | --- | --- |
  | `core/node` (32) and `core/property` (38) enabled and green | **Met, and exceeded** — all seven directories, 98 of 98, both backends, both widths, no skip list |
  | Progress floor retired or reduced | **Retired.** No disabled directories remain |
  | New exported symbols documented; package doc's memory contract updated; component list in README and package doc current | **Met.** No new exported symbols (`shape_term` and `fresh_blank` are file-private). Package doc: allocation budgets gained the suppressed-validation paragraph; "eight contracts" is nine, with the blank-node namespaces added; the ignored-record note corrected |
  | Ignored-parameter record empty for every enabled directory, asserted | **Met** — all 98 entries, and it is what made `core/complex` safe to enable |
  | `tests/readme` still compiles and asserts | **Met** — 4 tests, unchanged API. README changed for accuracy, not for API |
  | Store-evidence write-up refreshed | **Met.** Second finding in eleven tasks, and the first about odin-rdf-store at all — a *contract*, not a gap |
  | Language-tag status refreshed | **Met.** Trigger did not fire; the recommendation changed |
  | Exit criteria verified by a run | **Met** — counts above |
  | Handover notes for the SHACL-SPARQL phase | **Met** — `docs/handover-sparql.md` |

  ### The write-ups

  **Store evidence.** The log has its second finding, and it is the first that is about
  odin-rdf-store rather than about this repository. It is **not a capability gap**: both
  backends relabel loaded blank nodes densely from `b0` per dictionary (STORE-I-0001
  decision 6), which is correct and deliberate. What bites is the consequence — two stores
  collide *by construction*, not by coincidence — and it is documented only in the store's
  own `load.odin`. The one thing that may be worth offering upstream is a sentence of
  documentation, which is a suggestion for review rather than a proposal. Closing verdict
  for the initiative: **no proposal to odin-rdf-store**. Twenty-nine components, five
  target forms, seven path forms, suppressed validation, 98 of 98, all on `match` and
  `find_term`.

  **Language tags.** The trigger did not fire in SHACL-T-0014, and the reason is stronger
  than "no entry happened to exercise it": the two components that read a language tag both
  fold at the point of comparison because SHACL requires it of them — `sh:languageIn` is
  RFC 4647 basic filtering, `sh:uniqueLang` uses `equal_fold`. So the suite's silence is not
  evidence about the parser in those two cases at all. The residual exposure is
  `sh:hasValue` and `sh:in`, which compare **terms**; no corpus entry pairs them with a
  mixed-case tag. **The recommendation changed**: extend the trigger from "a suite entry
  fails" to "a suite entry fails **or** a user reports it", because the corpus now runs in
  full and has demonstrated it will not raise the alarm.

  ### Not done, and why

  - **No benchmark.** `bench/` still does not exist, so SHACL-A-0002's memoisation review
    trigger — *measured* cost — still cannot be pulled. Recorded in the handover as the gap
    most likely to matter first at ~200 processes per machine. Out of this task's scope,
    but it is the one open item with a deployment argument behind it.
  - **Duplicate results still not deduplicated**, and the corpus is now fully run, so
    "no entry exercises it" is a stronger statement than the spine could make.
  - **`sh:detail` still absent**, still a recorded omission rather than an oversight.

  Nothing committed; awaiting review of the diff, in particular the two scope decisions
  above.