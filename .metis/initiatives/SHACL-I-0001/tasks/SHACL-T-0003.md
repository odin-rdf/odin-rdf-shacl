---
id: shapes-model-and-compilation-and
level: task
title: "Shapes model and compilation, and SHACL-A-0001"
short_code: "SHACL-T-0003"
created_at: 2026-08-06T13:58:08.147080+00:00
updated_at: 2026-08-06T14:40:16.427055+00:00
parent: SHACL-I-0001
blocked_by: [SHACL-T-0001]
archived: false

tags:
  - "#task"
  - "#phase/active"


exit_criteria_met: false
initiative_id: SHACL-I-0001
---

# Shapes model and compilation, and SHACL-A-0001

## Parent Initiative

[[SHACL-I-0001]]

## Objective **[REQUIRED]**

Build the contract every later initiative programs against: the compiled shapes model, and the
compiler that produces it from a shapes graph read through the match interface. This is the
project's equivalent of odin-rdf-sparql's algebra, and SHACL-A-0001 exists to record it — the
ADR is finalised here, alongside the code, not after it.

## Acceptance Criteria **[REQUIRED]**

- [x] Shapes model types covering node shapes and property shapes, target declarations, paths
      (as compiled references — evaluation is SHACL-T-0004), constraint parameters,
      `sh:severity`, `sh:message`, and `sh:deactivated`.
- [x] Model is a **flat array with children named by index**, walked by an explicit stack —
      per SHACL-A-0001 decision 4 and the SPARQL-T-0011 compiler constraint. No
      self-referencing parametric struct, no self-calling generic over `$`-procedure
      constants.
- [x] Compilation reads the shapes graph **through `match`**, generic over the backend: the
      same compiler runs against a shapes graph in memstore and one in kvstore.
- [x] The model **interns and owns every term it holds**; `shapes_destroy` frees them.
      Verified by a test that destroys the shapes store immediately after compilation and then
      uses the model.
- [x] Convenience loader in `shacl/memstore`: Turtle file → memstore → compiled model, keeping
      `shacl` free of any backend dependency.
- [x] Ill-formed shapes detected at compile time with errors that **name the offending shape
      node and parameter** — see Risk Considerations; the initiative's phrase
      "position-carrying error style" does not transfer to graph-sourced input.
- [x] Allocation guards in `tests/guards` covering compile → destroy with no leak and no bad
      free, under `ODIN_TEST_FAIL_ON_BAD_MEMORY=true`.
- [x] Unit tests over hand-built shapes graphs at both widths, against both backends.
- [x] **SHACL-A-0001 finalised** and transitioned `discussion → decided` — updated to match
      what was actually built, with any divergence recorded rather than quietly absorbed.

## Implementation Notes

### Technical Approach

Compilation is random access: follow `sh:property` to a blank node, then read `sh:path`,
`sh:minCount`, `sh:class` off that node. That is why it reads from a store rather than the
parser stream (SHACL-A-0001 decision 1) — the access pattern, not the principle, is the
argument.

The model holds `rdf.Term`, not `Term_ID`: the shapes graph and the data graph may be
different stores with different dictionaries. Binding to the data store's IDs happens at
validation setup (SHACL-T-0007), mirroring odin-rdf-sparql's term-binding bridge.

### Dependencies

SHACL-T-0001 (package layout). Independent of SHACL-T-0002 — this task can run in parallel
with suite vendoring, and its unit tests use hand-built shapes graphs rather than suite data.

### Risk Considerations

**A correction discovered at decomposition, worth carrying rather than rediscovering.**
SHACL-I-0001's Goals say ill-formed shapes are reported "in the family's position-carrying
error style". That style comes from parsers, where an error has a byte offset, line, and
column. A shapes graph arrives as *triples in a store* — the text is long gone, and may never
have existed if the graph was built programmatically. There is no position to carry.

The equivalent precision here is graph-shaped: name the shape node (IRI, or blank-node label),
the parameter at fault, and the constraint from the spec that was violated. Keep the family's
other error conventions — a flat `Error_Kind` enum, no message string in the struct, a static
allocation-free `error_message(kind)` whose text ends with the spec section in parentheses.

If a caller wants text positions, that belongs to the *parse* that produced the graph and is
already odin-rdf-parser's job.

