# Store-interface evidence log

Every point where validation wants something odin-rdf-store's match interface
cannot answer, recorded with the concrete shape or target that wants it and
what it would buy. Consolidated into a written proposal at SHACL-T-0008.

**This log is evidence, not a ticket queue.** Nothing here is filed into
odin-rdf-store's Metis from this repository, and nothing here is worked around
with a backend-specific shortcut. Upstream repositories are read-only from this
project; findings go to review as a proposal.

Started SHACL-T-0005. Status below is as of that task.

## Summary so far

**Nothing yet.** No capability gap has been found. That is a result rather than
an absence of work: the vision predicted this project would pull two specific
store backlog items, and neither prediction has survived contact with the code.

| Predicted by the vision | Status |
| --- | --- |
| **STORE-T-0017** — a named-graph wildcard for the graph position | **Retired.** Not needed, and cannot become needed without reversing a decision. |
| **STORE-T-0016** — dataset introspection (the named-graph list, a graph's terms) | **Not wanted so far.** Target resolution turned out to be ordinary match patterns. |

## STORE-T-0017 — retired

The vision expected this project to want "any named graph" in the graph
position. It does not, and the reason is structural rather than incidental:
SHACL-A-0001 decision 5 validates **one caller-named graph**, because SHACL is
specified against a single RDF graph and the spec defines no semantics for a
union. Every pattern the validator builds therefore binds the graph position to
a concrete ID.

That is enforced by construction rather than by discipline. Neither `Step` nor
`Scan` — the two procedure pointers the core reaches the store through — takes
a graph parameter; the instantiation package's adapter supplies it from its own
handle. The core has no way to express a wildcard graph.

This can only reopen if a consumer needs cross-graph validation *and* can
defend a semantics for it, which is a review trigger already recorded in
SHACL-A-0001.

## STORE-T-0016 — not wanted so far

The vision expected target resolution to want the named-graph list and a
graph's terms. Having implemented all five Core target forms, none does:

| Target form | What it costs |
| --- | --- |
| `sh:targetNode` | One `find_term`. No match at all. |
| `sh:targetClass` | `rdfs:subClassOf*` closure, then one match per class in it — all patterns with two positions bound. |
| `sh:targetSubjectsOf` | One match, predicate bound, yielding subjects. |
| `sh:targetObjectsOf` | One match, predicate bound, yielding objects. |
| Implicit class target | Identical to `sh:targetClass`; the compiler stores the shape node as the class. |

Every one is served by the published interface as it stands. The prediction may
still come true in the catalogue initiative — `sh:closed` needs the predicates
a focus node actually uses, which is a wildcard-predicate match rather than
introspection, so probably not even there.

## Considered and rejected as a gap: focus nodes absent from the dictionary

Worth recording because it looks like an interface gap and is not.

`sh:targetNode ex:thing` makes `ex:thing` a focus node **whether or not the
data graph mentions it** — the spec targets the node, not its appearances. A
property shape with `sh:minCount 1` must then report a violation, because the
node has no values. But a term the data store has never interned has no
`Term_ID`, so there is nothing for `find_term` to return.

This is not something the store should fix. Assigning an ID would pollute the
dictionary and turn a read into a write, which is exactly what `find_term`
exists to avoid (STORE-T-0014). The right place to absorb it is here, and the
engine does: `Focus_Node` carries `bound: bool` and, when false, the term
borrowed from the compiled model. Every match involving it is empty, which is
correct — no triple can mention a term the dictionary does not hold — and
constraints that inspect the focus term have the term.

The case is only reachable when the shapes graph and the data graph are
different stores, which is why the split-store fixture in
`shacl/memstore/target_test.odin` exists.

## Not yet exercised

Recorded so the log's silence is legible rather than ambiguous:

- **STORE-T-0015 (ordered iteration), STORE-T-0018 (cardinality estimates)** —
  wanted by a planner. This engine has no planner and no join order to choose;
  a shape's targets are resolved in declaration order because the spec makes
  them a set.
- **STORE-T-0019 (snapshot reads)** — validation reads the data graph many
  times (targets, then a path per focus node). A concurrent write between those
  reads would produce a report describing no state the graph was ever in. The
  suites run single-threaded so nothing observes it, and the engine is correct
  over per-operation reads; this is an API-shape question rather than a bug,
  and it is the one item here most likely to become real evidence.
