---
id: adopt-odin-rdf-record-v0-9-0
level: task
title: "Adopt odin-rdf-record v0.9.0: snapshot_history, a verb this engine does not need"
short_code: "SHACL-T-0044"
created_at: 2026-09-04T20:30:00.000000+00:00
updated_at: 2026-09-04T20:30:00.000000+00:00
parent: 
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"
  - "#tech-debt"


exit_criteria_met: true
initiative_id: NULL
---

# Adopt odin-rdf-record v0.9.0: snapshot_history, a verb this engine does not need

## Objective

Move the CI pin from odin-rdf-record `v0.8.0` to `v0.9.0` and re-read this
engine's Current State for anything the release falsifies — the family's
walk-the-consumers rule.

## Context

**odin-rdf-record `v0.9.0` was tagged on 2026-09-04** (`eb270c1`,
`RECORD-T-0044`). One new name, `snapshot_history(snap, p) -> Range`: every
generation a pattern ever matched, visible at the snapshot's epoch or not,
over the same prefix window `snapshot_match` computes and driven by the same
`range_iter` / `scan_next` with the interval test omitted and nothing else. It
is a separate entry point and not a `Filter` option, by `api.md` §12.6's
audit argument. Filed by odin-rdf-app, which had been reading `Range.main`
through `v0.7.0` to tell "never asserted" from "asserted and since retracted".
Not a format change.

**For this engine the release is nothing.** A validator judges the visible
state of one snapshot — head plus changeset as a candidate, or an as-of
snapshot through `store_at` — and never asks what a pattern matched at some
other time. No session verb changes, no source changes.

## Acceptance Criteria

- [x] `ci.yml` pins `odin-rdf-record@v0.9.0` with a comment paragraph in the
      pin's history.
- [x] `make test` green against the record at the tagged commit: 98/98 W3C
      entries.
- [x] `make bench`: 7503 reads on the reference configuration, as pinned.
- [x] README and the vision's Current State carry the dated note.
- [x] CI green on the pin bump.

## Notes

Nothing to adopt. If SHACL ever wants "was this ever true" — a temporal
constraint is not in SHACL 1.0 and not on this engine's backlog — the verb
exists and pairs with `snapshot_fact` for the interval and
`snapshot_derived` for the origin.
