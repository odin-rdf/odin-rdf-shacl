---
id: the-memoisation-decision-and-shacl
level: task
title: "The memoisation decision, and SHACL-A-0002's amendment"
short_code: "SHACL-T-0025"
created_at: 2026-08-07T11:34:44.535089+00:00
updated_at: 2026-08-07T11:34:44.535089+00:00
parent: SHACL-I-0003
blocked_by: [SHACL-T-0023]
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: true
initiative_id: SHACL-I-0003
---

# The memoisation decision, and SHACL-A-0002's amendment

## Parent Initiative

[[SHACL-I-0003]]

## Objective **[REQUIRED]**

Pull the review trigger SHACL-A-0002 left. Measure the duplicated conformance work, decide
whether a `(shape, node)` cache is justified, implement it **only if the numbers say so**,
and write the outcome back into the ADR either way.

**Either answer is a deliverable.** "The trigger was pulled, here are the numbers, no cache
was warranted" closes the question as firmly as the opposite, and it is the answer the
design phase went to some trouble to keep reachable.

## Acceptance Criteria **[REQUIRED]**

- [x] **The duplicate is measured, not argued.** Reads and wall clock for a configuration
      that exercises the qualified family, against the same configuration with it absent —
      the knob [[SHACL-T-0023]] was required to expose.
- [x] **The decision is made on the numbers**, with the reasoning recorded: how many reads
      a cache would avoid, on what shape of workload, and at what hot-path cost.
- [x] **SHACL-A-0002 is amended with the outcome**, in the shape of SHACL-A-0001's "As
      Built" sections — the numbers, the decision, and the date. The ADR currently carries
      a review trigger with nothing behind it; after this it carries an answer.
- [x] **If and only if the cache is justified**: implemented as a `(shape, node)` cache.
      **Not justified — no cache landed.** See Status Updates; the deciding number is that
      the duplicate costs zero peak memory while the cache would cost a working set
      proportional to the data.
- [x] **If the cache lands, the read-count invariants are re-established.** Not applicable —
      no cache. The invariants are untouched and still hold, and the two new configurations
      are pinned alongside the rest.
- [x] **If the cache does not land**, `docs/store-evidence.md`'s standing note about the
      structural duplicate is updated to say it was measured and found not to matter,
      rather than left reading as an open concern.

## Implementation Notes **[CONDITIONAL: Technical Task]**

### Technical Approach

The duplicate is structural and provable from the code without measuring anything: a
qualified property shape carrying both `sh:qualifiedMinCount` and `sh:qualifiedMaxCount`
shares one `sh:qualifiedValueShape`, and the two constraints walk the same value nodes
against the same shape independently. `sh:qualifiedValueShapesDisjoint` multiplies it by
the sibling count. SHACL-T-0018 found it; `docs/store-evidence.md` records it.

What is *not* provable from the code is whether it matters, which is the whole reason
SHACL-A-0002 said measured.

### Dependencies

[[SHACL-T-0023]] for the instrument. [[SHACL-T-0024]]'s baselines are what a cached run
would be compared against.

### Risk Considerations

**The measurement must be able to say no, and the easiest way to fail this task is to
build a workload that cannot.** A configuration tuned to stress the qualified family will
endorse the cache whatever the truth is. The qualified family is the least-used corner of
SHACL Core; a cache costs a map lookup on the engine's hot path, on *every* suppressed
check, to save work that may be rare in the shapes graphs people actually write. The
configuration without it is the control, and the decision is not defensible without it.

**This is the class of optimisation that sounds obviously right.** The duplicate is real,
provable, and visible in the source — which is exactly why SHACL-A-0002 declined to act on
it and why acting on it now without numbers would be repeating the mistake the ADR
avoided.

**A cache interacts with the abnormal exits.** Early stop and recursion failure unwind by
hand, and anything added to `Validation` has to unwind with them. `tests/guards`'
`test_early_exit_and_recursion_unwind_cleanly` is the guard that would catch it, and it
should be checked deliberately rather than assumed from a green run.

