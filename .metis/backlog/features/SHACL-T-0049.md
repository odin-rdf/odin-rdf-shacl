---
id: context-only-graphs-in-a-union
level: task
title: "Context-only graphs in a union session: targets from some graphs, lookups across all"
short_code: "SHACL-T-0049"
created_at: 2026-09-16T15:15:46.294062+00:00
updated_at: 2026-09-16T15:15:46.294062+00:00
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

# Context-only graphs in a union session: targets from some graphs, lookups across all

## Objective **[REQUIRED]**

Let a caller validate over a union in which **some graphs supply focus nodes
and all of them supply values**, so that a graph added only so a reference
resolves is not also validated. **Low priority**: the consumer that asks for
it has a workaround, below, that costs nothing measurable today. The item
records the demand and the case, so the design starts from a real case.

## Context

`session_init_union` (SHACL-T-0039) gives a session one set of graphs, and the
engine uses that set for two jobs: the targets are selected from it, and every
path and `sh:class` lookup reads it. For a single data graph those are the
same thing, which is SHACL's model. A consumer that validates **one tenant's
write against a union** needs them apart.

`odin-rdf-app`, the placeholder consumer this repository writes its
consumer-driven items against, validates each write over:

- the graphs the write touches and the writer's own graphs, which it wants
  **validated**; and
- graphs it adds **only so that references resolve**: an ancestor tenant's
  public graph (a child's `app:parent` is `sh:class app:Tenant`, and the
  parent's type lives in the parent's graph), and the vocabulary graphs,
  which it now needs because data concepts point at schemes the vocabulary
  declares:

```turtle
# vocabulary graph
app:type-scheme a skos:ConceptScheme .

# a tenant's data graph
app:type-a a skos:Concept ; skos:inScheme app:type-scheme .

# the shape, compiled from the vocabulary
app:ConceptShape a sh:NodeShape ;
    sh:targetClass skos:Concept ;
    sh:property [ sh:path skos:inScheme ; sh:class skos:ConceptScheme ] .
```

`app:type-a` conforms only if the vocabulary graph is in the union. Once it
is, every node the vocabulary's shapes target is a focus node on every write:
the schemes, and any individuals and concepts the vocabulary declares.

## What the consumer does instead, and what it costs

It passes the whole union and accepts that the lookup graphs are validated
too.

- **Time:** nothing measurable. 200 gated writes took 2.1 ms each with the
  vocabulary in the union and without it.
- **Coupling:** a node in a lookup graph that does not conform refuses every
  write that includes that graph, including writes that have nothing to do
  with it. For the vocabulary, the consumer guards this with a test that the
  shipped vocabulary conforms. For an ancestor's public graph there is no
  guard: a statement committed there under `record.Mode.Record` that does not
  conform blocks the whole subtree's writes until someone fixes it. The
  consumer's suite shows it: a violator committed under `Record` in a graph
  makes the next `Enforce` write to that graph refuse a conforming asset.

## Design notes

- Two sets, not two sessions. The union is still one data graph for
  lookups, so a focus node's own triples in a lookup graph still count (a
  node typed in a lookup graph and described in a focus graph is one node).
  Only **target selection** is restricted to the focus set.
- A plausible surface is an optional focus set on the existing entry point,
  `session_init_union(se, snap, graphs, focus = nil)`, where nil keeps
  today's behaviour. Whether `sh:targetNode` for a node outside the focus
  graphs is still a target is a question for the design; the consumer only
  uses `sh:targetClass`.
- Record already filters by a graph set per fact (RECORD-T-0029), so target
  selection over the focus set is the same filter with a smaller set. No
  record change is expected.
- This is not SHACL's shapes graph versus data graph: the lookup graphs are
  data.

## Acceptance Criteria **[REQUIRED]**

- [ ] A union session can name a focus subset. Targets come from it; every
      lookup reads the whole union.
- [ ] With no focus subset given, behaviour is unchanged (the existing union
      tests pass as they are).
- [ ] A test: a non-conforming node in a lookup-only graph produces no
      result, and a reference from a focus node into that graph still
      resolves.
- [ ] A test: a node described across a focus graph and a lookup graph is
      judged on all its triples.

## Status Updates **[REQUIRED]**

- 2026-09-16: filed from the consumer's case above, low priority. The
  consumer runs with the whole union and a conformance test on its
  vocabulary until this lands.
