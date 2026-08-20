---
id: plumbing-the-record-checkout-and
level: task
title: "Plumbing: the record checkout and pin, collections, ols.json, CI legs, and a Mem_FS smoke test"
short_code: "SHACL-T-0031"
created_at: 2026-08-20T15:19:42.665955+00:00
updated_at: 2026-08-20T15:44:49.152613+00:00
parent: SHACL-I-0004
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: SHACL-I-0004
---

# Plumbing: the record checkout and pin, collections, ols.json, CI legs, and a Mem_FS smoke test

## Parent Initiative

[[SHACL-I-0004]]

## Objective

Make odin-rdf-record reachable from this repository everywhere the
parser and store are today — Makefile, `ols.json`, CI — pinned at
`v0.1.0`, and prove the wiring with a smoke test that opens a record
store over the memory seam, applies one changeset, matches it back,
and closes. This task only *adds*; `store:` and kvstore are deleted
by SHACL-T-0032/T-0033, so every existing suite stays green
throughout.

## Acceptance Criteria

- [ ] `COLL` in the Makefile gains
      `-collection:record=../odin-rdf-record` (`rdf:` and, for now,
      `store:` retained); `ols.json` mirrors it.
- [ ] `ci.yml` checks out `odin-rdf/odin-rdf-record` at `v0.1.0`
      beside the existing pins (`actions/checkout@v5` with
      `repository:`/`ref:`/`path:`), with a pin comment in the style
      of the store floor history (`SHACL-T-0020`/`-T-0028`/`-T-0030`)
      recording why the record enters. Note in the comment: record's
      `make test` needs python3, but a *consumer* compiling the
      library does not.
- [ ] A smoke test (placement per the one-package layout — it moves
      into the ported suite later) opens `record.store_open` over
      `Mem_FS` + `mem_file_ops`, applies a one-op `Changeset` built
      as a struct literal, reads it back via
      `store_latest`/`snapshot_match`/`range_iter`/`scan_next`
      (`Filter{origin = .Any}`), releases the snapshot, and
      `store_close`s.
- [ ] The Windows CI leg compiles `record` (the posix `File_Ops` file
      is `#+build linux, darwin`; the smoke test runs over
      `mem_file_ops`, which is platform-free).
- [ ] `make test` and `make check` green on all legs; every existing
      suite untouched.

## Implementation Notes

The local sibling checkout `../odin-rdf-record` already exists. The
collections-resolve-in-the-importer rule applies: `rdf:` must stay
declared because record's sources import it. Family convention on
import naming: no redundant aliases — Odin binds the last path
component already.

## Status Updates

**2026-08-20 — implemented, all criteria met; awaiting review.**
`COLL` gains `-collection:record=../odin-rdf-record` with a comment
saying why `rdf:` stays and when `store:` leaves; `ols.json` mirrors;
`ci.yml` checks out `odin-rdf-record@v0.1.0` with a pin comment in the
floor-history style (first tag, so pin and floor coincide; the
Windows/`mem_file_ops` and python3 notes are in it), and its header's
"two checkouts" paragraph updated to three. The smoke test lives in
`tests/smoke` (added to `PKGS`): `Mem_FS` → `store_open` → one-op
`Changeset` from a struct literal → `store_latest` →
`snapshot_resolve` ×3 + `snapshot_kind` → `snapshot_match` +
`range_iter{origin = .Any}` + `scan_next` → `snapshot_fact` component
checks (G = 0 for the default graph) → release, close, destroy.

Verified: the smoke test green standalone; `make check` green
(purity included, untouched); `make test` green at both widths, all
six packages; `odin check tests/smoke -target:windows_amd64` clean,
so the record package compiles without its posix `File_Ops` and the
Windows CI leg should hold (proven for real on the first push).

Nothing store-side was touched; every existing suite ran unchanged.