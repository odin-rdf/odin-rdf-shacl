---
id: suite-progress-instrumentation-a
level: task
title: "Suite progress instrumentation: a non-gating per-entry floor"
short_code: "SHACL-T-0009"
created_at: 2026-08-06T19:26:41.173927+00:00
updated_at: 2026-08-06T21:40:28.907409+00:00
parent: SHACL-I-0002
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: SHACL-I-0002
---

# Suite progress instrumentation: a non-gating per-entry floor

## Parent Initiative

[[SHACL-I-0002]]

## Objective **[REQUIRED]**

Give this initiative an incremental signal it would otherwise not have. Only two suite
directories remain, and under the family's "enabled means fully green" rule neither can be
enabled until nearly every component exists — so a ten-task initiative would run to task nine
with no measured progress at all. This adds a **non-gating per-entry floor**: how many entries
of the disabled directories pass today, pinned, asserted to only ever go up.

## Acceptance Criteria

## Acceptance Criteria **[REQUIRED]**

- [x] The runner can execute a *disabled* directory's entries and count how many match their
      expected report, without enabling the directory and without affecting the pass/fail of
      any existing test.
- [x] A pinned floor per disabled directory, asserted as a **minimum, not an equality**: the
      test fails if the count drops below the floor and passes if it exceeds it. Raising the
      floor is a deliberate edit, exactly as enabling a directory is.
- [x] The floor starts at the measured values: **`core/node` and `core/property` together, 18
      of 69**. Per-directory figures measured and pinned as part of this task rather than
      taken from this description.
- [x] The count is reported in the test output whether it passes or not, so a task that moved
      it by three can see that it moved it by three.
- [x] **`enabled means fully green` is untouched.** A directory in the floor is still disabled;
      nothing here enables, skips, or excuses anything, and `test_exactly_the_spine_directories_are_enabled`
      still holds.
- [x] Both backends, both `Term_ID` widths, and the floor is the same at both — a divergence
      between widths is a bug, not a lower floor.
- [x] `make test` and `make check` green.

## Implementation Notes

### Technical Approach

The runner already produces exactly the needed result per entry (`run_entry` plus
`report_isomorphic`); what is missing is a caller that runs disabled directories and counts
rather than asserting. Most of this task is deciding what *not* to build: no new comparison,
no per-entry allow-list, no expected-failure file. A count and a floor.

Report the count, not the list of passing entry names. A pinned list would be a
skip-list-by-another-name — it would encode which entries are expected to pass, and the
family's rule exists precisely to avoid that. A monotonic number carries the progress signal
without carrying the temptation.

### Dependencies

None. This is the first task and touches only `tests/w3c/harness`.

### Risk Considerations

**The floor must not become a second scoreboard.** The risk is that it starts being read as
"we pass 40 of 69" in a way that substitutes for a green directory. It does not: an entry can
pass for the wrong reason — two of the current 18 expect a *conforming* report, which an
engine that ignores a constraint also produces. Say so where the number is printed, not only
here.

**Runtime.** Running 69 extra entries against two backends on every `make test` roughly
triples the harness package's work. Measure it; if it is material, the floor test can run the
in-memory backend only, since it is a progress metric rather than a conformance claim.

## Status Updates **[REQUIRED]**

- **2026-08-06 — Implemented; awaiting review.** `make test` green at both `Term_ID` widths,
  `make check` green. Two files: `tests/w3c/harness/floor_test.odin` (new) and a `floor` field
  plus `PROGRESS_FLOOR` in `tests/w3c/harness/suite.odin`. Nothing in `shacl/` was touched —
  this is harness work, as planned.

  **The measurement, per directory.** The initiative's 18 of 69 reproduces exactly, and now
  splits: **`core/node` 7 of 32, `core/property` 11 of 38**. Identical on memstore and
  kvstore, identical at 64- and 32-bit. Those are the pinned floors; `PROGRESS_FLOOR` is 18.

  **`core/complex` is counted but pinned at 0 — the one judgement this task had to make.**
  It scores 1 of 2, and the passing entry is `shacl-shacl` (SHACL's own shapes validating
  SHACL's own shapes), which expects `sh:conforms true` and needs `sh:sparql`,
  `sh:shapesGraph`, and `sh:entailment` — none of which exist here. So it is not being
  validated, it is being ignored into a conforming report: the sharpest instance in the tree
  of the "passes for the wrong reason" hazard the task description warned about, and pinning
  it would have pinned exactly that. It is also fragile in the other direction — as the
  catalogue lands components that shapes graph starts producing real results, and the entry
  may go red before it goes green for the right reason. A floor of 0 costs nothing and
  pre-empts a false alarm during the SHACL-SPARQL phase. Recorded above `SUITES`.

  Consequence worth noting: the printed total reads **19 of 72 (floor 18)** because the
  `core/complex` pass is real but unpinned. The catalogue's number remains 18 of 69.

  **Three assertions, not one.** Count ≥ floor was the requirement; two more were cheap and
  are true by design. `ran == entries` — a floor over a partially-read directory is
  meaningless, and a runner that ran nothing would otherwise satisfy any floor of 0.
  Backends must agree — the runner is one procedure with a switch, so a divergence is a bug
  rather than a lower floor. Width divergence is caught by the pin itself, since one constant
  is asserted at both widths.

  **Both pins verified to bite**, by raising `core/node`'s floor to 8: the floor test fails
  on both backends *and* `test_progress_floor_is_consistent` fails on the sum, so a
  per-directory edit that skips `PROGRESS_FLOOR` cannot pass quietly. Reverted.

  **Runtime measured, per the risk note: not material, so both backends stay.** The floor
  test is 1.47s of the harness package's 1.85s wall — it does roughly triple that package's
  work as predicted, but `make test` end to end is ~10s for the whole matrix. The fallback of
  running memstore only was not needed, and taking it would have cost the backend-agreement
  assertion.

  **Two things guarded against, both in the doc comments rather than only here.** The caveat
  is printed as its own log line before the counts, so the number cannot travel into a status
  update without it. And the temporary LMDB store tag is prefixed `floor-`: entry ids repeat
  across directories (`node/and-001` and `property/and-001` both exist) and the Odin test
  runner is multi-threaded, so an unprefixed tag would have had this test and
  `test_enabled_suites_are_green` opening one store path concurrently.

  **`tests/w3c/README.md` updated** — its inventory table still said "Enabled directories:
  none" from SHACL-T-0002. Now carries state and floor per directory, and a section on what
  the floor is and is not.