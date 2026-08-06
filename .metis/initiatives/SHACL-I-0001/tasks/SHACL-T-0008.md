---
id: public-api-documentation-and-the
level: task
title: "Public API, documentation, and the evidence write-ups"
short_code: "SHACL-T-0008"
created_at: 2026-08-06T13:58:18.020873+00:00
updated_at: 2026-08-06T13:58:18.020873+00:00
parent: SHACL-I-0001
blocked_by: ["SHACL-T-0007"]
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
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

## Acceptance Criteria **[REQUIRED]**

- [ ] Package doc on `shacl` carrying the **memory contract** — who owns the shapes model, the
      result stream, the report graph, and until when — plus the allocator discipline and any
      stated allocation budgets, at the standard set by odin-rdf-parser and matched by
      odin-rdf-sparql.
- [ ] Every exported symbol documented across `shacl`, `shacl/memstore`, and `shacl/kvstore`.
- [ ] `README.md` with a compiled example — load shapes, validate a graph in memstore, iterate
      results — asserted by `tests/readme` under the README-as-contract convention.
- [ ] **The `sh:class` gotcha documented prominently**, not as a footnote: `sh:class` walks
      `rdfs:subClassOf*` in the *data* graph, so under single-graph validation the class
      hierarchy must live in the graph being validated. Recorded in SHACL-A-0001's Consequences
      as the user-facing surprise it is.
- [ ] Recursion behaviour documented: recursive shapes are reported as a failure, this is
      spec-sanctioned, and cycles in *data* are not recursion.
- [ ] **Store-evidence write-up delivered for review** — the log from SHACL-T-0005 onward
      consolidated into a proposal in the STORE-T-0014 pattern, each item naming the shape or
      target that wants the capability and what it would buy. **Brought to Greger; not filed
      into odin-rdf-store's Metis from here.** If the log is empty, say so plainly and record
      that STORE-T-0016 was a hypothesis this initiative did not confirm.
- [ ] **Language-tag status recorded**: the decision (fold to lowercase at literal
      construction), the designed implementation (detect in the scanner, fold in the
      constructor), the trigger, and whether it fired. If it did not, note that the exposure
      passes to the catalogue initiative.
- [ ] **Exit criteria verified by a run, not asserted**: `make test` at both widths and
      `make check`, with the per-package test counts and enabled suite directories recorded in
      the task log the way SPARQL-T-0019 did.
- [ ] Handover notes for the catalogue initiative: the constraint-dispatch seam's shape, what
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

*To be added during implementation*
