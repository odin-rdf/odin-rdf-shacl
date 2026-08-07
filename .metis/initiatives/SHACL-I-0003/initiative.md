---
id: performance-evidence-a-benchmark
level: initiative
title: "Performance evidence: a benchmark workload, and the memoisation decision"
short_code: "SHACL-I-0003"
created_at: 2026-08-07T10:48:30.161797+00:00
updated_at: 2026-08-07T10:48:30.161797+00:00
parent: SHACL-V-0001
blocked_by: []
archived: false

tags:
  - "#initiative"
  - "#phase/discovery"


exit_criteria_met: false
estimated_complexity: S
initiative_id: performance-evidence-a-benchmark
---

# Performance evidence: a benchmark workload, and the memoisation decision Initiative

## Context **[REQUIRED]**

Third initiative under SHACL-V-0001, and the first that is not about correctness.

SHACL Core is complete and measured: twenty-nine constraint components, all 98 entries of
the vendored W3C SHACL 1.0 `core/` suite green against both backends at both `Term_ID`
widths (SHACL-I-0002, closed 2026-08-07). **What the library has no evidence about at all
is cost.** `bench/` does not exist; `make bench` and `make build-bench` print "no bench/
package yet" and exit 0.

Three things make that a gap rather than a nicety:

- **It is the family's standard, though not universally kept.** odin-rdf-parser's
  headline claim — steady-state-zero-allocation parsing — is a *benchmark* result, not a
  test result, and odin-rdf-store ships a bulk-load benchmark (STORE-T-0006). `make bench`
  is listed as a family command for every project.

  **odin-rdf-sparql has no `bench/` either**, and that is worth stating rather than
  quietly omitting: two of four repositories have benchmarks, not three. It weakens the
  "everyone else does it" argument and it is a finding about the family rather than about
  this repository — a query engine with no performance evidence is at least as odd as a
  validator with none. Not this initiative's problem to fix, but the observation belongs
  upstream if anyone is collecting them.
- **The deployment shape is the argument.** ~200 processes per physical machine, each
  embedding a store, with CPU frugality a first-order requirement. Validation is the
  hungriest thing the family does, and it is the only part with no number attached.
- **A decision is blocked on it.** SHACL-A-0002 declined to memoise conformance answers
  until *measured* cost justified it. SHACL-T-0018 then found the case where the
  repetition is provably wasted, and SHACL-T-0017 widened it: the logical combinators run
  a suppressed sub-walk per branch per value node, so read volume is now proportional to
  shapes × data rather than to data. **A review trigger that can never fire is not a
  trigger**, and that is the state it is in today.

### Why this is an initiative and not a task

**Family precedent says task.** Both siblings folded benchmarking into a functional
initiative's closing task — RDF-T-0021 (allocation guards *and* benchmarks for
Turtle/TriG), STORE-T-0006 (round-trip test, bulk-load benchmark, and documentation
polish). Neither made it an initiative, and that is worth stating before departing from
it.

That precedent rests on two conditions, and both are false here:

1. **There was an open initiative to attach to.** SHACL-I-0001 and SHACL-I-0002 are both
   completed. A task's parent must be in decompose or active, so a bare task has nowhere
   to hang.
2. **The metric was obvious.** The parser measures throughput on a document; the store
   measures bulk-load rate. Each is one number with an evident unit and an evident
   input — the vendored corpus, at size.

**The second is the real reason.** There is no SHACL benchmark corpus, and the vendored
suite cannot become one: its 98 files were chosen to exercise semantics, several are a
dozen triples, and the largest shapes graph in the tree is four hundred lines.
Benchmarking against it would measure the harness. Validation cost is **shapes × data**,
so a workload has to be designed — how many shapes, how deeply nested, what target
selectivity, what path forms, what data size, against which backend — and a workload
designed badly does not produce a slow library, it produces confident numbers that
mislead. That is a design question, and improvising it inside an implementation task is
how it goes wrong quietly.

**Honest note on sizing:** this is a week or two of work, under the 1–6 month guideline
for an initiative. The justification is the design phase and the decision gate, not the
duration. Recorded so that the departure is deliberate rather than unnoticed.

## Goals & Non-Goals **[REQUIRED]**

**Goals:**

- **A `bench/` package and a workload that is defensible**, in the family's established
  shape: `make bench` builds with release flags and runs. What the workload *is* is this
  initiative's first decision, not an assumption.
- **Baselines recorded where the family records them** — the README, quoted the way
  odin-rdf-parser quotes its throughput figures, plus the numbers in this document.
