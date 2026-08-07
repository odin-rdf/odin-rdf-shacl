---
id: baselines-recorded-and-the-flat
level: task
title: "Baselines recorded, and the flat-memory promises tested at scale"
short_code: "SHACL-T-0024"
created_at: 2026-08-07T11:34:41.053696+00:00
updated_at: 2026-08-07T11:34:41.053696+00:00
parent: SHACL-I-0003
blocked_by: [SHACL-T-0023]
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
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

- [ ] **One reference configuration in the README, the full swept matrix in Metis**
      (Greger, 2026-08-07). The README carries a single configuration with its seed and
      knob settings, quoted the way odin-rdf-parser quotes its throughput figures; the
      matrix lives in this task's Status Updates and in [[SHACL-I-0003]]. A README with one
      number is unusable for extrapolation and a README with a matrix is noise nobody
      reads.
- [ ] **Both backends reported separately and labelled as what they are** — memstore the
      engine's own number, kvstore the deployment number. Neither is quoted without saying
      which it is.
- [ ] **Every quoted figure carries its configuration and its seed.** A per-focus-node cost
      without the shapes configuration beside it is not a number anybody can use, and a
      figure nobody can reproduce is an anecdote.
- [ ] **The README says plainly what the generator does not measure**: it is a synthetic
      workload chosen by this project, so the numbers are a regression baseline and a
      comparative instrument, not a claim about what SHACL costs in the world. This sits
      beside the numbers, not in a footnote.
- [ ] **`Conformance` allocates nothing at all, at scale** — `total_allocation_count == 0`
      on a high-violation-density configuration, which is the package doc's exact claim
      tested at a size `tests/guards` cannot build.
- [ ] **Peak memory holds steady as violation density rises**, with the result stream
      draining to a visitor that keeps nothing. This is the "memory stays flat exactly when
      the data is worst" promise, measured.
- [ ] **A `Report` grows and is seen to grow.** The counterpart to the two above: the one
      consumer that is *meant* to scale with the violation count does, and the number is
      recorded so a future change that made it superlinear would show.
- [ ] **32-bit `Term_ID` measured once and reported as a finding** — timings against the
      64-bit baseline, with the read counts confirmed identical. Whether a halved `Term_ID`
      shows up in cache behaviour is the question; either answer is a result.
- [ ] Anything the numbers reveal that is *not* the memoisation question is **recorded as
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

*To be added during implementation*
