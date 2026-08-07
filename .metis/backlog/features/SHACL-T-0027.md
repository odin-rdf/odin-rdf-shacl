---
id: validation-results-for-one-focus
level: task
title: "Validation results for one focus node, not only the boolean"
short_code: "SHACL-T-0027"
created_at: 2026-08-07T15:11:19.646429+00:00
updated_at: 2026-08-07T15:11:19.646429+00:00
parent: 
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/backlog"
  - "#feature"


exit_criteria_met: false
initiative_id: NULL
---

# Validation results for one focus node, not only the boolean

## Objective **[REQUIRED]**

Publish the per-focus-node validation walk with the **caller's** result
visitor, so that "validate this one node against this one shape" can answer
*why not* and not only *no*.

**Evidence — the question every write path asks has no entry point.**

`conforms_node` (`suppress.odin`) already asks the narrow question: does this
node conform to this shape and every property shape below it (§3.4)? It
deliberately produces no results, because it was built for the six components
that need conformance *without* a report — `sh:not`, `sh:or`, `sh:xone`, and
the three qualified parameters (SHACL-A-0002). That is the right design for
those consumers and should not change.

But an application asks the same narrow question and needs the opposite answer
shape. A CLI checking one resource, an interactive validator, a service telling
a caller which constraint their submission violated: same node, same shape,
**with** the results. Today that consumer has three options and all three are
bad:

1. **`conforms_node`** — a boolean with no explanation. The caller knows the
   submission is invalid and cannot say what is wrong with it.
2. **`validate`, then filter by focus node.** Correct, and it validates every
   targeted node in the dataset to answer about one. Worse, `Report` grows with
   the *whole graph's* violations — `bench` measures 9450 triples for the
   reference configuration and 48002 when everything violates — so the cost of
   asking about one node scales with the data around it. For a consumer doing
   this per write, that is both a latency problem and a denial-of-service
   surface.
3. **Compile a throwaway shapes graph carrying `sh:targetNode`.** Costs a fresh
   compile per question (`bench`: 37 µs memstore, 146 µs kvstore, both measured
   cold precisely because they are start-up costs, not per-operation ones), and
   requires generating Turtle to phrase a question the caller could have asked
   directly.

**The walk already exists.** `validate_focus(v, shape_index, focus)` is exactly
this operation and is `@(private)`. `conforms_node` is that same walk with a
suppressing probe swapped in for the visitor, and `shacl.validate` is the same
walk run once per resolved target. What is missing is the third caller: the one
that supplies its own visitor. This is an entry point and two instantiations,
not an engine.

## Backlog Item Details **[CONDITIONAL: Backlog Item]**

### Type
- [x] Feature - New functionality or enhancement

### Priority
- [x] P1 - High (important for user experience)

Cheapest item with the largest gap between "the code exists" and "a consumer
can reach it".

### Business Justification **[CONDITIONAL: Feature]**
- **User Value**: An application can tell a user *which constraint* their data violated, for the resource they submitted, at a cost proportional to that resource rather than to the dataset.
- **Business Value**: Makes the engine usable for interactive and request-scoped validation, which is where SHACL is most often wanted. Without it the library is shaped for batch validation of a whole graph only.
- **Effort Estimate**: S. A public entry point in `shacl`, its two backend instantiations as peers, a report-building sibling, and tests. No new evaluation logic.

## Acceptance Criteria **[REQUIRED]**

- [ ] A public per-focus-node validation in `shacl`, taking the shape index, the focus node, and a `Result_Visitor`. Results stream as `validate`'s do; a visitor returning false stops the walk.
- [ ] Instantiated in `shacl/memstore` and `shacl/kvstore` as peers, in the signature shape `conforms_node` already established there — node given as an `rdf.Term`, resolved through the non-interning lookup, `graph` defaulting to `store.DEFAULT_GRAPH`.
- [ ] A report-building consumer alongside it, standing to it as `validate_report` stands to `validate`, producing a `sh:ValidationReport` for the one node.
- [ ] **An unbound focus node behaves as it does in `conforms_node`**: a term the store has never seen is validated as an unbound focus node, paths from it reach nothing, and that emptiness is meaningful. The existing contract wording is correct and should be reused rather than restated differently.
- [ ] Same recursion set, same subclass-closure cache, same `Failure` semantics — `.None` means the walk completed or was stopped, anything else means the stream is incomplete and the answer must not be read as conformance.
- [ ] **The subset property is a test**: for a shapes graph targeting several nodes, the results this entry point yields for node N are exactly the results `validate` yields whose focus is N, in the same order. This is what makes the new entry point trustworthy rather than merely plausible.
- [ ] Tests run against both backends at both `Term_ID` widths, per the family convention.

## Implementation Notes **[CONDITIONAL: Technical Task]**

### Technical Approach

The core already has every piece:

- `validate_focus` is the walk. It needs no change, only a public caller.
- `Validation` construction, `validation_init` / `validation_destroy`, and the
  `Access` adapter set are what `conforms_node` already assembles per call —
  the new entry point assembles the same thing with the caller's visitor
  instead of the conformance probe.
- `shape_index_of` already resolves a shape IRI to the index this API names
  shapes by, so a caller with `ex:RiskShape` can get there.

The one genuine question is naming, and it should be settled against the
existing pair rather than invented: `conforms` / `validate` at graph scope
suggests `conforms_node` / `validate_node` at node scope, with
`validate_node_report` as the report-building form. Worth confirming that
`validate_node` does not read as "validate a node against every targeted
shape", which is a different and also reasonable operation — if the ambiguity
is real, name it for the pair it takes.

### Dependencies

None. The walk, the suppression mechanism, and both backend instantiations all
exist.

Consumer: `odin-rdf-app`, which validates a single submitted resource per
write and must report the violations back to whoever submitted it.

### Risk Considerations

The failure mode to design against is **a second evaluator**. If the new entry
point acquires its own copy of the walk, it will drift from `validate` — and
the drift will show up as two answers to the same question, which is the worst
possible bug in a validator. Mitigations: both paths call `validate_focus`, and
the subset test above pins them together rather than trusting that they agree.

A smaller one: this makes it easy for a consumer to validate a node against a
shape that does not target it, which SHACL permits (§3.4 defines conformance
for any node and shape) but which can mislead — a caller may believe they have
validated a resource when they have checked it against one shape of several
that target it. Worth a sentence in the doc comment, in the register of things
this repository states rather than lets a reader discover.

## Status Updates **[REQUIRED]**

- **2026-08-07 — Created from a consumer design review.** The first application-shaped consumer of the family (`odin-rdf-app`) needed per-resource validation feedback on a write path and found only the boolean. Awaiting pickup in an odin-rdf-shacl session.
