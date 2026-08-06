---
id: property-paths-compilation-and
level: task
title: "Property paths: compilation and value-node evaluation"
short_code: "SHACL-T-0004"
created_at: 2026-08-06T13:58:08.841199+00:00
updated_at: 2026-08-06T13:58:08.841199+00:00
parent: SHACL-I-0001
blocked_by: ["SHACL-T-0003"]
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: SHACL-I-0001
---

# Property paths: compilation and value-node evaluation

## Parent Initiative

[[SHACL-I-0001]]

## Objective **[REQUIRED]**

Implement the value-node mechanism: given a focus node and a compiled path, produce the value
nodes a property shape's constraints apply to. This is *the* property-shape primitive — every
property constraint in this initiative and the catalogue one consumes it — and it reads the
data graph through `match` alone.

## Acceptance Criteria **[REQUIRED]**

- [ ] The full SHACL Core path grammar compiled from the shapes graph: predicate paths,
      `sh:inversePath`, sequence paths (RDF lists), `sh:alternativePath`, `sh:zeroOrMorePath`,
      `sh:oneOrMorePath`, `sh:zeroOrOnePath`, and their nesting.
- [ ] Value-node evaluation over `Term_ID`s through `match`, with the graph position bound to
      the caller-named data graph (SHACL-A-0001 decision 5) in every call.
- [ ] **Cycle-safe reachability** for the zero-or-more and one-or-more forms: BFS with a
      visited set over `Term_ID`s. Tested against genuinely cyclic data — the asset-points-at-
      asset shape from the project's first use case is the natural fixture.
- [ ] Zero-or-more and zero-or-one include the focus node itself, per spec.
- [ ] Ill-formed paths rejected at compile time (SHACL-T-0003's error discipline): a malformed
      RDF list, an unknown path predicate, a path node with more than one path property.
- [ ] Duplicate value nodes handled per spec — value nodes are a *set*, so a path reaching the
      same node twice yields it once.
- [ ] Allocation guards: path evaluation frees what it allocates; the streaming shape does not
      allocate per value node beyond a documented budget.
- [ ] Unit tests at both widths against both backends, including deeply nested paths and paths
      over data with no matching triples.

## Implementation Notes

### Technical Approach

The reachability algorithm is the same shape odin-rdf-sparql uses for SPARQL's `*` and `+`
property paths — BFS with a visited set over integer IDs, not term values — so joins and
dedup stay integer comparisons. The specs align closely enough here that the algorithm
transfers; the *syntax* does not (SHACL paths are RDF structures, SPARQL paths are grammar),
which is why compilation is this repo's own.

Evaluation is stack-driven over the flat compiled path, consistent with SHACL-A-0001
decision 4.

### Dependencies

SHACL-T-0003 (the shapes model holds compiled paths; this task evaluates them). Can run in
parallel with SHACL-T-0005 and SHACL-T-0006.

### Risk Considerations

Sequence paths over long chains and `zeroOrMorePath` over dense data are where a naive
implementation materialises far more than it needs. The streaming discipline matters here more
than anywhere else in the initiative, and the allocation guard is the mechanism that keeps it
honest rather than aspirational.

## Status Updates **[REQUIRED]**

*To be added during implementation*
