---
id: retire-the-memstore-instantiation
level: task
title: "Retire the memstore instantiation: port tests, rehome compile_turtle, settle purity and the benchmarks"
short_code: "SHACL-T-0028"
created_at: 2026-08-07T16:45:00.000000+00:00
updated_at: 2026-08-07T16:45:00.000000+00:00
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

# Retire the memstore instantiation: port tests, rehome compile_turtle, settle purity and the benchmarks

## Objective **[REQUIRED]**

odin-rdf-store is removing its in-memory backend. Port `shacl/memstore`'s tests onto
kvstore, delete the package, and settle the three things in this repo that depend on
memstore for reasons other than testing.

**This is a request from upstream, not a decision taken here.** The stance is
**STORE-A-0006** (one backend, a library over LMDB), carried out in **STORE-I-0003**. This
is the odin-rdf-shacl half — the larger of the two sibling ports, and the only one carrying
decisions beyond a mechanical port, because **every non-test dependant of memstore in the
family is in this repo**.

**Why upstream decided it.** memstore was an architectural proposal in odin-rdf-store's
first initiative, never a consumer request. The forcing question was transactions:
STORE-T-0019 and STORE-T-0022 designed jointly produced a model dominated by memstore —
LMDB gives kvstore snapshot isolation, atomicity and read-your-own-writes free, while
memstore has no versioning, so one contract covering both needed a declared capability
constant, a capability-conditional conformance tier, a write journal, a generation counter,
and a deferred copy-on-write path. That ADR was archived undecided and the removal
sequenced ahead of the transaction work. The transaction model this repo will eventually
consume (its `Access` adapters would bind to a transaction rather than a bare dataset) is
simpler for it.

Measured, so it is not taken on faith: `shacl/memstore` runs 71 tests in 10.3 ms,
`shacl/kvstore` 14 tests in 124.5 ms — 61× per test, around a small absolute number. The
port costs roughly 0.6 s of suite time.

## Backlog Item Details **[CONDITIONAL: Backlog Item]**

### Type
- [x] Feature - New functionality or enhancement

### Priority
- [x] P1 - High (important for the next release)

**Blocks STORE-T-0030**: upstream cannot delete `store/memstore` while this repo imports
it, and the transaction work is queued behind that.

### Business Justification **[CONDITIONAL: Feature]**
- **User Value**: Mixed, and worth being honest about. `compile_turtle` gets a required
  store parameter, which is a real ergonomic change. In exchange a validation library stops
  silently owning a database.
- **Business Value**: One upstream contract with nothing conditional in it, and a simpler
  transaction model for the validate-before-commit path this engine is central to.
- **Effort Estimate**: L — 3,540 lines of tests move, 528 lines of code are deleted, and
  three separate decisions have to be made rather than executed.

## Acceptance Criteria **[REQUIRED]**

- [ ] Every assertion currently running against memstore runs against kvstore afterwards.
      Counts recorded before and after at **both `Term_ID` widths**; any reduction named.
      Note the kvstore-side count goes from **14 to ~85**, so this is also a coverage
      expansion on a path that has been much thinner than the memstore one.
- [ ] `shacl/memstore/` deleted: `memstore.odin`, `compile.odin`, `eval.odin`,
      `validate.odin`, `report.odin` (528 lines) and the five `_test` files (3,540 lines).

**`compile_turtle` — the caller supplies the store.** Recommended signature:

```odin
compile_turtle :: proc(s: ^shacl.Shapes, st: ^kvstore.Store, source: []byte,
                       graph: rdf.Graph_Label = nil, base := "",
                       allocator := context.allocator)
                 -> (err: shacl.Error, load_err: store.Load_Error, db_err: kvstore.Error)
```

- [ ] The procedure survives on `shacl/kvstore` over a caller-supplied store and scratch
      graph — or its removal is a recorded decision with the reason. Rationale for the
      shape: today's version builds a private store and destroys it, which was tolerable
      when the store was a hash map and is not when it is an LMDB environment; and its own
      doc comment's stated reason for living in an instantiation package ("keeps LMDB out of
      the link of every consumer that only wants an in-memory store") dies with memstore.
      Every shacl consumer already has a store open for the data graph, and `Session`'s doc
      already describes the replacement: "A caller whose shapes and data live in different
      graphs of one store uses two Sessions over the same store."
