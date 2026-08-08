---
id: validate-a-past-dataset-an-as-of
level: task
title: "Validate a past dataset: an as-of validation test, and the read-vs-write distinction"
short_code: "SHACL-T-0030"
created_at: 2026-08-08T20:04:41.286340+00:00
updated_at: 2026-08-08T20:04:41.286340+00:00
parent: 
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/backlog"
  - "#feature"


exit_criteria_met: false
initiative_id: NULL
---

# Validate a past dataset: an as-of validation test, and the read-vs-write distinction

## Objective **[REQUIRED]**

**Filed from odin-rdf-store as STORE-T-0052**, the closing task of STORE-I-0005 and the
verification half of `STORE-A-0008`. odin-rdf-store has gained transaction time: every quad
carries the epoch of the transaction that wrote it, `remove` retracts rather than erases, and
`txn_begin_as_of(s, horizon)` returns a **read** transaction through which *every* read is
as-of.

The claim the ADR is sold on, in its own words (§4): because
`shacl_kvstore.session_init_txn` already takes a `^kvstore.Txn` (SHACL-T-0029), **passing an
as-of transaction makes every SHACL validation as-of, with no line changing in this
repository.** That is a claim about this repo, made in another one, and the store's
initiative wrote it as an exit criterion in the form *"verified, not assumed"*.

This task is that verification, made permanent. A scratch program was the cheaper option and
odin-rdf-store rejected it explicitly: it verifies the claim at a moment, and *as-of costs the
siblings nothing* is precisely a claim a future change **here** could break. It should fail in
the repository that broke it.

**The distinction this task exists to keep straight, and the reason it is a task rather than a
line in someone else's:**

`session_init_txn` was built for **validate-before-commit** — a candidate assembled inside a
`.Write` transaction, validated through that same transaction, kept or discarded on the answer.
`txn_begin_as_of` deliberately takes no mode and always returns a `.Read` transaction, because
**an audit store must not expose an API for writing history** (STORE-A-0008 §4), and that is a
property of the signature rather than a runtime check.

So an as-of validation demonstrates something *different*: **validating a past dataset**, not a
candidate write. The two use the same call and are not the same feature, and they do **not**
compose — there is no way to assemble a candidate inside an as-of transaction, by construction.
A test that reads like validate-before-commit but is not would be worse than no test, because
it would leave the next reader believing in a combination the store refuses to offer.

## Backlog Item Details **[CONDITIONAL: Backlog Item]**

### Type
- [x] Feature - New functionality or enhancement

### Priority
- [x] P1 - High (important for user experience)

P1 for the reason SHACL-T-0029 was P1 and not P0: nothing in this repo is wrong today. This is
somebody else's release criterion reaching its last hop, and — if the claim holds — it is a
test file and a vision amendment rather than a change to the library.

### Business Justification **[CONDITIONAL: Feature]**
- **User Value**: "Did this resource conform to our shapes last quarter?" becomes a question
  the validator answers, with no temporal vocabulary in the shapes graph and nothing an
  application must remember to filter on. For a compliance consumer that is a primary
  question rather than a curiosity.
- **Business Value**: It keeps the store's central design bet honest from the consumer side.
  The bet — put the time axis on the transaction, not in the query language — pays off
  precisely in that the siblings need no changes, and this repo is one of the two places
  where that either holds or does not.
- **Effort Estimate**: S, *if the claim holds*. A test file, a vision amendment and a CI pin.
  If it does not hold, the finding is the deliverable and the size is unknown.

## What odin-rdf-store shipped **[CONDITIONAL: Feature]**

Unreleased on `main` as of 2026-08-08; **v0.5.0** when tagged. ADR `STORE-A-0008`, initiative
`STORE-I-0005`. Format version 2, which does not read version 1 and has no migration.

```odin
txn_begin_as_of (s: ^kvstore.Store, horizon: store.Epoch) -> (kvstore.Txn, kvstore.Error)
epoch_at        (s: ^kvstore.Store, nsec: i64)            -> (store.Epoch, kvstore.Error)
remove          (s: ^kvstore.Store, pattern: store.Match_Pattern) -> (int, kvstore.Error)
remove_txn      (t: ^kvstore.Txn,   pattern: store.Match_Pattern) -> (int, kvstore.Error)
epoch_info      (s: ^kvstore.Store, epoch: store.Epoch, allocator) -> (Epoch_Info, bool, Error)
match_history   — the only way to see version boundaries
```

Four things that bear on this repo:

- **The horizon lives on the transaction**, so `match_txn`, `count_txn`, `find_term_txn` and
  `lookup_term_txn` — the four reads `Session` goes through — are all as-of when the
  transaction is. Nothing in `shacl/kvstore` learns the concept exists.
