---
id: validation-results-the-streaming
level: task
title: "Validation results: the streaming result API and the report graph"
short_code: "SHACL-T-0006"
created_at: 2026-08-06T13:58:16.016854+00:00
updated_at: 2026-08-06T18:04:01.463154+00:00
parent: SHACL-I-0001
blocked_by: [SHACL-T-0003]
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: true
initiative_id: SHACL-I-0001
---

# Validation results: the streaming result API and the report graph

## Parent Initiative

[[SHACL-I-0001]]

## Objective **[REQUIRED]**

Build the output half of the spine: the programmatic result API that delivers violations as
they are found, and the `sh:ValidationReport` graph emitted over it. This is what makes the
initiative measurable — the W3C suite compares report graphs, so without this nothing can be
scored.

## Acceptance Criteria **[REQUIRED]**

- [x] Result type carrying the spec's `sh:ValidationResult` properties: focus node, result
      path, value, source shape, source constraint component, severity, and the shape's
      declared message if it has one.
- [x] **Streaming delivery** — results are handed to the caller as they are found; the
      validator holds no violation set. Memory stays flat as violation count grows, verified
      by a test over deliberately bad data.
- [x] **Early exit** supported: a conformance-only query stops at the first violation rather
      than validating everything.
- [x] `sh:ValidationReport` / `sh:ValidationResult` graph emission through odin-rdf-parser,
      with `sh:conforms` correct in both directions.
- [x] **Only shape-declared `sh:message` triples are emitted** — no processor-generated
      messages in the report graph (SHACL-I-0001 Detailed Design). Human-readable explanation
      is available through the programmatic API instead, and a test asserts the report graph
      carries nothing the shapes graph did not declare.
- [x] Report graphs verified against hand-written expected graphs using SHACL-T-0002's
      blank-node isomorphism comparison, closing the loop between emitter and harness before
      any suite entry depends on both.
- [x] Reports round-trip: emit → parse → compare isomorphic to the original.
- [x] Allocation guards: the streaming path holds to a stated per-result allocation budget.
- [x] Tests at both widths against both backends.

## Implementation Notes

### Technical Approach

The two layers are deliberately separate: the result stream is the primitive, and report-graph
emission is an ordinary consumer of it that happens to build a graph. That ordering is what
makes early exit possible and keeps `sh:conforms` — which is only knowable at the end — from
forcing the whole result set into memory.

`sh:conforms` is the one genuinely blocking bit of the report: it is `true` iff no result of
severity `sh:Violation` was produced. Emitting the report head after the stream drains handles
it without buffering results.

### Dependencies

SHACL-T-0003 (results reference source shapes from the model). Uses SHACL-T-0002's isomorphism
comparison for its own tests — if T-0002 has not landed, write the comparison here and hand it
over rather than duplicating it. Can run in parallel with SHACL-T-0004 and SHACL-T-0005.

### Risk Considerations

Streaming plus early exit interacts with ownership: a result handed to a caller must not
borrow from a buffer the next result overwrites, or the API is a trap. Decide explicitly
whether results borrow until the next call or are caller-owned, document it in the contract,
and enforce it with a guard test — this is exactly the kind of thing the family's memory
contract exists to state up front.

## Status Updates **[REQUIRED]**

- **2026-08-06 — Complete, awaiting review.** All nine criteria met. `make check` clean,
  `make test` green at both `Term_ID` widths: **67 tests per width**, up from 58 — 20 harness
  (6 new for reports), 8 kvstore (1 new), 7 guards (2 new).

  **What landed.** `shacl/result.odin` (the `Result` type, `Result_Visitor`, the component and
  severity IRI mappings, and the `Conformance` consumer), `shacl/report.odin` (the report
  graph builder including path serialisation), and `report_add` wrappers in both instantiation
  packages.

  **The layering is the design.** The result stream is the primitive; report building is an
  ordinary consumer of it that happens to build a graph. That ordering is what makes early
  exit possible at all, and it is what solves `sh:conforms` without buffering: conformance is
  only knowable when the last result has been seen, so the report **head trails the results** —
  `report_finish` writes `sh:conforms` after the stream has drained. A caller that only wants
  a boolean never builds a graph.

  **The ownership rule is stated rather than discovered**, which the task's Risk
  Considerations asked for: **a `Result` borrows and owns nothing.** It names nodes by
  `Term_ID` and shapes and paths by index into the compiled model, it allocates nothing, and
  it is valid only for the duration of the visitor call. A caller keeping one must copy what
  it needs. The alternative — results owning materialised terms — would allocate on the
  engine's hottest path to serve a case `Report` already serves.

  **Path serialisation is the piece that was not obvious.** `sh:resultPath` has to carry the
  path *back* as RDF, which for anything but a predicate path is a blank-node structure, and
  for sequences and alternatives a whole RDF list. `path-inverse-001`'s expected report really
  does contain `sh:resultPath [ sh:inversePath ex:child ]`. So one result can contribute a
  dozen triples of path, and this is the concrete reason report comparison must be blank-node
  isomorphism rather than a label match — which SHACL-T-0002 built and this task is the first
  consumer of.

  **The report tests live in `tests/w3c/harness`**, because that is where the isomorphism
  comparison is, and comparing a produced report against a hand-written expected one is
  precisely what SHACL-T-0007's suite runner will do. Writing them there closes the loop
  between emitter and comparison before any suite entry depends on both. Results are
  constructed by hand — there is no validator yet — which is a feature: it pins the report
  shape independently of whatever produces the results.

  **Two things asserted that a weaker test would miss.** `sh:conforms` is tested in **both**
  directions, because a builder that always said `false` would pass the main comparison. And
  a **warning does not break conformance** (§3.1.2) — only `sh:Violation` does — which is easy
  to get wrong and changes what an early-exit caller may stop on.

  **`Conformance` is the early-exit consumer**, delivered here as the concrete artifact rather
  than as a promise: its visitor returns false at the first violation. End-to-end early exit —
  a traversal that actually stops — is SHACL-T-0007's to assert, because there is no validator
  yet to stop. The guard asserts the consumer itself allocates nothing across 10,000 results.

  **One refactor.** `Focus_Node` became an alias for a new `Node_Ref`, because a result names
  a *value* node with the same shape and calling that a focus node would have been confusing.

  Nothing about the upstream repositories was touched.