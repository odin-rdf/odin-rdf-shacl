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

**The SHACL Core spine is built (SHACL-I-0001, completed 2026-08-06).** Shapes compilation, target resolution, property paths, constraint dispatch, validation results, and `sh:ValidationReport` emission all work end to end, against both storage backends, at both `Term_ID` widths.

- **Four of the W3C suite's seven `core/` directories are green** — `core/targets`, `core/path`, `core/misc`, `core/validation-reports`: 26 entries, no skip list, reports compared by blank-node isomorphism. 72 entries remain.
- **Seven constraint components** of the Core catalogue: `sh:minCount`, `sh:maxCount`, `sh:class`, `sh:datatype`, `sh:nodeKind`, `sh:hasValue`, `sh:in` — the set those four directories exercise. The rest of the catalogue is the second initiative.
- **The suite target is SHACL 1.0** (2026-08-06), not 1.2. 1.2 is still moving in the W3C, and a suite that goes green against a specification that can change under it is worth less than it looks. Review trigger and reasoning in `tests/w3c/README.md`.

Packages: `shacl` (backend-independent core), `shacl/memstore`, `shacl/kvstore`. The core names no backend and imports none, asserted rather than trusted — `make check` builds a core-plus-memstore consumer and fails if the binary carries LMDB symbols. **SHACL-A-0001** records the shapes model, term ownership, and graph scoping.

The dependencies are unchanged and all complete:

- **odin-rdf-parser** — done and tagged v0.1.0. All 1045 W3C conformance tests pass, RDF 1.2/RDF-star included, on Linux, macOS, and Windows. Shapes graphs and validation reports both parse and emit through it.
- **odin-rdf-store** — done and tagged v0.1.0. The match interface is published (STORE-A-0002, `store/interface.odin`) with **two** conforming backends, memstore and kvstore-over-LMDB, verified by one shared conformance suite passing verbatim against both at both `Term_ID` widths. LMDB archives are vendored for five platforms (STORE-A-0004), so a persistent SHACL run works everywhere CI does.
- **odin-rdf-sparql** — done and tagged v0.1.0, relevant here only for the later SHACL-SPARQL phase, which it is ready to serve.

**Both things this section told the project to expect turned out otherwise, and that is the most useful thing it now records:**

- **The store capabilities this project would "probably pull" were not pulled.** Both predicted items are retired rather than pending. *A named-graph wildcard for the graph position* (STORE-T-0017) cannot become needed without reversing SHACL-A-0001 decision 5, which validates one caller-named graph because the spec defines no semantics for a union — and the core cannot even express a wildcard graph, since neither of the two procedure pointers it reads through takes one. *Dataset introspection* (STORE-T-0016) was wanted for target resolution, and all five Core target forms turned out to be ordinary match patterns. A whole validator reaches odin-rdf-store through `match` and `find_term` and nothing else. The write-up is `docs/store-proposal.md`; it proposes no change.

- **The term-identity question is decided but was never forced.** The decision: **fold language tags to lowercase at literal construction in odin-rdf-parser** — what BCP 47 case-insensitivity implies, what §3.3's "the value space of language tags is always lower case" points at, and what Jena and RDF4J do. The implementation is designed (detect in the scanner, fold in the constructor, hot path unchanged) and **not built**, because surveying the entire vendored corpus found the exposure is zero: no suite entry can fail for this reason, in any directory. The rest of term identity was settled by spec rather than by us — IRIs are never normalized, lexical forms compare code-point-wise, and `"1"^^xsd:integer` versus `"01"^^xsd:integer` is the term/value distinction. `docs/language-tag-status.md` has the evidence and recommends widening the trigger from "a suite entry fails" to "a suite entry fails **or** a user reports it", since the suite has demonstrated it will not raise the alarm.

**Next:** the constraint-catalogue initiative — the rest of SHACL Core, scoped against the 1.0 corpus's remaining 72 entries. `docs/handover-catalogue.md` is its starting point: the four-edit shape of the dispatch seam, the per-directory component inventory, and what the spine deliberately left open. One item there is load-bearing and easy to miss: **shape discovery is narrower than §2.1.1**, and widening it is the catalogue's *first* job rather than a consequence of the components it adds.

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