## Status Updates **[REQUIRED]**

- **2026-08-07 — Measured, and the answer is no. SHACL-A-0002 amended; no engine change.**

  ### Isolating the duplicate

  The existing `qualified` configuration was not the right instrument: it exercises
  `sh:qualifiedValueShapesDisjoint`, which multiplies the walk by the *sibling* count. The
  duplicate SHACL-T-0018 actually found is different — both bounds of one property shape
  share one `sh:qualifiedValueShape`, and `check_qualified` walks the value nodes once per
  bound.

  So `Config.qualified` became a `Qualified_Form` enum rather than a bool, and two
  configurations were added that differ **only** in the second bound. That is what makes
  this a measurement instead of an argument.

  | | reads | allocations | peak | validate |
  | --- | ---: | ---: | ---: | ---: |
  | `qualified-min` | 9003 | 9018 | 27078 B | 930 µs |
  | `qualified-minmax` | 10003 | 11018 | 27078 B | 1043 µs |
  | **the duplicate** | **+1000** | **+2000** | **+0** | **+113 µs (11%)** |

  +1000 is exactly the 1000 `ex:q` value nodes, asked a second time for an answer that
  cannot have changed. The duplicate is real and is the size the code comment claimed.

  ### The decision, and the number that made it

  **No `(shape, node)` conformance cache.** The deciding column is peak: it does not move.
  Each suppressed sub-walk allocates and frees, so the duplicate costs time and store
  traffic but **no memory at all** — the working set stays 27078 bytes either way, flat in
  the data, exactly as SHACL-T-0024 measured and the package doc promises.

  A cache trades precisely that away. Its entries are the distinct (shape, node) pairs
  asked — proportional to focus nodes times shapes, 1000 on this configuration — so it
  would more than double a 27 KB working set here and grow without bound on real data where
  today's number does not move. At ~200 processes per machine, that is the wrong side of
  the trade for an 11% saving on one authoring pattern.

  Two things reinforce it without carrying it: the saving is narrow (only shapes graphs
  putting two bounds on one `sh:qualifiedValueShape` gain anything — `baseline`, `nested`,
  `qualified-min` and the rest gain nothing), while the cost is broad (a lookup on *every*
  `node_conforms` call, so `sh:not`, `sh:or`, `sh:xone` and `sh:node` would pay for a
  benefit they cannot receive).

  ### The alternative, recorded and deliberately not implemented

  The duplicate is worth removing; a cache is the wrong instrument for it. **Both bounds
  share one `sh:qualifiedValueShape` and one value-node set, so they could share one walk**
  — compile them into a single constraint carrying both bounds, count once, test twice.
  That deletes the whole +1000 with no hot-path lookup and no memory, because it removes
  the second walk rather than remembering the first.

  **Not implemented here.** This task was scoped to decide the cache, and making a
  different engine change under a task that says "decide" is how scope creep starts. It is
  in SHACL-A-0002's As Measured section as an evidence-backed proposal with its numbers
  already taken, which is what a future task needs to act on it.

  ### Where it is written down

  - **SHACL-A-0002** gains an **As Measured** section, in the shape of SHACL-A-0001's
    "As Built": the isolation, the table, the decision, the alternative, and the trigger
    marked **discharged** rather than deferred again. Reopening it needs evidence of a
    different kind, not a repeat of this measurement.
  - **`docs/store-evidence.md`**'s standing note said the duplicate was structural and
    awaiting a benchmark. It has one, and the section now says so — and repeats the
    peak-memory point, because that log is where a reader goes asking whether the engine's
    read volume is about to change. It is not.

  ### Verification

  `make check` green, `make test` green at both widths (12 package runs), `make bench`
  green at both widths with the two new configurations pinned at 9003 and 10003. No file
  under `shacl/` was touched — the only code change is `bench/`.
