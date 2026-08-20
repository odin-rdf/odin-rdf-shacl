---
id: the-record-of-the-port-vision-and
level: task
title: "The record of the port: vision and ADR amendments, the pin comment, the sparql-port handoff"
short_code: "SHACL-T-0037"
created_at: 2026-08-20T15:20:42+00:00
updated_at: 2026-08-20T19:50:58.748180+00:00
parent: SHACL-I-0004
blocked_by: [SHACL-T-0034, SHACL-T-0035, SHACL-T-0036]
archived: false

tags:
  - "#task"
  - "#phase/completed"


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

**2026-08-20 — session handoff, written at a context break before this
task started.** T-0031 … T-0036 are completed and committed; this task has
produced nothing yet. What the next session needs beyond the initiative,
each task's Status, and the family CLAUDE.md:

**1. The repository state.** Six commits on `main` are **unpushed**
(`212fc2e` T-0034, `6bbc6df` the alias sweep, `d220302` T-0035, `9998ed4`
T-0036, `a210728` the `v0.3.0` adaptation, plus this one); `origin/main` is
at `8aa303a` (T-0033). CI last ran green on `8aa303a` against
`odin-rdf-record@v0.2.0`; **it has not yet run against `v0.3.0`**, which
is what `ci.yml` now pins. The record repo is public as of today (it was
private, and the first CI run with a record checkout failed on that). Both
record tags are on GitHub: `v0.2.0` (`a0df591`, ingest dedup) and `v0.3.0`
(`5e9029a`, distinct id types); record's `main` is one docs commit past the
tag (`43ed124`).

**2. What this task inherits beyond its AC, by source.** From T-0032/33's
Status: prose in `shacl/{shacl,model,value,value_test,intern,result}.odin`
still names `Term_ID`, `kvstore` or "both widths" (`session.odin` and
`validator.odin` are clean); README's package table still lists
`shacl/kvstore`; `docs/handover-sparql.md` and `docs/handover-catalogue.md`
predate the port entirely and need the same dated treatment as
`store-proposal.md`. From today: the `Judge` → `Validator` rename (the ADR's
word "judge" survives only in the RECORD-A-0006 quote — keep it that way);
the redundant-import-alias sweep and the grep in `make check` that keeps it
out (`Makefile`, after the vet loop — worth one sentence in the README's
Building section); `make bench` is two builds (`SHACL_COUNT_READS`,
`shacl/counting.odin`) — the README's Building/Performance text already
says so, the vision does not.

**3. The vision's claims the port falsified, beyond the AC's list**, found
while working rather than by reading the vision (read it in full anyway):
"the core names no backend" (retired at the design gate, 2026-08-20);
anything about `purity`; the `Access` seam and "a second backend binds
here"; the standing language-tag exposure (see 5); the performance numbers
if it quotes any (T-0036's are the current ones: validate 1.17 ms on the
reference configuration, 2.3 µs/focus node, 7503 reads, peak 20868 B).

**4. Record-side facts a sparql port needs that no single document yet
gathers** — the core of the handoff this task writes:
- Pin **`v0.3.0` or later**, as a floor: `v0.2.0` for `ingest`'s set
  semantics (RECORD-T-0019 — a document that repeats a statement loads;
  below it `apply` refuses the second assert and the W3C SHACL suite's
  shacl-shacl graph cannot load), `v0.3.0` for the distinct `Term_ID` /
  `Fact_ID` / `Epoch` (RECORD-T-0020). An engine holding `u32` ids does
  not compile against `v0.3.0`; holding `record.Term_ID` natively is the
  adaptation (105 sites here, mechanical, one commit).
- **A candidate is the delta.** Re-asserting a quad that is live is
  `.Already_Live` at the op, judged *before* any validator runs; the old
  store's idempotent `insert` is gone. Fixtures written as "the whole
  document again" must become "what the write adds".
- **Under `.Record` a violation commits.** The next `apply` is validated
  against a dataset that still violates until something repairs it.
