---
id: bench-the-seeded-generator-the-two
level: task
title: "bench/: the seeded generator, the two modes, and the read-count invariants"
short_code: "SHACL-T-0023"
created_at: 2026-08-07T11:34:40.577743+00:00
updated_at: 2026-08-07T11:34:40.577743+00:00
parent: SHACL-I-0003
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: SHACL-I-0003
---

# bench/: the seeded generator, the two modes, and the read-count invariants

## Parent Initiative

[[SHACL-I-0003]]

## Objective **[REQUIRED]**

Build `bench/`. The design is settled (SHACL-I-0003, Detailed Design), so this is
construction: a seeded synthetic generator with seven knobs, the bench's own counting
`Access` per backend, the two measurement modes, and `make bench` running it with release
flags.

**This task produces the instrument, not the numbers.** Recording baselines is
[[SHACL-T-0024]] and deciding memoisation is [[SHACL-T-0025]]; a first set of figures will
inevitably appear here, and they are a smoke test rather than a deliverable.

## Acceptance Criteria **[REQUIRED]**

- [ ] **`bench/` exists and `make bench` runs it** with `-o:speed -no-bounds-check`, as the
      Makefile's existing target already spells. The `test -d $(BENCH)` guard that makes it
      a no-op today stops being reached.
- [ ] **A seeded, deterministic generator** producing a shapes graph and a data graph
      in-process, with the seed a parameter and reported alongside every figure. Running
      twice with one seed produces byte-identical graphs.
- [ ] **Seven knobs**, each independently settable: focus-node count, value-node fan-out
      per focus node, shape count, nesting depth, path form, violation density, and the
      qualified family present or absent.
- [ ] **A configuration with the qualified family absent is among the standing
      configurations**, not merely reachable. [[SHACL-T-0025]] cannot reach an honest
      answer without it, and a knob nobody sets to zero is not a knob.
- [ ] **Timing mode**: the real path (`shacl_memstore.validate` / `shacl_kvstore.validate`),
      the real allocator, nothing wrapped. Reports wall clock for `compile`, `bind`, and
      `validate` separately, with `validate` also normalised per focus node.
- [ ] **Instrumented mode**: the bench's own `Access` with counting adapters, plus a
      `mem.Tracking_Allocator`. Reports store reads (total and per focus node) and
      `peak_memory_allocated`, `total_memory_allocated`, `total_allocation_count`. **No
      timing is reported from this mode.**
- [ ] **The two read-count invariants are asserted, and the bench fails on a
      disagreement** rather than printing both numbers:
      - identical read counts on memstore and kvstore for the same workload and seed;
      - identical read counts at 64- and 32-bit `Term_ID`.
- [ ] **The read count for each standing configuration is pinned and asserted** — a
      constant in the bench source, changed only by deliberate edit, in the idiom of
      `TOTAL_ENTRIES` and `ENABLED_ENTRIES` rather than as a threshold. `make check`
      already vets `bench/`, so a drifting count fails the build. The comment beside the
      pin says what re-pinning means: an engine change that reads more is not necessarily
      wrong, but it must be seen.
- [ ] `make check` still passes — the Makefile already vets `bench/` when it exists, and
      that line stops being a no-op too.
- [ ] Generated graphs are **not** written to disk or vendored.
- [ ] **A package doc on `bench/` to the family's contract standard**, carrying what the
      initiative decided and why: the seven knobs and what each one is for, the two modes
      and why they cannot share a run, the two read-count invariants and the architectural
      reason they hold, and — stated plainly — that this is a workload this project chose,
      so the numbers are a regression instrument rather than a claim about the world. The
      initiative's exit criteria ask for the workload to be documented with its reasoning,
      and beside the generator is where a reader will look for it.

## Implementation Notes **[CONDITIONAL: Technical Task]**

### Technical Approach

**The counting `Access` needs no change to shipped code**, which is the design finding this
task depends on. `Access` is a struct of procedure pointers, `shacl.validate` takes one
directly, and `Access` and its four verb types (`Scan`, `Step`, `Outgoing`, `Term_Loader`)
are all exported. So `bench` writes its own adapters — calling `memstore.match` /
`kvstore.match` and bumping counters in the same body — and calls `shacl.validate` with
them, bypassing `shacl_memstore.validate`, which builds the uncounted one.

The instantiation packages' own adapters are `@(private)`. **Do not export them.** Widening
a shipped API for a benchmark's convenience is the wrong trade, and roughly thirty lines
per backend against the same match interface is the cheaper price. `tests/w3c/harness/compare.odin`
is this repository's precedent for copying a small thing rather than coupling to it, and
its header says why.

**The generator's shapes graph is easiest to build as Turtle text and load through the
existing path**, rather than by constructing a `Shapes` directly — it keeps the benchmark
measuring `compile` rather than measuring a hand-built model, and `compile` is one of the
three phases being timed.

**`core:time` for the clock**, and enough repetitions per configuration that a single
outlier does not carry the number. What "enough" is falls out of the first run.

### Dependencies

None inside the initiative — this is its first task. [[SHACL-T-0024]] and
[[SHACL-T-0025]] both need it.

### Risk Considerations

**The knobs are the deliverable, and the temptation is to hard-code one configuration and
call it a workload.** The whole argument for a generator over the vendored corpus was that
it can hold every dimension fixed but one. A bench with no dials is the corpus with extra
steps.

**Determinism is easy to lose and hard to notice.** Anything reading a clock, a map's
iteration order, or an unseeded `rand` inside the generator breaks the read-count
invariants in a way that will look like a backend divergence. If the invariant assertions
fail on the very first run, suspect the generator before the engine.

**The instrumented mode must not creep into the timed one.** They share a workload and
nothing else. A single figure quoting both is the failure this split exists to prevent.

## Status Updates **[REQUIRED]**

*To be added during implementation*
