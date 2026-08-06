# Proposal to odin-rdf-store: nothing

**From:** odin-rdf-shacl, SHACL-I-0001 (the SHACL Core spine)
**Status:** for review. **Not filed into odin-rdf-store's Metis from this repository.**
**Evidence:** [`store-evidence.md`](store-evidence.md), kept from SHACL-T-0005 onward.

## The proposal

The initiative found **no capability gap** in odin-rdf-store's match interface, and
proposes **no change to it**.

That is the whole proposal, and it is worth stating as a document rather than as a
shrug, because two specific changes were predicted before the work started and the
evidence retired both. A silent "we didn't need it" would leave those predictions
standing in the vision as though still open.

## What was predicted, and what happened

| Predicted by the vision | Outcome |
| --- | --- |
| **STORE-T-0017** — a named-graph wildcard in the graph position | **Retired.** Cannot become needed without reversing a design decision. |
| **STORE-T-0016** — dataset introspection (named-graph list, a graph's terms) | **Not wanted.** Every Core target form is an ordinary match pattern. |

### STORE-T-0017 — retired, structurally

The wildcard was wanted for validating a *union* of graphs. SHACL-A-0001 decision 5
validates **one caller-named graph** instead, because SHACL is specified against a
single RDF graph and the spec defines no semantics for a union — a union mode would
have made suite results indefensible.

This is enforced by construction rather than by discipline. The two procedure pointers
the core reaches the store through, `Scan` and `Step`, **take no graph parameter**; the
instantiation package's adapter supplies it from its own handle. The core has no way to
express a wildcard graph, so it cannot drift into wanting one.

Reopening requires a consumer that needs cross-graph validation *and* can defend a
semantics for it. That is already a recorded review trigger on SHACL-A-0001.

### STORE-T-0016 — not wanted

All five Core target declarations are implemented. None wants introspection:

| Target form | What it costs |
| --- | --- |
| `sh:targetNode` | One `find_term`. No match at all. |
| `sh:targetClass` | An `rdfs:subClassOf*` closure, then one match per class in it — every pattern two positions bound. |
| `sh:targetSubjectsOf` | One match, predicate bound, yielding subjects. |
| `sh:targetObjectsOf` | One match, predicate bound, yielding objects. |
| Implicit class target | Identical to `sh:targetClass`; the compiler stores the shape node as the class. |

The prediction may still come true in the catalogue initiative, but probably not:
`sh:closed` wants the predicates a focus node actually uses, which is a
wildcard-predicate match rather than introspection.

## Two near-misses, recorded because they look like gaps

Both are cases where the interface does not answer the question directly and the right
answer was still not to change the interface. They are written down so the reasoning is
not re-derived — and re-decided differently — by the catalogue initiative.

### Focus nodes absent from the dictionary

`sh:targetNode ex:thing` makes `ex:thing` a focus node **whether or not the data graph
mentions it** — the spec targets the node, not its appearances. A property shape with
`sh:minCount 1` must then report a violation. But a term the data store has never
interned has no `Term_ID`, so `find_term` has nothing to return.

**Not the store's problem.** Assigning an ID would pollute the dictionary and turn a
read into a write, which is precisely what `find_term` exists to avoid (STORE-T-0014).
The engine absorbs it: `Node_Ref` carries `bound: bool` and, when false, the term
borrowed from the compiled model. Every match involving it is empty — correct, since no
triple can mention a term the dictionary does not hold — and the constraints that need
to inspect the node have the term.

### "Does this node have a type in this set?"

`sh:class ex:C` holds of a value node when the node carries an `rdf:type` somewhere in
`ex:C`'s downward `rdfs:subClassOf*` closure. That is a **set membership** test, where
the interface offers one bound-object match at a time.

Two workarounds suggest themselves and both are worse. Asking the store once per class
in the closure is `|closure|` matches per value node. Asking for a set-match verb would
be a capability request built on one component's convenience rather than on evidence.

What the engine does instead: compute the closure once per class per validation into a
`map[Term_ID]bool`, then issue **one** match per value node — `(value, rdf:type, *)` —
stopping at the first type in the set. One store call per value node, the same cost as
any other value-scoped component, over a closure the interface already serves.

**The shape of this question recurs.** `sh:node` and `sh:qualifiedValueShape` in the
catalogue initiative will want membership tests too, and the answer should be the same
one: build the set above the interface, ask the interface for one bound match.

## The one item most likely to become real evidence

**STORE-T-0019 (snapshot reads).** A full validation is measurably read-heavy — one scan
per target declaration, one match per path step per focus node, one match per value node
per `sh:class`. A concurrent write partway through would produce a report describing no
state the graph was ever in.

This is **not** a gap: nothing in the interface is missing, and the question is whether a
caller can pin a read view across many operations. The engine is correct over
per-operation reads, the suites run single-threaded so nothing observes it, and no
consumer has asked. Inventing the requirement here would be the opposite of
evidence-driven — so it is recorded, not proposed.

Two more are listed as not-yet-exercised in the evidence log: **STORE-T-0015** (ordered
iteration) and **STORE-T-0018** (cardinality estimates), both wanted by a planner. This
engine has no planner and no join order to choose.

## What this means for the vision

The vision predicted this project would pull two store backlog items. It pulled neither,
against a complete validation path rather than a partial one — targets, paths, seven
constraint components, and report emission, greening four of the suite's seven `core/`
directories on both backends at both `Term_ID` widths. The prediction should be marked as
not confirmed rather than left pending.
