---
id: adopt-odin-rdf-record-v0-6-0-gpos
level: task
title: "Adopt odin-rdf-record v0.6.0: GPOS makes every session read a prefix, with no source change"
short_code: "SHACL-T-0041"
created_at: 2026-08-26T22:54:49.520477+00:00
updated_at: 2026-08-26T22:58:10.512809+00:00
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

# Adopt odin-rdf-record v0.6.0: GPOS makes every session read a prefix, with no source change

## Objective **[REQUIRED]**

**odin-rdf-record `v0.6.0` was tagged on 2026-08-27** (`4bf700c`, `RECORD-T-0028`): a
seventh permutation, `GPOS`, with `G` leading — `RECORD-A-0004`'s escape hatch, spent on
its own review trigger for the application's workspace design (a named graph per
workspace; "which `risk:Risk` are in this workspace" not to scan every Risk in the store).
`snapshot_match` chooses it whenever G is bound, S is not, and O is not bound without P.

This task is the family's walk-the-consumers step — the sixth floor raise, and the first
for which this engine changes **nothing**: every session verb already binds
`g = se.graph` on every read (`shacl/session.odin:155`, `:179`, `:206`), so at this pin
the reads behind `sh:targetClass` (`?s rdf:type C` in the graph), `sh:class` and the
inverted path step (`?s p o` in the graph) become `GPOS` prefix windows that are exactly
their answer, where they were `POSG` windows over every graph filtered residually. The
S-bound reads — the forward path step, `sh:closed`'s `session_outgoing` — stay on the SPO
family, as the ADR argued they should.

- **No source change.** `ci.yml` pins `v0.6.0` with the comment beside the fifth
  raise's; the README's floor paragraph and the vision's three floor mentions carry a
  dated note.
- **Nothing else moves.** `make test` green against the `v0.6.0` checkout — 133 + 13 +
  7 + 1 + 23 tests, the 98 W3C `core/` entries included; `make check` clean through both
  bench builds and the import-alias grep. No verdict moves. The read pins are this
  engine's own verb counts (`scan`/`step`/`outgoing`), which count calls and not
  candidates, so they cannot move — only the window each call opens got narrower,
  which is invisible from this side of the seam (`RECORD-T-0026`'s point, now in the
  engine's favour).
- **Not a format change.**

## Backlog Item Details **[CONDITIONAL: Backlog Item]**

### Type
- [x] Tech Debt - Code improvement or refactoring

### Priority
- [x] P2 - Medium. Unlike the two raises before it, nothing breaks below this pin; it
      is taken the day of the tag under the family's release convention, so the
      Current State says what the sibling checkout on every machine already is.

## Acceptance Criteria

**[REQUIRED]**

- [x] `.github/workflows/ci.yml` pins `odin-rdf-record@v0.6.0`, with the comment
      explaining the sixth raise beside the fifth's paragraph, which stands.
- [x] `make test` and `make check` green against `v0.6.0`; 98/98; no verdict moves.
- [x] The README's floor paragraph and the vision's three floor mentions amended with a
      dated note.

## Status Updates **[REQUIRED]**

- **2026-08-27 — Done in one commit**, the day of the tag, as part of the record's
  release walk (`RECORD-T-0028`). One floor, one README sentence, three vision notes;
  no source and no behaviour moved.