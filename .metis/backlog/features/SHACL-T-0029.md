---
id: bind-session-to-a-store
level: task
title: "Bind Session to a store transaction, so validate-before-commit is reachable"
short_code: "SHACL-T-0029"
created_at: 2026-08-08T00:05:00+00:00
updated_at: 2026-08-08T13:44:56.038724+00:00
parent: 
blocked_by: []
archived: false

tags:
  - "#task"
  - "#feature"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: NULL
---

# Bind Session to a store transaction, so validate-before-commit is reachable

## Objective **[REQUIRED]**

**Filed from odin-rdf-store as STORE-T-0041.** odin-rdf-store v0.3.0 published transactions,
and with them the thing an editing application actually needs: a validator that can read
*the dataset a write would produce*. This repo is what stands between that and the
application, because `Session` binds to a bare `^kvstore.Store` and every read below it goes
through the autocommit procedures.

Let `Session` optionally carry a `^kvstore.Txn`, and read through it when it does.

**This is not an enhancement. It is the second half of a P0 that odin-rdf-store has already
paid for.** `odin-rdf-app` accepts a description of a resource and has to decide whether it
may join the dataset. The decision procedure is SHACL, reading the data graph through this
package. Until that read can go through the caller's write transaction, the validator still
cannot see the write it is deciding about — the store has fixed its half and the gap is still
open where the application meets it.

The evidence is odin-rdf-store's STORE-T-0022, and the shape of the wrongness is worth
restating because it is not "slower":

- **Validate-then-commit leaves a window.** Two writers that each validate against a dataset
  lacking the other's write can both conform and both commit, producing a dataset that
  satisfies neither's constraints.
- **Commit-then-validate cannot be undone.** There is no `remove` in the store yet.
- **The isolated-candidate workaround is wrong, not merely slow** — and it is the one this
  repo's API currently steers a caller toward. Build the candidate in a second store, validate
  *that*, and every constraint that must consult existing data reads an empty world and passes
  vacuously: a class hierarchy already in the store, a reference to an existing resource,
  uniqueness across the dataset. **A validator that cannot fail is worse than one that is
  absent.** odin-rdf-store's conformance suite demonstrates this failure mode directly, using a
  uniqueness constraint chosen because it is exactly the shape the workaround approves.

## Backlog Item Details **[CONDITIONAL: Backlog Item]**

### Type
- [x] Feature - New functionality or enhancement

### Priority
- [x] P1 - High (important for user experience)

P1 rather than P0 because nothing in *this* repo is currently wrong: every test passes, the
W3C suite is green, and a validator over a committed dataset is correct. What is missing is
reach — this is the last hop of somebody else's P0, and it is a small hop.

### Business Justification **[CONDITIONAL: Feature]**
- **User Value**: An application can decide whether to keep a write by validating what the
  write would produce, rather than by validating something that is not the dataset.
- **Business Value**: Opens this validator to the whole class of consumers that accept data
  from outside themselves — services, editors, interactive shells — which is most of what the
  family is for.
- **Effort Estimate**: S. One field on a struct this package already threads everywhere, plus
  seven call sites. Stated as an estimate from the store side; this repo owns the number.

## What odin-rdf-store shipped **[CONDITIONAL: Feature]**

v0.3.0 (ADR `STORE-A-0007`, initiative `STORE-I-0004`). One opaque `Txn` handle with a
`.Read`/`.Write` mode, and **a read transaction *is* the snapshot** — no separate snapshot
type, nothing in the API says "snapshot".

```odin
Txn_Mode :: enum { Read, Write }        // in the store vocabulary package

txn_begin  (s: ^kvstore.Store, mode: store.Txn_Mode) -> (kvstore.Txn, kvstore.Error)
txn_commit (t: ^kvstore.Txn) -> kvstore.Error
txn_abort  (t: ^kvstore.Txn)
```

