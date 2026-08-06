---
id: validation-results-the-streaming
level: task
title: "Validation results: the streaming result API and the report graph"
short_code: "SHACL-T-0006"
created_at: 2026-08-06T13:58:16.016854+00:00
updated_at: 2026-08-06T13:58:16.016854+00:00
parent: SHACL-I-0001
blocked_by: ["SHACL-T-0003"]
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
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

- [ ] Result type carrying the spec's `sh:ValidationResult` properties: focus node, result
      path, value, source shape, source constraint component, severity, and the shape's
      declared message if it has one.
- [ ] **Streaming delivery** — results are handed to the caller as they are found; the
      validator holds no violation set. Memory stays flat as violation count grows, verified
      by a test over deliberately bad data.
- [ ] **Early exit** supported: a conformance-only query stops at the first violation rather
      than validating everything.
- [ ] `sh:ValidationReport` / `sh:ValidationResult` graph emission through odin-rdf-parser,
      with `sh:conforms` correct in both directions.
- [ ] **Only shape-declared `sh:message` triples are emitted** — no processor-generated
      messages in the report graph (SHACL-I-0001 Detailed Design). Human-readable explanation
      is available through the programmatic API instead, and a test asserts the report graph
      carries nothing the shapes graph did not declare.
- [ ] Report graphs verified against hand-written expected graphs using SHACL-T-0002's
      blank-node isomorphism comparison, closing the loop between emitter and harness before
      any suite entry depends on both.
- [ ] Reports round-trip: emit → parse → compare isomorphic to the original.
- [ ] Allocation guards: the streaming path holds to a stated per-result allocation budget.
- [ ] Tests at both widths against both backends.

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

*To be added during implementation*
