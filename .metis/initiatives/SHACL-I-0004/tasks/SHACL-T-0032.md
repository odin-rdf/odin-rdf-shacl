---
id: the-core-ports-u32-ids-records
level: task
title: "The core ports: u32 ids, record's read API bound directly, the seams collapsed, shacl/kvstore and store: deleted"
short_code: "SHACL-T-0032"
created_at: 2026-08-20T15:19:52.000000+00:00
updated_at: 2026-08-20T15:19:52.000000+00:00
parent: SHACL-I-0004
blocked_by:
  - SHACL-T-0031
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: SHACL-I-0004
---

# The core ports: u32 ids, record's read API bound directly, the seams collapsed, shacl/kvstore and store: deleted

## Parent Initiative

[[SHACL-I-0004]]

## Objective

The structural port, in one motion because the compiler is the
checklist: `shacl` becomes **one package** importing `rdf` and
`record` directly (initiative design §2, decided); term ids become
record's `u32` held natively (§1); the parapoly compile seam
(`shacl/query.odin:30`), the `Access` struct
(`shacl/validate.odin:48`) and the `shacl/kvstore` package (807
lines) are deleted; no `store:` import remains anywhere in the
library. The green boundary: `make check` green over the ported
library, and the non-W3C test files (compile/eval/validate semantics,
helpers) ported and green. The full W3C corpus and the remaining
harness files are SHACL-T-0033's gate.

## Acceptance Criteria

- [ ] One package: every library file lives in `shacl`, importing
      `rdf` and `record` only. `shacl/kvstore/` is gone; `store:` is
      gone from every import, then from `COLL`, `ols.json` and the CI
      checkout (removal of the build-file references may land here or
      in T-0033, whichever commit deletes the last store-importing
      test file).
- [ ] Ids are `u32` throughout the compiled shapes model, target
      sets, value-node lists and path frontiers. The sentinel
      mapping is record's, not a recreation of the store's:
      `0` = unbound in a `Pattern`, `MATCH_DEFAULT_GRAPH` = the
      default graph in G. Confirm (and record in Status) that shacl
      computes no term ids of its own; if it does, use
      `CONSUMER_ID_FIRST ..= CONSUMER_ID_LAST` and say so.
- [ ] `store.id_kind`'s eight call sites become
      `record.snapshot_kind` (IRI, Blank, Literal — never the tag
      byte).
- [ ] The read path calls record directly: `snapshot_match` +
      `range_iter` + `scan_next` (with `Filter{origin = .Any}` stated
      at every match), `snapshot_resolve` for term lookup by value,
      `snapshot_term`/`snapshot_bytes` for lookup by id,
      `snapshot_exists` for existence probes.
- [ ] One `session_init` over a `record.Snapshot` (a read handle
      *is* a snapshot: acquire, use, release); the store/txn split
      collapses; `find_graph_label`'s role is `snapshot_resolve` of
      the graph term. `session_init_txn` is deleted here — its role
      returns as the `Validator` in SHACL-T-0034.
- [ ] The two record safety rules are respected in code and stated in
      doc comments where relevant: a reader indexes only the
      published set's lists, and a `Snapshot` is never retained past
      its acquire/release scope.
- [ ] `make check` green (`-vet -strict-style`); the ported non-W3C
      tests green over `Mem_FS`.

## Implementation Notes

Read first: the initiative's Detailed Design §§1–3, RECORD-I-0003's
Status (the seven-point mapping), and the family CLAUDE.md record
section. The `purity` target is retired in the same motion (nothing
left for it to guard — record its removal in the Makefile comment;
the fuller record lands at SHACL-T-0037).

Term-identity note for the ported unit tests: language tags lowercase
on intern, and non-canonical numeric lexical forms are distinct terms
from canonical ones — a test asserting term identity across either
boundary is asserting store behavior, not engine behavior, and should
be adjusted knowingly (log any such case in Status for T-0033 and
T-0037).

SHACL-A-0001's model owns every term it holds — that contract is what
lets the model outlive any snapshot it compiled from; the port must
not weaken it (it is what T-0034 stands on).

## Status Updates

*To be added during implementation*
