---
id: target-resolution-focus-nodes-from
level: task
title: "Target resolution: focus nodes from all Core target declarations"
short_code: "SHACL-T-0005"
created_at: 2026-08-06T13:58:14.591923+00:00
updated_at: 2026-08-06T13:58:14.591923+00:00
parent: SHACL-I-0001
blocked_by: ["SHACL-T-0003"]
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: SHACL-I-0001
---

# Target resolution: focus nodes from all Core target declarations

## Parent Initiative

[[SHACL-I-0001]]

## Objective **[REQUIRED]**

Turn a shape's target declarations into the focus nodes it applies to, reading the data graph
through `match` alone. This is also the initiative's designated evidence generator: target
resolution is where the vision predicted this project would want store capabilities it does
not have, and this task starts the log that tests that prediction.

## Acceptance Criteria **[REQUIRED]**

- [ ] All SHACL Core target declarations resolved: `sh:targetNode`, `sh:targetClass`,
      `sh:targetSubjectsOf`, `sh:targetObjectsOf`, and **implicit class targets** (a shape
      that is itself an `rdfs:Class`).
- [ ] Class targeting follows `rdf:type` plus `rdfs:subClassOf*` reachability **in the data
      graph**, cycle-safe over `Term_ID`s, sharing SHACL-T-0004's reachability primitive
      rather than reimplementing it.
- [ ] Every `match` call binds the graph position to the caller-named data graph. No wildcard
      in the graph position anywhere in this task — that is the property that retires
      STORE-T-0017.
- [ ] Focus nodes are a set: a node targeted by two declarations on the same shape is
      validated once.
- [ ] Resolution streams — focus nodes are yielded, not materialised into a list, so a shape
      targeting a large class does not allocate proportionally to it.
- [ ] **Store-evidence log started** (`docs/store-evidence.md` or the task log — pick one and
      keep it): every point where resolution wants something `match` cannot answer, recorded
      with the concrete target declaration that wants it and what it would buy. An empty log
      is a valid and interesting result.
- [ ] Unit tests per target form at both widths against both backends, including targets that
      resolve to nothing and a `sh:targetClass` whose class term is absent from the data
      store.
- [ ] Allocation guards over the resolution path.

## Implementation Notes

### Technical Approach

Most Core target resolution is ordinary match patterns — `sh:targetSubjectsOf` is a
predicate-position match returning subjects, `sh:targetObjectsOf` the same returning objects,
`sh:targetClass` is `rdf:type` plus subclass reachability. This is the basis for the design
phase's judgement that STORE-T-0016 (dataset introspection) is a *hypothesis* rather than a
dependency: resolve the targets first, then see whether the log has anything in it.

### Dependencies

SHACL-T-0003 (shapes model carries target declarations). Shares SHACL-T-0004's reachability
primitive — whichever lands first owns it. Can run in parallel with SHACL-T-0006.

### Risk Considerations

**Absence is not emptiness.** A `sh:targetClass ex:Foo` whose class term is absent from the
data store resolves to *no focus nodes* — the shape simply does not apply. That is the
opposite of the analogous case in a constraint, where an absent `sh:class` term makes every
value node violate. Both are correct; they are easy to conflate, and the test suite will not
necessarily distinguish them. The unit test for an absent class term exists to pin this down.

Store capability findings go in the evidence log and, at SHACL-T-0008, into a written proposal
for review. They are not filed into odin-rdf-store's Metis from here, and they are not worked
around locally.

## Status Updates **[REQUIRED]**

*To be added during implementation*
