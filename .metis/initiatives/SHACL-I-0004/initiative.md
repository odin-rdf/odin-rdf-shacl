---
id: port-to-odin-rdf-record-the
level: initiative
title: "Port to odin-rdf-record: the validator moves off odin-rdf-store"
short_code: "SHACL-I-0004"
created_at: 2026-08-20T15:03:02.463825+00:00
updated_at: 2026-08-20T15:37:32.912099+00:00
parent: SHACL-V-0001
blocked_by: []
archived: false

tags:
  - "#initiative"
  - "#phase/active"


exit_criteria_met: false
estimated_complexity: M
initiative_id: port-to-odin-rdf-record-the
---

# Port to odin-rdf-record: the validator moves off odin-rdf-store Initiative

## Context **[REQUIRED]**

On 2026-08-20 the family decided to move odin-rdf-shacl, and after it
odin-rdf-sparql, off odin-rdf-store and onto **odin-rdf-record** — the
tamper-evident system of record (append-only hash-chained log, replayed
into a memory-resident projection serving epoch-pinned snapshots) — and
to retire odin-rdf-store once both ports are done. This repository is
the first port. The governing stance, stated once in `RECORD-I-0003`
and inherited here: **the siblings adapt to the record store, not the
reverse** — record changed as little as its write path required, at the
siblings' expense, and this initiative asks nothing further of it.

**The owner's scoping decision, 2026-08-20, which shapes everything
below:** there is no goal — at any point — of odin-rdf-shacl working
against both kvstore and record, and there are no known deployments to
consider. Where code can be made simpler, faster, or more
memory-efficient by **targeting odin-rdf-record directly**, without
preserving interface-seam parity with the old store, that path is
taken. The port is a replacement, not an addition: `shacl/kvstore`,
the `store:` dependency, and the seam machinery that existed to span
backends are all candidates for deletion, not preservation. (The
draft of this initiative, written earlier the same day, kept kvstore
green through the port and deferred the vocabulary retirement to a
"phase 2"; this paragraph supersedes that draft — both collapse into
this initiative.)

**And its extension, same day:** there is no need to keep — or design
room for — a generic store interface so that other stores can be
plugged in later. **odin-rdf-record is the one and only store,
forever.** No backend abstraction survives this port, and none is to
be reintroduced; "could another backend bind here" is no longer a
question any design in this repository answers.

The prerequisite is met: `odin-rdf/odin-rdf-record` is published and
tagged `v0.1.0` (at `e29764e`, 2026-08-20). Everything the port
consumes exists and is proven: the §12 read API over refcounted
snapshots, `apply(s, Changeset)` as the one write entrance, the
`Validator` hook wired at `store_open`, `record/ingest` (Turtle,
N-Triples, TriG, N-Quads → `[]Op`), `snapshot_kind`/`snapshot_exists`,
and `Mem_FS`/`mem_file_ops` for suites. The seven-point API mapping and
the CI list are in `RECORD-I-0003`'s Status section
(`odin-rdf-record/.metis/initiatives/RECORD-I-0003/initiative.md`);
the family `CLAUDE.md`'s record section carries the rest of the
handoff (harness call-site shapes, term-identity differences, the
Windows leg). Read both before designing here.

What this repository consumes today, from the 2026-08-20 survey — now
a demolition survey rather than a parity checklist:

- **The core** (`shacl`) imports `store:store` in 10 files as
  *vocabulary only* — `Term_ID`, sentinels, and `store.id_kind` at
  eight call sites — never `kvstore`. Compilation binds the backend
  through the parapoly seam (`shacl/query.odin:30`); validation reads
  through the runtime `Access` struct of four verbs
  (`shacl/validate.odin:48`). Both seams existed to span kvstore and
  the retired memstore; with one backend and no parity goal, each
  survives only if it still earns its indirection.
- **The instantiation** (`shacl/kvstore`) is 807 lines consuming 16
  kvstore names — `open_ephemeral`, `load_turtle`, `find_graph_label`,
  `session_init`/`session_init_txn` among them. It is deleted by this
  port.
- **The harness**: ~300 call sites across 20 test files, almost all
  `open_ephemeral` + `load_turtle` + close; the 98 W3C `core/` entries
  run against kvstore at both `Term_ID` widths. The width matrix is
  the store's and goes with it (record's widths are fixed by design).
- **CI** pins `odin-rdf-parser@v0.1.0` and `odin-rdf-store@v0.6.0` as
  sibling checkouts; the Makefile's `COLL` declares `rdf:` and
  `store:`, mirrored in `ols.json`. The store checkout and `store:`
  collection are removed, not joined.

