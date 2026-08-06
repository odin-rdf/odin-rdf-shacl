---
id: repo-scaffolding-package-layout
level: task
title: "Repo scaffolding: package layout, pinned PKGS, CI, and the test conventions"
short_code: "SHACL-T-0001"
created_at: 2026-08-06T13:58:05.326339+00:00
updated_at: 2026-08-06T14:13:27.751173+00:00
parent: SHACL-I-0001
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/active"


exit_criteria_met: false
initiative_id: SHACL-I-0001
---

# Repo scaffolding: package layout, pinned PKGS, CI, and the test conventions

## Parent Initiative

[[SHACL-I-0001]]

## Objective **[REQUIRED]**

Turn a repository that holds only a `Makefile`, `ols.json`, `LICENSE`, and Metis documents
into one that builds, tests, vets, and runs in CI. Establish the three-package layout the
backend-binding decision requires, pin `PKGS` as the `Makefile`'s own note asks, and stand up
the `tests/guards` and `tests/readme` conventions now rather than retrofitting them. No
validation logic — this task's deliverable is a green, empty skeleton every later task hangs
work on.

## Acceptance Criteria **[REQUIRED]**

- [x] Package layout established: `shacl` (backend-independent core), `shacl/memstore` and
      `shacl/kvstore` (thin instantiation packages), `tests/guards`, `tests/readme`,
      `tests/w3c/` reserved for SHACL-T-0002. Doc-only or placeholder contents are fine;
      every package must compile.
- [x] `Makefile` `PKGS` pinned to an explicit list, replacing the `find`-based discovery
      block and its note ("discovery cannot express intent about what belongs").
- [x] `make test` green at both `Term_ID` widths (`WIDTHS := 64 32`) and `make check` clean
      with `-vet -strict-style`.
- [x] CI workflow added, taken from odin-rdf-store's as the template, **including** the LMDB
      platform constraint — `shacl/kvstore` links the vendored archive, so the constraint
      applies from the first commit rather than "until a backend is actually linked".
- [x] `shacl/kvstore` demonstrably links and runs on CI, proving the LMDB path before any
      validation code depends on it.
- [x] `README.md` skeleton with the collections requirement stated (`rdf:` **and** `store:`,
      because the store's own sources import `rdf:`).
- [x] Core package purity check: nothing in `shacl` imports `store:store/memstore`,
      `store:store/kvstore`, or `sparql:` — asserted by a build of a consumer that links the
      core plus an in-memory backend and contains no LMDB symbols. **Deviation, deliberate:**
      the consumer imports `store:store/memstore` directly rather than `shacl/memstore`,
      because that package has no exported symbols yet; `tests/purity/main.odin` carries the
      note to switch the import in SHACL-T-0003. The property under test is unchanged.

## Implementation Notes

### Technical Approach

Mirror odin-rdf-sparql's layout, which resolved the same backend-binding question
(SPARQL-T-0011): a core package holding the engine, plus per-backend instantiation packages
that absorb handle shape, fallibility, and materialization lifetime. Collections wiring
already exists (commit 53709b0). odin-rdf-store's CI workflow is the template; its LMDB
platform matrix carries over because `shacl/kvstore` links the same vendored archives
(STORE-A-0004, five platforms).

The core-purity criterion is the one worth mechanising rather than asserting: it is the
property that makes a Core-only, in-memory consumer never link LMDB, and it is easy to break
silently with one convenience import.

### Dependencies

None — first task of the initiative.

### Risk Considerations

The `shacl/kvstore` package has nothing to instantiate yet, so it will be near-empty until
SHACL-T-0003. Keeping it in the layout (and in CI) from the start is deliberate: it makes the
LMDB link a solved problem before any deadline depends on it.

## Status Updates **[REQUIRED]**

- **2026-08-06 — Complete, awaiting review.** All seven criteria met; `make check` clean and
  `make test` green at both `Term_ID` widths (5 packages × 2 widths, 1 test each).

  **Layout.** `shacl` (core: package contract in `shacl.odin`, plus `vocab.odin`),
  `shacl/memstore` and `shacl/kvstore` (instantiation packages, doc + linkage test each),
  `tests/guards`, `tests/readme`, `tests/purity` (a `main` package, built not tested), and
  `tests/w3c/README.md` holding the ground for SHACL-T-0002. `Makefile` `PKGS` is pinned; the
  `find`-based discovery block and its note are gone, and `BUILD_PKGS` is the new home for
  packages that are built rather than tested.

  **The purity check is real, and verified against a negative control.** `make purity` builds
  `tests/purity` and greps `nm` output for `mdb_`. A check that can never fail is worse than
  none, so it was tested both ways: a probe binary importing `store:store/kvstore` shows
  **184** `mdb_` symbols, and the purity binary shows **0**. `nm` is absent on the Windows
  runner, where the check skips itself with a message rather than failing — the property is
  platform-independent, so proving it where possible is enough. `purity` runs as the last step
  of `make check`, so a vet-clean tree that quietly links LMDB into the core does not pass.

  **The LMDB linkage test is the point of `shacl/kvstore` existing this early.** It opens a
  real store in a temp directory, counts it, and closes it — so CI proves the vendored archive
  resolves *and runs* on each platform, rather than merely compiling. It carries its own
  `temp_path` helper: odin-rdf-store's is private to that package, and the fallback order
  (TMPDIR → TEMP → TMP → /tmp, trailing separator stripped) matters — concatenating straight
  onto the variable puts the path at the filesystem root on Linux.

  **Judgement call worth flagging.** `shacl/vocab.odin` is slightly beyond "empty scaffolding":
  it holds the SHACL namespace and ~40 IRI constants. They are spec facts rather than design
  decisions — no representation is committed — and they make the core package genuinely
  importable rather than an empty shell that `tests/purity` cannot exercise. odin-rdf-parser
  sets the precedent for vocabulary constants beside the model. Its test asserts the namespace
  prefix, absence of duplicates, and the exact spelling of the three constants whose local name
  differs most from the Odin identifier.

  **Deviation recorded above:** `tests/purity` imports `store:store/memstore` rather than
  `shacl/memstore`, which has no exported symbols yet. Switch it in SHACL-T-0003.

  **CI** checks out three sibling repositories (this one, parser, store), runs `make check`
  then `make test` on ubuntu/macos/windows. Both upstream checkouts track `main` with a note to
  pin by tag once the family publishes them — the same note odin-rdf-store's workflow carries.

  Nothing about the upstream repositories was touched.