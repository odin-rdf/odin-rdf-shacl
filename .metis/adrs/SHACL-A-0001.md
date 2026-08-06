---
id: 001-the-shapes-model-representation
level: adr
title: "The shapes model: representation, term ownership, and graph scoping"
number: 1
short_code: "SHACL-A-0001"
created_at: 2026-08-06T13:50:14.567908+00:00
updated_at: 2026-08-06T14:54:42.042733+00:00
decision_date: 
decision_maker: Greger Olsson
parent: 
archived: false

tags:
  - "#adr"
  - "#phase/decided"


exit_criteria_met: false
initiative_id: NULL
---

# ADR-1: The shapes model: representation, term ownership, and graph scoping

## Context **[REQUIRED]**

The shapes model is the compiled representation of a shapes graph — node shapes, property
shapes, targets, paths, and constraint parameters — produced by SHACL-I-0001 and consumed by
every later initiative: the Core constraint catalogue, and SHACL-SPARQL after it. It is this
project's equivalent of odin-rdf-sparql's algebra: the contract that outlives the initiative
that builds it.

Three questions have to be answered together, because their answers are coupled, and all
three are visible in the public API rather than internal:

1. **Where a shapes graph is read from.** Shapes are ordinary RDF. They can be compiled from
   odin-rdf-parser's stream directly, or loaded into a store and read through the match
   interface like any other graph.
2. **Who owns the terms in the compiled model.** The model must name IRIs and literals —
   `sh:path` predicates, `sh:class` targets, `sh:datatype` IRIs, `sh:hasValue` constants. The
   two backends differ here in a way that matters: memstore's `lookup_term` borrows, kvstore's
   allocates, and the store a shapes graph was compiled from may be destroyed while the model
   is still in use.
3. **What "the data graph" means.** SHACL is specified against a single RDF graph
   (SHACL §1.4: validation is defined over *a* data graph). odin-rdf-store holds a quad
   dataset — a default graph plus named graphs — so the API must say which graph validation
   reads. The spec offers no answer because the question does not arise in its model.

The family's constraint on all three: validation reads data exclusively through the store's
published match contract (vision success criterion), and capability gaps become
evidence-backed upstream proposals rather than local workarounds.

## Decision **[REQUIRED]**

1. **Shapes are compiled from a store, through `match`.** The compiler takes a store and a
   graph, not a parser. Compilation is generic over the backend, so a shapes graph persisted
   in kvstore compiles exactly as one in memstore does. The convenience path most callers
   want — a Turtle file on disk — is a helper in `shacl/memstore` that parses into a memstore
   and compiles from it, keeping the core `shacl` package free of any backend dependency.

2. **The compiled model holds `rdf.Term` values, not `Term_ID`s.** The shapes graph and the
   data graph may live in different stores with different dictionaries, so a `Term_ID` from
   the shapes store means nothing against the data store. Binding to the data store's IDs
   happens once at validation setup, as odin-rdf-sparql's term-binding bridge does for
   algebra constants.

3. **The model interns and owns every term it holds**, and frees them at `shapes_destroy`.
   The model is therefore independent of the store it was compiled from: that store may be
   destroyed immediately after compilation. Shapes graphs are small and bounded, so ownership
   is cheap, and it removes a lifetime coupling that would otherwise be load-bearing and
   backend-dependent (memstore borrows, kvstore allocates).

4. **The model is a flat array with children named by index**, walked by an explicit stack
   rather than by recursion. This is not a stylistic choice: SPARQL-T-0011 established that a
   generic procedure taking `$`-procedure constants and calling itself sends the Odin compiler
   (dev-2026-07) into unbounded instantiation — it hangs rather than failing — and that a
   self-referencing parametric struct does the same. SHACL's evaluator is naturally recursive
   (`sh:node`, the logical combinators, `sh:qualifiedValueShape`), so the constraint binds
   here harder than it did in odin-rdf-sparql.

5. **Validation reads one caller-named graph.** `validate` takes the graph to read — the
   default graph, or one named graph. The graph position is therefore a bound constant in
   every `match` call the validator makes. Dataset-union validation is *not* offered in v1;
   if it is ever wanted it arrives as an explicit, separately documented mode, not as the
   default meaning of "the data graph".

6. **Recursion is detected and reported as a failure**, using the shape set carried on the
   evaluator's explicit stack. The SHACL specification leaves the validation of recursive
   shapes undefined and permits a processor to signal a failure rather than support them.
   Cycle-breaking ("assume valid on re-entry") is a strictly additive future option.

## Alternatives Analysis **[CONDITIONAL: Complex Decision]**

