---
id: bench-rebuilt-against-record-setup
level: task
title: "bench/ rebuilt against record: setup over Mem_FS + ingest, read counting rehomed, new baselines recorded"
short_code: "SHACL-T-0036"
created_at: 2026-08-20T15:20:32.000000+00:00
updated_at: 2026-08-20T15:20:32.000000+00:00
parent: SHACL-I-0004
blocked_by:
  - SHACL-T-0033
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: SHACL-I-0004
---

# bench/ rebuilt against record: setup over Mem_FS + ingest, read counting rehomed, new baselines recorded

## Parent Initiative

[[SHACL-I-0004]]

## Objective

`SHACL-I-0003`'s benchmark harness breaks twice over in this port:
five of its six files bind the deleted kvstore, and its read-count
instrumentation hooks the deleted `Access` seam. Rebuild it against
record (initiative design §8, decided at the design gate) so
`SHACL-A-0002`'s memoisation trigger — which requires *measured*
cost — stays pullable. New baselines are measured; **the old numbers
stand as the record** of what the old store cost.

## Acceptance Criteria

- [ ] `bench/` builds and runs against record: the seeded generator
      loads through `Mem_FS` + `ingest` + `apply`, and all eight
      standing configurations from SHACL-T-0023 run to completion
      with `make bench` (release flags, as before).
- [ ] Read counting rehomed onto record's read API — with no seam
      struct, the instrumentation wraps the iterator/read calls the
      one-package engine actually makes (mechanism at
      implementation; the requirement is a per-validation read count
      as trustworthy as the Access-seam one was, with a pinned count
      per configuration as before).
- [ ] New baselines recorded where the old ones live (wall-clock,
      reads, allocations per configuration), labeled as record-backend
      numbers with the measurement environment stated.
- [ ] The old store-backend baselines are not deleted or overwritten:
      a dated note marks them as measuring odin-rdf-store, retired by
      this port; store-read and record-read counts are stated to be
      incomparable.
- [ ] `SHACL-A-0002`'s As Built numbers get the same dated
      annotation, and its memoisation review trigger is re-read
      against the new numbers — fired or not, the re-reading is
      recorded in the ADR (the RECORD-A-0005 convention).
- [ ] `make check` covers `bench/` as before.

## Implementation Notes

The generator's output documents feed `ingest` with a fixed
`blank_prefix` per generated document so blank-node identity across
configurations is deterministic (record interns labels as given,
globally per store).

If a configuration's runtime shifts wildly against the old numbers,
that is a finding, not a failure — record it in Status for the
SHACL-T-0037 handoff; the sparql port will want to know how the
backends compare in practice.

## Status Updates

*To be added during implementation*
