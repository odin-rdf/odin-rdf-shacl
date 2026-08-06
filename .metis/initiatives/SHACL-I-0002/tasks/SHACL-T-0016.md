---
id: sh-closed-and-sh-ignoredproperties
level: task
title: "sh:closed and sh:ignoredProperties, and the store evidence it produces"
short_code: "SHACL-T-0016"
created_at: 2026-08-06T19:27:10.389847+00:00
updated_at: 2026-08-06T19:27:10.389847+00:00
parent: SHACL-I-0002
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: SHACL-I-0002
---

# sh:closed and sh:ignoredProperties, and the store evidence it produces

## Parent Initiative

[[SHACL-I-0002]]

## Objective **[REQUIRED]**

`sh:closed` and `sh:ignoredProperties` (§4.8.1) — the component that asks the store a question
the spine never asked: which predicates a focus node actually *uses*. Small by entry count and
disproportionately interesting, because it is the likeliest source of new store evidence in
this initiative.

## Acceptance Criteria **[REQUIRED]**

- [ ] `sh:closed true` violates for every triple whose predicate is neither declared by one of
      the shape's property shapes nor listed in `sh:ignoredProperties`.
- [ ] The result names the offending predicate and value the way the suite expects — measured
      against `core/node`'s entries, not assumed.
- [ ] The "predicates in use" read is a wildcard-predicate match from the focus node through
      the published interface, with the graph bound. **If it wants something the interface
      cannot answer, that goes in `docs/store-evidence.md` with the shape that wants it** — and
      it is a proposal for review, never a backend-specific workaround.
- [ ] `sh:ignoredProperties` compiles as an RDF list of predicate IRIs, like `sh:in`'s members.
- [ ] The set of declared predicates comes from the shape's property shapes whose path is a
      **predicate path**; a shape whose path is a sequence or an inverse declares no single
      predicate, and what the spec says about that is checked rather than guessed.
- [ ] The progress floor moves and the new figure is pinned.
- [ ] Tests at both widths against both backends; `make test` and `make check` green.

## Implementation Notes

### Technical Approach

Set-scoped: asked once per focus node about everything the node asserts, not once per value
node. The interesting part is the model question — "which predicates does this shape declare"
is a property of the shape's children, which the flat model can answer at compile time and
cache rather than recompute per focus node.

### Dependencies

None. Independent; can run in parallel with the other mechanical families.

### Risk Considerations

**This is the store-evidence task.** Its risk is not failure but silence: doing the work, using
the interface, and forgetting to record what the experience was. The evidence log has been
open since SHACL-T-0005 and has found nothing; a genuine finding here would be the first, and
a genuine non-finding is also a result worth writing down.

## Status Updates **[REQUIRED]**

*To be added during implementation*