- **Terms are not epoch-scoped; facts are.** A term resolves at every
  epoch, including before it was first written; `store_at(0)` resolves a
  graph label and reads an empty graph through it. One compiled model
  binds at any epoch.
- **Language tags lowercase on intern** and `rdf.equal_term` is byte-wise
  on the tag, so a produced report renders `@en-nz` where a document said
  `@en-NZ`. The SHACL corpus has exactly two uppercase-tagged literals and
  neither reaches an expected report (T-0033); sparql's corpus is larger
  and its results formats render tags — check before assuming.
- **Non-canonical numerics are distinct terms** from canonical inlined ones
  (`"01"^^xsd:integer` vs `"1"`); inlineable literals are always
  resolvable (a small canonical integer named in a query is *bound* even
  if absent from the data — T-0032's third shift).
- **Triple terms are refused by `apply`** (`.Unsupported_Term` at the op)
  — 20 of sparql's vendored data files carry them; a recorded backend
  limit on sparql's side, not a skip list to hide.
- **Read counts survived the port to the integer** (T-0036): the engine
  asks record exactly the questions it asked LMDB; `validate` is ~4×
  faster (4.69 → 1.17 ms), `compile` ~4× (146 → 35 µs), peak memory the
  old 32-bit figure. Expect the same shape for sparql: timings move,
  pins do not.
- **The `Validator` binding** (`shacl/validator.odin`) is the pattern for
  any engine that wants to judge writes: caller-owned state, `check` over
  the candidate snapshot, report on the caller's allocator, reset per
  apply, a `Failure` is a refusal. Decision 5: the log does not record a
  verdict.
- **Call-site transformation patterns that worked**: `Test_DB`/`Guard_DB`/
  `Graph_Store` (open over `Mem_FS`, ingest + apply, pin the head
  snapshot on first session, release before close; never copied after
  open — the writer points at the `Mem_FS` inside); `blank_prefix` =
  label characters only; `base` = the manifest's base for documents with
  relative IRIs; three fork agents per test-file batch worked for T-0032's
  ~20 files.
- **Say it plainly in the handoff**: shacl's no-dual-backend and
  one-and-only-store decisions were made for shacl; sparql asks the owner,
  not assumes.

**5. `docs/language-tag-status.md`**: the finding to fold in is T-0033's
— the exposure is resolved *on record* for term identity, and latent for
report rendering (byte-wise `equal_term`); nothing in the corpus moved.
Flag the parser-side fold for family discussion; do not rescind it here.

**6. Family side** (`odin-rdf/.github`, the family root — its own git
repo; commit and push there): the record section's "not a replacement"
stance is already superseded in text; add `v0.2.0`/`v0.3.0` and the
visibility note; the shacl section must say: one package over record, no
`shacl/kvstore`, no width matrix, no `purity`, the `Validator`, as-of via
`store_at`, `make bench` two builds, pin `v0.3.0`. The "Handoff for the
sibling ports" paragraph becomes "shacl's port is done; sparql's is next",
pointing at this task's handoff. The Metis MCP has no workspace at the
family root; edit the file directly.

**7. Process, unchanged**: the metis CLI from the repo root (`metis
transition <CODE> <phase>`, `metis sync` after editing a file directly);
the owner's loop is finish → report → "transition and commit" → commit to
`main` with the family message style and the Claude trailer; **no push
unless told**. Redundant import aliases fail `make check` now — write
`import "record:record"`, never `import record "record:record"`.

**2026-08-20, evening — implemented, all criteria met; awaiting review.**
Documentation and comments only; no library change. `make check` and `make
test` green after the comment edits (shacl 125, guards 13, readme 7, smoke 1,
harness 23). CI is green on all three runners at `a21d751` against
`odin-rdf-record@v0.3.0` (2026-08-20 18:26Z) — the run the previous handoff
said had not happened yet. Nothing committed, nothing pushed; both
repositories (this one and the family root `odin-rdf/.github`) hold the
changes in their working trees for the owner's review.

**What was amended, by criterion.**

- **`.metis/vision.md`** — a dated block at the head of Current State says what
  is true now (backend, one package, the six session verbs, the two owner
  decisions verbatim, the 98, the `Validator`, `store_at`, T-0036's numbers and
  the read-count finding, the `v0.3.0` floor, the two term-identity shifts), and
  the old text stands below a rule with dated notes beside each falsified
  sentence: the Purpose and Overview store references, "both backends, both
  widths", the Packages/`purity` paragraph, the dependency paragraph, the
  T-0030 as-of paragraph (now `store_at`), the store-capabilities bullet, the
  language-tag bullet. Future State's "any odin-rdf-store backend" and the
  success criterion "exclusively through odin-rdf-store's public match
  interface" are **retired** with dated notes naming the narrower surviving form;
  the Principles "consume the interface" line, and both store-naming
  Constraints, are amended.
- **`docs/language-tag-status.md`** — a dated amendment at the top folds in
  T-0033's finding in both directions: term identity resolved on the record
  (tags fold on intern, so the `sh:hasValue`/`sh:in` residual is closed and the
  "spurious violation today" sentence is no longer true here), and report
  rendering newly latent (byte-wise `equal_term`; the corpus's two uppercase
  tags both conform, so none reaches an expected report). The parser-side fold
  is **flagged for family discussion, not rescinded**; "neither store dictionary
  changes" is noted as no longer accurate.
- **`docs/store-proposal.md`** — annotated: addressed to a store this
  repository no longer consumes; the blank-node suggestion moot (the record
  interns labels as `ingest` hands them over, so the collision is constructed,
  and the harness test was rewritten to construct it); the near-misses survived
  the port unchanged; STORE-T-0019 answered by construction by a pinned
  snapshot. **`docs/store-evidence.md`** closed with a dated note (not in the
  AC; it is the proposal's evidence and would otherwise read as open).
- **`SHACL-A-0001`** — a 2026-08-20 Amendments entry per decision: 1 (compiled
  from a snapshot through the session, generic over nothing, the file helper
  gone, read-only-compile now by type), 2 (`record.Term_ID`), 3 (the
  backends-disagree justification gone, the arena a stronger one), 5 (bound in
  one file; STORE-T-0017 moot), the compile-once caveat's new shape
  (`.Already_Live` under one prefix, duplicates under two), and the retired
  positive consequences. **`SHACL-A-0002`** — an Amendments section for the
  prose: the entry point's signature and "wrapper per instantiation package",
  "the store access", where `test_qualified_both_bounds_violate` lives, the
  suppress tests' real store.
- **`README.md`** — intro, status line, Packages (one package; the seam history
  in one paragraph), Building (collections, the `v0.3.0` floor and why, the
  three `make` targets as they are, no width, the alias rule, two bench builds,
  the POSIX/`mem_file_ops`/python3 notes), **Quick start replaced with
  `tests/readme`'s bodies verbatim** (the README's one stated difference kept:
  `posix_file_ops()` over a directory where the tests use `Mem_FS`), "Scratch
  datasets" → "Scratch stores" (`Mem_FS`, the don't-move rule, release before
  close), the three-consumer examples on `se` with the current
  `conforms_node`/`validate_node` argument order, the blank-node table for
  prefixed labels and the `blank_prefix` rule, the inlineable-literal note, the
  memory contract's arena wording, "Validation reads one graph" on the record.
