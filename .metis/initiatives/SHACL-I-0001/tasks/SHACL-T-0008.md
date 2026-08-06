---
id: public-api-documentation-and-the
level: task
title: "Public API, documentation, and the evidence write-ups"
short_code: "SHACL-T-0008"
created_at: 2026-08-06T13:58:18.020873+00:00
updated_at: 2026-08-06T18:39:22.607114+00:00
parent: SHACL-I-0001
blocked_by: [SHACL-T-0007]
archived: false

tags:
  - "#task"
  - "#phase/active"


exit_criteria_met: true
initiative_id: SHACL-I-0001
---

# Public API, documentation, and the evidence write-ups

## Parent Initiative

[[SHACL-I-0001]]

## Objective **[REQUIRED]**

Close the initiative: document the public API to the family's contract standard, verify the
exit criteria with a full run rather than an assertion, and deliver the two review-gated
write-ups. Nothing here is optional polish — the documentation standard is a stated success
criterion of the vision, and the write-ups are the whole output of the upstream boundary this
project works under.

## Acceptance Criteria

## Acceptance Criteria **[REQUIRED]**

- [x] Package doc on `shacl` carrying the **memory contract** — who owns the shapes model, the
      result stream, the report graph, and until when — plus the allocator discipline and any
      stated allocation budgets, at the standard set by odin-rdf-parser and matched by
      odin-rdf-sparql.
- [x] Every exported symbol documented across `shacl`, `shacl/memstore`, and `shacl/kvstore`.
- [x] `README.md` with a compiled example — load shapes, validate a graph in memstore, iterate
      results — asserted by `tests/readme` under the README-as-contract convention.
- [x] **The `sh:class` gotcha documented prominently**, not as a footnote: `sh:class` walks
      `rdfs:subClassOf*` in the *data* graph, so under single-graph validation the class
      hierarchy must live in the graph being validated. Recorded in SHACL-A-0001's Consequences
      as the user-facing surprise it is.
- [x] Recursion behaviour documented: recursive shapes are reported as a failure, this is
      spec-sanctioned, and cycles in *data* are not recursion.
- [x] **Store-evidence write-up delivered for review** — the log from SHACL-T-0005 onward
      consolidated into a proposal in the STORE-T-0014 pattern, each item naming the shape or
      target that wants the capability and what it would buy. **Brought to Greger; not filed
      into odin-rdf-store's Metis from here.** If the log is empty, say so plainly and record
      that STORE-T-0016 was a hypothesis this initiative did not confirm.
- [x] **Language-tag status recorded**: the decision (fold to lowercase at literal
      construction), the designed implementation (detect in the scanner, fold in the
      constructor), the trigger, and whether it fired. If it did not, note that the exposure
      passes to the catalogue initiative.
- [x] **Exit criteria verified by a run, not asserted**: `make test` at both widths and
      `make check`, with the per-package test counts and enabled suite directories recorded in
      the task log the way SPARQL-T-0019 did.
- [x] Handover notes for the catalogue initiative: the constraint-dispatch seam's shape, what
      the suite inventory says is left, and anything the spine deliberately left open.

## Implementation Notes

### Technical Approach

Follow SPARQL-T-0019's closing pattern: verify each exit criterion individually, record the
evidence, and where a criterion is not met in full, say so and propose either a re-scope or
holding the initiative open — rather than quietly declaring victory. That task's re-scope
decision, taken with human review and recorded in the initiative, is the model.

### Dependencies

SHACL-T-0007 (everything must be working before it can be documented and verified).

### Risk Considerations

The two write-ups are the initiative's contract with the read-only upstream rule, and they are
the easiest thing to shortchange at the end of a build. They are acceptance criteria rather
than "nice to have" for that reason.

If the exit criteria are not fully met, the honest options are a recorded re-scope with reasons
or holding the initiative open — both go to review. Neither is "mark it done and file the rest
as backlog" without saying so.

## Status Updates **[REQUIRED]**