Every read this package uses has a `_txn` form taking the handle alone: `match_txn`,
`find_term_txn`, `lookup_term_txn`, `count_txn`, `find_graph_label_txn`,
`lookup_graph_label_txn`, plus the loaders. `match_txn`'s iterator **borrows** the transaction
— `match_destroy` closes the cursor and leaves the transaction alone — so nothing about this
package's iterator handling changes.

**The bare procedures are unchanged and are now defined as autocommit**, so this proposal is
additive on this side too: a `Session` that carries no transaction keeps working exactly as it
does today, and every existing caller compiles untouched.

## Acceptance Criteria **[REQUIRED]**

- [x] `Session` gains an optional transaction — the natural home, since it is already the
      dataset handle this package threads and is "a struct rather than a handle [that] costs
      nothing" (its own doc comment). **Nil means autocommit**, which is today's behaviour and
      must stay the default.
- [x] A constructor beside `session_init` that binds one — `session_init_txn(s, tx, graph)` or
      equivalent — so the existing three-argument `session_init` keeps its meaning.
- [x] The seven read sites switch to the `_txn` form when a transaction is present:
  - `shacl/kvstore/compile.odin:56` — `match_adapter`, the compile path's reader
  - `shacl/kvstore/compile.odin:93` — `load_adapter`, `lookup_term`
  - `shacl/kvstore/compile.odin:106` — `find_adapter`, `find_term`
  - `shacl/kvstore/compile.odin:190` — `find_graph_label`
  - `shacl/kvstore/eval.odin:39` — `step_adapter`
  - `shacl/kvstore/eval.odin:95` — `scan_adapter`
  - `shacl/kvstore/eval.odin:134` — `outgoing_adapter`
- [x] **The error-slot contract is unchanged.** A failed read still records into `Session.err`
      and still hands back an already-done iterator, because a failed match that looks like an
      exhausted one is how a broken store reads as a conforming graph. Transactions change
      where a read comes from, not what a failure means.
- [x] **A test that would fail without this**, and it should be the vacuity case rather than
      the happy path: pre-existing committed data, a candidate loaded into a write transaction,
      and a constraint that violates *only because* the pre-existing data is visible.
      `sh:maxCount` over a property the candidate adds a second value to, or `sh:class` against
      a hierarchy that lives only in the committed graph. Validating the same candidate in
      isolation must pass — that assertion is what makes the test about this feature rather
      than about SHACL.
- [x] **The cost is documented where a caller will read it, as contract rather than as a
      note**: a write transaction held across a validation **serializes every other writer
      against that environment for its lifetime**, and the validate-before-commit pattern holds
      one across the *entire* validation by construction, since read-your-own-writes is the
      whole point. On the read side, a long-held snapshot pins pages and makes a concurrent
      writer grow the file. Neither should be discovered in production.
- [x] `make test` green at both `Term_ID` widths; `make check` clean, including `purity`.
- [x] The CI pin moves to `v0.3.0`. Note it is a **floor, not just a pin**, as `v0.2.0` already
      is here: `match_txn` does not exist before it.

## Implementation Notes **[CONDITIONAL: Technical Task]**

### Technical Approach

`Session` is `{db: ^kvstore.Store, graph: store.Term_ID, err: kvstore.Error}` at
`shacl/kvstore/compile.odin:32`. Adding `txn: ^kvstore.Txn` and branching in the adapters is
the whole change; the core (`shacl.Access`, the `Result_Visitor` contract, the shapes model)
is untouched, and so is every signature above `Session`.

**SHACL-A-0001's ownership property is unaffected, and worth saying out loud so nobody
re-derives it.** The shapes model owns every term it holds and outlives the store it compiled
from. Binding the *data* side to a transaction changes nothing about the shapes side —
compile once at startup, validate many, each validation optionally inside a transaction. The
compile-once contract that STORE-I-0003 established (reloading a shapes graph does not dedupe,
because per-load blank-node scoping mints fresh blanks) is likewise untouched, and now has a
sharper edge: **two loads into one transaction still mint distinct blanks**, which
odin-rdf-store asserts.