| Option | Pros | Cons | Risk Level | Implementation Cost |
|--------|------|------|------------|-------------------|
| Compile from a store via `match` (chosen) | Random access is what compilation needs; consumes the family's own interface; persisted shapes graphs work unchanged | Requires a store for the common "shapes in a .ttl file" case — absorbed by a helper in `shacl/memstore` | Low | Low |
| Compile from the parser stream | No store needed for a file; fewer moving parts in the simplest case | Compilation is random-access (follow `sh:property` → blank node → its parameters); a stream forces buffering the whole graph plus a private index — a store, reimplemented worse | Medium | Medium |
| Model holds `Term_ID`s of the shapes store | Integer comparisons inside the model; smaller | Meaningless against a different data store; couples model lifetime to the shapes store; breaks the split-store case entirely | High | Low |
| Model borrows terms from the shapes store | No interning cost; zero-copy, matching RDF-A-0001's spirit | Backend-dependent lifetime (memstore borrows, kvstore allocates); the shapes store must outlive every validation; a footgun in the public API | Medium | Low |
| Validate the dataset union | One call validates everything; no graph argument to get wrong | The spec defines no semantics for it, so suite results become indefensible; needs the store's named-graph wildcard (STORE-T-0017) | High | Medium |
| Support recursion by cycle-breaking | More useful to shape authors; no failure on legitimate-looking shapes | Semantics undefined by the spec, so correctness is asserted against our own reading rather than the suite; more machinery in the spine | Medium | Medium |

## Rationale **[REQUIRED]**

- **Compilation is random access, and that settles question 1 on the merits rather than on
  principle.** Reading a property shape means following `sh:property` to a blank node and then
  reading `sh:path`, `sh:minCount`, `sh:class` off *that* node. A streaming parser delivers
  document order. Compiling from the stream would mean buffering every triple and building an
  index over it — which is a store, written again and worse. That the store-based answer also
  honours "consume the interface, don't bypass it" is a bonus, not the argument.

- **Ownership beats borrowing here precisely because the two backends disagree.** The family's
  zero-copy discipline (RDF-A-0001) is about the hot path, and shapes compilation is not one:
  it runs once, over a small graph, and its output is consulted for the lifetime of a
  validator. Paying a bounded interning cost once buys a model with a single, backend-independent
  lifetime rule that can be stated in one sentence of the public contract.

- **The single-graph decision keeps conformance defensible and retires an upstream
  dependency.** SHACL's own model is one graph; adopting it means every suite result means what
  the spec says. It also removes the need for STORE-T-0017 (a named-graph wildcard), which the
  vision predicted this project would pull — that prediction rested entirely on dataset-wide
  validation being the default.

- **The flat-array/explicit-stack shape is forced, and is cheaper to adopt than to retrofit.**
  The compiler hang is a known, documented failure mode from odin-rdf-sparql, and it hangs
  rather than erroring — the worst way to discover a constraint. Adopting the known-good shape
  from the first line costs nothing; discovering it at `sh:node` in the catalogue initiative
  would mean rebuilding the model's representation with consumers already attached.

- **Detect-and-fail on recursion is what the spec sanctions**, is deterministic, and is nearly
  free given decision 4 — the stack that avoids the compiler hang is the same stack that
  detects re-entry. Supporting recursion is additive later; a spine built around a fixpoint
  assumption would be much harder to simplify.

## Consequences **[REQUIRED]**

### Positive

- A compiled shapes model that can be built once and used against many data graphs, in many
  stores, with a lifetime rule independent of both.
- Persisted shapes graphs work with no special case: compile from kvstore exactly as from
  memstore.
- The core `shacl` package depends on no backend, so a Core-only, in-memory consumer never
  links LMDB.
- Every `match` call the validator makes is fully bound in the graph position, which is the
  cheapest pattern a backend can serve.
- STORE-T-0017 is not needed by this project, reducing the upstream surface the vision
  anticipated.

### Negative

- **Interning costs a copy of every term in the shapes graph.** Bounded and small, but it is a
  real departure from the family's borrow-by-default reflex and must be documented as a
  deliberate exception rather than an oversight.
- **`sh:class` walks `rdfs:subClassOf*` in the data graph**, so under the single-graph decision
  a class hierarchy must live in the graph being validated. This is a genuine user-facing
  surprise and needs prominent documentation, not a footnote.
- **No dataset-union validation in v1.** Callers wanting it must validate graph by graph and
  combine reports themselves, which is not equivalent for cross-graph constraints.
- **Legitimately recursive shapes are rejected rather than validated.** Data of the
  asset-points-at-asset shape invites `sh:node`; users who reach for it get a reported failure.
  Intended, spec-sanctioned, and documented — but it will be met as a limitation.
- **The flat-array representation is less readable than a pointer tree** and its index-named
  children need care in review. The alternative does not compile.

## As Built (SHACL-T-0003, 2026-08-06)

Every decision above is implemented as written. Three things the design phase did not
anticipate are recorded here rather than left for rediscovery.

