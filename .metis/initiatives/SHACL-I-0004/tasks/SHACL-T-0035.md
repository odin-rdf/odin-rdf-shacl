---
id: as-of-validation-on-record-the
level: task
title: "As-of validation on record: the SHACL-T-0030 scenarios via store_at"
short_code: "SHACL-T-0035"
created_at: 2026-08-20T15:20:22.000000+00:00
updated_at: 2026-08-20T15:20:22.000000+00:00
parent: SHACL-I-0004
blocked_by:
  - SHACL-T-0033
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: SHACL-I-0004
---

# As-of validation on record: the SHACL-T-0030 scenarios via store_at

## Parent Initiative

[[SHACL-I-0004]]

## Objective

Preserve the capability SHACL-T-0030 established on the store:
validating a past dataset. On record it needs no dedicated API at
all — `store_at(s, epoch)` returns a `Snapshot` pinned at that
epoch, `session_init` binds it like any other, and every read
through the session answers about that moment. The task is the
proof, not machinery.

Why the capability exists at all (owner discussion, 2026-08-20 — the
record is immutable, so remediation is never the purpose): validating
past data under the *current* model explains the present (bisect for
the epoch that introduced a violation, `snapshot_epoch_meta` names
who and why) and reports exposure windows for newly adopted rules;
validating past data under the *then-current* model is the
accountability question ("did it conform to the rules in force at
the time") — and, sharper, it is the recomputation that
`RECORD-A-0006` decision 5 relies on: the log deliberately does not
record that a judge objected, so a verdict about the past is
recoverable only by recomputing it over the epoch-pinned dataset.
As-of validation is what keeps conformance claims about the past
independently checkable, which is the record's value proposition
extended.

## Acceptance Criteria

- [ ] The as-of scenario tests (the `as_of_test.odin` set before the
      port) re-expressed over record: build epochs through `apply`,
      validate at a historical epoch via `store_at` + `session_init`,
      and at head via `store_latest` — a violation introduced in a
      later epoch is absent at the earlier one, and vice versa for a
      violation later retracted.
- [ ] A retracted-graph case: a graph whose quads were all retracted
      validates as empty at head and as populated at the earlier
      epoch (record's retraction is logical — `Filter{origin = .Any}`
      at a pinned epoch is the read).
- [ ] Epoch metadata is the audit trail: a test reads
      `snapshot_epoch_meta` (actor, reason, wall) for the epoch it
      validates, demonstrating the who/when/why alongside the
      verdict.
- [ ] **Shapes-as-of-then**: shapes stored in the same store evolve
      across epochs; compile a model from a session over
      `store_at(E)`'s shapes graph, validate `store_at(E)`'s data
      graph with it, and show the verdict differs from validating
      the same pinned data under the head shapes — the decision-5
      recomputation, and time-consistency for free since one
      snapshot feeds both sessions (`SHACL-A-0001` releases it after
      compile). This scenario is expected to be **test code only** —
      compile already reads through a session, so no library change
      is in its scope; if implementation finds otherwise, stop and
      report rather than rewriting code T-0035 would not otherwise
      touch.
- [ ] Documented: the as-of coordinate is the **epoch**, not a
      wall-clock time — record deliberately has no `epoch_at(wall)`
      (an application-side ask, per RECORD-I-0003's non-goals), so a
      caller holding a time finds its epoch by its own bookkeeping or
      via epoch metadata.

## Implementation Notes

The suppressed-validation path (`SHACL-A-0002`) and the ordinary
report path should both appear in at least one as-of scenario, since
both ride the same session.

## Status Updates

*To be added during implementation*
