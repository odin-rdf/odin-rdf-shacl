---
id: repo-scaffolding-package-layout
level: task
title: "Repo scaffolding: package layout, pinned PKGS, CI, and the test conventions"
short_code: "SHACL-T-0001"
created_at: 2026-08-06T13:58:05.326339+00:00
updated_at: 2026-08-06T13:58:05.326339+00:00
parent: SHACL-I-0001
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/todo"


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

- [ ] Package layout established: `shacl` (backend-independent core), `shacl/memstore` and
      `shacl/kvstore` (thin instantiation packages), `tests/guards`, `tests/readme`,
      `tests/w3c/` reserved for SHACL-T-0002. Doc-only or placeholder contents are fine;
      every package must compile.
- [ ] `Makefile` `PKGS` pinned to an explicit list, replacing the `find`-based discovery
      block and its note ("discovery cannot express intent about what belongs").
- [ ] `make test` green at both `Term_ID` widths (`WIDTHS := 64 32`) and `make check` clean
      with `-vet -strict-style`.
- [ ] CI workflow added, taken from odin-rdf-store's as the template, **including** the LMDB
      platform constraint — `shacl/kvstore` links the vendored archive, so the constraint
      applies from the first commit rather than "until a backend is actually linked".
- [ ] `shacl/kvstore` demonstrably links and runs on CI, proving the LMDB path before any
      validation code depends on it.
- [ ] `README.md` skeleton with the collections requirement stated (`rdf:` **and** `store:`,
      because the store's own sources import `rdf:`).
- [ ] Core package purity check: nothing in `shacl` imports `store:store/memstore`,
      `store:store/kvstore`, or `sparql:` — asserted by a build of a consumer that links only
      `shacl` + `shacl/memstore` and contains no LMDB symbols.

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

*To be added during implementation*
