---
id: close-the-catalogue-core-node-and
level: task
title: "Close the catalogue: core/node and core/property green, docs, and the write-ups"
short_code: "SHACL-T-0019"
created_at: 2026-08-06T19:27:22.833772+00:00
updated_at: 2026-08-06T19:27:22.833772+00:00
parent: SHACL-I-0002
blocked_by: [SHACL-T-0013, SHACL-T-0014, SHACL-T-0015, SHACL-T-0016, SHACL-T-0017, SHACL-T-0018]
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: SHACL-I-0002
---

# Close the catalogue: core/node and core/property green, docs, and the write-ups

## Parent Initiative

[[SHACL-I-0002]]

## Objective **[REQUIRED]**

Close the initiative: enable `core/node` and `core/property`, verify each exit criterion by a
run rather than an assertion, document the components to the family contract standard, and
refresh the two standing write-ups for review. The spine's SHACL-T-0008 is the model, including
its finding that verification is not a formality — it found three shipped bugs.

## Acceptance Criteria **[REQUIRED]**

- [ ] **`core/node` (32) and `core/property` (38) enabled and fully green**, pinned counts, no
      skip list, both backends, both `Term_ID` widths. A directory that cannot pass entirely
      stays disabled and the reason is recorded.
- [ ] The progress floor from SHACL-T-0009 is **retired or reduced to the directories still
      disabled** — a floor over a green directory is noise.
- [ ] Every new exported symbol documented; the `shacl` package doc's memory contract updated
      for whatever suppressed validation added; the constraint-component list in the README and
      the package doc brought up to date.
- [ ] The ignored-parameter record is **empty for every enabled directory**, asserted — the
      check SHACL-T-0010 added, now meaning what it was built to mean.
- [ ] `tests/readme` still compiles and still asserts; if the API changed, the README changed.
- [ ] **Store-evidence write-up refreshed for review.** The log has been open since
      SHACL-T-0005 and found nothing through the spine; `sh:closed` and the shape-based
      constraints are the likeliest places for a first finding. Empty is a fine answer if it is
      said plainly.
- [ ] **Language-tag status refreshed.** Whether the trigger fired in SHACL-T-0014, and if not,
      where the exposure now sits.
- [ ] **Exit criteria verified by a run**: `make test` at both widths and `make check`, with
      per-package test counts and enabled directories recorded in the task log.
- [ ] Handover notes for the SHACL-SPARQL phase, in the shape of
      `docs/handover-catalogue.md` — what `core/complex` needs, where the `sparql:` collection
      goes, and what this initiative left open.

## Implementation Notes

### Technical Approach

Follow SHACL-T-0008's closing pattern: verify each exit criterion individually, record the
evidence, and where one is not met in full, say so and propose either a re-scope or holding
the initiative open rather than declaring victory.

Expect the verification pass to find things. It did last time, in code that had shipped and
been reviewed, because the newly-enabled directories test corners the earlier ones never
reached.

### Dependencies

Everything: SHACL-T-0013 through SHACL-T-0018. SHACL-T-0009 through SHACL-T-0012 are transitive
dependencies through those.

### Risk Considerations

**The two write-ups are the easiest thing to shortchange at the end of a build**, which is why
they are acceptance criteria rather than closing notes — the same reason SHACL-T-0008 gave.

**If the exit criteria are not fully met**, the honest options are a recorded re-scope with
reasons or holding the initiative open. Both go to review. Neither is "mark it done and file
the rest as backlog" without saying so.

## Status Updates **[REQUIRED]**

*To be added during implementation*
