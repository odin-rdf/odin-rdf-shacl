---
id: refresh-the-vision-s-current-state
level: task
title: "Refresh the vision's Current State, two initiatives stale"
short_code: "SHACL-T-0022"
created_at: 2026-08-07T10:50:38.110262+00:00
updated_at: 2026-08-07T11:53:37.497463+00:00
parent: 
blocked_by: []
archived: false

tags:
  - "#task"
  - "#tech-debt"
  - "#phase/completed"


exit_criteria_met: true
initiative_id: NULL
---

# Refresh the vision's Current State, two initiatives stale

## Objective **[REQUIRED]**

Bring `.metis/vision.md`'s **Current State** section up to date. It was rewritten at
SHACL-I-0001's close and describes the project as it stood then — four green suite
directories, seven constraint components, 72 entries remaining, and "**Next:** the
constraint-catalogue initiative". Two initiatives have completed since.

## Backlog Item Details **[CONDITIONAL: Backlog Item]**

### Type
- [x] Tech Debt - Code improvement or refactoring

### Priority
- [x] P2 - Medium (nice to have)

### Technical Debt Impact

- **Current Problems**: The vision is the strategic source of truth for this repository,
  and the family's convention is to read it before making design decisions. Its Current
  State now understates the project by two initiatives, which is the one kind of staleness
  that actively misleads rather than merely ages.
- **Benefits of Fixing**: The next person to open this repository — including the
  SHACL-SPARQL phase — reads an accurate position instead of reconstructing it from
  initiative status updates.
- **Risk Assessment**: Low, but it compounds: each initiative that closes without
  refreshing it makes the gap larger and the eventual rewrite less likely to be accurate.

## Acceptance Criteria **[REQUIRED]**

- [x] Current State reflects the position at SHACL-I-0002's close: SHACL Core complete,
      all twenty-nine non-SPARQL constraint components of §4, **all 98 entries of the
      vendored `core/` suite green** across all seven directories, both backends, both
      `Term_ID` widths.
- [x] The `core/complex` correction is carried up: it was never a SHACL-SPARQL directory.
      `sh:sparql`, `sh:shapesGraph`, and `sh:entailment` appear in
      `shacl-shacl-data-shapes.ttl` only as targeted vocabulary — objects of
      `sh:targetSubjectsOf` and `sh:targetObjectsOf` — not as constraint parameters. The
      vision does not state this belief itself, but the documents it points at do.
- [x] SHACL-A-0002 is named alongside SHACL-A-0001; the vision predates it and mentions
      only the first.
- [x] **The two "turned out otherwise" notes are kept and updated, not deleted.** They are
      the most useful thing the section records. The store prediction stayed retired
      through the whole catalogue — a validator with all twenty-nine components reaches
      odin-rdf-store through `match` and `find_term` and nothing else — and the
      language-tag trigger still has not fired, now with the corpus fully run. The
      recommendation to widen that trigger to "a suite entry fails **or** a user reports
      it" has been taken in `docs/language-tag-status.md`.
- [x] "**Next:**" points at what is actually next — [[SHACL-I-0003]] and the SHACL-SPARQL
      phase — with `docs/handover-sparql.md` as the starting point rather than
      `docs/handover-catalogue.md`.
- [x] The remaining sections (Purpose, Future State, Major Features, Success Criteria,
      Principles, Constraints) are checked and left alone unless something in them is now
      false. They were written to outlast initiatives and mostly have.

## Implementation Notes **[CONDITIONAL: Technical Task]**

### Technical Approach

Sources for the refresh, in order of usefulness: SHACL-I-0002's closing status update,
`docs/handover-sparql.md`, and the two write-ups (`docs/store-evidence.md`,
`docs/language-tag-status.md`).

### Dependencies

None. Worth doing before the SHACL-SPARQL phase begins rather than after, since that phase
will read it.

### Risk Considerations

**The temptation is to rewrite more than Current State.** The rest of the vision was
written to outlast initiatives and largely has; changing it should need a reason beyond
tidiness.

## Status Updates **[REQUIRED]**

- **2026-08-07 — Current State rewritten. Awaiting review.**

  Rewritten from SHACL-I-0002's closing update, `docs/handover-sparql.md`, and the two
  write-ups. Every acceptance criterion met.

  **What it now says:** SHACL Core complete, all twenty-nine non-SPARQL components of §4,
  **all 98 entries of the vendored `core/` suite green** across all seven directories, both
  backends, both `Term_ID` widths, no skip list and an empty ignored-parameter record.
  SHACL-A-0002 named alongside SHACL-A-0001. The `core/complex` correction carried up,
  because it changes what the SHACL-SPARQL phase is *for* rather than merely being a fact
  about one directory.

  **The two "turned out otherwise" notes are kept and strengthened, not deleted** — the
  criterion that mattered most. Both predictions held through the catalogue, and both are
  now stated against a fully-run corpus rather than a partial one:

  - The store predictions stay retired, and the evidence log's two findings are summarised
    with the second one named for what it is: a **contract** (labels dense from `b0` per
    dictionary, so two dictionaries collide by construction), not a capability gap.
  - The language-tag exposure is zero, and the *reason* is now stronger than "no entry
    happens to exercise it": the two components that read a tag fold at comparison because
    SHACL requires it of them. The widened trigger is recorded.

  **"Next:" now points at SHACL-I-0003 and the SHACL-SPARQL phase**, with
  `docs/handover-sparql.md` as the starting point rather than `docs/handover-catalogue.md`,
  and notes that the phase's first task is vendoring `tests/sparql/` rather than fixing
  `core/complex`.

  **Everything else was checked and left alone**, which was the other half of the brief.
  Purpose, Product/Solution Overview, Future State, Major Features, Success Criteria,
  Principles, and Constraints contain nothing that is now false — they were written to
  outlast initiatives and they have. The temptation the Risk Considerations named was to
  tidy them anyway; it was not acted on.

  No code touched. Nothing in `shacl/`, `tests/`, or the build changed.