**1. The compiler-hang constraint has a second, sharper face.** Decision 4 was taken
against the failure SPARQL-T-0011 documented: a generic procedure over `$`-procedure
constants that calls itself hangs the compiler. The constraint that actually bit first
was different and fails loudly rather than hanging — a generic procedure **cannot forward
its `$MATCH` constant to another generic procedure**, because the callee would be
introducing `$It` in the return type of a procedure-typed parameter and the compiler
reports *"cannot determine complete type of partial polymorphic procedure"*.

The fix is the one odin-rdf-sparql already uses without naming it: bind `$D` and `$It` on
an earlier *value* parameter, which is why its helpers take `e: ^Exec($D, $It)` first.
This repo's equivalent is `Reader($D, $It)` in `shacl/query.odin`, carrying the dataset,
the graph, and the RDF-list vocabulary that nearly every read needs anyway. Decision 4 is
unchanged; it now has two independent reasons rather than one.

**2. Shape discovery is narrower than §2.1.1, deliberately.** The spec defines a shape
broadly — including any node that is the value of a shape-expecting parameter such as
`sh:node`. The spine implements three cases: a node typed `sh:NodeShape` or
`sh:PropertyShape`, a node carrying a target declaration, and a value of `sh:property`.
That covers the exit-criteria directories. The catalogue initiative widens it when
`sh:node` and the logical combinators arrive, which is the case this omits.

**3. Decision 6 is designed but not yet realised.** Recursion detection belongs to the
evaluator's stack, and there is no evaluator until SHACL-T-0007. The model and the
compiler are structured for it — the flat array and the explicit walk are in place — but
nothing detects a recursive shape today, because nothing yet follows one.

Two properties are asserted rather than assumed. The model's independence from its store
is tested on both backends by destroying the store before reading the model, which matters
far more on kvstore, where every term is built from database bytes that closing
invalidates. And compilation's read-only nature is tested by compiling from a **read-only
LMDB environment**: `find_term` never assigns, so a shapes graph can be compiled from a
store opened without write access — the strongest available form of "compiling never
writes".

## As Built (SHACL-T-0007, 2026-08-06)

Decision 6 is now realised, and the two user-facing consequences above are documented rather
than merely predicted. Three notes.

**1. Recursion detection is the stack, not a search.** The evaluator is an explicit stack over
the flat model, so "the shapes currently being validated" is literally the stack contents, and
membership is one bit per shape in a `[]bool` sized by the model. Detection fires at the
re-entry itself, before another triple is read, and `validate` returns
`Failure.Recursive_Shape`. Cost: one bit per shape and one branch per shape entered.

The distinction that has to reach users, and now does — package doc, README, and the test that
pins it — is that **cycles in data are not recursion**. `ex:a ex:partOf ex:b ex:partOf ex:a`
validates normally; every path form is separately cycle-safe by a visited set. What triggers a
failure is a *shape* that reaches itself. Since `sh:node` is a catalogue constraint, the only
way to write one today is a `sh:property` self-reference, which is what the spine's recursion
test uses — the mechanism reached is identical.

Also settled by the implementation: a shape reached twice as a **sibling** is not recursion.
The on-stack set is what is currently being validated, not what has ever been validated, so a
property shape shared by two parents is validated twice, correctly. Getting this backwards
would have turned every reused shape into a spurious failure.

**2. The `sh:class` consequence is documented where it will be met.** It appears in the package
doc's contracts section, in the README's "three things to know", and beside the check itself.
The framing that seems to land: `sh:targetClass` walks the same closure, so a target that
unexpectedly finds nothing usually has the same cause as a `sh:class` that unexpectedly passes.

**3. Term ownership paid for itself in an unplanned place.** Decision 3 was justified by the
two backends disagreeing about `lookup_term`. The W3C suite runner turned out to depend on it
for a different reason: it loads an entry's shapes graph and data graph into **two separate
stores**, destroying the first before opening the second, even though nearly every entry names
the same file for both. That is only possible because the model owns its terms — and it means
the ownership property is exercised on all 40 entry runs per width rather than only in the two
tests that name it. It also keeps the two graphs' blank-node label spaces apart, which the
entries with separate shapes files would otherwise need a special case for.

## Review Triggers

This decision should be revisited if any of the following occurs:

- **A consumer needs cross-graph or dataset-wide validation** with a semantics it can defend.
  That reopens decision 5 and, with it, the STORE-T-0017 question.
- **Recursive shapes turn out to be common** in real shapes graphs rather than a corner case —
  which would make decision 6's failure mode a recurring obstacle rather than a documented
  limit.
- **Interning shows up in a profile**, which would mean shapes graphs are far larger than
  assumed and decision 3's cost analysis was wrong.
- **The Odin compiler fixes the unbounded-instantiation hang**, which would make decision 4's
  flat array optional rather than forced. The representation would still be defensible; the
  argument for it would change.