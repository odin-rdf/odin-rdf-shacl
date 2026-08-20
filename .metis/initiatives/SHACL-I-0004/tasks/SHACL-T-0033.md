---
id: the-full-suite-on-record-every
level: task
title: "The full suite on record: every harness call site ported, all 98 W3C core entries green, the width matrix removed"
short_code: "SHACL-T-0033"
created_at: 2026-08-20T15:20:02.000000+00:00
updated_at: 2026-08-20T15:20:02.000000+00:00
parent: SHACL-I-0004
blocked_by:
  - SHACL-T-0032
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: SHACL-I-0004
---

# The full suite on record: every harness call site ported, all 98 W3C core entries green, the width matrix removed

## Parent Initiative

[[SHACL-I-0004]]

## Objective

Finish what SHACL-T-0032's boundary left: the W3C runner and every
remaining test file — ~300 call sites across 20 files before the
port — moved onto `Mem_FS` + `ingest` + `apply`, with **all 98
entries of the W3C SHACL 1.0 suite's `core/` tree green** against
record, no skip list, no expected-failure file. The dual-width
matrix leaves the Makefile and CI with the store that owned it
(record's widths are fixed by design).

## Acceptance Criteria

- [ ] Every `open_ephemeral` + `load_turtle` + close becomes
      `Mem_FS` + `store_open(&s, name, mem_file_ops(&fs))` +
      `ingest.turtle(src, graph, allocator, blank_prefix = <scope>,
      base = …)` + `apply` + `ingest.ops_destroy` + `store_close`
      (every snapshot released first — `store_destroy` asserts it).
- [ ] `blank_prefix` scoping: prefixes derived from test identity and
      sanitized to **label characters** (`t1_`, not `t1/` — W3C
      entry names contain path separators). Two documents loaded
      under different prefixes keep distinct blank nodes; the suite's
      report-isomorphism checks still pass.
- [ ] `base` supplied where documents carry relative IRIs (the W3C
      inputs resolve against their vendored locations, as the record
      repo's own ingest-by-reference suite does).
- [ ] The ops-own-their-terms contract observed: source buffers
      outlive `apply`; `ops_destroy` after.
- [ ] All 98 `core/` entries green; the suite-progress
      instrumentation (SHACL-T-0009's) reports the same totals as
      before the port.
- [ ] The width matrix (`-define:RDF_STORE_TERM_ID_BITS` legs) is
      gone from Makefile and CI; if not already removed in T-0032,
      `store:` is gone from `COLL`, `ols.json` and the CI checkout —
      after this task the repository's dependencies are
      odin-rdf-parser and odin-rdf-record, and no LMDB is in any
      link.
- [ ] `make test` and `make check` green on all CI legs, Windows
      included (suites run over `mem_file_ops`).

## Implementation Notes

The term-identity corpus check from the initiative's design §5 is
settled here by running, not by argument: the expectation is that no
entry moves on lowercased language tags or non-canonical numeric
forms. If an entry does move, record it in Status — it feeds the
`docs/language-tag-status.md` amendment in SHACL-T-0037 — and
resolve it as an expected-behavior change only with the evidence
written down.

## Status Updates

*To be added during implementation*
