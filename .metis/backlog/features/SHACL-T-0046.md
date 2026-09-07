---
id: shacl-sparql-the-cross-node-rule
level: task
title: "SHACL-SPARQL: a consumer's first cross-node rule, and the shape of the demand"
short_code: "SHACL-T-0046"
created_at: 2026-09-07T00:00:00.000000+00:00
updated_at: 2026-09-07T00:00:00.000000+00:00
parent: 
blocked_by: []
archived: false

tags:
  - "#task"
  - "#feature"
  - "#phase/backlog"


exit_criteria_met: false
initiative_id: NULL
---

# SHACL-SPARQL: a consumer's first cross-node rule, and the shape of the demand

## Objective **[REQUIRED]**

Record the first concrete demand for the SHACL-SPARQL phase the vision names,
with the case that produced it, so that when the phase starts it starts from a
rule somebody actually needed rather than from the specification's chapter
order. **Not a request to build it now**: the consumer worked around it, and
the workaround is described below because it bounds what SHACL-SPARQL would
have to be worth.

## Context

`odin-rdf-app` — the placeholder consumer this repository writes its
consumer-driven items against — lets an administrator declare, *as data*, a
property whose values come from a `skos:ConceptScheme`:

```turtle
app:sensitivity
    a app:Aspect ;
    rdfs:label "Sensitivity" ;
    rdfs:domain app:Thing ;
    app:scale app:sensitivity-levels .

app:sensitivity-levels a skos:ConceptScheme .
app:low  a skos:Concept ; skos:inScheme app:sensitivity-levels .
app:high a skos:Concept ; skos:inScheme app:sensitivity-levels .
```

A value is one triple, `<thing> app:sensitivity app:high`, and the rule that
must hold is:

> the object of `?p` is a `skos:Concept` **in the scheme that `?p` declares
> through `app:scale`**.

That is a cross-node rule. The constraint on the object depends on a term
reached from the **predicate**, which is not the focus node and not on any
path from it. Core has no way to state it: `sh:in` enumerates a fixed list at
authoring time, `sh:class skos:Concept` admits a concept from *any* scheme,
and there is no property shape whose value set is computed. In SHACL-SPARQL it
is one `sh:sparql`:

```sparql
SELECT $this ?value WHERE {
  $this ?p ?value .
  ?p app:scale ?scheme .
  FILTER NOT EXISTS { ?value skos:inScheme ?scheme }
}
```

## What the consumer does instead, and why it is worth recording

It **generates a Core shape per declared property** when the property is
written, and regenerates it when the scheme's membership changes:

```turtle
app:sensitivity-shape
    a sh:PropertyShape ;
    sh:targetSubjectsOf app:sensitivity ;
    sh:path app:sensitivity ;
    sh:maxCount 1 ;
    sh:in ( app:low app:high ) .
```

This works, and it works well — the shape is data in the same graph as the
declaration, the engine compiles it with everything else, and the rule is
enforced by SHACL rather than by a check in application code, which is that
consumer's own standing rule. Three things it costs, and they are the honest
measure of what SHACL-SPARQL would buy:

1. **The generated shape is derived state that must be kept in step.** Adding a
   concept to a scheme has to rewrite the `sh:in` list of every property
   drawing on that scheme. The consumer does this transactionally, in the same
   changeset, and holds it with a test.
2. **It is regenerated per writer scope.** A property declared in one graph and
   a scheme in another means the derived shape can lag when the write that
   would refresh it happens somewhere the writer cannot write.
3. **The list is enumerated, so its size is the scheme's.** A scheme of a few
   dozen values is nothing; a scheme of thousands would put a value list of
   thousands into a shapes graph that is compiled on a write path.

None of those is currently painful. If the phase is scheduled on demand rather
than on the specification's order, this is one data point and not a forcing
one.

## Design notes for the phase, from this case

- **The constraint's query must run under the session's own graph set.**
  `SHACL-T-0039` gave a `Session` a set of graphs and made the three read verbs
  honour it; a `sh:sparql` constraint that ran unscoped would see more than the
  validation it serves — which for a consumer whose graph set *is* its
  authorization boundary is not a performance question but a disclosure one.
  `SHACL-T-0039`'s implementation notes already flag this; this item is the
  concrete case behind the flag.
- **`$this` and pre-bound variables** are the specification's, and
  `odin-rdf-sparql` takes a text and a scope (`query_init`), so the binding
  seam is a substitution or an initial solution rather than a new API.
- **Optional dependency, as the vision says.** A Core-only consumer must keep
  compiling and validating with no query engine linked.

## Acceptance Criteria **[REQUIRED]**

*(For the phase, not for this item, which is a record.)*

- [ ] The rule above expressible as one `sh:sparql` constraint, with a test
      over a two-scheme fixture: a value from the declared scheme conforms and
      one from another scheme reports.
- [ ] The constraint's query reads through the session's graph set, with a test
      that a fact outside the set reaches no solution.
- [ ] Core-only builds unaffected: no query-engine symbol required, and the
      existing pins unchanged.

## Implementation Notes

### Dependencies

`odin-rdf-sparql`, optionally. Nothing from the record beyond what is pinned.
`SHACL-T-0039` is what makes the scoping requirement statable.

### Effort

Not estimated; this is a filed demand, not a plan.

## Status Updates **[REQUIRED]**

- **2026-09-07 — Filed** from `odin-rdf-app`'s classification model, which met
  the first rule Core could not state and worked around it with a generated
  per-property `sh:in` shape. Recorded so the SHACL-SPARQL phase has a real
  case to start from, and so the workaround's three costs are on the record as
  the measure of what the phase is worth. Not scheduled; whether the phase
  starts is the owner's call.
