---
id: baselines-recorded-and-the-flat
level: task
title: "Baselines recorded, and the flat-memory promises tested at scale"
short_code: "SHACL-T-0024"
created_at: 2026-08-07T11:34:41.053696+00:00
updated_at: 2026-08-07T12:55:50.148070+00:00
parent: SHACL-I-0003
blocked_by: [SHACL-T-0023]
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: true
initiative_id: SHACL-I-0003
---

# Baselines recorded, and the flat-memory promises tested at scale

## Parent Initiative

[[SHACL-I-0003]]

## Objective **[REQUIRED]**

Turn the instrument into evidence. Record baselines where the family records them, and use
the instrumented mode to test two promises the `shacl` package doc makes that
`tests/guards` is too small to reach.

## Acceptance Criteria **[REQUIRED]**

- [x] **One reference configuration in the README, the full swept matrix in Metis**
      (Greger, 2026-08-07). The README carries a single configuration with its seed and
      knob settings, quoted the way odin-rdf-parser quotes its throughput figures; the
      matrix lives in this task's Status Updates and in [[SHACL-I-0003]]. A README with one
      number is unusable for extrapolation and a README with a matrix is noise nobody
      reads.
- [x] **Both backends reported separately and labelled as what they are** — memstore the
      engine's own number, kvstore the deployment number. Neither is quoted without saying
      which it is.
- [x] **Every quoted figure carries its configuration and its seed.** A per-focus-node cost
      without the shapes configuration beside it is not a number anybody can use, and a
      figure nobody can reproduce is an anecdote.
- [x] **The README says plainly what the generator does not measure**: it is a synthetic
      workload chosen by this project, so the numbers are a regression baseline and a
      comparative instrument, not a claim about what SHACL costs in the world. This sits
      beside the numbers, not in a footnote.
- [x] ~~**`Conformance` allocates nothing at all, at scale** — `total_allocation_count == 0`
      on a high-violation-density configuration.~~ **Mis-specified; corrected in flight
      (2026-08-07).** The package doc's "nothing at all" is a claim about the *consumer*,
      and the sentence before it says validation allocates per focus node. The checkable
      form is a comparison: on a graph that **conforms** nothing exits early, so
      `Conformance` and the raw stream walk identically and any difference is the
      consumer — asserted as an **equality**, and it holds exactly (5518 = 5518). On a
      graph that does not conform it must allocate strictly less. See Status Updates.
- [x] **Peak memory holds steady as violation density rises**, with the result stream
      draining to a visitor that keeps nothing. This is the "memory stays flat exactly when
      the data is worst" promise, measured.
- [x] **A `Report` grows and is seen to grow.** The counterpart to the two above: the one
      consumer that is *meant* to scale with the violation count does, and the number is
      recorded so a future change that made it superlinear would show.
- [x] **32-bit `Term_ID` measured once and reported as a finding** — timings against the
      64-bit baseline, with the read counts confirmed identical. Whether a halved `Term_ID`
      shows up in cache behaviour is the question; either answer is a result.
- [x] Anything the numbers reveal that is *not* the memoisation question is **recorded as
      evidence for a later initiative rather than acted on** — the initiative's non-goal.

## Implementation Notes **[CONDITIONAL: Technical Task]**

### Technical Approach

The flat-memory tests are the instrumented mode with the density knob swept, holding
everything else fixed. `Conformance` is the interesting consumer because its promise is
absolute — *nothing at all, whatever the violation count* — so it is a single integer
compared against zero rather than a trend.

### Dependencies

[[SHACL-T-0023]]. Independent of [[SHACL-T-0025]] and can run alongside it, though the
memoisation task will want these baselines to compare against.

### Risk Considerations

**A promise measured at scale may not hold**, and that is the point of measuring it. If
`Conformance` allocates on a large graph, the package doc is wrong and the fix comes before
the baseline is published — a documented promise that the benchmark quietly disproves is
worse than no benchmark.

**The README is a contract here, not decoration.** `tests/readme` compiles its examples;
it cannot check that a quoted figure is still true. Numbers in a README rot, so they need a
date and a seed beside them saying what they were measured against.

## Status Updates **[REQUIRED]**