- **The memoisation trigger pulled, and SHACL-A-0002 amended either way.** "The trigger
  was pulled, here are the numbers, no cache was warranted" is as much worth recording as
  the opposite, and SHACL-A-0001's "As Built" sections are the precedent for writing an
  outcome back into an ADR.
- **The flat-memory claims verified at scale.** The package doc promises that
  `Conformance` allocates *nothing at all, whatever the violation count*, and that memory
  stays flat exactly when the data is worst. `tests/guards` asserts that on fixtures of a
  few dozen triples. A benchmark is the only thing that can say it holds at size.
- **A store-read count, not only wall clock.** The store-evidence log's standing note is
  that reads are the engine's cost, and a memoisation cache's payoff is reads avoided.
  Whether this is worth building is a design decision; wanting it is a goal.

**Non-Goals:**

- **This is not a performance-optimisation initiative.** Nothing is optimised that a
  measurement has not justified, and the only optimisation pre-identified is the
  memoisation question SHACL-A-0002 parked. If the numbers say something else is slow,
  that is evidence for a *later* initiative, recorded here rather than acted on.
- **No comparison against other SHACL engines.** Cross-implementation benchmarking is a
  different discipline — different languages, different data structures, different
  definitions of the workload — and it would produce a headline nobody could defend. The
  baselines are this engine against itself over time.
- **Not benchmarking the parser or the store.** Loading a shapes graph and loading data
  are upstream's measured business. What is measured here is compile, bind, and validate.
- **No CI performance gate.** Hosted runners are too noisy for a threshold that would not
  either flap or be set so loose it catches nothing. Baselines are recorded and compared
  deliberately, the way the family compares them.
- **Not the v0.1.0 release.** Tagging, the CI pins, and the vision refresh are backlog
  items ([[SHACL-T-0020]], [[SHACL-T-0021]], [[SHACL-T-0022]]), independent of this and of
  each other.

## Detailed Design **[REQUIRED]**

Nothing is settled yet — this initiative is in discovery, and the list below is what the
design phase has to answer. Each says what would settle it.

- **What the workload is.** The central question. Three shapes suggest themselves and they
  are not exclusive:

  - **A synthetic generator with knobs** — shape count, nesting depth, data size, target
    selectivity, path form. Most controllable, most defensible as a regression baseline,
    and the easiest to accuse of measuring something nobody writes.
  - **A real shapes graph, and there is one already vendored.**
    `tests/w3c/core/complex/shacl-shacl-data-shapes.ttl` is SHACL's own shapes for
    validating SHACL shapes graphs: four hundred lines, genuinely nested, using the
    logical combinators, the qualified family, property paths, and `sh:closed`. It is the
    most realistic shapes graph in the tree and it is already there under a known licence.
    What it lacks is *data* at any scale — it validates one document.
  - **Replicating the corpus** to manufacture size. Cheapest, and probably the least
    informative: a thousand copies of a twelve-triple graph is a thousand small
    validations, which measures start-up rather than validation.

  **What would settle it:** deciding what question the baseline is meant to answer. A
  regression tripwire wants the generator; a claim about real-world cost wants the real
  shapes graph over generated data. They may both be worth having, and the honest answer
  may be one of each.

- **What is measured, and in what units.** Compile (shapes graph → model), bind (model →
  store IDs), and validate are three different costs with three different scaling
  behaviours, and reporting them as one number would hide the interesting one. Validation
  probably wants normalising per focus node rather than per run. **What would settle it:**
  a first set of numbers — the shape of the data usually names its own unit.

- **Whether to count store reads.** A counter in the instantiation packages' adapters
  would be a handful of lines and would measure the thing the store-evidence log says is
  the engine's real cost. It is also the number that decides memoisation, since a cache's
  payoff is reads avoided rather than time saved. Against it: a counter on the hot path
  that ships in release builds is exactly the kind of thing that quietly costs what it
  measures. **What would settle it:** whether it can be compiled out — a `-define:` like
  the family's `RDF_STORE_TERM_ID_BITS`, or a bench-only adapter.

- **Which backend, and which `Term_ID` width.** kvstore's numbers are dominated by LMDB
  and measure the store as much as the engine; memstore's are the engine's own. Both,
  reported separately, is the likely answer, with memstore as the number that means
  something about this repository. Width is a build-time choice and anything
  width-sensitive is tested at both — whether it is worth *benchmarking* at both is a
  separate question, and a 32-bit `Term_ID` halving a hot array is the kind of thing that
  shows up in cache behaviour.

