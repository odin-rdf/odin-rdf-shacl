---
id: performance-evidence-a-benchmark
level: initiative
title: "Performance evidence: a benchmark workload, and the memoisation decision"
short_code: "SHACL-I-0003"
created_at: 2026-08-07T10:48:30.161797+00:00
updated_at: 2026-08-07T11:30:43.132727+00:00
parent: SHACL-V-0001
blocked_by: []
archived: false

tags:
  - "#initiative"
  - "#phase/ready"


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
- **No CI performance gate on timings.** Hosted runners are too noisy for a threshold that
  would not either flap or be set so loose it catches nothing. Timing baselines are
  recorded and compared deliberately, the way the family compares them.

  **Narrowed from an absolute once store-read counting was decided** (2026-08-07). A read
  count for a fixed workload and seed is an exact integer and does not vary with the
  machine, so the noise argument does not reach it. Gating one is not in scope here, but
  it is no longer excluded by this document — see Detailed Design.
- **Not the v0.1.0 release.** Tagging, the CI pins, and the vision refresh are backlog
  items ([[SHACL-T-0020]], [[SHACL-T-0021]], [[SHACL-T-0022]]), independent of this and of
  each other.

## Detailed Design **[REQUIRED]**

**All four design questions are settled** (2026-08-07, with Greger). Each is recorded below
with what it buys, what it gives up, and the consequence that was not obvious when the
question was asked — those consequences are the reason this had a design phase rather than
being improvised inside the first task.

The fifth entry is not a decision but a framing: the memoisation question, stated so that
the measurement is capable of answering it either way.

- **The workload is a synthetic generator with knobs — decided (Greger, 2026-08-07).**
  The two alternatives set aside were the vendored SHACL-SHACL shapes graph over generated
  data, and replicating the corpus to manufacture size.

  **What this buys and what it gives up.** A generator is controllable, reproducible, and
  the only one of the three that can hold every dimension fixed but one — which is what a
  baseline is for. What it gives up is the claim to realism: it measures a shape of
  workload *we chose*, so it is a regression tripwire and a comparative instrument, not a
  statement about what SHACL costs in the world. Saying that in the README beside the
  numbers is part of the deliverable, not a caveat to be buried. If a real-world claim is
  ever wanted, `tests/w3c/core/complex/shacl-shacl-data-shapes.ttl` over generated data is
  the option that was set aside and it stays available.

  **Reproducibility is a requirement, not a nicety.** The generator is seeded and
  deterministic, and the seed is recorded with the numbers. A baseline nobody can
  reproduce is an anecdote.

  **Generated in-process into a store rather than vendored as fixtures**, so size is a
  parameter rather than a file and the repository stays free of a megabyte of synthetic
  Turtle.

  **The knobs, drawn from what the engine's cost actually depends on:** focus-node count
  (target selectivity), value-node fan-out per focus node, shape count, nesting depth,
  path form, violation density, and the qualified family present or absent. Two of those
  are easy to leave out and neither should be:

  - **Violation density.** `Conformance` early-exits at the first result and a `Report`
    grows with the violation count, so conforming data and heavily-violating data are two
    workloads rather than one workload at two settings. The `shacl` package doc promises
    that memory stays flat *exactly when the data is worst*; only a high-density
    configuration can test that.
  - **The qualified family, and this one is load-bearing.** The baseline must include a
    configuration **without** it. Discovery named the failure mode — a benchmark built
    only on a workload that stresses the qualified family will endorse the memoisation
    cache whatever the truth is — and this knob is the mitigation. It is what lets the
    measurement say no.

- **What is measured — decided (2026-08-07).** Three phases separately, two modes, and
  never both instruments in one run.

  **Three phases, because they scale differently and are paid at different rates.**
  `compile` (shapes graph → model) and `bind` (model → data-store IDs) are once-per-process
  costs; `validate` is the repeated one. Rolling them into a single number would hide the
  interesting one, and the once-per-process pair is not negligible here — **~200 processes
  per machine each compile a shapes graph at start-up**, so compile time is a deployment
  cost rather than a footnote. Reported as absolute time per operation.

  **`validate` is normalised per focus node**, with the configuration stated beside it,
  plus the raw wall clock for the run. Per *focus node* rather than per value node or per
  triple because it is the only one of the three a reader can map onto their own data: how
  many nodes will be validated is a thing a user knows about their graph. It is only
  meaningful with the shapes configuration named, which is why the configuration travels
  with the number everywhere it is quoted.

  **Two modes over one workload, because every instrument here perturbs what it measures.**

  - **Timing mode** — the real path (`shacl_memstore.validate`), the real allocator,
    nothing wrapped. Wall clock only.
  - **Instrumented mode** — the bench's counting `Access` and a `mem.Tracking_Allocator`.
    Reports **store reads** (per validation and per focus node) and **allocation**:
    `peak_memory_allocated`, `total_memory_allocated`, and `total_allocation_count`. No
    timings are taken in this mode and none should be quoted from it.

  Allocation joins reads in the instrumented mode rather than getting a third mode: both
  are deterministic for a fixed workload and seed, neither belongs in a timed run, and
  they answer adjacent questions. `peak` is what tests the flat-memory promise; `total`
  and the count are what a per-result leak would show up in.

  **This turns two package-doc claims into measurements rather than assertions.**
  `shacl.odin` promises that memory stays flat *exactly when the data is worst* and that
  `Conformance` allocates **nothing at all, whatever the violation count**. The second is
  an exact statement — `total_allocation_count == 0` — and at high violation density on a
  generated graph it is a far stronger test than `tests/guards` can build. The first is
  peak holding steady as the density knob rises.