- **Source comments** (the stragglers T-0032/33 listed): `model.odin`,
  `intern.odin`, `value.odin` (two places, incl. `tests/purity`),
  `value_test.odin`, `result.odin`; `tests/w3c/README.md`'s "both backends at
  both widths" line. `shacl.odin`, `session.odin`, `validator.odin`,
  `validator_test.odin` and `bench/` keep their deliberate historical
  references unchanged.
- **`docs/handover-sparql.md` / `docs/handover-catalogue.md`** — dated
  translation notes at the top (inherited item): `COLL`, `tests/purity` gone and
  what replaces its assertion, seam item 6 → a session verb, item 5 →
  `record.Term_ID`, the language-tag and evidence-log bullets, the triple-term
  limit for the `sparql/` suite.
- **Family side** (`odin-rdf/.github`, `CLAUDE.md`, uncommitted): the intro's
  LMDB sentence, the diagram, the record section's `v0.2.0`/`v0.3.0` and
  visibility note, "What moves next" and "Handoff for the sibling ports"
  superseded to "shacl's port is done; sparql's is next" pointing here, the
  shacl section rewritten above its (kept) four contracts, the sibling-checkout
  and dual-width conventions, the Commands block.
- **Every claim checked against the built code**: session verbs and their
  count, `Node_Ref.bound`, `session_outgoing` as `sh:closed`'s verb,
  `store_open`'s parameters and four returns, `conforms_node`/`validate_node`/
  `validate_node_report` signatures, `Snapshot_Error.Future_Epoch`,
  `snapshot_epoch_meta`, `posix_file_ops`/`mem_file_ops`, where
  `test_qualified_both_bounds_violate` lives, the record's three tags, CI's
  refs, the T-0036 table.

