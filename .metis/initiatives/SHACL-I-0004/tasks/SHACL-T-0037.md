---
id: the-record-of-the-port-vision
level: task
title: "The record of the port: vision and ADR amendments, the pin comment, the sparql-port handoff"
short_code: "SHACL-T-0037"
created_at: 2026-08-20T15:20:42.000000+00:00
updated_at: 2026-08-20T15:20:42.000000+00:00
parent: SHACL-I-0004
blocked_by:
  - SHACL-T-0034
  - SHACL-T-0035
  - SHACL-T-0036
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: SHACL-I-0004
---

# The record of the port: vision and ADR amendments, the pin comment, the sparql-port handoff

## Parent Initiative

[[SHACL-I-0004]]

## Objective

The port's paper trail, in the family convention: amend rather than
rewrite, the old text standing with a dated note saying what moved.
The next session — and the sparql port — trusts what these documents
claim, so this task is not optional cleanup; it is the initiative's
"a release is not done until its consumers' Current State is
re-read" obligation, applied to ourselves.

## Acceptance Criteria

- [ ] **`.metis/vision.md`**: Current State amended (backend is
      odin-rdf-record; kvstore, the width matrix and the `purity`
      target retired; validate-before-commit is the `Validator`
      hook); the success criteria naming odin-rdf-store ("reads
      exclusively through odin-rdf-store's public match interface",
      "runs against any odin-rdf-store backend") retired with dated
      notes; the owner's two decisions (no dual-backend, record is
      the one and only store forever) recorded where the next
      session will read them.
- [ ] **`docs/language-tag-status.md`** amended: record lowercases
      language tags on intern, so the exposure the document tracks
      is resolved on this backend; the decided-but-unbuilt
      parser-side fold is now moot *for this repository* — flag
      for family discussion rather than rescinding a family decision
      unilaterally. Any corpus finding from SHACL-T-0033's
      term-identity check folded in.
- [ ] **`docs/store-proposal.md`** annotated: its one outstanding
      upstream suggestion was to odin-rdf-store, which this
      repository no longer consumes — dated note, text standing.
- [ ] **`SHACL-A-0001`/`SHACL-A-0002`** re-read for claims the port
      falsified (store references, the Access seam, memstore-era
      wording); amended with dated notes where they name what no
      longer exists. (A-0002's numbers are annotated in
      SHACL-T-0036; this is the prose pass.)
- [ ] **`README.md`** updated: dependencies, build instructions
      (collections, no width matrix), the validate-before-commit
      story, and the record's POSIX-only note with the `mem_file_ops`
      answer for suites.
- [ ] **The sparql-port handoff** written (in this task's Status or a
      docs note — wherever the sparql initiative's author will look,
      stated here): what the port actually cost, the call-site
      transformation patterns that worked, the `blank_prefix`
      sanitization rule, any term-identity or performance findings,
      and the explicit note that shacl's no-dual-backend and
      one-and-only-store decisions were made for shacl — sparql asks
      the owner, not assumes.
- [ ] **Family side** (committed in the family-root repo, which is
      its own git repository): the family `CLAUDE.md`'s shacl section
      re-written for what shacl now is, its record section's
      "sibling ports" handoff updated to say shacl's port is done and
      sparql's is next.
- [ ] Every claim in the amended documents checked against the built
      code — version numbers, procedure names, counts.

## Implementation Notes

Tagging the release (presumably `v0.2.0`) is the owner's act and not
gated here; this task leaves the documents ready for it, with the
annotated-tag convention (`Release vX: title` with a bulleted body)
noted.

Cross-repo pieces (the family CLAUDE.md, anything touching the
record's or parser's documents — e.g. the parser's negative-`column`
observation RECORD-T-0017 owed it, if still unfiled) follow the
family convention: discussed with the owner before filing on a
sibling's side.

## Status Updates

*To be added during implementation*