### Dependencies

odin-rdf-store **v0.3.0**. Nothing in this repo blocks it.

### Risk Considerations

**The long-writer cost is real and is the thing to think about before adopting the pattern
widely, not after.** A validation is not fast, and a write transaction held across one blocks
every other writer against that environment. For the deployment shape this family targets —
~200 processes per machine, each embedding its own store — that serializes within an
environment and not between them, which is why it is acceptable. A consumer that puts one
store behind many concurrent writers should know the shape of what it is buying.

A smaller one: with a transaction present, the adapters have two paths, and the untested path
is whichever the suite does not exercise. The existing suite runs the autocommit path, so the
new tests must run the transactional one — not merely construct a transaction and then take
the old branch.

## Status Updates **[REQUIRED]**

- **2026-08-08 — Filed from odin-rdf-store (STORE-T-0041), which supplies the argument and the
  call sites and does not edit this repo.** Raised before filing, per the family's convention
  on touching sibling repos. odin-rdf-store's half shipped as v0.3.0 and is CI-verified on all
  three platforms; the sequencing of this half is this repo's own.

  **Worth pairing with something this repo already asked for.** SHACL-T-0028 reported the
  temp-path duplication upstream — "five copies of the temp-path dance in this repo alone and
  nine across the family" — and odin-rdf-store answered it in the same v0.3.0 with
  `kvstore.open_ephemeral`: a store with no path to name, make unique or clean up, whose 16 MiB
  default map replaces the 1 GiB one. That matters here for a reason beyond tidiness. LMDB has
  no sparse-file handling on Windows, so every `open` there materializes `map_size` in full,
  and **this repo's Windows CI job takes 211s against ubuntu's 17s** for exactly that reason.
  odin-rdf-store's own job went 64s → 41s while running 83% more tests once it adopted it.
  Bumping the pin to v0.3.0 is the prerequisite for both, so they are one pass.

- **2026-08-08 — Done. 151 tests per width, green at both, `make check` clean including
  `purity`.** The estimate held: one field, one constructor, and the call sites. Counts went
  145 → 151, all six in `shacl/kvstore/txn_test.odin` except the README's, which is in
  `tests/readme`.

  **The seven read sites went through three wrappers rather than seven branches.**
  `session_match`, `session_lookup` and `session_find_term` are the only places that know a
  transaction might be present, so the transactional and autocommit forms cannot drift apart
  one site at a time. They report failure rather than recording it — the error slot stays with
  the adapters, which are the ones that have to keep the walk well-formed afterwards, so that
  contract is untouched.

  **`session_init_txn` takes the transaction alone, not `(store, txn)`.** A `Txn` carries its
  own store, but that field is odin-rdf-store's business — STORE-A-0007 exists to keep LMDB
  types off consumers, and reading it here would bypass the interface for convenience. The
  consequence is that `db` is nil on a transactional session, documented on the struct; the two
  test helpers that read `s.db` now go through the wrappers.

  **`compile_turtle_txn` was added**, because it is the only way the `find_graph_label` site
  named above has a transaction to read through — `compile_turtle` builds its session after
  loading. It also covers the case the acceptance criteria did not ask about: a shapes graph
  loaded inside a transaction that is then thrown away, with the model surviving it.

  **One assumption in the test plan was wrong, and the correction is worth keeping.** An
  autocommit *read* is not refused while a write transaction is open — only writes are
  (`.Write_Txn_Open` covers `insert` and the loaders). A bare read opens a read transaction of
  its own, succeeds, and answers about the last committed dataset. So a session bound to the
  wrong thing does not announce itself, which is a sharper statement of the bug than the
  refusal would have been, and `test_autocommit_session_cannot_see_the_open_write` now pins it.
  It is also what proves the vacuity test is not passing for free: the same store at the same
  instant gives two different answers through the two sessions.

  **The cost went in twice**: as contract on `session_init_txn`, and as a README section a
  consumer will actually meet, with a worked example mirrored in `tests/readme`.

  **One finding beyond the item's scope, fixed in the same pass at the maintainer's request.**
  The README's quick start had drifted from `tests/readme` — no `session_init` calls, a `Sink`
  field name that did not exist, `lookup_term` at the wrong arity, `compile_turtle`'s three
  returns taken as two. The "compiled and asserted, so they cannot drift" claim does not hold
  for a mirror maintained by hand, and it had silently not held for some time. The block is now
  identical to the mirror apart from the store path, verified by diffing the two rather than by
  eye, and both files now state the two permitted divergences instead of implying there are
  none.

  **Not done here, and deliberately**: the paired `open_ephemeral` adoption. The pin bump it
  needs is in, but it touches four scratch-path helpers across three packages and belongs in
  its own pass rather than inflating this diff.