**Not done, deliberately:** no release tagged (the owner's act; `v0.2.0` is the
obvious number and the annotated-tag convention is `Release vX: title` with a
bulleted body); nothing filed on the record's or parser's side (the
negative-`column` observation RECORD-T-0017 owes the parser is still unfiled —
raise with the owner first); the family `CLAUDE.md` is edited, not committed.

---

## The handoff for odin-rdf-sparql's port (written 2026-08-20)

Where the sparql initiative's author should start. The family `CLAUDE.md` points
here; `SHACL-I-0004`'s design sections and the Status of T-0031 … T-0036 have
the detail behind each line.

**Say it first: shacl's two governing decisions — no dual-backend period at any
point, and odin-rdf-record as the one and only store forever, with every seam
that existed to span backends deleted — were made by the owner *for shacl*.
sparql asks the owner whether they apply, and does not assume.** Everything
below is what was learned; none of it is a decision for the sparql repository.

**What the port cost.** One day, seven tasks, one session per task.
`shacl/kvstore` (807 library lines, ~5,100 test lines), the `Access` struct,
`Term_Loader`/`Term_Finder`, the parapoly `$MATCH` seam, `tests/purity`, the
width matrix and the `store:` collection deleted; `shacl/session.odin` (~200
lines) added; the harness port was three files. The `v0.3.0` adaptation was
105 sites, mechanical, one commit. Three record releases were cut from what
the port found (`v0.2.0` ingest set-semantics, `v0.3.0` distinct id types) — the
record changed where the *record* was wrong or untyped, and nowhere else.
Expect sparql's to cost more in one place: its corpus is 5x larger and carries
triple terms (below).

**Pin `v0.3.0` or later, as a floor.** Below `v0.2.0`, `apply` refuses a
document that states a triple twice (`ingest` emitted the list, not the set);
below `v0.3.0`, an engine holding `record.Term_ID` does not compile. Hold the
record's types natively (`Term_ID`, `Fact_ID`, `Epoch`), not `u32`.

**Record facts an engine must know** — each one cost a test or a fixture here:

- *A candidate is the delta.* Re-asserting a live quad is `.Already_Live` at the
  op, judged before any validator runs. Fixtures written as "the whole document
  again" become "what the write adds". The old store's idempotent `insert` is gone.
- *Under `.Record` a violation commits.* The next `apply` is judged against a
  dataset that still violates; a "reset" needs a repair, not an unrelated write.
- *Terms are not epoch-scoped; facts are.* A term resolves at every epoch,
  including before it was first written; `store_at(0)` resolves a graph label
  and reads an empty graph through it. One compiled artefact binds at any
  epoch. `store_at` past head is `.Future_Epoch`, refused rather than clamped.
  The as-of coordinate is the epoch — there is no `epoch_at(wall)`; `wall` in
  `snapshot_epoch_meta` is advisory.