Why shacl first: it is the smaller consumer (no triple terms anywhere
in its corpus — sparql has 20 affected data files), and its
validate-before-commit (`SHACL-T-0029`) maps onto the record store's
`Validator` hook, which was designed with this binding named
(`RECORD-A-0006`: "odin-rdf-shacl will own the catalogue and
validator").

## Goals & Non-Goals **[REQUIRED]**

**Goals:**

- **odin-rdf-record is the backend**, targeted directly. The
  dependencies after this initiative are odin-rdf-parser and
  odin-rdf-record; `store:` is gone from the Makefile, `ols.json`, CI
  and every import. No LMDB anywhere in the link.
- **The 98 W3C `core/` entries green against record** — no skip list,
  no expected-failure file, same standard as today.
- **Simpler, not parallel — and no store abstraction at all.** The
  parapoly compile binding, the `Access` struct, and the 64-bit
  `Term_ID` vocabulary are removed with the backend they spanned;
  record's read API is called directly and its `u32` ids are held
  natively (half the id footprint in every resident structure that
  holds one). A package split, if any survives, is code organization
  — never pluggability. Record is the one and only store, forever,
  and the code is allowed to say so.
- **The harness ported**: `Mem_FS` + `mem_file_ops` replaces
  `open_ephemeral`; `ingest.turtle` + `apply` + `ops_destroy` replaces
  `load_turtle`, with `blank_prefix` as the load scope (label
  characters only — `t1_`, not `t1/`).
- **Validate-before-commit as the record's `Validator` hook**: a
  `check` over the candidate `Snapshot` — the post-state through the
  ordinary read API — with `Enforce` refusing before a byte is written
  and `Record` committing and reporting. This is `session_init_txn`'s
  role rehomed onto the mechanism built for it.
- **As-of validation preserved** (`SHACL-T-0030`'s capability):
  validating a past dataset via `store_at(epoch)`.
- **CI and build plumbing**: `odin-rdf-record@v0.1.0` checked out and
  pinned (a pin comment in the style of the store floor history —
  `SHACL-T-0020`/`-T-0028`/`-T-0030` — recording the port),
  `-collection:record=../odin-rdf-record` with `rdf:` retained; the
  width matrix removed; a green Windows leg (record has no Windows
  `File_Ops`; `mem_file_ops` is platform-free, so the suites run
  everywhere).
- **The record of the port**: vision Current State and success
  criteria amended (several claims name odin-rdf-store and are
  falsified by this port — amend with dated notes, old text standing,
  per the family convention), and a handoff of what the sparql port
  can reuse (it follows at ~170 call sites, plus the triple-term
  limit; note that this repo's no-dual-backend decision was made for
  shacl and sparql should ask, not assume).

**Non-Goals:**

- **Changing odin-rdf-record.** The stance rules it out; a genuine
  capability gap becomes an evidence-backed note for the record's
  backlog, never a workaround and never a precondition of this port.
- **Keeping any store-era compatibility**: no transitional dual
  build, no store-shaped shim, no deprecation window. There are no
  deployments; the suites are the only consumer, and they move in the
  same motion.
- **Retiring odin-rdf-store itself** — a family-level act that waits
  for the sparql port; this initiative only ends *this* repository's
  dependency on it.
- **SHACL-SPARQL** — unchanged by the port; still gated on
  odin-rdf-sparql, whose own port comes after this one.
- **Durable validation reports.** The record store does not log that a
  judge objected (`RECORD-A-0006`, decision 5); a consumer wanting the
  verdict durable writes it as facts. Whether shacl should offer a
  report-as-facts helper is future evidence, not this port.
- **The odin-rdf-sparql port** — its initiative is created on its side
  once this one has proven the shape.

## Detailed Design **[REQUIRED]**

To be settled in the design phase; what is already known, with the
lean where one exists. The test for every choice is the owner's rule:
simpler, faster, or more memory-efficient by targeting record
directly beats parity with anything.

**1. Ids: adopt `u32` natively — the lean, and the biggest
simplification available.** The record handoff's widening rule
(engine keeps 64-bit `Term_ID`, record's `u32` widened at the seam)
was designed for a transitional engine spanning both stores; with the
store gone there is nothing to span. The core drops `store.Term_ID`
for record's `u32` ids: every resident id — in the compiled shapes
model, target sets, value-node lists, path frontiers — halves, and
the widen/narrow layer never gets written. `store.id_kind`'s eight
call sites become `snapshot_kind` (IRI, Blank, Literal). Sentinel
mapping: `0` is unbound in a record `Pattern` and
`MATCH_DEFAULT_GRAPH` binds the default graph — the design phase
maps each `store.UNBOUND`/`store.WILDCARD`/`store.DEFAULT_GRAPH` use
onto those rather than recreating the store's sentinel set. If the
engine ever needs ids of its own, `CONSUMER_ID_FIRST ..=
CONSUMER_ID_LAST` is the stated range; the survey suggests shacl
(unlike sparql) computes no terms, to be confirmed.

**2. The seams: collapsed — decided, not a lean.** The parapoly
compile binding (`shacl/query.odin:30`) and the `Access` struct
(`shacl/validate.odin:48`) exist so the core could name no backend.
That property is retired by the owner's decision, not just
unexercised: record is the one and only store forever, so the code
binds record's read API directly — `snapshot_match` + `range_iter` +
`scan_next`, `snapshot_resolve`, `snapshot_term`/`snapshot_bytes`,
`snapshot_exists` — and `shacl/kvstore`'s 807 lines and the
indirection they fed disappear rather than being re-instantiated. No
replacement abstraction is designed. **Decided at the design gate,
2026-08-20: one package.** Everything lands in `shacl`, importing
`rdf` and `record` directly — the core/instantiation split existed to
keep the core backend-nameless, and with that criterion retired the
split guards nothing. The vision's "core names no backend" success
criterion is retired with a dated note; what it protected — the
SHACL-SPARQL phase's optionality — never depended on backend
abstraction.

**3. The session over a snapshot.** A record read handle *is* a
snapshot (acquire, use, release; `store_latest`/`store_at`), so the
store/txn split kvstore needed collapses: one `session_init` over a
`Snapshot`. `find_graph_label`'s role (resolving the caller-named
graph) becomes `snapshot_resolve` of the graph term. Two record facts
the code must respect (RECORD-I-0003 handoff, point 7): reader safety
under a live writer rests on every list a reader indexes being the
published set's copies, and a `Snapshot` handed to a `Validator`
carries no reference of its own — **it must not be retained** past
the check.

**4. Validate-before-commit.** `session_init_txn`'s counterpart is a
`record.Validator{check, data}` wired once at `store_open`: `check`
receives the candidate `Snapshot` at the new epoch and the resolved
ops; the pre-state is a `store_latest` away. The lean for what shacl
exports: a procedure that binds a compiled shapes model
(`SHACL-A-0001`: the model owns its terms and outlives the store it
compiled from — exactly what a validator judging another store's
candidates needs) and adapts it to the `Validator` signature, with
conformance driving the `bool` and the report reachable through
`data`. Plain after-the-fact validation is `session_init` against any
snapshot.

**5. Term identity shifts under the engine's feet in two places**
(family CLAUDE.md handoff): language tags are lowercased on intern —
which *resolves* this repo's standing language-tag exposure on the
record backend, the fold the vision decided for the parser having
happened in the store's dictionary; and a non-canonical numeric
lexical form (`"01"^^xsd:integer`) is a different term from the
canonical one. `sh:hasValue`/`sh:in` compare terms and inherit both;
value comparisons (`SHACL-T-0012`'s conversion layer) are the
engine's and unchanged. The design phase checks the corpus for
entries these shifts could move; the expectation from the survey is
none.

**6. Blank-node scoping.** Record interns labels as given, globally
per store (`RECORD-I-0003`, decision 4); `ingest`'s `blank_prefix` is
the per-document scope — the discipline this engine's own two shipped
bugs (vision, Current State) taught it to want. Harness prefixes are
derived from test names and must be sanitized to label characters.

**7. Build and CI.** `COLL` becomes `-collection:rdf=…
-collection:record=../odin-rdf-record` (`rdf:` stays — record's
sources import it, the collections-resolve-in-the-importer rule);
`ols.json` mirrors; the store checkout leaves `ci.yml` and
`odin-rdf-record@v0.1.0` enters. The width matrix targets go. The
Windows leg compiles record without the posix file
(`#+build linux, darwin`) and runs suites over `mem_file_ops`.
`python3` is record's own test-suite need, not a consumer's. The
`purity` target (grep for `mdb_` symbols) is retired: it becomes
trivially true with LMDB gone, and the seam it lately guarded — a
future backend's binding point — no longer exists by decision.

**8. `bench/` ports in this initiative — decided at the design gate,
2026-08-20.** All of `SHACL-I-0003`'s harness binds kvstore (five of
six files) and its read-count instrumentation hooks the `Access` seam
this port collapses, so it breaks twice over. It is rebuilt against
record — `Mem_FS` + `ingest` + `apply` for setup, read counting
rehomed onto record's read API (how, exactly, is a design-phase
detail: the one-package layout means the instrumentation wraps
record's iterators rather than a seam struct). **Baselines are
re-measured and the old numbers stand as the record** — store-read
counts and record-read counts are not comparable, and
`SHACL-A-0002`'s As Built numbers get a dated note saying which store
they measured. The point of paying this inside the port:
`SHACL-A-0002`'s memoisation trigger requires *measured* cost, and
deleting bench would make the trigger unpullable again — the exact
gap `SHACL-I-0003` existed to close.

## Alternatives Considered **[REQUIRED]**

- **Adapting odin-rdf-record to this engine** (tagged ids, graph-first
  indexes, a `load_turtle`): ruled out by the family stance — the
  siblings adapt, and RECORD-I-0003 already litigated the specific
  asks (kind, loaders, id range) at its design gate.
- **A second instantiation behind the existing seams, kvstore kept
  green** — this initiative's own first draft. Rejected by the
  owner's decision: dual-backend operation was never a goal, there
  are no deployments to migrate, and parity with the store's
  interface is cost without a customer. The draft's "phase 2"
  (vocabulary retirement) collapses into the port for the same
  reason.
- **A shim implementing odin-rdf-store's match interface over
  record**, so `shacl/kvstore` runs unmodified: a third contract to
  maintain, hiding exactly the seams — `Validator`, epoch pinning,
  snapshot values — the port exists to use.
- **Keeping the 64-bit `Term_ID` and widening at the seam** (the
  record handoff's transitional rule): correct for an engine spanning
  both stores, pure overhead for one that spans nothing — a
  conversion layer and doubled id storage bought back nothing once
  kvstore is gone.
- **Retaining a backend-agnostic seam for a hypothetical future
  store**: ruled out by the owner's decision that record is the one
  and only store forever. The family already has the counterexample —
  the store's memstore was retired because no consumer ever asked for
  a second backend, and its abstraction cost was paid family-wide for
  years; this repository does not rebuild that bet in miniature.

## Implementation Plan **[REQUIRED]**

Sequenced so each task ends green. The port is a replacement, so the
honest unit of "green" is the task boundary, not every intermediate
commit; the suite gate is the same 98 entries throughout. Decomposed
2026-08-20 into SHACL-T-0031 … T-0037, one per step; dependencies are
in each task's `blocked_by`:

1. **Plumbing** (SHACL-T-0031): the record checkout, pin, collections,
   `ols.json`, CI leg changes — proven by a smoke test that opens a
   record store over `Mem_FS`. Adds only; nothing store-side deleted
   yet.
2. **The core ports** (SHACL-T-0032): ids to `u32`, `id_kind` to
   `snapshot_kind`, the read path onto record's API per the §2
   decision, one package, the session over a snapshot;
   `shacl/kvstore` and the `store:` imports deleted in the same
   motion — the compiler is the checklist. Green boundary: `make
   check` plus the ported non-W3C tests.
3. **The full suite** (SHACL-T-0033): `mem_file_ops` + `ingest` +
   `apply` across every remaining harness file; all 98 `core/`
   entries green; the width matrix and the last `store:` references
   removed from Makefile and CI; the term-identity corpus check
   settled by running.
4. **Validate-before-commit** (SHACL-T-0034): the `Validator`
   binding, `Enforce` and `Record` semantics tested, the
   candidate-not-retained rule respected and tested.
5. **As-of validation** (SHACL-T-0035): the `SHACL-T-0030` scenarios
   via `store_at`.
6. **`bench/` rebuilt against record** (SHACL-T-0036, design §8):
   setup over `Mem_FS` + `ingest`, read counting over record's read
   API, new baselines recorded, `SHACL-A-0002`'s numbers annotated
   and its trigger re-read.
7. **The record of the port** (SHACL-T-0037): vision Current State
   and success criteria amended with dated notes; the docs pass
   (`language-tag-status.md`, `store-proposal.md`, README, the
   ADRs' prose); the `purity` retirement recorded; sparql-port
   handoff notes; family CLAUDE.md amended on the family side.
   Blocked by tasks 4, 5 and 6 (tasks 5 and 6 run in parallel with 4
   after task 3).

Exit: `make test` green with odin-rdf-parser and odin-rdf-record as
the only dependencies — no `store:` collection, no LMDB in any link,
no width matrix; the 98 W3C `core/` entries green; validate-before-
commit demonstrated through the record's `Validator` hook; CI green
on all legs with the record pinned at `v0.1.0`; the odin-rdf-sparql
port unblocked with a written handoff.