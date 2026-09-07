---
id: odin-rdf-shacl
level: vision
title: "odin-rdf-shacl"
short_code: "SHACL-V-0001"
created_at: 2026-08-04T16:47:41.838764+00:00
updated_at: 2026-08-20T20:30:00.000000+00:00
archived: false

tags:
  - "#vision"
  - "#phase/published"


exit_criteria_met: false
initiative_id: NULL
---

# odin-rdf-shacl Vision

## Purpose

Provide the Odin RDF family with shape-based validation: a SHACL (Shapes Constraint Language) implementation that validates RDF data graphs against shapes graphs. It stands as a peer of odin-rdf-sparql on the same foundation — shapes are themselves RDF (loaded via odin-rdf-parser), and validation reads the data graph through odin-rdf-store's match interface. SHACL Core requires no query engine; the SHACL-SPARQL extension is a later phase that consumes odin-rdf-sparql. *(Amended 2026-08-20, SHACL-I-0004: the data graph is a snapshot of **odin-rdf-record**, the family's system of record, and odin-rdf-store is no longer a dependency. The rest of the sentence stands.)*

## Product/Solution Overview

odin-rdf-shacl is a library (not an application) targeting Odin developers who need to validate RDF data. It offers:

- **Shapes graph loading**: shapes are parsed from Turtle (or any supported format) with odin-rdf-parser and compiled into an internal shapes model, with meaningful errors for ill-formed shapes.
- **SHACL Core validation**: target resolution (`sh:targetClass`, `sh:targetNode`, and friends), the Core constraint components (`sh:minCount`, `sh:datatype`, `sh:pattern`, `sh:node`, logical constraints, property paths, and the rest), reading the data graph exclusively through the store's match interface. *(Amended 2026-08-20: through an epoch-pinned snapshot of odin-rdf-record, via the session verbs in `shacl/session.odin` — one file, no interface seam.)*
- **Validation reports**: standard `sh:ValidationReport` result graphs, emittable through odin-rdf-parser, plus a programmatic result API for embedding.
- **SHACL-SPARQL (later phase)**: `sh:sparql` constraints and SPARQL-based constraint components, delegating query evaluation to odin-rdf-sparql as an optional dependency.

The library is deliberately validation-only: inference/entailment, SHACL rules (SHACL-AF), and server layers are out of scope.

## Current State

**Amended 2026-08-20 — the engine runs on odin-rdf-record, and odin-rdf-store is
gone from this repository (SHACL-I-0004).** Everything below this block was
written against odin-rdf-store and stands as the record; where a sentence names
what no longer exists, a dated note beside it says what moved. What is true now:

- **The backend is odin-rdf-record** — the family's tamper-evident system of
  record: an append-only, hash-chained log replayed into a memory-resident
  projection serving epoch-pinned snapshots. The engine is **one package**,
  `shacl`, importing `rdf` and `record` and nothing else; the store is touched
  in one file, `shacl/session.odin` (a `Session` over a `record.Snapshot` and
  six verbs: `session_term`, `session_resolve`, `session_kind`, `session_scan`,
  `session_step`, `session_outgoing`), with the graph of SHACL-A-0001 decision 5
  bound into every pattern there. Ids are `record.Term_ID` natively. *(Amended 2026-08-27, SHACL-T-0039: or the **union of
  a set of graphs** — `session_init_union`, `validator_init_union` — decision 5
  generalised on its own review trigger for the application's workspace
  design; the single graph is the one-element case and every pin holds.)*
- **Two owner decisions shape it, recorded here because the next session will
  look here first (2026-08-20):** there is **no dual-backend goal, at any
  point** — the port was a replacement, not an addition — and **odin-rdf-record
  is the one and only store, forever**. Wherever targeting the record directly
  made the code simpler, faster or smaller, that path was taken: `shacl/kvstore`
  (807 library lines, ~5,100 test lines), the `Access` struct, the parapoly
  `$MATCH` seam, the `Term_ID` width matrix, the `purity` target and the
  `store:` collection were deleted, not retained beside the record. These
  decisions were made *for this repository*; odin-rdf-sparql's port asks the
  owner rather than inherits them.