## Status Updates **[REQUIRED]**

- **2026-08-06 — Complete, awaiting review.** All nine criteria met. `make check` clean,
  `make test` green at both `Term_ID` widths: 34 tests per width, of which 11 are memstore
  compilation, 4 kvstore, and 3 allocation guards. **SHACL-A-0001 is transitioned to
  `decided`** with an "As Built" section recording three things the design phase did not
  anticipate.

  **What landed.** `shacl/model.odin` (the flat model: shapes, targets, constraints, paths,
  messages, and the child-index arrays they span into), `shacl/intern.odin` (the term table
  that makes the model own what it holds), `shacl/error.odin`, `shacl/query.odin` (the flat
  generic reads plus the pure value decoders), `shacl/path.odin` (path compilation on an
  explicit stack), `shacl/constraints.odin` (the seven components), `shacl/compile.odin` (the
  worklist-driven compiler), and the two instantiation packages'
  `compile` — plus `compile_turtle` in `shacl/memstore`, the convenience path.

  **Finding — the compiler-hang constraint has a second, sharper face, and it is the one
  that bit.** SHACL-A-0001 decision 4 was taken against SPARQL-T-0011's documented failure: a
  generic procedure over `$`-procedure constants that calls itself hangs. What actually
  stopped the first build was different, and it fails loudly rather than hanging — a generic
  procedure **cannot forward its `$MATCH` constant to another generic procedure**, because
  the callee introduces `$It` in the return type of a procedure-typed parameter, and the
  compiler reports *"cannot determine complete type of partial polymorphic procedure"*.

  The fix is what odin-rdf-sparql already does without naming it: bind `$D` and `$It` on an
  earlier *value* parameter, which is why its helpers take `e: ^Exec($D, $It)` first. This
  repo's equivalent is `Reader($D, $It)`, carrying the dataset, the graph, and the RDF-list
  vocabulary nearly every read needs anyway — so it shortened the signatures as well as
  fixing them. Decision 4 is unchanged and now has two independent reasons. Recorded in the
  ADR so the next person meets it as documentation rather than as a compiler message.

  **Scope note — shape discovery is narrower than §2.1.1, deliberately.** The spec makes any
  value of a shape-expecting parameter a shape. The spine implements three cases: typed
  `sh:NodeShape`/`sh:PropertyShape`, a node carrying a target declaration, and a value of
  `sh:property`. That covers the exit-criteria directories; the catalogue initiative widens it
  when `sh:node` and the logical combinators arrive. In the ADR's As Built section.

  **Decision 6 is designed but not realised.** Recursion detection belongs to the evaluator's
  stack and there is no evaluator until SHACL-T-0007. The model and compiler are structured
  for it; nothing detects a recursive shape today because nothing follows one yet.

  **Two properties are asserted rather than assumed.**

  - *The model outlives its store* — tested on both backends by destroying the store before
    reading the model. This matters far more on kvstore, where every term is built from
    database bytes that closing invalidates, which is exactly the asymmetry that made
    ownership the right call.
  - *Compiling never writes* — tested by compiling from a **read-only LMDB environment**.
    `find_term` assigns nothing, so this succeeds; a compiler that interned anything could
    not open the store at all. That is the strongest available form of the claim, and
    stronger than the memstore dictionary-size check beside it.

  **The error style is graph-shaped, as the decomposition predicted.** Ten ill-formed-shape
  cases each assert the kind *and* that the error names the offending shape node and the
  parameter at fault — the substitute for the line/column a shapes graph cannot carry. A
  failed compile still returns the model, because the error's terms borrow from its table, so
  the failure path is guarded for leaks alongside the success path.

  **The guards test a different promise from the parser's.** odin-rdf-parser's guards assert
  parsing allocates *nothing* in steady state, because its terms borrow the caller's buffer.
  A shapes model deliberately does the opposite. So what is guarded here is "every allocation
  is owned and returned": compile-then-destroy is net zero, including on the failure path and
  across repeated compiles.

  `tests/purity` now goes through `shacl/memstore` rather than naming the store directly,
  discharging the note SHACL-T-0001 left — and the purity check still passes, so the
  instantiation package pulls in no LMDB.

  Nothing about the upstream repositories was touched.