---
id: adopt-odin-rdf-record-v0-8-0-the
level: task
title: "Adopt odin-rdf-record v0.8.0: the permutations are B+trees, and every read pin holds"
short_code: "SHACL-T-0043"
created_at: 2026-09-04T19:40:00.000000+00:00
updated_at: 2026-09-04T19:40:00.000000+00:00
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

# Adopt odin-rdf-record v0.8.0: the permutations are B+trees, and every read pin holds

## Objective

Move the CI pin from odin-rdf-record `v0.7.0` to `v0.8.0` and re-read this
engine's Current State for anything the release falsifies — the family's
walk-the-consumers rule.

## Context

**odin-rdf-record `v0.8.0` was tagged on 2026-09-04** (`975693b`,
`RECORD-I-0009`, `RECORD-A-0012`). Every `apply` there had been re-sorting all
seven permutations from scratch — 37.1 ms of a 37.5 ms commit at 4×10⁵ facts —
and each permutation is now a copy-on-write B+tree of fact ids: a commit
inserts, path-copying the leaf and ancestors it touches, and costs **0.24 ms**
mean on the memory seam with 0.43 MB transient. Boot is unchanged in shape
(sort, then pack full; `log.md` §8 re-measured and holding by 13×). Not a
format change.

**For this engine the release is a read-path change with no source change.**
Every session read goes through `snapshot_match` / `range_iter` / `scan_next`;
`Range` lost `main` and `delta` and `Scan` lost `ids`, and this engine never
named them. Matches are 10–30% faster on the record's own benchmark. What it
changes for the *application* is what validate-before-commit through the
`Validator` hook costs per edit: milliseconds now.

## Acceptance Criteria

- [x] `ci.yml` pins `odin-rdf-record@v0.8.0` with a comment paragraph in the
      pin's history.
- [x] `make test` green against the tag: 138 + 13 + 7 + 1 tests, 98/98 W3C
      entries.
- [x] `make bench`: 7503 reads on the reference configuration, as pinned.
- [x] README and the vision's Current State carry the dated note.
- [x] CI green on the pin bump.

## Notes

Nothing to adopt: no new verb, no changed contract. The one record test worth
knowing about is `test_read_ordered_output`, which now asserts scan order for
every permutation over a duplicate-heavy corpus — the guarantee a session's
prefix reads have always assumed and the record now pins for its consumers.