- **All 98 entries of the W3C SHACL 1.0 `core/` suite pass against the record**,
  one run, no skip list, no expected-failure file, ignored-parameter record
  empty throughout. The suites open every store over the record's platform-free
  memory seam (`Mem_FS` + `mem_file_ops`), which is also why CI's three runners
  all run the same `make test`: the record has no Windows `File_Ops`. *(Amended 2026-09-01, SHACL-T-0042: **Windows is dropped**, `RECORD-A-0011` — the leg proved this engine passes on a platform its store cannot host on, and since record `v0.7.0` the package does not compile there at all. Two runners, ubuntu and macos.)*
- **Validate-before-commit is the record's `Validator` hook**
  (`shacl/validator.odin`, SHACL-T-0034), which replaces `session_init_txn`:
  a compiled model wired in at `record.store_open`, handed the dataset a write
  would produce as an ordinary snapshot at the new epoch, before a byte is
  written. `.Enforce` refuses; `.Record` commits and reports; the log does not
  record that a validator objected (RECORD-A-0006 decision 5); a `Failure` is
  a refusal. The vacuity argument below — an isolated candidate is wrong, not
  slow — is unchanged and is still the central test.
- **As-of validation is `record.store_at(&db, epoch)`** in place of
  `store_latest`, and nothing below the session changes (SHACL-T-0035). The
  coordinate is the epoch, not a time; terms are not epoch-scoped, facts are, so
  one compiled model binds at any epoch, and a model compiled from a pinned
  snapshot's shapes graph validates that snapshot's data under the rules then in
  force. The "as-of and validate-before-commit do not compose" distinction below
  holds in a different form: a `Validator`'s candidate is head plus changeset,
  and a pinned snapshot is read-only by type.
- **Performance** (SHACL-T-0036, `bench/` rebuilt over the record): on the
  reference configuration `validate` 1.17 ms (was 4.69 ms on kvstore),
  2.3 µs per focus node, `compile` 35 µs, `bind` 8 µs, peak 20868 B — and
  **the read counts are the old store's to the integer** on all eight
  configurations (7503 on the reference), because the engine asks exactly the
  questions it asked before. `make bench` is two builds, since read counting is
  now a build-time switch in the engine (`SHACL_COUNT_READS`) rather than a
  seam. SHACL-A-0002's trigger stays discharged.
- **Dependencies:** odin-rdf-parser `v0.1.1` (bumped the day it was tagged;
  RDF-T-0025's scanner fix, found by the record's W3C sweep) *(amended
  2026-09-07, SHACL-T-0047: **`v0.1.2`**, RDF-T-0026 — `resolve()` no longer
  strips an absolute IRI's dot segments, so a shapes graph naming one is
  compiled against the term it states)* and
  **odin-rdf-record `v0.3.0` as a floor** (`v0.2.0` for `ingest`'s set semantics, `v0.3.0` for the distinct
  `Term_ID`/`Fact_ID`/`Epoch` types the engine holds). *(Amended 2026-08-25,
  SHACL-T-0038: the floor is **`v0.4.0`**, the release that brought RDF 1.2's
  triple terms and base-direction literals. It was cut for the odin-rdf-sparql
  port and this engine needs neither term kind — it needs the two things their
  arrival changed: `record.Term_Kind` gained `.Triple`, which `node_kind_of`
  switches on exhaustively, and `snapshot_term` can now return a term it owns,
  for which `snapshot_term_destroy` is paired with every decode. That pairing
  also closes the split-IRI leak `session_term`'s contract had admitted since
  the port and had no verb to fix.)* *(Amended 2026-08-27, SHACL-T-0040: the floor is **`v0.5.0`** — `Filter.scope`, RECORD-T-0029; seven sites state `.All`, no verdict or read count moves.)* *(And **`v0.6.0`** the same day, SHACL-T-0041: record's `GPOS` order — every graph-bound read here is a prefix now, no source change.)* *(Amended 2026-09-01, SHACL-T-0042: **`v0.7.0`** — record's exported surface went from 195 names to 73, everything that was not API marked `@(private)` (RECORD-I-0005, -I-0007). This engine compiles unchanged, which is the point: not one of the 122 names that stopped being exported was reached from here.)* odin-rdf-sparql is still
  relevant only to the SHACL-SPARQL phase, which has not started; its handover
  (`docs/handover-sparql.md`) predates the port and carries a translation note.
