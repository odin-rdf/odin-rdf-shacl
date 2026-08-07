---
id: 002-suppressed-validation-conformance
level: adr
title: "Suppressed validation: conformance without results"
number: 2
short_code: "SHACL-A-0002"
created_at: 2026-08-06T22:02:15.434731+00:00
updated_at: 2026-08-06T22:02:15.434731+00:00
decision_date: 2026-08-06
decision_maker: Greger Olsson
parent:
archived: false

tags:
  - "#adr"
  - "#phase/decided"


exit_criteria_met: false
initiative_id: NULL
---

# ADR-2: Suppressed validation: conformance without results

## Context **[REQUIRED]**

The engine streams. Every validation result goes to the caller's `Result_Visitor` as it is
found, nothing is buffered, and returning false from the visitor stops the traversal where it
stands — reaching the store's iterators rather than being simulated above them. That design is
what makes `Conformance` cost one triple on badly broken data, and what keeps memory flat when
the data is worst.

**Six of SHACL Core's constraint components need the opposite of a report.** `sh:not` (§4.6.1)
validates a node against a shape and violates precisely when the inner shape was *satisfied*,
emitting none of the inner shape's results. `sh:or` (§4.6.3) and `sh:xone` (§4.6.4) need the
same per branch, and count how many branches conformed. `sh:node` (§4.7.1) needs it directly.
`sh:qualifiedValueShape` with `sh:qualifiedMinCount` / `sh:qualifiedMaxCount` (§4.7.3) needs it
per value node, and counts.

The engine has no way to do this today, and none of the six can be built without it. That is
why SHACL-I-0002 ordered its tasks risk-first: the mechanism is designed once, before any
consumer exists, rather than shaped by whichever of the six happened to land first and
retrofitted into the other five.

Three constraints frame the design:

1. **The `Validation` state is not all alike.** Some of it is the caller's — the visitor, its
   data, and the `stopped` flag the visitor sets. Some of it is the whole run's — the model,
   the bindings, the store access, the allocator. And two pieces are shared mutable state
   whose behaviour under nesting is the actual question: the recursion set (`on_stack`) and
   the subclass-closure cache (`classes`).
2. **Recursion detection is positional.** §3.4 leaves recursive shapes undefined and permits a
   processor to signal a failure; this engine does exactly that, at the first re-entry of a
   shape already being validated, detected as a bit per shape index because the set of shapes
   being validated *is* the stack. A suppressed run enters shapes too, so it has to answer
   whether it enters them into the same set.