- **`txn_begin` grew a defaulted third parameter** (`store.Txn_Annotation`), which is why
  every existing call site here compiles unchanged.
- **Epoch 0 is never assigned**, so `store.EPOCH_NEVER` is "before anything" and yields the
  empty dataset; a horizon past the newest epoch is HEAD rather than a failure. That makes an
  uninitialised `Epoch` mean "empty" rather than "the first commit".
- **`count_txn` is a scan in an as-of transaction** where it is O(1) at HEAD. Nothing in this
  repo's validation path calls `count`, so the documented asymmetry does not reach us — worth
  recording as checked rather than left implicit, since the store's task flags it for the
  siblings.

## Acceptance Criteria **[REQUIRED]**

- [x] **This repo's full suite passes against odin-rdf-store's working tree with no source
      change here**, both `Term_ID` widths. This is the criterion; the demonstration below is
      the interesting part but it is not what "no source change" means, so it is run **first**.
- [x] **A permanent as-of validation test** in `shacl/kvstore`, satisfying the store task's
      wording: *a shape that a candidate violates at HEAD and conforms to at an earlier epoch,
      or the reverse*. It must genuinely differ between the two — a validation reporting the
      same answer either way demonstrates nothing, which is the store task's own stated
      second-likeliest failure.
- [x] **The epochs are built with `remove` and ordinary inserts across several
      transactions**, so retraction is exercised rather than only assertion: the past showing
      a quad the present does not is the whole of what retraction-not-erasure buys.
- [x] **The test says in its own comment which of the two features it is.** As-of validation
      is *validating a past dataset* through a read transaction; validate-before-commit is a
      candidate inside a write transaction (`shacl/kvstore/txn_test.odin`, SHACL-T-0029).
      Same entry point, different feature, and they do not compose.
- [x] **`SHACL-A-0001` decision 5 respected in the fixture**: validation reads one
      caller-named graph, so everything the constraints need — including any class hierarchy —
      is in that graph. One of the two tests turns on exactly this, retracting an
      `rdfs:subClassOf` triple out of the validated graph.
- [x] **Nothing puts `store:store/kvstore` into package `shacl`.** The test belongs on the
      `shacl/kvstore` side, and `make check`'s `purity` target is what asserts it.
- [x] `make test` green at both widths; `make check` clean, including `purity`.
- [ ] **The CI pin moves to `v0.5.0`** — a **floor**, not just a pin: `txn_begin_as_of` does
      not exist before it, so this test does not compile against `ref: v0.4.0`. **Blocked
      until odin-rdf-store tags v0.5.0**, and it must land in the *same commit* as the test,
      or CI goes red on merge. Local verification needs no tag, because `make` reaches the
      store through `-collection:store=../odin-rdf-store` — the working tree.
- [x] **`.metis/vision.md` Current State amended, dated**, per the family's "a release is not
      done until its consumers' Current State is re-read" convention: the store this sits on
      now has a time dimension, as-of reaches validation with no source change, and the
      read-vs-write distinction is recorded there too — a future reader will otherwise assume
      as-of and validate-before-commit compose.

## Implementation Notes **[CONDITIONAL: Technical Task]**

### Technical Approach

Nothing in `shacl/` changes. `Session` already branches on `txn != nil` in three wrappers
(`session_match`, `session_lookup`, `session_find_term`), and an as-of transaction is an
ordinary `^kvstore.Txn` to all three. The work is a fixture and two assertions.

**Epochs are counted, not clocked.** Only a quad write allocates an epoch (STORE-A-0008 §6),
and each autocommit loader or `remove` is one write transaction, so a fixture of three edits
holds epochs 1, 2, 3 deterministically — which is how odin-rdf-store's own `as_of_test.odin`
builds its history. `epoch_at` is deliberately **not** used here: turning a wall clock into a
horizon is the store's concern and is tested there, and a downstream suite that depends on two
commits landing in distinguishable clock ticks would be a flake on the coarsest-clocked
platform in CI rather than a statement about validation.

### Dependencies

odin-rdf-store **v0.5.0** (unreleased at filing; verified against its working tree). Nothing
in this repo blocks it. odin-rdf-sparql carries the same task's other half independently.

### Risk Considerations

**The likeliest outcome is that this works, and the second likeliest is that it works for the
wrong reason** — a fixture whose validation would give the same answer at HEAD proves nothing.
Both tests are therefore written so the answers differ, and each pins the *dataset* it read as
well as the verdict, so a conformance that is really "the graph was empty" cannot pass for a
conformance that is "the graph was fine".

