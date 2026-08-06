---
id: shapes-model-and-compilation-and
level: task
title: "Shapes model and compilation, and SHACL-A-0001"
short_code: "SHACL-T-0003"
created_at: 2026-08-06T13:58:08.147080+00:00
updated_at: 2026-08-06T13:58:08.147080+00:00
parent: SHACL-I-0001
blocked_by: ["SHACL-T-0001"]
archived: false

tags:
  - "#task"
  - "#phase/todo"


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

- [ ] Shapes model types covering node shapes and property shapes, target declarations, paths
      (as compiled references — evaluation is SHACL-T-0004), constraint parameters,
      `sh:severity`, `sh:message`, and `sh:deactivated`.
- [ ] Model is a **flat array with children named by index**, walked by an explicit stack —
      per SHACL-A-0001 decision 4 and the SPARQL-T-0011 compiler constraint. No
      self-referencing parametric struct, no self-calling generic over `$`-procedure
      constants.
- [ ] Compilation reads the shapes graph **through `match`**, generic over the backend: the
      same compiler runs against a shapes graph in memstore and one in kvstore.
- [ ] The model **interns and owns every term it holds**; `shapes_destroy` frees them.
      Verified by a test that destroys the shapes store immediately after compilation and then
      uses the model.
- [ ] Convenience loader in `shacl/memstore`: Turtle file → memstore → compiled model, keeping
      `shacl` free of any backend dependency.
- [ ] Ill-formed shapes detected at compile time with errors that **name the offending shape
      node and parameter** — see Risk Considerations; the initiative's phrase
      "position-carrying error style" does not transfer to graph-sourced input.
- [ ] Allocation guards in `tests/guards` covering compile → destroy with no leak and no bad
      free, under `ODIN_TEST_FAIL_ON_BAD_MEMORY=true`.
- [ ] Unit tests over hand-built shapes graphs at both widths, against both backends.
- [ ] **SHACL-A-0001 finalised** and transitioned `discussion → decided` — updated to match
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

*To be added during implementation*