3. **The flat model and the explicit stack are not negotiable** (SHACL-A-0001 decision 4,
   forced by SPARQL-T-0011's compiler hang). Whatever suppression is, it cannot be "make the
   evaluator recursive".

## Decision **[REQUIRED]**

**A suppressed run is the same walk with the visitor swapped, performed on the in-flight
`Validation` rather than on a copy of it.**

`node_conforms(v, shape_index, focus)` saves `visit`, `visit_data`, and `stopped`; installs a
probe visitor that records one bit and returns false; runs `validate_focus` — the ordinary
stack-driven walk, unchanged; then restores the three saved fields and answers "no result was
produced". Nesting is safe because each level saves its own three values as locals and
restores them in the order it entered.

Four consequences of "reuse, not copy", stated because each is a property something depends on:

- **Shared: the subclass-closure cache.** A suppressed run's `sh:class` checks populate the
  same cache the outer walk uses, and vice versa. This is the correctness argument as much as
  the performance one — see the alternatives.
- **Shared: `failure`.** A suppressed run that hits shape recursion could not answer, and it
  propagates the failure to the whole validation rather than reporting a conformance it never
  established. The outer loop sees it and abandons the traversal, exactly as it would for a
  failure it raised itself. **The boolean answer is meaningless when the failure is set**, and
  the six consumers must check it — the same rule `conforms` already publishes.
- **Restored: `stopped`.** The probe stops at its first result, which sets the same flag a
  caller's visitor sets to abandon a traversal. If that survived the sub-run, one inner
  violation would silently truncate the outer validation and the report would look complete.
- **Not shared: the frame stack.** `validate_focus` builds its own, so a suppressed run has no
  way to disturb the frames of the walk that started it.

**Recursion: a suppressed run shares the outer walk's `on_stack` set.** A shape re-entered
*through* a suppressed check is recursion exactly as one re-entered through `sh:property` is,
and `ex:S sh:not [ sh:node ex:S ]` reports `Failure.Recursive_Shape` rather than validating.

**The mechanism gets a public entry point**, `conforms_node(s, b, access, shape_index, focus)`
in the core with a wrapper per instantiation package. It answers §3.4's conformance question
for one node against one named shape, producing no results.

## Alternatives Analysis **[CONDITIONAL: Complex Decision]**

### How suppression is expressed

| Option | Pros | Cons | Risk | Cost |
|--------|------|------|------|------|
| **Swap the visitor on the in-flight `Validation`** (chosen) | Reuses the walk verbatim; shared state is shared by construction; nesting is LIFO locals; ~15 lines | The save/restore is a discipline rather than a type: a future field belonging to the caller's stream must be added to it | Low | Low |
| Copy the `Validation` for the sub-run | Reads as obviously isolated | **Wrong, not merely costly**: `classes` holds dynamic arrays the inner run appends to, so the outer's copy keeps stale headers and, after a reallocation, dangling ones. Corrupted class closures under nesting, far from the cause | High | Low |
| Split `Validation` into per-run and shared halves, joined by a pointer | Makes the sharing explicit in the type | Splits a struct in two to express what five lines of save/restore already say; touches every field access in the evaluator | Low | Medium |
| A suppression flag on the frame, checked in `emit_result` | Cheapest to write | Leaks in both directions: the mark must be cleared on every abnormal exit, and there is **no natural place to collect the answer** — which is precisely what `sh:or` needs per branch | High | Low |
| A second evaluator for conformance | Could be specialised for early exit | Two implementations of §3.4 that must agree forever; the first divergence would be silent | High | High |

### Whether a suppressed run shares the recursion set

| Option | Behaviour on `ex:S sh:not [ sh:node ex:S ]` | Verdict |
|--------|--------------------------------------------|---------|
| **Share the outer set** (chosen) | `Failure.Recursive_Shape` | Terminates, fails loudly, consistent with `sh:property` recursion |
| Fresh set per suppressed run | **Does not terminate.** Enter `ex:S`, reach `sh:not`, start a sub-run with an empty set, enter `ex:S` again, repeat | Rejected: this is not a different answer, it is no answer |
| Snapshot copy per suppressed run | Identical to sharing in every observable case | Rejected: same behaviour, plus an allocation per ask and a write-back to get wrong |

## Rationale **[REQUIRED]**

**On the mechanism.** The chosen option is the only one that reuses `validate_focus` without
duplicating or reshaping it, and the walk is where the semantics live — one implementation of
§3.4 is the property worth protecting. The copy option is worth recording precisely because it
is the one that looks safest and is not: value semantics on a struct holding dynamic arrays
buys isolation of the headers, not of the storage, and the bug it produces appears only under
nesting.

**On recursion.** The decisive argument is not which reading of §3.4 is nicer — the spec
leaves it undefined and both readings are defensible — but that one of them does not
terminate. Once a fresh set is out, a snapshot and a share are behaviourally identical, and
sharing is the one with no allocation and no write-back.

Sharing also gives the mechanism its memory bound, which is the second reason to prefer it: a
shape cannot appear twice on the stack, so nesting cannot go deeper than `len(s.shapes)`
before the failure is raised. **The depth of a suppressed walk is bounded by the shapes graph,
not by the data**, which is what makes this safe to call per value node.

The cost is honest and worth stating: `ex:S sh:not [ sh:node ex:S ]` is arguably a shapes graph
a cycle-breaking processor could validate ("assume conforming on re-entry"), and this one
refuses it. That refusal is the same one SHACL-I-0001 already chose for `sh:property`
recursion, for the same reason — a failure is not a conformance answer, and the alternative
is a guess the spec does not license.

**On the public entry point.** Two reasons, and the second is the one that decided it. It is a
coherent primitive: "does this node conform to this shape?" is §3.4's own question, and a
caller naming both is doing something ordinary that the whole-graph `conforms` cannot express
— the family's "primitives over frameworks" line. And it is what makes the mechanism testable
against a real backend *now*: the six internal consumers arrive in SHACL-T-0017 and
SHACL-T-0018, so without it the engine's newest and least-covered capability would go two
tasks with no backend-level test at all.

## Consequences **[REQUIRED]**

### Positive

- The six components that need conformance-without-results can be written as ordinary
  constraint cases: ask, get a boolean, emit or do not.
- One implementation of §3.4. A suppressed run and an ordinary one cannot diverge, because
  they are the same procedure.
- Nesting depth is bounded by the number of shapes, not by anything about the data.
- `conforms_node` is a useful public primitive in its own right.

### Negative

- **The save/restore is a discipline, not a type.** A future field that belongs to the
  caller's result stream must be added to `node_conforms`'s three, and nothing in the compiler
  will say so. Mitigated by `shacl/suppress_test.odin`, which asserts each of the three
  explicitly rather than asserting "it worked".
- **No suite entry exercises this until SHACL-T-0017.** Its cover is a hand-built model in the
  core package, an allocation guard over repeated asks, and the backend tests of
  `conforms_node` — deliberately more than a mechanism this size would usually get.
- A suppressed run repeats work: asking twice about the same node and shape validates twice.
  No memoisation, because no consumer has shown it is needed and a conformance cache would
  have to be invalidated by nothing (the data does not change mid-validation) but keyed by
  (shape, node) pairs whose count is unbounded.
- `validate_focus` moved from file-private to package-private. A wider surface inside the
  package, and the compensation is that it is documented as being the whole of a suppressed
  run.

### Neutral

- `sh:detail` remains out of scope (SHACL-I-0002, decided by measurement: it appears nowhere
  in the vendored corpus). If it is ever wanted, the probe is where a child's results would be
  collected instead of discarded, and the change would be local to `Suppressed_Probe`.

## Review Schedule **[CONDITIONAL: Temporary Decision]**

Permanent as a design, but two parts of it are open to evidence.

### Review Triggers

- **A suite entry that a cycle-breaking processor would validate and this one fails.** The
  recursion decision is the one most likely to meet a case in `core/node` or `core/property`
  when SHACL-T-0017 and SHACL-T-0018 land. If one appears, the answer is to revisit
  cycle-breaking as a whole (SHACL-I-0001 left it addable without redesign), not to give
  suppressed runs a private rule.
- **A consumer that needs the inner results, not just the count.** `sh:detail` is the obvious
  one. That reopens `Suppressed_Probe`, not this decision.
- **Measured cost of repeated asks.** `sh:qualifiedValueShape` runs one suppressed validation
  per value node; if that shows up in the benchmarks against a large data graph, memoisation
  is the thing to consider, and this ADR is where the reasoning for not having it lives.