**The blurring risk is the one specific to this repo.** `session_init_txn`'s doc comment, its
existing tests, and the README all frame a caller-held transaction as validate-before-commit.
An as-of test dropped in beside them would be read as another instance of that pattern, and
the next person would reasonably conclude they could build a candidate inside an as-of
transaction and validate the merged result. They cannot: the signature returns `.Read`. The
mitigation is prose — in the test file, in this task, and in the vision — rather than code.

**If this repo turns out to need a store change**, that is a finding, not a fix: it falsifies
STORE-I-0005's exit criterion and belongs upstream as a proposal raised before it is filed.

## Status Updates **[REQUIRED]**

- **2026-08-08 — Filed from odin-rdf-store (STORE-T-0052), raised before filing per the family
  convention on touching sibling repos.** The store's own status update records that the claim
  had already been checked throwaway on the SPARQL side — one query, two answers, no source
  change — and that a scratch check is explicitly *not* the deliverable. This is the SHACL
  half, made permanent.

- **2026-08-08 — Done, and the claim holds: as-of costs this repository nothing.** Not one
  line of `shacl/` or `shacl/kvstore/` changed; the only addition is
  `shacl/kvstore/as_of_test.odin`. The full suite was run against odin-rdf-store's working
  tree **before** anything was written — 156 tests per width, green at both, `make check`
  clean including `purity` — which is the "no source change" criterion, and only then were the
  demonstrations added. 158 per width afterwards (`shacl/kvstore` 94 → 96), green at both
  widths, `make check` still clean.

  **Two tests, and each differs between HEAD and the horizon in the opposite direction**, so
  neither can be passing because as-of quietly read HEAD:

  - `test_as_of_validation_sees_the_dataset_as_it_was` — three epochs from one `sh:maxCount 1`
    shape. Epoch 1 loads a person with one `ex:email` (conforms), epoch 2 inserts a second
    (violates), epoch 3 `remove`s the second (conforms again). **HEAD conforms; horizon 2
    violates** — the present cannot see a violation the past holds, which is retraction being
    logical rather than physical, observed from the validator. Horizon 1 conforms
    *non-vacuously*, and the test pins that with `count_txn` per horizon so "conforms" cannot
    silently mean "the graph was empty". Horizon 0 conforms **and is asserted to be the
    vacuous case**, since `store.EPOCH_NEVER` is the value a caller reaches by forgetting to
    set one.
  - `test_as_of_validation_sees_a_retracted_class_hierarchy` — `sh:class` over an
    `rdfs:subClassOf` triple that epoch 2 retracts out of the validated graph. **HEAD
    violates; horizon 1 conforms** — the reverse direction, and the one that exercises
    SHACL-A-0001 decision 5 head-on: the hierarchy has to be in the one graph validation
    reads, so retracting it is retracting the shape's ability to see the subclass. The data
    triples are untouched across the two epochs, so the only thing that moved is the
    hierarchy.

  **Both tests were checked against the failure they exist to catch**, rather than trusted
  because they were green. Swapping the one line that binds the session — `session_init_txn`
  on the as-of transaction for an autocommit `session_init` on the store, which is "read HEAD
  and pretend it is the horizon" — turns *both* tests red, at every horizon they assert. That
  is the mutation the store task warns about ("works for the wrong reason"), and it does not
  survive here. The line was restored and the suite re-run.

  **The read-vs-write distinction is stated three times and in the place it will be met**: at
  the top of the new test file (a header contrasting it with `txn_test.odin` directly), in the
  test names — nothing here says "candidate" — and in the vision amendment. The two features
  share `session_init_txn` and are not the same thing, and they do not compose in the direction
  somebody will want: `txn_begin_as_of` returns `.Read` by signature, so there is no candidate
  to assemble inside one.

  **Nothing surprising surfaced, and two things were checked rather than assumed.** `count` is
  not on any validation path in this repo, so the as-of scan asymmetry the store flags for its
  siblings does not reach validation here — it appears only in this test's own non-vacuity
  guard, where a scan of three quads costs nothing. And `open_ephemeral` is fine for every test
  here: neither holds a reader open across a writer, which is the `NOLOCK` rule that sent two
  of SHACL-T-0029's tests back to `kvstore.open`.

  **Outstanding, and deliberately not done: the CI pin.** `.github/workflows/ci.yml` still
  pins `v0.4.0`, and moving it now would make CI red, because v0.5.0 does not exist yet. It
  must move in the *same commit* as this test, once odin-rdf-store tags it — the test does not
  compile against v0.4.0.
