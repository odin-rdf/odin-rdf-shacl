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

