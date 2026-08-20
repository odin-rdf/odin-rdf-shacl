---
id: validate-before-commit-the-shapes
level: task
title: "Validate-before-commit: the shapes model bound as a record Validator, Enforce and Record semantics tested"
short_code: "SHACL-T-0034"
created_at: 2026-08-20T15:20:12+00:00
updated_at: 2026-08-20T17:26:52.472605+00:00
parent: SHACL-I-0004
blocked_by: [SHACL-T-0033]
archived: false

tags:
  - "#task"
  - "#phase/completed"


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

**2026-08-20 — implemented, all criteria met; awaiting review.**

**The binding is `Validator`** (`shacl/validator.odin`): `validator_init(v,
shapes, graph = nil, reporting = true, allocator)`,
`validator_hook(v) -> record.Validator` for `store_open`,
`validator_report(v) -> ^Report`, `validator_destroy(v)`; the installed
`check` is `validator_check`. The spec's word, deliberately: the first cut
named it `Judge` after RECORD-A-0006's prose ("a judge objected") to keep
it apart from `record.Validator`, and the owner asked for the rename — the
two live in different packages, so `shacl.Validator` and `record.Validator`
never collide, and a type named for the ADR's metaphor in a file named for
the SHACL concept cost every reader a translation. Only `validator_hook`
says "adapter" in its name, because it is the one procedure whose job is to
produce record's type. The model is borrowed and outlives
the validator (SHACL-A-0001 — every test compiles its shapes from a store that
is closed before the validated store opens); the validator outlives the store
(`store_close` before `validator_destroy`, and the doc says why). The graph
label is copied. One validator, one store.

**What a check does.** Session over the candidate with the validator's graph —
resolved against the candidate, so a graph the changeset is the first to
name is judged rather than read as absent — bindings and validation
transients from apply's scratch allocator, the report (when reporting) on
the validator's own; whole-graph validation, every target of every shape, since
a change to one node can make another violate (narrowing is the consumer's,
with `validate_node` and the ops — said in the doc). The candidate is not
retained: session, bindings and every read live inside the call; the
pre-state is never needed, the candidate being head plus change. **A
`Failure` is a refusal**: `Recursive_Shape` returns `false` with
`v.failure` set, so a validator that cannot answer does not let a write
through and the caller can tell a refusal from a violation. **Reset per
apply**: the report and verdict are always the last apply's, valid until the
next `apply` or `validator_destroy`; `reporting = false` keeps no report and
allocates nothing per result (`Conformance`). Decision 5 stated in the file
header and the README: the log does not record that a judge objected.

**Semantics tested from shacl's side** (`shacl/validator_test.odin`, 11
tests): Enforce + nonconforming → `apply` returns `{.Rejected, -1}`, epoch
not issued, head epoch unchanged, the quad absent, the committed quad still
there, the report populated, and the next conforming write commits as the
next epoch (the store is not poisoned); Record + nonconforming → commits,
`conforms == false`, quad at head, report populated; conforming commits
under both modes. The vacuity case (T-0029's central test): the candidate
is refused only because the committed data is visible — the same world from
an empty store under the same validator is accepted. `sh:class` with the
hierarchy in head and the instance in the changeset conforms, and without
the hierarchy is refused. A `sh:targetNode` the store has never seen
refuses an unrelated write (unbound focus, `sh:minCount 1`) and is satisfied
by the write that names it — the changeset-introduced term resolves in the
candidate. A retraction is judged on the post-state (the candidate hides the
retracted quad): taking away the only `ex:name` is refused under Enforce and
committed-with-verdict under Record. A validator on a named graph ignores writes
to other graphs and refuses a write into its graph even when the changeset
is the first to name the graph. Report reset: a Record-mode violation then a
*repair* leaves zero results. Recursive shape → refused with
`failure == .Recursive_Shape`. Verdict-only validator: same refusals, no report.
Plus `tests/guards.test_validator_is_net_zero` (four applies alternating
verdicts under the tracker, store included) and the README's fifth example,
compile-verified in `tests/readme`. `make test`/`make check` green;
`windows_amd64` check clean.

**Two things learned writing the tests, both record semantics rather than
validator semantics, worth the sparql port knowing:** (1) a candidate on record
is the *delta* — re-asserting a quad that is live is `.Already_Live` at the
op, judged before any validator runs — so the T-0029 fixture's
self-contained candidate became two fixtures (the delta, and the same world
from empty for the isolation half); (2) under `.Record` a violation
*commits*, so the next write is judged against a dataset that still
violates — a "reset" test needs a repair, not an unrelated write.

**Docs:** README's "Deciding whether a write may join the dataset" rewritten
for the `Validator` (the old `session_init_txn` text is gone; its argument — the
isolated candidate is wrong, not slow — stands verbatim); the package doc
points at `validator.odin`; `tests/readme`'s header note resolved. The
README's remaining kvstore-era prose (`shacl/kvstore` in the package table,
"LMDB-backed", the width matrix) is T-0037's.