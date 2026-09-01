---
id: adopt-odin-rdf-record-v0-7-0-the
level: task
title: "Adopt odin-rdf-record v0.7.0: the store's surface is its API, and this engine never reached past it"
short_code: "SHACL-T-0042"
created_at: 2026-09-01T12:05:31.039983+00:00
updated_at: 2026-09-01T12:05:31.039983+00:00
parent: 
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/backlog"
  - "#tech-debt"


exit_criteria_met: false
initiative_id: NULL

# Adopt odin-rdf-record v0.7.0: the store's surface is its API, and this engine never reached past it

## Objective

Bump the record pin from `v0.6.0` to `v0.7.0` — the seventh, and the first that
*removes* names from the store's API rather than adding to it.

## Context

**odin-rdf-record `v0.7.0` was tagged on 2026-09-01** (`61cdfa6`,
`RECORD-I-0005` and `RECORD-I-0007`). Odin exports every top-level declaration
not marked `@(private)`, so that repository's surface had been a residue of what
its own code needed to share with its CLI, its out-of-package test suites, and
itself: **195 exported names, of which 65 were the API.** It is **73** now, and
`doc/api-surface.txt` states them normatively with `make api` failing the build
on any drift.

**For this engine the release is a test, not a change.** Since `SHACL-I-0004`
the vision has claimed that shapes validation reads the record through one file
of session verbs and the published API — `shacl/session.odin` and nothing else.
122 names stopped being exported. If that claim were false anywhere, this bump
would not compile.

It compiled unchanged.

## Acceptance Criteria

- [x] `.github/workflows/ci.yml` pins `odin-rdf-record@v0.7.0`, with the comment
      beside it saying what the release was and why a bump that changes nothing
      here is worth making.
- [x] `make check` and `make test` green with **no source change** — all 98 W3C
      SHACL `core/` entries, no skip list.
- [x] `make bench`: every read pin holds, 7503 on the reference configuration.
- [x] `.metis/vision.md` (three sites) and `README.md` amended, the old text
      standing with a dated note, per the family convention.

## Notes

**What is new in the store that this engine might want later.** `log_read` is
the decoded counterpart to `replay`: it walks a log and hands over `rdf.Quad`s,
owning the dictionary and the term resolution, without booting a store. Nothing
here wants it today — this engine validates *snapshots*, and a shapes graph is
loaded through `record/ingest`, not read out of a log. It is the seam to reach
for if a validation report ever needs to say what the log said rather than what
the store holds.

**What is gone that this engine never named:** `replay`, `Consumer`,
`term_decode`, `inline_term`, `Fact_Op`, `Resolve_Iri`, `Resolve_Term`,
`DEFAULT_GRAPH`, `INLINE_FLAG`, `TERM_TAG_IRI`, and the whole encode/writer
surface — `writer_create`, `frame_next`, `commit_encode`, `Segment_Header` and
their kind — plus the projection builders (`store_init`,
`store_build_permutations`, `store_publish`, `Loader`, `dict_bytes`,
`store_fact`). The last two are worth noting because a test *could* plausibly
have reached for them: `dict_bytes` and `store_fact` are the resident
equivalents of `snapshot_bytes` and `snapshot_fact`, and the record's own
out-of-package suite had been using them until `RECORD-T-0034` ported it onto
the public read API. Nothing here had.

**Three names were added, not removed, and are worth knowing about**:
`snapshot_bytes`, `snapshot_visible` and `snapshot_derived` were briefly marked
private during that work and then promoted back — `api.md` §12 names *Bytes* as
part of the read API, and under-exporting is as wrong as over-exporting. This
engine uses none of the three today; `session_term` covers what it needs.

**Not a format change.** A `v0.6.0` store reads and writes identically; the log,
the encoding and both of the record's verifiers are untouched. The floor
therefore rises for tidiness rather than necessity — this engine would still
compile against `v0.6.0`. It is stated as the pin because the family walks its
consumers on release, and because a pin that names the surface-stating release
is the one worth having.