- **Term identity moved with the store, twice** (SHACL-T-0032/-0033): the record
  lowercases language tags on intern, so the `sh:hasValue`/`sh:in` exposure
  tracked below is closed *here* and the latent exposure is now report
  rendering (`rdf.equal_term` is byte-wise on the tag; the corpus's two
  uppercase-tagged literals both conform, so none reaches an expected report);
  and inlineable literals are always resolvable, so a small canonical integer
  named by `sh:targetNode` is bound even when absent from the data — no verdict
  changed. The family's parser-side fold decision is flagged for family
  discussion, not rescinded here (`docs/language-tag-status.md`).
- **Remaining:** SHACL-SPARQL, unchanged in scope. The port's own paper trail is
  SHACL-T-0037, whose Status carries the handoff for odin-rdf-sparql's port.
- **Released as `v0.2.0`** (2026-08-20, tag at `b3ca168`, the commit CI verified on
  all three runners; GitHub release with notes). The first tag since `v0.1.0`, which
  is the store-era engine — a consumer pinning tags gets the record engine from here.
  The owner's reading on tagging: the rewrite is complete and, barring a consumer
  saying otherwise or the record's API moving for the sparql port, this is the
  version to use for the foreseeable future. No shacl consumer pins a tag today, so
  the release walk ends here. *(Amended 2026-09-07: **`v0.3.0` is the release**, and
  the "barring the record's API moving" clause is what happened — six adoptions
  (`v0.4.0` through `v0.10.0`) and two capabilities of this engine's own landed after
  `v0.2.0`, so a consumer pinning that tag gets neither `session_init_union` nor
  `.Triple` as an ordinary value node. `v0.2.0` stands as the port's tag. The reading
  on tagging is otherwise unchanged: SHACL Core is complete, and `v0.3.0` is the
  version to use.)*

---

**SHACL Core is complete, and the vendored W3C corpus is fully green.** Two initiatives
delivered it: SHACL-I-0001 (the spine, completed 2026-08-06) and SHACL-I-0002 (the
constraint catalogue, completed 2026-08-07).

- **All 98 entries of the vendored W3C SHACL 1.0 `core/` suite pass**, across all seven
  directories, against both storage backends, at both `Term_ID` widths *(2026-08-20:
  against odin-rdf-record, one run — see the block above)*. No skip list, no
  expected-failure file, and an empty ignored-parameter record throughout — the family's
  rule is unchanged, and every directory now satisfies it.
- **All twenty-nine constraint components** of §4 that do not require SPARQL: value-type,
  cardinality, value-range, string-based, property-pair, logical, shape-based, and
  `sh:closed`. Alongside them: shape discovery to §2.1.1, all five target forms, all seven
  path forms, and `sh:ValidationReport` emission.
- **Suppressed validation** — asking whether a node conforms without reporting why — is the
  one architectural addition the catalogue needed, and it has its own ADR (**SHACL-A-0002**)
  because six components depend on it and a mechanism retrofitted from whichever landed
  first would have carried that one's assumptions. **SHACL-A-0001** still records the
  shapes model, term ownership, and graph scoping.
- **The suite target is SHACL 1.0** (2026-08-06), not 1.2. 1.2 is still moving in the W3C,
  and a suite that goes green against a specification that can change under it is worth
  less than it looks. Review trigger and reasoning in `tests/w3c/README.md`.

