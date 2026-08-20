---
id: bench-rebuilt-against-record-setup
level: task
title: "bench/ rebuilt against record: setup over Mem_FS + ingest, read counting rehomed, new baselines recorded"
short_code: "SHACL-T-0036"
created_at: 2026-08-20T15:20:32+00:00
updated_at: 2026-08-20T18:20:31.925040+00:00
parent: SHACL-I-0004
blocked_by: [SHACL-T-0033]
archived: false

tags:
  - "#task"
  - "#phase/completed"


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

**2026-08-20 — implemented, all criteria met; awaiting review.**

**The rebuild.** `bench/` is four files over record: `generate.odin`
(untouched — pure strings), `config.odin` (the pins, re-measured),
`store.odin` (new: `Graph_Store` over `Mem_FS` + `ingest` + `apply`, one
epoch per generated document under a fixed `blank_prefix` — `s_` for shapes,
`d_` for data — and `compile_model`, which compiles from a scratch store and
closes it before the run), `main.odin` and `consumers.odin` (ported).
`access.odin` and `instrument.odin` — the counting `Access` and the LMDB
temp-store plumbing — are deleted with the seam they wrapped.

**Read counting rehomed: a build-time switch in the engine, not a seam.**
With no procedure-set to substitute, the honest place to count is where the
reads are: `shacl/counting.odin` declares `SHACL_COUNT_READS ::
#config(SHACL_COUNT_READS, false)` and, under `when`, a process-wide
`Read_Counts{scan, step, outgoing, term}` with `read_counts_reset`/`_get`;
`session_scan`, `session_step`, `session_outgoing` and `session_term` each
carry a `when SHACL_COUNT_READS { … += 1 }`. **Off, it does not exist** — a
compile-time branch, no counter, no global, no cost — and `make test` and
every consumer build it off. **`make bench` therefore builds twice**: the
plain binary for timings (nothing wrapped, the old design's rule kept) and
`-define:SHACL_COUNT_READS=true` for reads, allocation and the
cross-configuration assertions, where no timing is taken. `make check` vets
`bench/` both ways; the alias guard covers it.

**The finding, and it reverses a prediction this task's AC wrote down: the
read counts are the old store's to the integer.** 7503 / 11504 / 11596 /
7503 / 7503 / 9003 / 9003 / 9003 — every pin measured at SHACL-T-0023 over
memstore and kvstore, re-pinned once at T-0026, holds over record. The AC
and the initiative's §8 expected them to differ and asked that the two be
"stated to be incomparable"; I had written that into the prose before the
first run and took it out after. The four session verbs map one-to-one onto
the old seam's four verbs and the engine's control flow did not change in
the port, so it asks exactly the same questions; the cross-backend invariant
the old benchmark asserted on every run (memstore = kvstore) and lost with
memstore's retirement is re-established after the fact by a third store.
`term` is 0 on every configuration, as `load` was. **Wall clock and total
bytes are what changed**, and the prose everywhere now says that instead.

**New baselines (record, memory seam, Apple M-series, `-o:speed
-no-bounds-check`, single run of best-of-5 after warm-up):**

| configuration | compile | bind | validate | ns/focus | reads | raw peak | total B | allocs | report triples |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `baseline` | 35 µs | 8 µs | 1.17 ms | 2338 | 7503 | 20868 | 1 165 092 | 5518 | 9450 |
| `qualified` | 53 µs | 6 µs | 2.10 ms | 4202 | 11504 | 21192 | 4 909 800 | 14522 | 9450 |
| `nested` | 52 µs | 3 µs | 1.90 ms | 3807 | 11596 | 20874 | 3 199 146 | 11284 | 11473 |
| `dense` | 43 µs | 4 µs | 0.97 ms | 1947 | 7503 | 20868 | 1 165 092 | 5518 | 48002 |
| `clean` | 38 µs | 4 µs | 1.14 ms | 2274 | 7503 | 20868 | 1 165 092 | 5518 | 2 |
| `alternative-path` | 41 µs | 5 µs | 1.71 ms | 3410 | 9003 | 20868 | 2 269 092 | 13018 | 15355 |
| `qualified-min` | 51 µs | 4 µs | 1.54 ms | 3089 | 9003 | 20870 | 2 477 094 | 9018 | 9450 |
| `qualified-minmax` | 46 µs | 4 µs | 1.53 ms | 3069 | 9003 | 20870 | 2 477 094 | 9018 | 9450 |

`conforms`: 16 allocations, peak 2148 B on every violating configuration;
equal to the raw stream's 5518 on `clean`, as the promise requires. Against
the odin-rdf-store baselines (kept in T-0023/T-0024's Status, `config.odin`,
and the README, each with a dated note): `validate` on the reference
configuration **4.69 ms → 1.17 ms** (memstore was 0.67 ms — record lands
between the two, closer to the engine than to LMDB); `compile` 146 → 35 µs;
`bind` 27 → 8 µs; raw peak 27076 → **20868 B, the old 32-bit figure**, since
ids are `u32` natively; allocation counts and report sizes identical;
`dense` still the fastest configuration for the reason `config.odin`
records. No configuration shifted wildly; the ~4x on validate is the
LMDB-cursor-to-resident-range difference and is the number the sparql port
should expect (T-0037 handoff).

**`SHACL-A-0002` re-read** ("Re-read after the port"): the As Measured and
As Built tables are annotated as odin-rdf-store measurements; over record
the pair is still indistinguishable (9003 / 9018 / 2 477 094 B / ~1.54 ms)
and `qualified` still 11504; **the trigger stays discharged** — the
sharing-dominates-caching reasoning never depended on what a read costs,
and a faster store raises the bar for reopening rather than lowering it.

**Docs:** README "Performance" rewritten with the record numbers, the
old-store table kept under a dated paragraph, the width paragraph replaced
by why the peak is the old 32-bit figure; `bench/main.odin`'s package doc
rewritten for two builds and the pins' survival; `config.odin` carries both
tables. `make check`, `make bench`, `make test` green; `windows_amd64` check
clean for `bench/` in both builds (it runs over `mem_file_ops`).