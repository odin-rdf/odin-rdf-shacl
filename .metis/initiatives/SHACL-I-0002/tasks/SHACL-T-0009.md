---
id: suite-progress-instrumentation-a
level: task
title: "Suite progress instrumentation: a non-gating per-entry floor"
short_code: "SHACL-T-0009"
created_at: 2026-08-06T19:26:41.173927+00:00
updated_at: 2026-08-06T19:26:41.173927+00:00
parent: SHACL-I-0002
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/todo"


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

## Acceptance Criteria **[REQUIRED]**

- [ ] The runner can execute a *disabled* directory's entries and count how many match their
      expected report, without enabling the directory and without affecting the pass/fail of
      any existing test.
- [ ] A pinned floor per disabled directory, asserted as a **minimum, not an equality**: the
      test fails if the count drops below the floor and passes if it exceeds it. Raising the
      floor is a deliberate edit, exactly as enabling a directory is.
- [ ] The floor starts at the measured values: **`core/node` and `core/property` together, 18
      of 69**. Per-directory figures measured and pinned as part of this task rather than
      taken from this description.
- [ ] The count is reported in the test output whether it passes or not, so a task that moved
      it by three can see that it moved it by three.
- [ ] **`enabled means fully green` is untouched.** A directory in the floor is still disabled;
      nothing here enables, skips, or excuses anything, and `test_exactly_the_spine_directories_are_enabled`
      still holds.
- [ ] Both backends, both `Term_ID` widths, and the floor is the same at both — a divergence
      between widths is a bug, not a lower floor.
- [ ] `make test` and `make check` green.

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

*To be added during implementation*
