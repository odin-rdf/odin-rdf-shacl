---
id: widened-shape-discovery-and-the
level: task
title: "Widened shape discovery, and the ignored-parameter record"
short_code: "SHACL-T-0010"
created_at: 2026-08-06T19:26:45.111936+00:00
updated_at: 2026-08-06T19:26:45.111936+00:00
parent: SHACL-I-0002
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: SHACL-I-0002
---

# Widened shape discovery, and the ignored-parameter record

## Parent Initiative

[[SHACL-I-0002]]

## Objective **[REQUIRED]**

Widen shape discovery from the spine's three cases to §2.1.1's full definition, and make the
engine say what it did not understand. Both are prerequisites: every shape-nesting component
in this initiative is unreachable until a node that is the value of `sh:node` or `sh:not`
counts as a shape, and the ignored-parameter record is what stops an incomplete engine from
looking complete while the rest of the catalogue lands.

## Acceptance Criteria **[REQUIRED]**

- [ ] A node is compiled as a shape when it is the value of any shape-expecting parameter —
      `sh:node`, `sh:not`, `sh:and`, `sh:or`, `sh:xone`, `sh:qualifiedValueShape` — in addition
      to the spine's three cases (typed `sh:NodeShape`/`sh:PropertyShape`, carrying a target,
      value of `sh:property`).
- [ ] Discovery still terminates on a shapes graph whose shape references form a cycle. The
      compiler's worklist already dedupes by ID; assert it with a self-referencing `sh:node`.
- [ ] **The compiled model records every `sh:`-namespace predicate it saw on a shape and did
      not implement**, readable from `Shapes`, owned by it like every other term.
- [ ] That record distinguishes **not implemented** from **recognised but non-validating**.
      `sh:name`, `sh:description`, `sh:order`, `sh:group`, and `sh:defaultValue` are
      spec-defined annotations no engine acts on; a record that flagged them would cry wolf on
      every real shapes graph, and `core/property` uses `sh:name`.
- [ ] The suite harness asserts the record is empty for every **enabled** directory. A green
      directory whose entries compiled with unimplemented parameters is a green whose meaning
      is unclear, and this is what makes that visible.
- [ ] Compiling a shapes graph still never writes to the store it reads (the existing
      read-only-environment test still passes).
- [ ] Allocation guards hold: the record is owned and freed with the model.
- [ ] Tests at both widths against both backends; `make test` and `make check` green.

## Implementation Notes

### Technical Approach

Discovery is the block at the top of `compile`, and the worklist below it already handles
shapes found late — a shape enqueued while compiling another is compiled in the same pass, and
the fixup pass resolves indices afterwards. Adding six more predicates that enqueue is the
mechanical part.

The ignored-parameter record is a list of interned terms on `Shapes`, populated during
`compile_constraints` when a `sh:`-namespace predicate on a shape node matches neither an
implemented component nor the inert list. Note this is a *per-model* record, not per-shape:
the question it answers is "did this shapes graph use anything we do not implement", which is
a property of the compile.

### Dependencies

None. Independent of SHACL-T-0009, though the floor makes its effect visible.

### Risk Considerations

**Widening discovery finds shapes that were previously invisible, and some of them may be
ill-formed.** A shapes graph that compiled cleanly before can start failing compilation now —
`path-unused-001` in the spine's own green set carries deliberately ill-formed path nodes that
are unreachable today. If widening makes any of them reachable, that is a real finding, and
the answer is to check whether the spec makes them shapes at all rather than to loosen
validation.

**The inert list is a judgement call that ages.** Every SHACL revision adds annotation
properties. Keep the list short, spec-cited, and in one place.

## Status Updates **[REQUIRED]**

*To be added during implementation*