Packages: `shacl` (backend-independent core) and `shacl/kvstore`. The core
names no storage backend and imports none, asserted rather than trusted — `make check`
builds a core-only consumer and fails if the binary carries LMDB symbols. *(Amended 2026-08-07, SHACL-T-0028: it built a core-plus-memstore consumer until odin-rdf-store retired that backend — STORE-A-0006. The check is narrower now and is internal hygiene rather than a promise to users, since every consumer links LMDB.)* *(Amended 2026-08-20, SHACL-I-0004: one package, `shacl`, importing the record directly; `shacl/kvstore` and the `purity` target are deleted — "the core names no backend" was retired at the port's design gate, by decision, and no consumer links LMDB because nothing in the chain has native code.)*

The dependencies are unchanged and all complete: **odin-rdf-parser** and
**odin-rdf-store** at v0.1.0, and **odin-rdf-sparql** at v0.1.0, relevant here only for
the later SHACL-SPARQL phase. *(Amended 2026-08-08: odin-rdf-store is at **v0.4.0** and
this repository pins it. v0.2.0 retired the in-memory backend (STORE-A-0006), v0.3.0
shipped transactions (STORE-A-0007) — which SHACL-T-0029 consumed, and which is what makes
validate-before-commit expressible here — and v0.4.0 fixed a Windows failure in
`open_ephemeral` that this repository's own suite surfaced (STORE-T-0042). odin-rdf-parser
and odin-rdf-sparql are unchanged at v0.1.0.)* *(Amended 2026-08-20: odin-rdf-store is no
longer a dependency at any version; odin-rdf-record `v0.3.0` is the pin and a floor.)*
*(Amended 2026-08-25: `v0.4.0`, RDF 1.2's two term kinds — SHACL-T-0038.)* *(Amended 2026-08-27, SHACL-T-0040: the floor is **`v0.5.0`** — `Filter.scope`, RECORD-T-0029; seven sites state `.All`, no verdict or read count moves.)* *(And **`v0.6.0`** the same day, SHACL-T-0041: record's `GPOS` order — every graph-bound read here is a prefix now, no source change.)* *(Amended 2026-09-01, SHACL-T-0042: **`v0.7.0`** — record's exported surface went from 195 names to 73, everything that was not API marked `@(private)` (RECORD-I-0005, -I-0007). This engine compiles unchanged, which is the point: not one of the 122 names that stopped being exported was reached from here.)*

*(Amended 2026-08-08, SHACL-T-0030 — filed from odin-rdf-store's STORE-T-0052: **the store
this validator sits on has gained a time dimension, and it reaches validation with no source
change here.** STORE-A-0008 gives every quad the epoch of the transaction that wrote it,
makes `remove` a retraction rather than an erasure, and puts the horizon on the transaction:
`txn_begin_as_of(db, epoch)` returns a transaction through which every read is as-of. Since
`session_init_txn` already takes a `^kvstore.Txn` (SHACL-T-0029), **a validation through such
a transaction answers about the dataset as it was**, and `shacl/kvstore/as_of_test.odin`
asserts it — a shape that HEAD conforms to and an earlier epoch violates, and a `sh:class`
that HEAD violates and an earlier epoch conforms to. Not one line of `shacl/` or
`shacl/kvstore/` changed. That is odin-rdf-store's central bet paying off from the consumer
side: put the time axis on the transaction, and the siblings inherit it without learning the
concept exists. It arrives with **format version 2, which does not read version 1 and has no
migration**, so it is a floor rather than a pin — the store's v0.5.0, unreleased at the time
of writing, and the CI pin moves with the test rather than before it.

*(Amended 2026-08-20, SHACL-T-0035: the paragraph above describes odin-rdf-store's as-of
transactions, which this repository no longer reaches. The same scenarios run on the record
through `store_at` — `shacl/as_of_test.odin`, five tests including shapes-as-of-then — and
the bet paid off a second time in the same way: nothing below the session changed.)*

**The distinction that will otherwise be mis-derived: as-of and validate-before-commit are
two features through one entry point, and they do not compose.** Validate-before-commit is a
candidate assembled inside a **write** transaction and validated through it, deciding a
future. As-of validation is a **read** transaction with a horizon, describing a past.
`txn_begin_as_of` takes no mode and always returns a read transaction, because an audit store
must not expose an API for writing history — so there is no way to assemble a candidate
inside an as-of transaction and validate the merged result. A reader meeting both in
`session_init_txn`'s doc comment should not conclude otherwise.

Two things checked rather than assumed while asserting this. The store documents `count` as
O(1) at HEAD and a scan under a horizon, and flags the asymmetry for its consumers: **no
validation path in this repository calls `count`**, so it does not reach us. And the
dictionary sits outside the epoch model by design, which is what keeps a term nameable in a
read of the past — the term-binding bridge resolves the shapes model's terms through an as-of
transaction unchanged, including terms whose last quad has been retracted.)*

**`core/complex` was never a SHACL-SPARQL directory, and the correction is worth carrying
up to this level** because it changes what that phase is for. It was documented for the
whole of SHACL-I-0002 as needing `sh:sparql`, `sh:shapesGraph`, and `sh:entailment`. All
three appear in `shacl-shacl-data-shapes.ttl` only as *targeted vocabulary* — objects of
`sh:targetSubjectsOf` and `sh:targetObjectsOf` — not as constraint parameters. Nothing in
that file asks for a query engine, and both entries are green for the right reason: the
ignored-parameter record is empty for each, and breaking `sh:datatype` or `sh:nodeKind` in
the evaluator turns both red. The belief survived a discovery phase, a design phase, a
decomposition, and ten task write-ups because each was reading the previous one; nobody read
the file until the closing task.

**Both things this section originally told the project to expect turned out otherwise, and
that is still the most useful thing it records:**

- **The store capabilities this project would "probably pull" were not pulled**, and the
  catalogue did not change that. Both predicted items stay retired. *A named-graph wildcard*
  (STORE-T-0017) cannot become needed without reversing SHACL-A-0001 decision 5, and the
  core cannot express one — neither procedure pointer it reads through takes a graph. *(Decision 5 was generalised to a union on 2026-08-27, SHACL-T-0039, and the
  wildcard is still not needed: a union is a set of graphs, not a class of them.)*
  *Dataset introspection* (STORE-T-0016) was wanted for target resolution, and all five
  target forms turned out to be ordinary match patterns; `sh:closed`, the last thing
  predicted to want it, did not either. **A validator with all twenty-nine components
  reaches odin-rdf-store through `match` and `find_term` and nothing else.** *(2026-08-20:
  and reaches odin-rdf-record through six session verbs and nothing else, with the read
  counts identical to the integer — SHACL-T-0036. The odin-rdf-store backlog items named
  here are moot for this repository; `docs/store-proposal.md` is annotated.)*

  The evidence log has produced two findings in eleven tasks and neither is a capability
  gap. The first was a narrowing this project wrote — `Access` had three read verbs and
  `sh:closed` needed a fourth. The second is the only one about odin-rdf-store at all, and
  it is a **contract** rather than a missing verb: blank-node labels are generated densely
  from `b0` *per dictionary*, so two dictionaries collide by construction, and a consumer
  merging terms from both into one graph must standardise them apart. This engine did not,
  and shipped two bugs for it. `docs/store-proposal.md` carries it as a documentation
  suggestion — the only thing that document has ever asked upstream for.

- **The term-identity question is decided and still has not been forced.** The decision
  stands: **fold language tags to lowercase at literal construction in odin-rdf-parser**.
  The implementation is designed and not built, because the exposure is zero — and that is
  now measured against a fully-run corpus rather than predicted against a partial one. The
  two components that read a language tag both fold at the point of comparison because
  SHACL requires it of them: `sh:languageIn` is RFC 4647 basic filtering, `sh:uniqueLang`
  compares with `equal_fold`. The residual exposure is `sh:hasValue` and `sh:in`, which
  compare terms; no corpus entry pairs them with a mixed-case tag.
  **The trigger is now widened** (2026-08-07) from "a suite entry fails" to "a suite entry
  fails **or** a user reports it", because the corpus runs green in full and will not be
  the thing that raises the alarm. `docs/language-tag-status.md` has the evidence.
  *(Amended 2026-08-20, SHACL-T-0033: the record lowercases tags on intern, so the
  `sh:hasValue`/`sh:in` residual is closed on this backend; what remains latent is report
  rendering, and no corpus entry reaches it. The family decision is flagged for discussion,
  not rescinded here — see the block at the top of this section.)*

**Next**, and neither is about correctness:

- **SHACL-I-0003 — performance evidence.** `bench/` does not exist, so the library has no
  evidence about cost, and SHACL-A-0002's review trigger for memoising conformance answers
  requires *measured* cost — a trigger that cannot currently be pulled. Active, decomposed
  into three tasks. The `v0.1.0` tag waits for it, because every sibling shipped `v0.1.0`
  with performance evidence.
  *(Amended 2026-08-09, SHACL-T-0026: every clause above is now false and the paragraph
  stands as the record. `bench/` exists with eight standing configurations and a pinned read
  count each; the trigger was pulled at SHACL-T-0025 and **discharged — no conformance
  cache**; `v0.1.0` shipped. What the measurement produced instead was one duplicate worth
  deleting, and SHACL-T-0026 deleted it: a property shape's two qualified bounds compile to
  one constraint that counts once and tests the count twice, so `qualified-minmax` and
  `qualified-min` are now identical in reads, allocations and bytes. SHACL-A-0002's
  *As Built* section has the numbers. **The performance line is idle again**, and nothing in
  the backlog schedules more of it.)*
- **The SHACL-SPARQL phase.** `docs/handover-sparql.md` is its starting point:
  what it inherits, where the `sparql:` collection goes in all three places, the dispatch
  seam as it actually is (five edits, not the four `docs/handover-catalogue.md` described),
  and what SHACL-I-0002 left open. Its first task is vendoring
  `data-shapes-test-suite/tests/sparql/`, not fixing `core/complex`.

*(Amended 2026-09-04: **odin-rdf-record `v0.8.0`** — the record's permutations
are copy-on-write B+trees of fact ids (`RECORD-A-0012`), and a commit there is
0.24 ms where it was 37. For this engine that changes what validate-before-
commit costs the application per edit, and nothing in the engine: every
session read goes through the store's published verbs, `make test` is green
and the reference configuration reads 7503 as pinned.)*

*(Amended 2026-09-04, later: **odin-rdf-record `v0.9.0`** — `snapshot_history`,
every generation a pattern ever matched over the same window and scan with the
interval test omitted, `api.md` §12.6 built as written at the application's
asking (`RECORD-T-0044`). A validator judges the visible state of one
snapshot and asks no temporal question; nothing here changed, `make test` is
green and 7503 as pinned. The pin moves because the floor stated here should
be the family's current tag.)*

*(Amended 2026-09-05: **odin-rdf-record `v0.9.1`**, `SHACL-T-0045` — a
test-only release. Three of the record's own tests found their fixtures
relative to the working directory and now find them by their source file
(`RECORD-T-0047`, filed by odin-rdf-app, whose suite is one
`-all-packages` binary). Nothing on either side's source, format or API
moved; this repository's own W3C harness has anchored `SUITE_ROOT` to
`#directory` since it was written, so it never had the defect. `make test`
green, 7503 as pinned, the floor stated here kept at the family's current
tag.)*

*(Amended 2026-09-07: **odin-rdf-record `v0.10.0` and odin-rdf-parser
`v0.1.2`**, `SHACL-T-0047` — two pins in one walk. The record's is its CLI
release (`rdfrecord`, a `stats` subcommand, the environment note stating
the real format version) and its **library is byte-identical to `v0.9.1`**:
74 exported names unmoved, no format change, and this repository links the
library and never the tool. The parser's is the interesting half and the
reason this was not bookkeeping: `RDF-T-0026` stopped `resolve()` from
stripping an *absolute* IRI's dot segments, which Turtle §6.3 does not
permit and RDF 1.1 Concepts §3.2 forbids. **A shapes graph is an ordinary
Turtle document loaded through that parser**, so below `v0.1.2` a shape
naming `<http://ex/a/./b>` in `sh:targetNode`, `sh:class` or `sh:hasValue`
was compiled against a term the document never stated, and would silently
fail to match. The pin had sat at `v0.1.1` since 2026-08-20 because the
record built against the parser's `main` and had no CI; it has had both
since `RECORD-I-0007`, so this was the family's last stale parser pin. No
vendored entry writes such an IRI, so no verdict moves: `make test` green,
7503 as pinned, every other read pin unmoved. **Released as `v0.3.0`** the
same day — the second record-era tag, cut so that the union verbs and the
RDF 1.2 term handling below have a fixed point a consumer can pin instead
of tracking `main`.)*

## Future State

A complete, well-tested Odin library where:

- SHACL Core validation conforms to the W3C SHACL specification, measured against the official SHACL test suite.
- Validation runs against any odin-rdf-store backend through the match interface alone. *(Amended 2026-08-07, SHACL-T-0028: this read "…so the same shapes validate in-memory and LMDB-backed data identically", and it was met — the engine ran verbatim against both backends at both `Term_ID` widths, which is what proved it reached storage through the contract alone. odin-rdf-store has since retired its in-memory backend (STORE-A-0006), so the identical-behaviour half is no longer verifiable and is retracted rather than left standing. The criterion itself survives: the core still names no backend.)* *(Retired 2026-08-20, SHACL-I-0004: the engine names odin-rdf-record and only it, by decision. What replaces the criterion is narrower and verifiable — the store is reached through `shacl/session.odin` alone, and a port that changed the store's cost without changing a single read count is the evidence that the engine's questions were never backend-shaped.)*
- Validation reports are spec-conformant RDF graphs that round-trip through odin-rdf-parser.
- The SHACL-SPARQL phase covers SPARQL-based constraints by embedding odin-rdf-sparql, keeping it strictly optional for Core-only users.

## Major Features

- **Shapes model**: compiled representation of node shapes, property shapes, targets, paths, and constraint parameters, built from a shapes graph with validation of the shapes themselves.
- **Target resolution**: all Core target declarations resolved to focus nodes via store matching.
- **Core constraint components**: the full SHACL Core catalogue, including property paths (shared path semantics with SPARQL where the specs align), logical combinators (`sh:and`/`sh:or`/`sh:not`/`sh:xone`), and shape-based constraints (`sh:node`, `sh:qualifiedValueShape`).
- **Validation reports**: `sh:ValidationReport`/`sh:ValidationResult` graphs with severities, messages, and paths per spec; programmatic API for tooling.
- **W3C test-suite harness**: the official SHACL test suite vendored and run hermetically, in the family's established style.
- **SHACL-SPARQL (later phase)**: SPARQL-based constraints and constraint components via odin-rdf-sparql.

## Success Criteria

- SHACL Core passes the W3C SHACL test suite's Core tests (vendored, offline-reproducible).
- Validation reads data exclusively through odin-rdf-store's public match interface — no private hooks into a specific backend. *(Retired 2026-08-20, SHACL-I-0004: odin-rdf-store is not consumed. The surviving form: validation reads data exclusively through odin-rdf-record's public snapshot read API, in one file.)*
- Validation reports are spec-conformant: emitted via odin-rdf-parser and verifiable against the suite's expected report graphs (blank-node isomorphism, as in the parser's eval harness).
- SHACL Core has zero dependency on odin-rdf-sparql; the SHACL-SPARQL phase adds it as a clean optional layer.
- The public API is documented and idiomatic Odin, to the contract-documentation standard of the sibling projects.

## Principles

- **Suite-driven correctness**: the W3C SHACL test suite defines "done", as the format and query suites do for the sibling projects.
- **Core before SPARQL**: everything achievable without a query engine ships first; the optional dependency stays optional forever.
- **Consume the interface, don't bypass it**: data access goes through odin-rdf-store's published match contract; capability gaps are proposed upstream as evidence-backed needs. *(Amended 2026-08-20: through odin-rdf-record's published snapshot read API and `Validator` hook; the record changed as little as its own write path required and this repository asks nothing further of it — the siblings adapt to the record, not the reverse. Findings still go to its owner first.)*
- **Idiomatic Odin**: explicit memory management, allocator awareness, straightforward procedural APIs — the family's conventions.
- **Primitives over frameworks**: a validation engine as a library; pipelines, servers, and rule systems belong downstream.

## Constraints

- Written in Odin with no external dependencies; odin-rdf-sparql is an optional dependency confined to the SHACL-SPARQL phase.
- Depends on odin-rdf-parser (data model, shapes/report parsing and emitting) and odin-rdf-store (match interface); consumed as published. *(Amended 2026-08-20: and odin-rdf-record (snapshots, `apply`, the `Validator` hook, `record/ingest`) in place of odin-rdf-store; pinned at `v0.3.0` as a floor. The record is POSIX-only for durable storage; the suites here use its memory seam.)* *(Amended 2026-08-25: `v0.4.0`, SHACL-T-0038.)* *(Amended 2026-08-27, SHACL-T-0040: the floor is **`v0.5.0`** — `Filter.scope`, RECORD-T-0029; seven sites state `.All`, no verdict or read count moves.)* *(And **`v0.6.0`** the same day, SHACL-T-0041: record's `GPOS` order — every graph-bound read here is a prefix now, no source change.)* *(Amended 2026-09-01, SHACL-T-0042: **`v0.7.0`** — record's exported surface went from 195 names to 73, everything that was not API marked `@(private)` (RECORD-I-0005, -I-0007). This engine compiles unchanged, which is the point: not one of the 122 names that stopped being exported was reached from here.)*
- Scope is SHACL Core validation plus the later SHACL-SPARQL phase. Out of scope: SHACL Advanced Features (rules, functions), inference/entailment regimes, and any server or protocol layer.
- Validation performance is bounded by the store's match capabilities; correctness must never depend on backend-specific behavior. *(Amended 2026-08-20: there is one backend by decision, so the second clause now means: correctness must not depend on the record's representation — term identity is RDF's (language tags fold on intern; `"01"^^xsd:integer` and `"1"` are distinct terms) and value comparison is the engine's job, in `shacl/value.odin`.)*