- [ ] **The compile-once contract is in the doc comment, with its reason**, because the
      failure is silent. `load_turtle` applies per-load blank-node scoping (`fresh_blank_txn`)
      and shapes graphs are blank-node dense (`sh:property [ sh:path ex:p ; sh:minCount 1 ]`),
      so reloading the same shapes into the same named graph does **not** dedupe — repeated
      loads accumulate a second copy of every blank-node-rooted shape and a later compile
      sees duplicated shapes. Contract: load at startup, keep the `Shapes` value (it outlives
      the store by design, SHACL-A-0001), never recompile per request. Relaxes when
      STORE-T-0023 (`remove`) lands.

**The `purity` target — decide, do not leave broken.**

- [ ] `tests/purity/` and `make purity` are retargeted, retired, or deleted, as a recorded
      decision. Its guarded property — "a consumer that only ever wants an in-memory store"
      must not link LMDB — has no beneficiary once there is no in-memory store.
      Recommendation: **retarget it at the `shacl` core package alone** (it still catches a
      stray `kvstore` import in the core, still meaningful as internal hygiene, and the
      core/instantiation split is still what a future backend would use) **and amend
      SHACL-A-0001 decision 1**, whose recorded justification is exactly the property that
      evaporates.

**The benchmarks — a changed measurement, not a port.**

- [ ] `bench/consumers.odin` ported with its changed question stated. It uses memstore
      *deliberately* — its own comment: "memstore only, deliberately. The question is what
      *this engine* allocates, and on kvstore every figure would carry LMDB's page handling
      and term [decoding]." That reason is real: memstore's `lookup_term` borrows from
      dictionary storage and allocates nothing, while kvstore's copies every string into the
      caller's allocator. Upstream's decision (STORE-I-0003) is **port it and accept that the
      figures now include term materialization** — arguably the more honest number, since
      every real consumer pays it. Mark the historical figures as not comparable rather than
      leaving them looking like a regression.
- [ ] Recorded as lost rather than silently dropped: `bench/main.odin`'s cross-backend
      timing comparison, and the invariant it asserts that "the read count is identical on
      memstore and kvstore."
- [ ] `tests/readme/`, `tests/guards/`, `tests/w3c/harness/runner.odin` and `bench/access.odin`
      all reference memstore and need triage.

**The vision.**

- [ ] `.metis/vision.md`'s success criterion "Validation runs against any odin-rdf-store
      backend through the match interface alone, so the same shapes validate **in-memory and
      LMDB-backed** data identically" is retracted — it becomes unverifiable. A port that
      leaves a falsified criterion standing in a published vision is incomplete. Recommend a
      dated amendment rather than a rewrite. The package list naming `shacl/memstore` and the
      purity-target description need the same treatment.

## Implementation Notes **[CONDITIONAL: Technical Task]**

### Technical Approach

`shacl/kvstore` already has every piece the port needs — `Session`, the five adapters, and
`compile` over a session. The mechanical change in tests is store construction:
`dictionary_init` + `dataset_init` become `kvstore.open` against a temp path.
`shacl/kvstore/link_test.odin` already has the `temp_path` helper.

**Do not rewrite assertions during the port.** A coverage change hidden inside a mechanical
change is the main risk here and is invisible in review — especially given the count is
going from 14 to ~85 on the kvstore side, where a quietly dropped check will not stand out.

Order suggestion: tests first (largest, mechanical, unblocks the deletion), then
`compile_turtle`, then purity, then the benchmarks — the last three are decisions and
benefit from the tests already being green.

### Dependencies

Upstream: STORE-A-0006, STORE-I-0003, STORE-T-0027 (the task that filed this).
**Blocks STORE-T-0030.**

Adjacent: STORE-T-0023 (`remove`) would relax `compile_turtle`'s compile-once restriction,
and the eventual transaction handle (STORE-T-0032) is where this repo's `Access` adapters
would rebind — both later, neither blocking.

### Risk Considerations

Three decisions in one item is where scope gets dropped. The one most likely to be skipped
is the **compile-once contract**, because it is a doc comment rather than code and the
failure it prevents is silent and slow. The one most likely to be contested is
`compile_turtle`'s signature — a caller with a shapes file and no database now needs a
store, which is the right boundary but a real ergonomic change, and worth pushing back on
here if this repo disagrees.

If the port produces a third and fourth copy of the temp-path boilerplate, say so upstream:
`kvstore.open_ephemeral` is scoped as an optional convenience (STORE-I-0003 Detailed Design
point 3), explicitly waiting on evidence from these ports.

## Status Updates **[REQUIRED]**

- **2026-08-07 — Filed from odin-rdf-store STORE-T-0027**, the sibling-proposal task of
  STORE-I-0003. Sequencing and shape are this repo's call; the blocking relationship with
  STORE-T-0030 is the one part that is not.