- **Backend and `Term_ID` width — decided (2026-08-07). Both backends, reported
  separately; 64-bit as the standing baseline, 32-bit measured once.**

  **Both backends, and they answer different questions.** memstore is the engine's own
  number, uncontaminated by storage, and it is the regression baseline. kvstore is the
  *deployment* number: ~200 processes per machine each embedding a persistent store is the
  shape this family is designed around, so a validator benchmarked only in memory would be
  measuring a configuration nobody runs. Neither substitutes for the other and neither is
  quoted without saying which it is.

  **The read count is an assertion, not a comparison.** It must be **identical** on both
  backends, and that follows from the architecture rather than from luck: the
  backend-independent core decides *what* to ask and the adapter decides only *how*, so
  the number of `scan`, `step`, `outgoing`, and `load` calls cannot depend on the backend.
  A divergence is a bug, and the bench should fail on it rather than report it — the same
  reasoning the suite harness used when it asserted the two backends agree on a count.

  **Width: 64-bit is the standing baseline**, since it is the default and doubling the
  matrix on every run buys little. **32-bit is measured once, at the close, and reported
  as a finding** — a 32-bit `Term_ID` halves the quad arrays, the bindings arrays, and the
  subclass-closure map, so whether that shows up in cache behaviour is a real question
  worth one answer and not a standing cost.

  **Reads are width-invariant too, by the same argument** — ID width cannot change the
  core's control flow — so the identity assertion extends across the whole matrix: **one
  read count for a given workload and seed, across two backends and two widths.** Four
  configurations, one integer, and any disagreement is a defect rather than a measurement.

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

1. **`bench/`: the generator, the two modes, and `make bench`.** The design is settled, so
   this is construction: the seeded generator with its seven knobs, the bench's own
   counting `Access` per backend, timing and instrumented modes, and `make bench` running
   with release flags. Two properties are asserted rather than reported, and they are the
   cheapest bugs this initiative can catch — **the read count is identical across both
   backends**, and identical across both `Term_ID` widths.
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

- **2026-08-07 — Both open decisions settled with Greger; transitioned to design.**
  A **synthetic generator with knobs**, and **store reads counted** alongside wall clock.
  Both are written into Detailed Design with their consequences; three things fell out
  that were not obvious when the questions were asked.

  1. **The read counter needs no change to shipped code.** `Access` is a struct of
     procedure pointers and `shacl.validate` takes one directly, so `bench` supplies its
     own counting adapters and bypasses `shacl_memstore.validate` entirely. No `-define:`
     flag, no counter on a hot path in release builds. The design question as posed
     ("can it be compiled out?") had a better answer than either option it offered.
  2. **One of this initiative's own Non-Goals had to be narrowed.** "No CI performance
     gate" was reasoned from timing noise on hosted runners, and a read count for a fixed
     workload and seed is an exact machine-independent integer — the reasoning does not
     reach it. Gating one is still out of scope; excluding it by argument is no longer
     honest, and the Non-Goal now says which half it means.
  3. **The two modes cannot share a run.** Counting adapters add an indirection per read,
     so timing runs take the real path and counting runs take the bench's. Same workload,
     two passes.

  **The knob that decides whether this initiative can reach an honest answer is the
  qualified family, present or absent.** Discovery named the failure mode — a workload
  built to stress the qualified family will endorse the memoisation cache whatever the
  truth is — and a configuration without it is the mitigation. It is called out in
  Detailed Design rather than left to whoever writes the generator.

  Still open for design, and smaller: what is measured and in what units, and which
  backend and `Term_ID` width. Both are likely to be settled by a first set of numbers
  rather than by argument.

- **2026-08-07 — The remaining two settled; design complete, transitioned to ready.**
  They turned out to be settleable by argument after all, and the argument produced two
  assertions the initiative can make for free.

  **What is measured:** the three phases separately — `compile` and `bind` are
  once-per-process, `validate` is the repeated cost — with validate normalised **per focus
  node**, because that is the only unit a reader can map onto their own graph. **Two
  modes, never combined:** timing on the real path with the real allocator, and an
  instrumented mode carrying both the counting `Access` and a `mem.Tracking_Allocator`.
  Allocation joined reads in the instrumented mode rather than taking a third, since both
  are deterministic for a fixed seed and neither belongs in a timed run.

  **The compile phase earned its place on the deployment argument, not on principle.**
  ~200 processes per machine each compile a shapes graph at start-up, so a once-per-process
  cost is a deployment cost here in a way it would not be in a library used once.

  **Backend and width:** both backends reported separately — memstore is the engine's own
  number and the regression baseline, kvstore is the deployment number, and neither
  substitutes for the other. 64-bit is the standing baseline; **32-bit is measured once at
  the close and reported as a finding**, since a halved `Term_ID` shrinks the quad arrays,
  the bindings arrays, and the subclass-closure map, which is a cache question worth one
  answer rather than a doubled matrix forever.

  **Two invariants fell out, and they are the useful part.** The backend-independent core
  decides *what* to ask and the adapter decides only *how*, so the read count cannot depend
  on the backend; and ID width cannot change the core's control flow, so it cannot depend
  on the width either. That gives **one read count for a given workload and seed, across
  two backends and two widths** — an exact integer, four ways. The bench asserts it rather
  than reporting it, and a disagreement is a defect rather than a measurement. It is the
  same reasoning the suite harness used when it required the two backends to agree on a
  count, and it costs nothing to add.

  **The design is complete and nothing in Detailed Design is open.** Ready to decompose
  into the three tasks in the Implementation Plan.