- **2026-08-06 — Complete, awaiting review.** All nine criteria met. `make check` clean,
  `make test` green at both `Term_ID` widths.

  **Verification record** (both widths, identical counts):

  | Package | Tests |
  | --- | ---: |
  | `shacl` | 1 |
  | `shacl/memstore` | 40 |
  | `shacl/kvstore` | 12 |
  | `tests/guards` | 10 |
  | `tests/readme` | 3 |
  | `tests/w3c/harness` | 22 |
  | **total per width** | **88** |

  Enabled suite directories: `core/targets` (7), `core/path` (13), `core/misc` (5),
  `core/validation-reports` (1) — **26 entries, 52 entry runs per width**, no skip list,
  both backends. `make check` vets all six test packages plus `tests/purity` and asserts
  the core links no LMDB.

  **The verification pass was not a formality — it found three bugs**, all in code
  SHACL-T-0006 and -0007 had already shipped and all invisible to the directories those
  tasks enabled. This is exactly what "verify by a run, not an assertion" was for.

  1. **The report emitted `sh:message` where §3.1 says `sh:resultMessage`.** A shape
     declares `sh:message`; a *result* carries `sh:resultMessage`. They are different
     properties. `misc/message-001` says so in a comment on the entry itself: "this test
     verifies that the sh:message is copied into sh:resultMessage."
  2. **`sh:severity` accepted only three IRIs.** §2.1.4 names `sh:Violation`,
     `sh:Warning`, and `sh:Info` as built-ins but does not close the set, and
     `misc/severity-002` declares `sh:severity ex:MySeverity` and expects it echoed into
     the report. The three-valued enum did not merely mis-report it — it **rejected the
     shapes graph at compile time**, which is worse than a missing feature. `Severity` is
     gone; `Shape.severity` and `Result.severity` are `rdf.Term`, and `severity_is`
     compares one against a vocabulary constant.
  3. **`sh:conforms` ignored warnings.** T-0006 implemented "only `sh:Violation` breaks
     conformance" and asserted it in two tests. It is wrong: §3.1 makes `sh:conforms` true
     if and only if there are **no results**, whatever severity they carry.
     `misc/severity-001` produces exactly one `sh:Warning` result and expects
     `sh:conforms false`. `severity_breaks_conformance` is gone and `Conformance` stops at
     the first result of any kind — which also makes early exit strictly stronger.

  **Two directories were enabled beyond the exit criteria**, and this is flagged as a
  scope change rather than slipped in. `core/misc` (5) went green once the three bugs
  above were fixed; `core/validation-reports` (1) was green untouched. Neither exercises a
  constraint component outside the spine's seven, so no catalogue work was smuggled in.
  The family's rule cuts both ways: leaving a green directory disabled misstates the
  position as surely as enabling a broken one. The initiative's stated exit criteria —
  `core/targets` and `core/path` — are met independently of this.

  **What landed for documentation.** The `shacl` package doc now carries the memory
  contract as a contract: who owns what and until when, per object, with the two
  deliberate departures from borrow-by-default named and justified, plus the stated
  allocation budgets. Every exported symbol across the three packages is documented; four
  procedures that were public only by omission (`intern`, `intern_string`,
  `term_table_init`, `term_table_destroy`) became `@(private)`, which is the better fix
  than documenting internal machinery as API. `vocab.odin`'s constants are documented by
  group heading rather than individually — the same style odin-rdf-parser uses, and a
  per-constant comment on `MAX_COUNT :: NS + "maxCount"` would be pure restatement.

  **README-as-contract** now has three compiled examples (`tests/readme`, 3 tests): the
  streaming visitor, the conformance-only form, and the report form. The README also gained
  a memory-contract table and a fourth "thing to know".

  **The two review-gated write-ups are delivered**, both to review and neither filed
  upstream:

  - `docs/store-proposal.md` — **proposes no change to odin-rdf-store.** Both predicted
    items are retired with reasons (STORE-T-0017 structurally, STORE-T-0016 by
    measurement), and the two near-misses are written down so the catalogue initiative
    does not re-derive them differently. STORE-T-0019 is sharpened but explicitly not
    promoted.
  - `docs/language-tag-status.md` — **the trigger did not fire, and cannot on this
    corpus.** Decision, designed implementation, and evidence recorded.
    odin-rdf-parser is untouched. Recommends extending the trigger from "a suite entry
    fails" to "a suite entry fails **or** a user reports it", since the suite has now
    demonstrated it will not be the one to raise the alarm.

  **`docs/handover-catalogue.md`** is the catalogue initiative's starting point: the
  four-edit shape of the dispatch seam, what the spine deliberately left out (shape
  discovery is narrower than §2.1.1, and widening it is the catalogue's *first* job, not a
  later one), the per-directory component inventory, and the open questions — duplicate
  results, recursion-as-detection, and the undecided SHACL 1.0-vs-1.2 suite question.

  **SHACL-A-0001 gained a second "As Built"** recording that decision 6 is now realised,
  that a sibling shape is not recursion, and that term ownership paid for itself in an
  unplanned place — the suite runner loads shapes and data into two separate stores, which
  exercises the property on every entry run rather than only in the tests that name it.
