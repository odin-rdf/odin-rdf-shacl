---
id: odin-rdf-shacl
level: vision
title: "odin-rdf-shacl"
short_code: "SHACL-V-0001"
created_at: 2026-08-04T16:47:41.838764+00:00
updated_at: 2026-08-06T12:00:00.000000+00:00
archived: false

tags:
  - "#vision"
  - "#phase/published"


exit_criteria_met: false
initiative_id: NULL
---

# odin-rdf-shacl Vision

## Purpose

Provide the Odin RDF family with shape-based validation: a SHACL (Shapes Constraint Language) implementation that validates RDF data graphs against shapes graphs. It stands as a peer of odin-rdf-sparql on the same foundation — shapes are themselves RDF (loaded via odin-rdf-parser), and validation reads the data graph through odin-rdf-store's match interface. SHACL Core requires no query engine; the SHACL-SPARQL extension is a later phase that consumes odin-rdf-sparql.

## Product/Solution Overview

odin-rdf-shacl is a library (not an application) targeting Odin developers who need to validate RDF data. It offers:

- **Shapes graph loading**: shapes are parsed from Turtle (or any supported format) with odin-rdf-parser and compiled into an internal shapes model, with meaningful errors for ill-formed shapes.
- **SHACL Core validation**: target resolution (`sh:targetClass`, `sh:targetNode`, and friends), the Core constraint components (`sh:minCount`, `sh:datatype`, `sh:pattern`, `sh:node`, logical constraints, property paths, and the rest), reading the data graph exclusively through the store's match interface.
- **Validation reports**: standard `sh:ValidationReport` result graphs, emittable through odin-rdf-parser, plus a programmatic result API for embedding.
- **SHACL-SPARQL (later phase)**: `sh:sparql` constraints and SPARQL-based constraint components, delegating query evaluation to odin-rdf-sparql as an optional dependency.

The library is deliberately validation-only: inference/entailment, SHACL rules (SHACL-AF), and server layers are out of scope.

## Current State

**SHACL Core is complete, and the vendored W3C corpus is fully green.** Two initiatives
delivered it: SHACL-I-0001 (the spine, completed 2026-08-06) and SHACL-I-0002 (the
constraint catalogue, completed 2026-08-07).

- **All 98 entries of the vendored W3C SHACL 1.0 `core/` suite pass**, across all seven
  directories, against both storage backends, at both `Term_ID` widths. No skip list, no
  expected-failure file, and an empty ignored-parameter record throughout — the family's
  rule is unchanged, and every directory now satisfies it.
- **All twenty-nine constraint components** of §4 that do not require SPARQL: value-type,
  cardinality, value-range, string-based, property-pair, logical, shape-based, and
  `sh:closed`. Alongside them: shape discovery to §2.1.1, all five target forms, all seven
  path forms, and `sh:ValidationReport` emission.
- **Suppressed validation** — asking whether a node conforms without reporting why — is the
  one architectural addition the catalogue needed, and it has its own ADR (**SHACL-A-0002**)
  because six components depend on it and a mechanism retrofitted from whichever landed
  first would have carried that one's assumptions. **SHACL-A-0001** still records the
  shapes model, term ownership, and graph scoping.
- **The suite target is SHACL 1.0** (2026-08-06), not 1.2. 1.2 is still moving in the W3C,
  and a suite that goes green against a specification that can change under it is worth
  less than it looks. Review trigger and reasoning in `tests/w3c/README.md`.

Packages: `shacl` (backend-independent core), `shacl/memstore`, `shacl/kvstore`. The core
names no storage backend and imports none, asserted rather than trusted — `make check`
builds a core-plus-memstore consumer and fails if the binary carries LMDB symbols.

The dependencies are unchanged and all complete: **odin-rdf-parser** and
**odin-rdf-store** at v0.1.0, and **odin-rdf-sparql** at v0.1.0, relevant here only for
the later SHACL-SPARQL phase.

**`core/complex` was never a SHACL-SPARQL directory, and the correction is worth carrying
up to this level** because it changes what that phase is for. It was documented for the
whole of SHACL-I-0002 as needing `sh:sparql`, `sh:shapesGraph`, and `sh:entailment`. All
three appear in `shacl-shacl-data-shapes.ttl` only as *targeted vocabulary* — objects of
`sh:targetSubjectsOf` and `sh:targetObjectsOf` — not as constraint parameters. Nothing in
that file asks for a query engine, and both entries are green for the right reason: the
ignored-parameter record is empty for each, and breaking `sh:datatype` or `sh:nodeKind` in
the evaluator turns both red. The belief survived a discovery phase, a design phase, a
decomposition, and ten task write-ups because each was reading the previous one; nobody read
the file until the closing task.

**Both things this section originally told the project to expect turned out otherwise, and
that is still the most useful thing it records:**

- **The store capabilities this project would "probably pull" were not pulled**, and the
  catalogue did not change that. Both predicted items stay retired. *A named-graph wildcard*
  (STORE-T-0017) cannot become needed without reversing SHACL-A-0001 decision 5, and the
  core cannot express one — neither procedure pointer it reads through takes a graph.
  *Dataset introspection* (STORE-T-0016) was wanted for target resolution, and all five
  target forms turned out to be ordinary match patterns; `sh:closed`, the last thing
  predicted to want it, did not either. **A validator with all twenty-nine components
  reaches odin-rdf-store through `match` and `find_term` and nothing else.**

  The evidence log has produced two findings in eleven tasks and neither is a capability
  gap. The first was a narrowing this project wrote — `Access` had three read verbs and
  `sh:closed` needed a fourth. The second is the only one about odin-rdf-store at all, and
  it is a **contract** rather than a missing verb: blank-node labels are generated densely
  from `b0` *per dictionary*, so two dictionaries collide by construction, and a consumer
  merging terms from both into one graph must standardise them apart. This engine did not,
  and shipped two bugs for it. `docs/store-proposal.md` carries it as a documentation
  suggestion — the only thing that document has ever asked upstream for.

