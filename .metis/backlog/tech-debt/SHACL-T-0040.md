---
id: adopt-odin-rdf-record-v0-5-0
level: task
title: "Adopt odin-rdf-record v0.5.0: Filter.scope stated at seven sites, and what the release means for SHACL-T-0039"
short_code: "SHACL-T-0040"
created_at: 2026-08-26T22:19:39.007357+00:00
updated_at: 2026-08-26T22:24:10.873609+00:00
parent: 
blocked_by: []
archived: false

tags:
  - "#task"
  - "#tech-debt"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: NULL
---

# Adopt odin-rdf-record v0.5.0: Filter.scope stated at seven sites, and what the release means for SHACL-T-0039

## Objective **[REQUIRED]**

**odin-rdf-record `v0.5.0` was tagged on 2026-08-27** (`6bc27c4`, `RECORD-T-0029`):
`record.Filter` gained `scope: Graph_Scope { All = 1, Set = 2 }` beside `origin`,
under the same rule — no valid zero, refused by `range_iter` at the first read; under
`.Set` the length of `graphs` alone decides, and an empty set admits nothing. The
reason was found by the application's workspace design: `Filter.graphs` had decided
scoped-versus-unscoped by whether the slice was nil, and Odin makes that a fact about
allocation history, so the same empty set read every graph or nothing.

This task is the family's walk-the-consumers step for that release — the fifth floor
raise, and like the fourth (`SHACL-T-0038`) it is for an API change rather than a
capability this engine wants. **It is small and precisely bounded**: this engine binds
one graph through `Pattern.g` and never constructs a set (that is `SHACL-T-0039`), so
the only change is that every `Filter` it builds states `.All`.

- **Seven sites**, found by `grep -rn -E 'origin *= *\.(Any|Asserted|Derived)'
  --include='*.odin' | grep -v scope` — the `Filter{` spelling misses Odin's untyped
  literals, which is how the release notes first said three: the three session verbs
  (`shacl/session.odin:156`, `:182`, `:207` — every read the engine makes),
  `shacl/query.odin:38`, and three tests (`tests/smoke/smoke_test.odin:63`,
  `shacl/validator_test.odin:135`, `shacl/as_of_test.odin:122`).
- **Nothing else moves.** `make test` green against the `v0.5.0` checkout — 133 + 13 +
  7 + 1 + 23 tests, the 98 W3C `core/` entries included; `make check` clean through
  both bench builds and the import-alias grep. No verdict moves, and read counts
  cannot — the graph check runs inside record's `scan_next`, on the far side of
  `SHACL_COUNT_READS`.
- **Not a format change.** Nothing in `Mem_FS` or the suites notices beyond the
  seven lines.

A hazard worth carrying, from the record's own adoption: an unstated `Filter` reached
from a spawned thread **hangs** a test runner rather than failing it. This
repository's suites are not threaded, and the grep above is the check; it is
recorded so the next bump of this kind greps before it runs.

## What it means for SHACL-T-0039

That task's "an empty set is an empty data graph, never the whole store" is now the
record's own guarantee: under `.Set` an empty `graphs` admits nothing, so binding
`GRAPH_ABSENT` for an empty set becomes belt and braces rather than the guard. Its
session verbs will state `scope = .Set, graphs = se.graphs` on the set path and keep
`.All` with `g = se.graph` on the single-graph path. `SHACL-T-0039`'s Status carries
the note.

## Backlog Item Details **[CONDITIONAL: Backlog Item]**

### Type
- [x] Tech Debt - Code improvement or refactoring

### Priority
- [x] P1 - High. CI pinned `v0.4.0` and was green, but the Makefile reaches
      `../odin-rdf-record`, which is `v0.5.0` on any current family checkout: without
      this, every read in this repository asserts at its first call — `SHACL-T-0038`'s
      argument exactly.

## Acceptance Criteria

**[REQUIRED]**

- [x] Every `Filter` literal states scope; the grep above finds nothing.
- [x] `.github/workflows/ci.yml` pins `odin-rdf-record@v0.5.0`, with the comment
      explaining the fifth raise beside the fourth's paragraph, which stands.
- [x] `make test` and `make check` green against `v0.5.0`; 98/98; no verdict moves.
- [x] The README's floor paragraph and the vision's three floor mentions amended
      with a dated note.
- [x] `SHACL-T-0039` told what the release settles.

## Status Updates **[REQUIRED]**

- **2026-08-27 — Done in one commit**, the day of the tag, as part of the record's
  release walk (`RECORD-T-0029`). Seven sites, one floor, one README paragraph, three
  vision notes; no behaviour moved.