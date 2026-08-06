---
id: target-resolution-focus-nodes-from
level: task
title: "Target resolution: focus nodes from all Core target declarations"
short_code: "SHACL-T-0005"
created_at: 2026-08-06T13:58:14.591923+00:00
updated_at: 2026-08-06T17:41:54.648706+00:00
parent: SHACL-I-0001
blocked_by: [SHACL-T-0003]
archived: false

tags:
  - "#task"
  - "#phase/active"


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

- [x] All SHACL Core target declarations resolved: `sh:targetNode`, `sh:targetClass`,
      `sh:targetSubjectsOf`, `sh:targetObjectsOf`, and **implicit class targets** (a shape
      that is itself an `rdfs:Class`).
- [x] Class targeting follows `rdf:type` plus `rdfs:subClassOf*` reachability **in the data
      graph**, cycle-safe over `Term_ID`s, sharing SHACL-T-0004's reachability primitive
      rather than reimplementing it.
- [x] Every `match` call binds the graph position to the caller-named data graph. No wildcard
      in the graph position anywhere in this task — that is the property that retires
      STORE-T-0017.
- [x] Focus nodes are a set: a node targeted by two declarations on the same shape is
      validated once.
- [x] Resolution streams — focus nodes are yielded, not materialised into a list, so a shape
      targeting a large class does not allocate proportionally to it.
- [x] **Store-evidence log started** (`docs/store-evidence.md` or the task log — pick one and
      keep it): every point where resolution wants something `match` cannot answer, recorded
      with the concrete target declaration that wants it and what it would buy. An empty log
      is a valid and interesting result.
- [x] Unit tests per target form at both widths against both backends, including targets that
      resolve to nothing and a `sh:targetClass` whose class term is absent from the data
      store.
- [x] Allocation guards over the resolution path.

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

- **2026-08-06 — Complete, awaiting review.** All eight criteria met. `make check` clean,
  `make test` green at both `Term_ID` widths: 58 tests per width, up from 47 — 30 memstore
  (9 new), 7 kvstore (1 new), 5 guards (1 new).

  **The headline is what the evidence log does *not* contain.** `docs/store-evidence.md` is
  started, and after implementing all five Core target forms it records **no capability gap**.
  Both of the vision's predictions have now failed to survive contact with the code:

  - **STORE-T-0017 (named-graph wildcard) is retired**, and structurally rather than
    incidentally. Neither `Step` nor `Scan` — the two procedure pointers the core reaches the
    store through — takes a graph parameter; the adapter supplies it from its own handle, so
    the core has no way to *express* a wildcard graph. It can only reopen by reversing
    SHACL-A-0001 decision 5, which is already a recorded review trigger.
  - **STORE-T-0016 (dataset introspection) is not wanted.** Every target form is an ordinary
    match: `sh:targetNode` is one `find_term` and no match at all; the two `*Of` forms are one
    predicate-bound match each; class targeting is a `rdfs:subClassOf*` closure plus one
    two-position-bound match per class.

  That is a result, not an absence of work, and it is the shape SHACL-T-0008's write-up will
  have to report honestly rather than padding.

  **One thing was considered as a gap and rejected, and it is in the log because it looks like
  one.** `sh:targetNode ex:thing` makes `ex:thing` a focus node *whether or not the data graph
  mentions it* — the spec targets the node, not its appearances — so a property shape with
  `sh:minCount 1` must report a violation. But a term the store has never interned has no
  `Term_ID`. Asking the store to fix that would mean assigning an ID, which pollutes the
  dictionary and turns a read into a write — exactly what `find_term` exists to avoid. So the
  engine absorbs it: `Focus_Node` carries `bound: bool` and, when false, the term borrowed
  from the compiled model. Every match involving it is empty, which is correct.

  **That case is only reachable across two stores**, which is why the fixture keeps the shapes
  graph and the data graph in **separate memstores** — the arrangement SHACL-A-0001 decision 2
  exists for, now exercised rather than only argued. In the W3C suite the two share a document,
  so every `sh:targetNode` there is necessarily in the dictionary.

  **Resolution streams, with one honest caveat.** Focus nodes go to a visitor as they are
  found and are never collected into a list. What is kept is the set of nodes already yielded,
  and that is unavoidable: §2.1.3 makes a shape's focus nodes the *union* of its targets, so a
  node reached twice must be validated once. `multipleTargets-001` is exactly that case, and
  the test for it asserts `ex:n1` — named directly *and* an instance of the targeted class —
  appears once.

  **Early exit reaches the store layer** rather than being simulated above it: a visitor
  returning false stops the scan mid-iteration and `resolve_targets` reports it. That is the
  mechanism "does this graph conform?" will use in SHACL-T-0006.

  **Direction, stated because it is easy to invert.** `sh:targetClass ex:Super` walks *down*
  the hierarchy: a node typed `ex:Sub` is a focus node when `ex:Sub rdfs:subClassOf ex:Super`.
  The closure therefore scans for *subjects* of `subClassOf` whose object is already in the
  set. It is cycle-safe, and tested against a deliberate `ex:A ⊑ ex:B ⊑ ex:A` loop —
  ill-advised but not prevented, and non-terminating without a visited set.

  Nothing about the upstream repositories was touched.