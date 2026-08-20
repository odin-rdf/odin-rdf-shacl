---
id: validate-before-commit-the-shapes
level: task
title: "Validate-before-commit: the shapes model bound as a record Validator, Enforce and Record semantics tested"
short_code: "SHACL-T-0034"
created_at: 2026-08-20T15:20:12.000000+00:00
updated_at: 2026-08-20T15:20:12.000000+00:00
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

# Validate-before-commit: the shapes model bound as a record Validator, Enforce and Record semantics tested

## Parent Initiative

[[SHACL-I-0004]]

## Objective

Rehome `session_init_txn`'s role (SHACL-T-0029) onto the mechanism
built for it: an exported shacl binding that adapts a compiled
shapes model to `record.Validator{check, data}`, wired once at
`store_open`, so every `apply` is judged against **the dataset that
write would produce** — the candidate `Snapshot` at the new epoch,
read through the ordinary API. This is the binding `RECORD-A-0006`
named this repository for.

## Acceptance Criteria

- [ ] An exported procedure (name at implementation) that takes a
      compiled shapes model plus caller-owned report/config state and
      returns a `record.Validator` ready for `store_open`.
      `SHACL-A-0001`'s term ownership is the load-bearing contract:
      the model outlives any store it compiled from, so shapes may be
      compiled from a snapshot of the same store, another store, or a
      parsed document.
- [ ] The report's lifetime is solved caller-side: `check` returns
      only `bool` to record, so the full `sh:ValidationReport` (or
      the suppressed-validation fast path — `SHACL-A-0002` applies
      here too) lands in state reachable through `data`, owned by the
      caller, valid after `apply` returns. Its reset-per-apply
      discipline is documented.
- [ ] The candidate `Snapshot` is **not retained** past `check`
      (record's contract — it carries no reference of its own), and
      the doc comment says so; the pre-state, where a constraint
      needs it, is a `store_latest` acquire/release inside `check`.
- [ ] Semantics tested from shacl's side: `Enforce` + nonconforming
      changeset → `apply` returns `.Rejected`, nothing written, the
      published state unchanged; `Record` + nonconforming → commits,
      `conforms == false`, report populated; conforming → commits
      under both modes. A constraint that must consult existing data
      (`sh:class` with the hierarchy already in the graph,
      `sh:uniqueLang` against existing values) sees head *and*
      changeset together in the candidate — the vacuous-pass failure
      `SHACL-T-0029` existed to kill stays dead.
- [ ] A check that resolves a term first introduced by the changeset
      finds it in the candidate.
- [ ] The SHACL-T-0029 scenario tests are re-expressed in this
      shape and green; the old `session_init_txn` tests are gone
      with the procedure (deleted in SHACL-T-0032).

## Implementation Notes

The log does not record that a judge objected (`RECORD-A-0006`,
decision 5): a `Record`-mode verdict is not durable, and a consumer
wanting it durable writes facts. Out of scope here per the
initiative's non-goals — but say it plainly in the binding's doc
comment so no caller assumes otherwise.

`apply` is not thread-safe against itself and the `check` runs on
the applying thread; the binding inherits that and documents it
rather than adding locking.

## Status Updates

*To be added during implementation*