- **The memoisation question itself, stated so the measurement can answer it.** The
  duplicate is structural, not incidental: a qualified property shape carrying both
  `sh:qualifiedMinCount` and `sh:qualifiedMaxCount` shares one `sh:qualifiedValueShape`,
  and the two constraints walk the same value nodes against the same shape independently.
  `sh:qualifiedValueShapesDisjoint` multiplies it by the sibling count. The proposed fix
  is a `(shape, node)` conformance cache in `Validation`.

  **The measurement has to be able to say no.** A cache costs a map lookup on the engine's
  hot path, on every suppressed check, to save work that may be rare in the shapes graphs
  people actually write — the qualified family is the least-used corner of SHACL Core. A
  benchmark built only on a workload that stresses it will say yes whatever the truth is,
  which is the failure mode to design against.

## Alternatives Considered **[REQUIRED]**

- **A single backlog item instead of an initiative.** The fallback if the initiative
  overhead is not worth it, and it is a real option: one `feature` item with the workload
  question written into it as the first thing to settle. Rejected for now because the
  design phase is the whole value — the risk here is not that the benchmark is hard to
  write, it is that it measures the wrong thing convincingly.
- **Tag v0.1.0 without benchmarks.** Defensible: the suite is 98 of 98 and that is the
  claim a consumer cares about most. Rejected as the *only* plan, because it leaves the
  family's one unmeasured library unmeasured indefinitely and leaves SHACL-A-0002's
  trigger permanently unpullable. It stays available as a sequencing choice — see
  [[SHACL-T-0021]], which does not depend on this initiative.
- **Benchmark against the vendored W3C corpus directly.** Rejected by measurement rather
  than by taste: 98 files, several of a dozen triples, chosen to exercise semantics. It
  would report the harness's own cost with a validation-shaped label on it.
- **Implement the `(shape, node)` cache now, on the structural argument alone.** Tempting,
  because the duplicate is provable from the code without measuring anything. Rejected
  because SHACL-A-0002 said *measured* for a reason, and because this is precisely the
  class of optimisation that sounds obviously right and is wrong about half the time — the
  cost is on the hot path and the saving is on a corner of the language.
- **A CI performance gate.** Rejected in Non-Goals; recorded here because it is the
  natural next thought after "record baselines", and the answer is that hosted runners
  cannot support a threshold worth having.

## Implementation Plan **[REQUIRED]**

Three tasks, with a decision gate between the second and the third. Decomposition happens
in the decompose phase; this is the shape.

1. **The workload decision, and `bench/`.** Settle the Detailed Design questions above,
   then build the harness: the bench package, the workload, and `make bench` producing
   numbers with release flags. The decision is the deliverable as much as the code, and it
   goes in this document rather than only in the source.
2. **Baselines, and the flat-memory claims at scale.** Record the numbers where the family
   records them — the README, quoted as odin-rdf-parser quotes its throughput. Verify at
   size what `tests/guards` verifies on fixtures: that `Conformance` allocates nothing
   whatever the violation count, and that memory does not grow with the result stream.
3. **The memoisation decision, and SHACL-A-0002's amendment.** Measure the duplicate,
   decide, and write the outcome back into the ADR — *either* outcome. If and only if the
   numbers justify it, implement the `(shape, node)` cache in `Validation`, with the suite
   still 98 of 98 at both widths and both backends. If the cache is not justified, that
   result is the task's deliverable and the ADR says so.

**Exit criteria:** `bench/` exists and `make bench` runs it with release flags; the
workload is documented with the reasoning for choosing it; baselines are recorded in the
README and in this document for both backends; the flat-memory promises in the `shacl`
package doc are verified at a size the guards cannot reach; SHACL-A-0002 carries a
measured answer to its own review trigger; and if a conformance cache landed, the W3C
suite is still 98 of 98 against both backends at both `Term_ID` widths.

## Status Updates

- **2026-08-07 — Created in discovery.** Drafted at the close of SHACL-I-0002, from the
  gap list in `docs/handover-sparql.md` and the review trigger SHACL-A-0002 left unpullable.

  The judgement this document rests on: **the workload is the risk, not the harness.**
  Writing a benchmark for a SHACL engine is a day; deciding what a representative SHACL
  workload *is* has no obvious answer, no upstream corpus, and a failure mode — confident
  numbers about the wrong thing — that is worse than having no numbers at all. That is why
  this departs from the family precedent of benchmarking as a closing task.

  Awaiting human review of scope. Two things are worth deciding early because they change
  what gets built: **what the workload is** (synthetic generator, the vendored
  SHACL-SHACL shapes graph over generated data, or both), and **whether store reads are
  counted** as well as wall clock — the latter is what actually decides the memoisation
  question, and it is easier to build in than to add later.
