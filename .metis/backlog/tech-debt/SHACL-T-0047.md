---
id: adopt-odin-rdf-record-v0-10-0-and-parser-v0-1-2
level: task
title: "Adopt odin-rdf-record v0.10.0 and odin-rdf-parser v0.1.2: the record's CLI release, and the parser pin that had not moved since August"
short_code: "SHACL-T-0047"
created_at: 2026-09-07T19:20:00.000000+00:00
updated_at: 2026-09-07T19:20:00.000000+00:00
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

# Adopt odin-rdf-record v0.10.0 and odin-rdf-parser v0.1.2

## Objective

Move both CI pins to the family's current tags — odin-rdf-record `v0.9.1` →
`v0.10.0`, odin-rdf-parser `v0.1.1` → `v0.1.2` — and re-read this engine's
Current State for anything either release falsifies. The walk-the-consumers
rule, run for two repositories at once because the parser's was overdue.

## Context

**odin-rdf-record `v0.10.0`** (2026-09-07) is the record's CLI release:
`RECORD-T-0048` renamed the tool to `rdfrecord` and gave it a `make install`,
`RECORD-T-0050`/`-T-0052` added a `stats` subcommand folded from the log
rather than answered from a booted store (an auditor's tool must not mutate
the thing it is auditing), and `RECORD-T-0053` made the §5.5 environment note
state the real format version instead of a literal `1` that had been wrong
since `v0.4.0`. **The library is byte-identical to `v0.9.1`** —
`doc/api-surface.txt` unmoved at 74 exported names, no format change. This
repository links the library and never the tool, so there is nothing here to
adapt.

**odin-rdf-parser `v0.1.2`** (2026-08-25) is the interesting half, and the
reason this task is not purely bookkeeping. `RDF-T-0026`: `resolve()` had
been running *absolute* IRIs through RFC 3986 §5.2 reference resolution and
stripping their dot segments, base or no base, so a Turtle document loaded an
IRI it does not contain — which Turtle §6.3 does not permit and RDF 1.1
Concepts §3.2 forbids outright ("further normalization MUST NOT be
performed"). **A shapes graph is an ordinary Turtle document loaded through
this parser**, so below `v0.1.2` a shape naming `<http://ex/a/./b>` in
`sh:targetNode`, `sh:class`, `sh:hasValue` or `sh:in` was compiled against a
term the document never stated, and would silently fail to match the data.

The pin was left at `v0.1.1` when `v0.1.2` was cut because odin-rdf-record —
which this engine loads every document through — had no CI at the time and
built against the parser's `main`. It has had CI and a `v0.1.2` pin since
2026-09-01 (`RECORD-I-0007`), so this was the last stale parser pin in the
family.

No vendored SHACL entry writes an absolute IRI with dot segments, so no
verdict moves; the exposure was real and unexercised.

## Acceptance Criteria

- [x] `ci.yml` pins `odin-rdf-record@v0.10.0` and `odin-rdf-parser@v0.1.2`,
      each with a comment paragraph in its pin history saying what the
      release was and why nothing here moved.
- [x] `make check`, `make test` and `make bench` green locally against both
      releases' content, with every read pin holding.
- [x] Current State re-read: README's pin chain and `.metis/vision.md` carry
      dated notes, the parser's on the dependency bullet rather than only in
      the record's chain.

## Status Updates

- 2026-09-07 — done, pins only, no source file changed. `make check` clean
  (every package vetted, import aliases clean), `make test` green — 23 W3C
  harness tests, the shacl package suite, guards, readme and smoke — and
  `make bench` "all assertions passed" with **7503 on the reference
  configuration, as pinned**, every other read pin unmoved (alternative-path
  and both qualified cases at 9003, 11504 and 11596 where they were). Run
  against local checkouts sitting exactly at the two tags.
