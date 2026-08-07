# Store-interface evidence log

Every point where validation wants something odin-rdf-store's match interface
cannot answer, recorded with the concrete shape or target that wants it and
what it would buy. Consolidated into a written proposal at SHACL-T-0008.

**This log is evidence, not a ticket queue.** Nothing here is filed into
odin-rdf-store's Metis from this repository, and nothing here is worked around
with a backend-specific shortcut. Upstream repositories are read-only from this
project; findings go to review as a proposal.

Started SHACL-T-0005. Status below is as of **SHACL-T-0016**, the task
SHACL-I-0002 named as the one most likely to produce a finding. Consolidated for
review in [`store-proposal.md`](store-proposal.md).

## Summary so far

**Still no capability gap.** That is a result rather than an absence of work: the
vision predicted this project would pull two specific store backlog items, and
neither prediction has survived contact with the code. A validator with
twenty-one constraint components reaches the store through `match` and
`find_term` and nothing else.

**SHACL-T-0016 is the task that was supposed to break that, and it half did.**
`sh:closed` asks the data graph a question no earlier component asked — which
predicates a node actually uses — and the store answered it with one ordinary
`match`. What could *not* answer it was this repository's own `Access` struct.
See the section below: the first real finding in this log is a narrowing we
built, not a capability the store lacks, and the log had never thought to look
there.

| Predicted by the vision | Status |
| --- | --- |
| **STORE-T-0017** — a named-graph wildcard for the graph position | **Retired.** Not needed, and cannot become needed without reversing a decision. |
| **STORE-T-0016** — dataset introspection (the named-graph list, a graph's terms) | **Retired.** Target resolution turned out to be ordinary match patterns, and so did `sh:closed`, which was the last thing predicted to want it. |

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

**SHACL-T-0016 settled it: not even there.** `sh:closed` is implemented and asks
for nothing STORE-T-0016 would supply. What it wants is the outgoing triples of
one node, which is a match pattern, and the section below is what that turned up
instead.

## SHACL-T-0016 — `sh:closed`, and the first finding this log has produced

The initiative singled this component out as the likeliest source of store
evidence, for a good reason: it is the only one that asks what a node *has*
rather than checking a value the shape already named. Recorded in full, including
the part that is a non-finding, because a prediction that half held is worth more
than a verdict.

**What the store was asked for: one match, already served.** The question is "the
predicates and objects of every triple with this node as subject", and the
pattern is `(node, *, *, graph)` — two positions bound, two wildcard, the graph
bound like every other read this engine issues. `match` returns whole
`Encoded_Quad`s, so the predicate and the object arrive together with no second
read and no new verb. Both backends served it unchanged; neither needed a line.

**What did not serve it: `Access`, which is ours.** The core reaches the data
graph through a struct of procedure pointers the instantiation packages fill in,
and until this task it had three read verbs — `Scan`, which streams **one**
position of each matched quad, `Step`, which streams nodes reachable by a
predicate, and `Term_Loader`. Every question the engine had asked until now
wanted a single position, so the narrowing had never cost anything. `sh:closed`
wants the predicate and the object of the *same* triple, and no composition of
those three produces a pair: `Scan` yielding `QUAD_P` and then a `Step` per
predicate found is two reads per node and a different answer on a repeated
predicate.

So `Access` gained a fourth verb, `Outgoing`, and each instantiation package
gained an eight-line adapter around the same `match` it already calls.

**Why this belongs in an evidence log about somebody else's interface.** Because
the log had been asking one question and there were two. "Can the published
interface answer this?" was asked at every component and always answered yes.
"Can *our* narrowing of it answer this?" was never asked at all, because the
narrowing was written before there was a component that strained it — and a
narrowing that predates its consumers is exactly the thing that quietly becomes
the constraint. Nothing was worked around: the fix is in this repository, where
it belongs, and no backend-specific shortcut was taken. But an engine that had
been less careful would have reached this point, found `Access` insufficient,
and filed it upstream as a store gap.

**One thing this sharpens, without changing a verdict.** `sh:closed` reads an
empty answer as "this node uses no predicates" and reports conformance, so on the
persistent backend a failed read is silently a *pass* rather than silently a
missing value node. That is the hazard `shacl/kvstore/eval.odin`'s header already
names and `session_error` already covers; it is recorded here only because this
is the component where the consequence is most inverted, and a caller who skips
the error check has a `sh:conforms true` that means nothing.

Verdict: **no proposal to odin-rdf-store from this task.** STORE-T-0016 is
retired as a prediction rather than merely unexercised — the one target this
project had for wanting graph introspection has landed and does not want it.

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

## Considered and rejected as a gap: "does this node have a type in this set?"

The one question constraint evaluation asks that the interface does not answer
directly. `sh:class ex:C` holds of a value node when the node carries an
`rdf:type` somewhere in `ex:C`'s downward `rdfs:subClassOf*` closure — a *set*
membership test, where the interface offers one bound-object match at a time.

Two shapes of workaround suggest themselves and both are worse than what the
engine does. Asking the store once per class in the closure is |closure| matches
per value node. Asking for a set match would be a new interface verb, which is a
capability request built on one component's convenience rather than on evidence.

What the engine does instead: compute the closure once per class per validation,
into a `map[Term_ID]bool`, and then issue **one** match per value node —
`(value, rdf:type, *)` — stopping at the first type in the set. That is one
store call per value node, which is the same cost as any other value-scoped
component, and the closure is a walk the interface already serves. The cache
lives in `Validation` and is a linear scan over the handful of classes a shapes
graph names.

Recorded because the shape of the question recurs: `sh:node` and
`sh:qualifiedValueShape` in the catalogue initiative will want membership tests
too, and the answer will be the same one — build the set above the interface,
ask the interface for one bound match.

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

  **SHACL-T-0007 sharpens it without changing the verdict.** A full validation
  is now measurably read-heavy — one scan per target declaration, one match per
  path step per focus node, one match per value node per `sh:class` — so the
  window a concurrent writer could open in is wide rather than theoretical. It
  is still not a *gap*: nothing in the interface is missing, and the question is
  whether a caller can pin a read view. Left as it is because no consumer has
  asked, and inventing the requirement here would be the opposite of
  evidence-driven.
