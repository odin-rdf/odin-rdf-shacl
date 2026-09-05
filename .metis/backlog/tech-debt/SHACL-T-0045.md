---
id: adopt-odin-rdf-record-v0-9-1
level: task
title: "Adopt odin-rdf-record v0.9.1: a test-only release, and a defect this repository never had"
short_code: "SHACL-T-0045"
created_at: 2026-09-05T21:40:00.000000+00:00
updated_at: 2026-09-05T21:40:00.000000+00:00
parent: 
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"
  - "#tech-debt"


exit_criteria_met: true
initiative_id: NULL
---

# Adopt odin-rdf-record v0.9.1: a test-only release, and a defect this repository never had

## Objective

Move the CI pin from odin-rdf-record `v0.9.0` to `v0.9.1` and re-read this
engine's Current State for anything the release falsifies — the family's
walk-the-consumers rule.

## Context

**odin-rdf-record `v0.9.1` was tagged on 2026-09-05** (`RECORD-T-0047`),
filed by odin-rdf-app. Three of the record's own tests located what they
needed relative to the *process's working directory* rather than to their
own source file — the Python cross-implementation verifier
(`tests/verify/rdflog_verify.py`) and the `record` CLI (`build/record`) —
so a consumer whose suite is one binary, `odin test <main> -all-packages`,
compiled those tests into it, ran them from its own directory, and got
three red lines on a tree whose own tests all pass. They are anchored to
`#directory` now, and the CLI test says when the CLI is simply not built
rather than asserting an exit code against nothing.

**No source, format or API change.** A `v0.9.0` store reads and writes
identically.

Two reasons this changes nothing here beyond the pin:

- **This engine's suite is not an `-all-packages` binary** over the
  record's package, so it never carried those tests.
- **This repository already does what the fix does.**
  `tests/w3c/harness/suite.odin` has located the vendored corpus with
  `SUITE_ROOT :: #directory + ".."` since it was written, and the record's
  task cites it as one of the three precedents. The defect was the record's
  alone.

## Acceptance Criteria

- [x] `ci.yml` pins `odin-rdf-record@v0.9.1`, with a comment paragraph in
      the pin's history saying what the release was and why nothing here
      moved.
- [x] `make check`, `make test` and `make bench` green locally against the
      release's content, with every read pin holding.
- [x] Current State re-read: README's pin chain and `.metis/vision.md`
      carry a dated note.

## Status Updates

- 2026-09-05 — done, pin only. `make check` clean, `make test` 23 tests
  green, `make bench` "all assertions passed" with **7503 on the reference
  configuration, as pinned**, and every other read pin unmoved (the
  qualified-minmax case at 9003). No source file changed. Run against the
  record's `main` at the release's content before the tag was pushed, the
  family's order for a walk.