- **The term-identity question is decided and still has not been forced.** The decision
  stands: **fold language tags to lowercase at literal construction in odin-rdf-parser**.
  The implementation is designed and not built, because the exposure is zero — and that is
  now measured against a fully-run corpus rather than predicted against a partial one. The
  two components that read a language tag both fold at the point of comparison because
  SHACL requires it of them: `sh:languageIn` is RFC 4647 basic filtering, `sh:uniqueLang`
  compares with `equal_fold`. The residual exposure is `sh:hasValue` and `sh:in`, which
  compare terms; no corpus entry pairs them with a mixed-case tag.
  **The trigger is now widened** (2026-08-07) from "a suite entry fails" to "a suite entry
  fails **or** a user reports it", because the corpus runs green in full and will not be
  the thing that raises the alarm. `docs/language-tag-status.md` has the evidence.

**Next**, and neither is about correctness:

- **SHACL-I-0003 — performance evidence.** `bench/` does not exist, so the library has no
  evidence about cost, and SHACL-A-0002's review trigger for memoising conformance answers
  requires *measured* cost — a trigger that cannot currently be pulled. Active, decomposed
  into three tasks. The `v0.1.0` tag waits for it, because every sibling shipped `v0.1.0`
  with performance evidence.
- **The SHACL-SPARQL phase.** `docs/handover-sparql.md` is its starting point:
  what it inherits, where the `sparql:` collection goes in all three places, the dispatch
  seam as it actually is (five edits, not the four `docs/handover-catalogue.md` described),
  and what SHACL-I-0002 left open. Its first task is vendoring
  `data-shapes-test-suite/tests/sparql/`, not fixing `core/complex`.

## Future State

A complete, well-tested Odin library where:

- SHACL Core validation conforms to the W3C SHACL specification, measured against the official SHACL test suite.
- Validation runs against any odin-rdf-store backend through the match interface alone, so the same shapes validate in-memory and LMDB-backed data identically.
- Validation reports are spec-conformant RDF graphs that round-trip through odin-rdf-parser.
- The SHACL-SPARQL phase covers SPARQL-based constraints by embedding odin-rdf-sparql, keeping it strictly optional for Core-only users.

## Major Features

- **Shapes model**: compiled representation of node shapes, property shapes, targets, paths, and constraint parameters, built from a shapes graph with validation of the shapes themselves.
- **Target resolution**: all Core target declarations resolved to focus nodes via store matching.
- **Core constraint components**: the full SHACL Core catalogue, including property paths (shared path semantics with SPARQL where the specs align), logical combinators (`sh:and`/`sh:or`/`sh:not`/`sh:xone`), and shape-based constraints (`sh:node`, `sh:qualifiedValueShape`).
- **Validation reports**: `sh:ValidationReport`/`sh:ValidationResult` graphs with severities, messages, and paths per spec; programmatic API for tooling.
- **W3C test-suite harness**: the official SHACL test suite vendored and run hermetically, in the family's established style.
- **SHACL-SPARQL (later phase)**: SPARQL-based constraints and constraint components via odin-rdf-sparql.

## Success Criteria

- SHACL Core passes the W3C SHACL test suite's Core tests (vendored, offline-reproducible).
- Validation reads data exclusively through odin-rdf-store's public match interface — no private hooks into a specific backend.
- Validation reports are spec-conformant: emitted via odin-rdf-parser and verifiable against the suite's expected report graphs (blank-node isomorphism, as in the parser's eval harness).
- SHACL Core has zero dependency on odin-rdf-sparql; the SHACL-SPARQL phase adds it as a clean optional layer.
- The public API is documented and idiomatic Odin, to the contract-documentation standard of the sibling projects.

## Principles

- **Suite-driven correctness**: the W3C SHACL test suite defines "done", as the format and query suites do for the sibling projects.
- **Core before SPARQL**: everything achievable without a query engine ships first; the optional dependency stays optional forever.
- **Consume the interface, don't bypass it**: data access goes through odin-rdf-store's published match contract; capability gaps are proposed upstream as evidence-backed needs.
- **Idiomatic Odin**: explicit memory management, allocator awareness, straightforward procedural APIs — the family's conventions.
- **Primitives over frameworks**: a validation engine as a library; pipelines, servers, and rule systems belong downstream.

## Constraints

- Written in Odin with no external dependencies; odin-rdf-sparql is an optional dependency confined to the SHACL-SPARQL phase.
- Depends on odin-rdf-parser (data model, shapes/report parsing and emitting) and odin-rdf-store (match interface); consumed as published.
- Scope is SHACL Core validation plus the later SHACL-SPARQL phase. Out of scope: SHACL Advanced Features (rules, functions), inference/entailment regimes, and any server or protocol layer.
- Validation performance is bounded by the store's match capabilities; correctness must never depend on backend-specific behavior.