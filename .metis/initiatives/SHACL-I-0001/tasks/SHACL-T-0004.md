---
id: property-paths-compilation-and
level: task
title: "Property paths: compilation and value-node evaluation"
short_code: "SHACL-T-0004"
created_at: 2026-08-06T13:58:08.841199+00:00
updated_at: 2026-08-06T17:41:53.773742+00:00
parent: SHACL-I-0001
blocked_by: [SHACL-T-0003]
archived: false

tags:
  - "#task"
  - "#phase/completed"


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

- [x] The full SHACL Core path grammar compiled from the shapes graph: predicate paths,
      `sh:inversePath`, sequence paths (RDF lists), `sh:alternativePath`, `sh:zeroOrMorePath`,
      `sh:oneOrMorePath`, `sh:zeroOrOnePath`, and their nesting.
- [x] Value-node evaluation over `Term_ID`s through `match`, with the graph position bound to
      the caller-named data graph (SHACL-A-0001 decision 5) in every call.
- [x] **Cycle-safe reachability** for the zero-or-more and one-or-more forms: BFS with a
      visited set over `Term_ID`s. Tested against genuinely cyclic data — the asset-points-at-
      asset shape from the project's first use case is the natural fixture.
- [x] Zero-or-more and zero-or-one include the focus node itself, per spec.
- [x] Ill-formed paths rejected at compile time (SHACL-T-0003's error discipline): a malformed
      RDF list, an unknown path predicate, a path node with more than one path property.
- [x] Duplicate value nodes handled per spec — value nodes are a *set*, so a path reaching the
      same node twice yields it once.
- [x] Allocation guards: path evaluation frees what it allocates; the streaming shape does not
      allocate per value node beyond a documented budget.
- [x] Unit tests at both widths against both backends, including deeply nested paths and paths
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

- **2026-08-06 — Complete, awaiting review.** All nine criteria met. `make check` clean,
  `make test` green at both `Term_ID` widths: 47 tests per width, up from 34 — 21 memstore
  (10 new for evaluation), 6 kvstore (2 new), 4 guards (1 new).

  The first criterion — the full path grammar compiled — was already met by SHACL-T-0003;
  this task delivered the evaluator over it: `shacl/path_eval.odin`, plus the step adapter
  and `bind_paths` in both instantiation packages.

  **Design decision — the store is reached through a procedure pointer here, where
  compilation used compile-time constants.** Path evaluation recurses over the path
  structure, and a generic procedure over `$`-procedure constants that calls itself hangs the
  Odin compiler. Rather than hand-rolling a CPS interpreter to keep the whole evaluator
  generic, the structure recursion is ordinary non-generic code and the single place it
  touches the store is a `Step` the instantiation package supplies concretely.

  This is not an improvisation: odin-rdf-sparql hit exactly this, for exactly property paths,
  and answered it exactly this way — its `expand_adapter` is documented as "the same door for
  a property path's step: the traversal is running inside the executor and has to run an
  operator tree to expand a frontier node, which only a concrete procedure can ask for."
  Inside the adapter the match call is direct, so the indirection is one call per predicate
  step, and SPARQL-T-0011 measured that dispatch as noise (−2%). Recursion depth is bounded
  by path nesting in the shapes graph, never by the data.

  **Direction is carried, not rewritten.** `inverted` descends the tree, so the inverse of a
  sequence is the same nodes walked in reverse rather than a compile-time transformation.
  That is the piece most likely to be silently wrong — it only shows up on graphs where the
  two predicates are not symmetric — so it has its own test on both backends, asserting both
  that `^( ex:p ex:q )` from `ex:y` reaches `ex:a` and that it reaches nothing from `ex:a`.

  **The cyclic fixture is the point, not decoration.** `ex:a → ex:b → ex:c → ex:a` is what a
  reachability walk gets wrong, and it is an ordinary modelling situation rather than an
  exotic one — assets that point at assets produce exactly this. Two assertions turn on it
  that a weaker test would miss: `ex:p*` from `ex:a` terminates and returns all three nodes,
  and `ex:p+` from `ex:a` **includes `ex:a`**, because the cycle genuinely reaches it. A
  "drop the input node" implementation of one-or-more passes the acyclic case and fails this
  one, so both are tested.

  **Absence means opposite things in the two places it appears.** A predicate the data store
  has never seen makes a path step empty, which is correct — no triple can mention a term the
  dictionary does not hold. An absent `sh:class` term will make every value node *violate*.
  Both are recorded in the code comments where they bite, because the symmetry is inviting
  and wrong.

  **One rename, worth knowing.** `Session.store` became `Session.db`: a field named `store`
  in a struct that also names `store.Term_ID` is an illegal declaration cycle in Odin. It
  worked in odin-rdf-sparql only because its Session does not reference the store package's
  types in the same struct.

  Nothing about the upstream repositories was touched.