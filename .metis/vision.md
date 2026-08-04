---
id: odin-rdf-shacl
level: vision
title: "odin-rdf-shacl"
short_code: "SHACL-V-0001"
created_at: 2026-08-04T16:47:41.838764+00:00
updated_at: 2026-08-04T16:48:59.367044+00:00
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

The project is at its inception; no validation code exists. odin-rdf-parser is complete (100% W3C conformance, RDF 1.2/RDF-star included); odin-rdf-store is newly started and will provide the match interface this project reads through; odin-rdf-sparql is newly started and only matters here for the later SHACL-SPARQL phase. Work can begin once the store's first match interface exists — shape model design and shapes-graph parsing can start against odin-rdf-parser alone.

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