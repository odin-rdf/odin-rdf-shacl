---
id: vendor-the-w3c-shacl-test-suite
level: task
title: "Vendor the W3C SHACL test suite and build the manifest-driven harness"
short_code: "SHACL-T-0002"
created_at: 2026-08-06T13:58:06.773159+00:00
updated_at: 2026-08-06T13:58:06.773159+00:00
parent: SHACL-I-0001
blocked_by: ["SHACL-T-0001"]
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: SHACL-I-0001
---

# Vendor the W3C SHACL test suite and build the manifest-driven harness

## Parent Initiative

[[SHACL-I-0001]]

## Objective **[REQUIRED]**

Land the thing that defines "done" for this project: the official W3C SHACL test suite,
vendored at a pinned commit for hermetic offline runs, plus a manifest-driven harness that can
read it. Because SHACL has no syntax suite, every entry is *data graph + shapes graph →
validation report*, so the harness needs graph comparison by blank-node isomorphism from the
outset rather than as a later addition.

Deliverable is a harness that reads manifests, pins entry counts per directory, and compares
report graphs — with **zero directories enabled**, since nothing can validate yet. It also
produces two survey findings the initiative depends on: the real directory inventory, and the
language-tag exposure.

## Acceptance Criteria **[REQUIRED]**

- [ ] W3C SHACL test suite vendored verbatim under `tests/w3c/` from `w3c/data-shapes` at a
      pinned commit (its own pin — a different repository from the `w3c/rdf-tests` commit the
      sibling projects share).
- [ ] `tests/w3c/README.md` provenance record in odin-rdf-parser's shape: upstream repo,
      pinned commit, retrieval date, license, local-directory → upstream-path table, and
      explicit exclusions (the `sparql/` portions of the suite are out of scope until the
      SHACL-SPARQL phase).
- [ ] Harness parses suite manifests with the family's own Turtle parser via the `rdf:`
      collection, walks entries preserving order, and asserts a pinned entry count per
      directory as the circularity guard.
- [ ] Report comparison by **blank-node isomorphism**, reusing odin-rdf-parser's eval-harness
      technique; verified against hand-written report pairs (isomorphic, and
      non-isomorphic-but-similar) before any suite entry uses it.
- [ ] `sht:Failure` expectations are recognised as a distinct outcome and counted, never
      silently dropped. An unhandled entry type fails hard — no skip list, no
      expected-failure file.
- [ ] Directory inventory recorded in the task log: which directories exist at the pinned
      commit, their entry counts, and which this initiative targets (the target and path
      directories) versus which belong to the catalogue initiative.
- [ ] **Language-tag exposure survey recorded**: grep the vendored corpus for language tags
      containing uppercase, and report which entries and which directories would be affected
      by the folding decision. This is the evidence behind the deferral in SHACL-I-0001's
      Detailed Design, and the thing that would fire its trigger.
- [ ] `make test` / `make check` green at both widths with the harness present and no suite
      directories enabled.

## Implementation Notes

### Technical Approach

Mirror `tests/w3c/harness/` from odin-rdf-parser and odin-rdf-sparql (`manifest.odin`
pattern, `MANIFEST_BASE`, plain `odin test`, no custom runner). The SHACL manifest vocabulary
differs from `mf:`-style query manifests — entries carry a shapes graph and a data graph and
an expected report — so manifest reading needs its own shape here, but per-directory
enablement, pinned counts, and fail-hard-on-unknown carry over unchanged.

Blank-node isomorphism is the piece with no precedent in this repo but a working precedent
next door: odin-rdf-parser's eval harness compares graphs that way for its `*-eval` suites.
Validation reports are blank-node-heavy (each `sh:ValidationResult` is typically a blank
node), so this is load-bearing rather than incidental.

### Dependencies

SHACL-T-0001 (package layout, `tests/w3c/` reserved, green build).

### Risk Considerations

The suite's exact directory names and layout are confirmed *here*, not assumed — SHACL-I-0001
names the target and path directories as its exit criteria on the expectation that they exist
as separable directories. If the layout differs materially from that expectation, say so in
the task log and raise it before SHACL-T-0007 depends on it: the exit criteria may need
restating in terms of whatever the suite actually offers.

## Status Updates **[REQUIRED]**

*To be added during implementation*
