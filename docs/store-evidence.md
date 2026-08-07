# Store-interface evidence log

Every point where validation wants something odin-rdf-store's match interface
cannot answer, recorded with the concrete shape or target that wants it and
what it would buy. Consolidated into a written proposal at SHACL-T-0008.

**This log is evidence, not a ticket queue.** Nothing here is filed into
odin-rdf-store's Metis from this repository, and nothing here is worked around
with a backend-specific shortcut. Upstream repositories are read-only from this
project; findings go to review as a proposal.

Started SHACL-T-0005. Status below is as of **SHACL-T-0019**, which closes
SHACL-I-0002. Consolidated for review in [`store-proposal.md`](store-proposal.md).

## Summary so far

**Still no capability gap.** That is a result rather than an absence of work: the
vision predicted this project would pull two specific store backlog items, and
neither prediction has survived contact with the code. A validator with all
twenty-nine of SHACL Core's non-SPARQL constraint components reaches the store
through `match` and `find_term` and nothing else.

**SHACL-T-0016 is the task that was supposed to break that, and it half did.**
`sh:closed` asks the data graph a question no earlier component asked — which
predicates a node actually uses — and the store answered it with one ordinary
`match`. What could *not* answer it was this repository's own `Access` struct.
See the section below: the first real finding in this log is a narrowing we
built, not a capability the store lacks, and the log had never thought to look
there.

**SHACL-T-0019 produced the second finding, and it is the first that is about
odin-rdf-store at all.** It is still not a capability gap: it is a *contract* —
both backends relabel loaded blank nodes densely from `b0` per dictionary, so
two stores collide by construction, and a consumer merging terms from both into
one graph must standardise them apart. This engine did not, and shipped reports
that conflated a shape with the value it blamed. The fix is here; what goes
upstream, if anything, is a sentence of documentation. Full write-up below.

**Closing verdict for SHACL-I-0002: no proposal to odin-rdf-store.** Twenty-nine
constraint components, five target forms, seven path forms, suppressed
validation, and 98 of 98 suite entries, all served by `match` and `find_term`.

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

## SHACL-T-0019 — the second finding, and it is a contract rather than a capability

The initiative's closing task, and the one that verifies rather than builds. It
found a defect, and unlike SHACL-T-0016's — which was about a narrowing this
repository wrote — this one is about something odin-rdf-store does. It is still
**not a gap**, and the store is not wrong; what it is is a contract that is true,
documented only in the store's own source, and easy for a consumer to get wrong
in a way nothing catches.

**The contract.** Both backends relabel blank nodes on load. A document's
`_:b79526` does not keep that label: `Load_Scope` maps it to a fresh blank node
from the dictionary, and `fresh_blank` generates `b0`, `b1`, … densely from zero,
per dictionary. This is right and it is deliberate — STORE-I-0001 decision 6 —
because two documents loaded into one store that both write `_:b1` must not be
merged into one node.

**The consequence a consumer meets.** Because the labels are dense from zero *per
store*, two stores hand out **the same labels for unrelated nodes**, with
certainty rather than by unlucky coincidence. Any consumer that takes terms from
two stores and puts them in one graph is performing an RDF merge, and an RDF
merge must standardise blank nodes apart. A SHACL report does exactly that: it
names nodes of the data graph (`sh:focusNode`, `sh:value`) and of the shapes
graph (`sh:sourceShape`), which are two stores by construction here
(SHACL-A-0001 decision 3 destroys the shapes store before the data store opens).

This engine did not standardise them apart, and produced graphs asserting that a
shape and the value it blamed were the same node. Fixed in
`shacl/report.odin` — the data graph's labels are kept, because they are the ones
a consumer can act on; the shapes graph's are prefixed; the report's own are
minted in a third namespace.

**Verdict: nothing to file, and one sentence worth offering upstream.** No
capability is missing and no interface changes. But the store's public
documentation describes what `load_*` does to blank node labels only in the
source of `load.odin`, and the property that bites — *labels are dense from zero
per dictionary, so two dictionaries collide by construction* — is worth stating
where a consumer will read it. That is a documentation suggestion for review, not
a proposal, and it is the only thing this log has ever had to say about the store
itself.

**Why the suite could not have caught it.** Every `core/` entry names one file as
both its data graph and its shapes graph, so the two loads assign identical
labels and merging the two namespaces is accidentally correct. The half that
*was* caught — `property/nodeKind-001` and `complex/personexample` — collided
with the report's own minted labels, which is a third namespace and not a store
question at all.

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

  **SHACL-T-0017 sharpens it again, and this time by a multiplier.** The logical
  combinators run a whole suppressed validation *per branch per value node*, and
  they nest: `sh:and ( [ sh:not … ] [ sh:or ( … ) ] )` is four sub-walks for one
  value node, each re-reading the paths it needs. Nothing new is asked of the
  interface — a suppressed run is the ordinary walk with the visitor swapped, so
  every read it makes is a read the engine already made — but the number of reads
  over one validation is no longer proportional to the data. It is proportional
  to the shapes graph times the data, and SHACL-A-0002 explicitly declined to
  memoise conformance answers until a consumer showed it was needed. If the read
  window ever becomes a real complaint, this is the task that widened it, and the
  answer is likelier to be memoisation here than a snapshot verb upstream.

  **SHACL-T-0018 adds the case where the repetition is provably wasted**, which
  is the first concrete argument for memoisation the engine has produced. A
  qualified property shape with both a minimum and a maximum shares one
  `sh:qualifiedValueShape`, and the two constraints walk the same value nodes
  against the same shape independently — the same question, asked twice, with an
  answer that cannot have changed in between. `qualifiedValueShape-001` and
  `qualifiedValueShapesDisjoint-001` both have that shape, and
  `sh:qualifiedValueShapesDisjoint` multiplies it again by asking each sibling's
  shape per value node.

  Still not a store gap. **And now measured, at SHACL-T-0025**: the duplicate is
  real and is the size this note assumed — one extra walk of every value node,
  +1000 reads and +2000 allocations on a 500-focus-node configuration, about 11%
  of validation time and **+1.2 MB of total allocation**. **The conformance cache
  was decided against**, but not on the memory argument this note first carried:
  peak does not move, yet peak measures *live* bytes and says nothing about a
  caller using an arena, where the total is what is paid. The reason that survives
  is that sharing one walk between the two bounds beats a cache on every axis and
  under every allocator. SHACL-A-0002's "As Measured" section has the full
  reasoning, the correction, and the numbers.

  So the read volume this section worried about is unchanged and will stay
  unchanged: **the engine still asks the store nothing it did not ask before**,
  and nothing here becomes a request upstream.