- **2026-08-07 — Implemented. Baselines recorded, both memory promises tested at scale,
  and one acceptance criterion corrected because it was wrong.**

  ### The criterion that was wrong, and what replaced it

  This task asked for `Conformance` to allocate **nothing at all** at scale —
  `total_allocation_count == 0` over a validation. Implemented as written, it failed on
  every configuration, and the engine is right and the criterion was wrong.

  The package doc's paragraph reads: *validation* allocates per focus node, per
  reachability round, and per shape entered; "the two streaming consumers hold to a
  tighter promise: `Conformance` allocates nothing at all, whatever the violation count."
  The tighter promise is about the **consumer**, not the walk it rides on —
  `tests/guards`' `test_conformance_consumer_allocates_nothing` asserts exactly that, in
  isolation, over a synthetic result stream.

  **The data settles it and gives a sharper assertion than the original.** On `clean`, the
  graph conforms, so nothing exits early and the walk is precisely the raw stream's walk:
  `Conformance` made **5518 allocations against the raw stream's 5518** — equal to the
  allocation. The consumer costs nothing, exactly as promised. So the assertion is now an
  *equality* on conforming configurations and a strict *inequality* on the rest, where
  early exit must save rather than cost. Confirmed to bite by adding one phantom
  allocation.

  Recorded rather than quietly re-worded, because a criterion that a correct engine cannot
  meet is worth knowing about — the same failure mode as a test that passes for the wrong
  reason, seen from the other side.

  ### The matrix (memstore, 64-bit, seed 0x5EED0001)

  | configuration | compile | validate | ns/focus node | reads | raw peak | report triples |
  | --- | ---: | ---: | ---: | ---: | ---: | ---: |
  | `baseline` | 37 µs | 666 µs | 1332 | 7503 | 27076 | 9450 |
  | `qualified` | 55 µs | 1.29 ms | 2574 | 11504 | 27400 | 9450 |
  | `nested` | 57 µs | 1.10 ms | 2204 | 11596 | 27082 | 11473 |
  | `dense` | 35 µs | 603 µs | 1205 | 7503 | 27076 | 48002 |
  | `clean` | 41 µs | 698 µs | 1395 | 7503 | 27076 | 2 |
  | `alternative-path` | 48 µs | 1.09 ms | 2185 | 9003 | 27076 | 15355 |

  kvstore on the reference configuration: compile 146 µs, bind 27 µs, validate 4.69 ms
  (9.4 µs/focus node), same 7503 reads. Roughly **7x** memstore's validation time, which
  is the cost of persistence rather than of the engine.

  ### The two promises, now measured rather than asserted

  **Memory is flat in the violation count** — peak is **27076 bytes** on `clean` (0
  results), `baseline` (1181), and `dense` (6000), on an identical walk with an identical
  read count. Not "close": byte-identical, which is what the streaming design predicts and
  what a tolerance would have let a slow leak hide behind.

  **And it is not flat because nothing happened.** The counterweight is asserted too: a
  `Report` is the one consumer meant to grow with the violation count, and does — 2
  triples for a conforming graph, 9450 at 20% violating, 48002 at 100%. Without that,
  every flatness assertion above would pass equally well on an engine that had quietly
  stopped reporting.

  ### 32-bit `Term_ID`, measured once as a finding

  | | 64-bit | 32-bit |
  | --- | ---: | ---: |
  | memstore validate | 701 µs | 722 µs |
  | kvstore validate | 4.54 ms | 4.37 ms |
  | raw peak | 27076 B | 20868 B |
  | allocations | 5518 | 5518 |
  | store reads | 7503 | 7503 |

  **It buys about 23% of the working set and no measurable time.** Timings differ in both
  directions and by less than run-to-run noise. The likely reason is unexciting and worth
  saying: at 27 KB the working set already fits in cache, so halving it has nothing to win
  back. A much larger graph might answer differently; that would be a new configuration
  rather than a new instrument.

  Read counts and allocation *counts* are identical, which is the invariant holding — same
  number of allocations, smaller ones.

  ### Recorded as evidence, not acted on

  Per the initiative's non-goal, the numbers that are interesting but not the memoisation
  question:

  - **kvstore validation is ~7x memstore's.** Expected, and the deployment number that
    matters, but nothing here says whether it is *good*. A store-side comparison would be
    odin-rdf-store's initiative, not this one.
  - **`qualified` allocates 14522 times against `baseline`'s 5518** — 2.6x the
    allocations for 1.5x the reads. Suppressed validation allocates per branch per value
    node, so this is expected in direction; the magnitude is a data point for
    [[SHACL-T-0025]] rather than a finding on its own.
  - **`alternative-path` allocates 13018 times for only 1.2x baseline's reads.** The RDF
    list walk and the two branches cost more in allocation than in store traffic. Nothing
    is wrong; it is simply the one place where reads are a poor proxy for cost, which is
    worth knowing before anyone uses the read count as a stand-in for time.