- *Language tags lowercase on intern*, and `rdf.equal_term` is byte-wise on the
  tag, so a produced result renders `@en-nz` where a document said `@en-NZ`. The
  SHACL corpus has exactly two uppercase tags and neither reaches an expected
  report; **sparql's results formats render tags and its corpus is larger —
  check before assuming.** `docs/language-tag-status.md` here carries the
  family-level question (the parser-side fold), flagged, not rescinded.
- *Non-canonical numerics are distinct terms* from the inlined canonical ones
  (`"01"^^xsd:integer` vs `"1"`), and *inlineable literals are always
  resolvable* — a small canonical integer named in a query is bound even if
  absent from the data. Term identity is RDF's; value equality is the engine's.
- *Triple terms are refused by `apply`* (`.Unsupported_Term` at the op). Twenty of
  sparql's vendored data files carry them: a recorded backend limit on sparql's
  side, stated as such, not a skip list to hide.
- *Blank-node labels are the document's, under the loader's `blank_prefix`*, which
  must be label characters (`t1_`, not `t1/`) and is the `Load_Scope`. Two
  documents under one prefix sharing a label collide by construction — which is
  what you want when that is the test.
- *A read cannot fail.* The projection is resident; the error slot and the
  `*_error` check after every entry point that the kvstore instantiation carried
  were deleted here, not ported. An empty answer is the answer.
- *`session_term` borrows* — the dictionary arena or the caller's buffer
  (`Term_Buf`, `record.INLINE_LEXICAL_MAX`); clone what you keep. Closing the
  store frees the arena, so anything that outlives a store owns its terms.

**The read side in one breath.** `0` is unbound in a `Pattern`,
`MATCH_DEFAULT_GRAPH` binds the default graph in G; `Filter{origin = .Any}` —
origin must be stated; `range_iter`/`scan_next` stream fact ids, `snapshot_fact`
reads one; `snapshot_kind` replaces `id_kind`; `snapshot_exists` for the
existence question; `snapshot_epoch_meta` carries actor/reason/wall. A
`Snapshot` is acquire/use/release; `store_destroy` asserts every snapshot was
released. The consumer id range for an engine's own values is
`CONSUMER_ID_FIRST ..= CONSUMER_ID_LAST` — shacl uses exactly one
(`GRAPH_ABSENT`, the binding of a graph label the store has never seen).

**Call-site patterns that worked.** A harness store type (`Test_DB`/`Guard_DB`/
`Graph_DB`/`Graph_Store`): `Mem_FS` + `store_open(&s, "x", mem_file_ops(&fs))`,
load every document with `ingest.<format>(src, graph, allocator, blank_prefix,
base)` + `apply` + `ops_destroy`, pin the head snapshot on first session,
release before `store_close` — and **never copy or move it after open** (the
writer points at the `Mem_FS` inside; returning one by value segfaults). `base`
is needed for documents with relative IRIs (the W3C inputs). Shapes/query
artefacts compiled from a scratch store that is closed before the data store
opens, to keep the owns-its-terms proof live on every entry. Three fork agents
per test-file batch worked for ~20 files. Odin gotcha: `&m[k]` on a map with
the key absent is `nil`, not an inserted zero — insert first.

**The `Validator` binding** (`shacl/validator.odin`) is the pattern if sparql
ever wants to judge writes: caller-owned state, a `check` over the candidate
snapshot that retains nothing, output on the caller's allocator, reset per
apply, a `Failure` is a refusal. Decision 5: the log does not record a verdict.

**Performance shape to expect.** Read counts survived shacl's port to the
integer because the engine's questions were never backend-shaped; timings
moved ~4x on validate (an LMDB cursor became a range over a resident
permutation) and allocation totals shrank with native `u32` ids. If sparql has
read pins, expect them to hold; if it has timings, expect them to move. (It has
neither today — `bench/` does not exist there.)

**CI.** Replace the store checkout with `odin-rdf/odin-rdf-record` at
`ref: v0.3.0` (`actions/checkout@v5`, `path: odin-rdf-record`), keep the parser
checkout, drop any width override; `rdf:` stays in `COLL` because the record's
sources import it. Windows compiles the record without its posix file; the
suites must open stores over `mem_file_ops`. No `python3` needed for a consumer.