- **2026-08-08 — The paired half followed in its own commit.** 58 opens moved to
  `kvstore.open_ephemeral`, three of the four scratch-path helpers deleted outright, and with
  them the fixtures' dead `path` fields and the `name` arguments that existed only to label a
  scratch directory. Net −207 lines. Per-width suite time went ~2.95s → ~0.25s on macOS, where
  the map size is nearly free; Windows is where the 265s CI job should fall, since that is where
  every `open` materializes `map_size` in full.

  **Three opens keep `kvstore.open`, and the reasoning is the part worth keeping.** The linkage
  proof stays on the durable constructor because `open_ephemeral` opens with
  `NOSUBDIR | NOLOCK | NOSYNC` — a different flag set, no lock file, an unlinked inode on POSIX —
  and proving the vendored archive resolves is a claim that should be made against the
  configuration a consumer runs, not a test-only one. `test_kvstore_compilation_does_not_write`
  keeps it because it closes a store and reopens *the same path* read-only, which an ephemeral
  store has no way to express and whose `read_only` it ignores by contract. So `temp_path`
  survives in `link_test.odin` with two callers rather than sixty.

  **`bench/` was left on `open` with `DEFAULT_OPTIONS`, deliberately.** `EPHEMERAL_OPTIONS`
  carries `no_sync = true` and a 16 MiB map, so adopting it there would quietly change what the
  benchmark measures; benchmarks are not in CI, so there is no time argument to weigh against
  that. That is the fourth of the helpers SHACL-T-0028 counted, and it stays on purpose.

  The README gained a **Scratch datasets** section, so `open_ephemeral` is documented for
  consumers rather than only used internally — including the Windows caveat that an abnormal
  termination leaks one file, and the two exceptions above.
- **2026-08-08 — A correction to the `open_ephemeral` pass above, and the upstream fix it
  led to.** Two of the tests converted in that pass hold a reader open across a writer —
  `test_read_txn_does_not_see_a_later_commit` and
  `test_autocommit_session_cannot_see_the_open_write` — which is the one arrangement
  LMDB's `NOLOCK` contract forbids, and `open_ephemeral` opens with `NOLOCK`. Both are
  back on `kvstore.open`. They had passed, and would have gone on passing: the fixtures
  are a handful of quads, so the freelist never wraps and no reused page is ever handed
  back. odin-rdf-store now documents that rule on `open_ephemeral` itself rather than
  leaving it in this repository's test comments.

  Adopting `open_ephemeral` also surfaced a Windows bug in it: this suite's job failed
  intermittently, one or two of ~58 opens per run, a different test each time. That is
  `STORE-T-0042`, fixed in odin-rdf-store v0.4.0 by retrying a reservation Windows
  transiently refuses; the CI pin here moved v0.3.0 → v0.3.1 → v0.4.0 along the way, and
  the middle step existed only to make the error say what it was. Five consecutive green
  Windows runs followed, against three of three failing before.
