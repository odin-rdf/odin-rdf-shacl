---
id: the-full-suite-on-record-every
level: task
title: "The full suite on record: every harness call site ported, all 98 W3C core entries green, the width matrix removed"
short_code: "SHACL-T-0033"
created_at: 2026-08-20T15:20:02+00:00
updated_at: 2026-08-20T17:06:55.219294+00:00
parent: SHACL-I-0004
blocked_by: [SHACL-T-0032]
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: SHACL-I-0004
---

# The full suite on record: every harness call site ported, all 98 W3C core entries green, the width matrix removed

## Parent Initiative

[[SHACL-I-0004]]

## Objective

Finish what SHACL-T-0032's boundary left: the W3C runner and every
remaining test file — ~300 call sites across 20 files before the
port — moved onto `Mem_FS` + `ingest` + `apply`, with **all 98
entries of the W3C SHACL 1.0 suite's `core/` tree green** against
record, no skip list, no expected-failure file. The dual-width
matrix leaves the Makefile and CI with the store that owned it
(record's widths are fixed by design).

## Acceptance Criteria

- [ ] Every `open_ephemeral` + `load_turtle` + close becomes
      `Mem_FS` + `store_open(&s, name, mem_file_ops(&fs))` +
      `ingest.turtle(src, graph, allocator, blank_prefix = <scope>,
      base = …)` + `apply` + `ingest.ops_destroy` + `store_close`
      (every snapshot released first — `store_destroy` asserts it).
- [ ] `blank_prefix` scoping: prefixes derived from test identity and
      sanitized to **label characters** (`t1_`, not `t1/` — W3C
      entry names contain path separators). Two documents loaded
      under different prefixes keep distinct blank nodes; the suite's
      report-isomorphism checks still pass.
- [ ] `base` supplied where documents carry relative IRIs (the W3C
      inputs resolve against their vendored locations, as the record
      repo's own ingest-by-reference suite does).
- [ ] The ops-own-their-terms contract observed: source buffers
      outlive `apply`; `ops_destroy` after.
- [ ] All 98 `core/` entries green; the suite-progress
      instrumentation (SHACL-T-0009's) reports the same totals as
      before the port.
- [ ] The width matrix (`-define:RDF_STORE_TERM_ID_BITS` legs) is
      gone from Makefile and CI; if not already removed in T-0032,
      `store:` is gone from `COLL`, `ols.json` and the CI checkout —
      after this task the repository's dependencies are
      odin-rdf-parser and odin-rdf-record, and no LMDB is in any
      link.
- [ ] `make test` and `make check` green on all CI legs, Windows
      included (suites run over `mem_file_ops`).

## Implementation Notes

The term-identity corpus check from the initiative's design §5 is
settled here by running, not by argument: the expectation is that no
entry moves on lowercased language tags or non-canonical numeric
forms. If an entry does move, record it in Status — it feeds the
`docs/language-tag-status.md` amendment in SHACL-T-0037 — and
resolve it as an expected-behavior change only with the evidence
written down.

## Status Updates

**2026-08-20 — session handoff, written at a context break just after this
task went active.** T-0031 and T-0032 are completed and committed
(`5e77479`, `3d08720`); this task has produced no code yet — only the
phase transition (uncommitted) and a read of every harness file. What the
next session needs beyond the initiative and T-0032's Status:

**1. The port surface is three files.** Only `runner.odin` and
`report_test.odin` touch the store; `runner_test.odin` touches the
`Backend` enum. `harness_test.odin`, `manifest.odin`, `suite.odin`,
`compare.odin`, `compare_test.odin` are parser-based and port untouched.

**2. The runner plan, decided by reading.** Delete `Backend` and
`backend_name` outright — the "seam a second backend would use" comment is
exactly what the owner ruled out — and `run_entry(r, dir, e)` loses its
`backend` and `tag` parameters (`tag` existed to name LMDB temp stores;
`Mem_FS` needs none). `run_kvstore` becomes `run_record`: shapes store in
a scoped block (open over `Mem_FS`, `ingest.turtle(src, nil, allocator,
blank_prefix = "b", base = shapes_base)` + `apply`, `store_latest`,
`session_init`, `compile`, release + close — preserving the
model-outlives-its-store proof per run), then the data store the same
way, `bindings_init`, `validate_report`. Detail mapping: an ingest error
is "graph failed to parse", an apply error "could not be loaded"; every
`session_error` check is deleted. In `runner_test.odin` the
`for backend in Backend` loop collapses to one run and `origin` drops the
backend name.

**3. `report_test.odin` needs its own mini-harness** — package w3c cannot
see shacl's package-private `Test_DB`; copy the `Guard_DB` pattern from
`tests/guards/guards.odin` (open/load/session/close, ~50 lines).
`term_id` becomes `session_resolve`; `report_add(&r, &shapes, result, se)`.
**The blank-nodes-standardised-apart test needs a real rewrite**: it
relies on both stores densely minting `b0`, which `ingest` does not do
(labels are the document's, prefixed). Rewrite its two fixtures with
explicitly-labelled blanks sharing one label (e.g. `_:n0` in both
documents) loaded under the same `blank_prefix`, so the collision the
test exists to catch is constructed rather than inherited.

**4. An unverified risk to check first when entries run: language-tag
case in report isomorphism.** Record lowercases tags on intern, so a
produced report renders `"Hill"@en-nz` where the expected report parsed
from the suite document says `@en-NZ` (`property/languageIn-001` has
exactly this literal). If `report_isomorphic`/`rdf.equal_term` compares
tags byte-wise, such entries mismatch — that would be the corpus evidence
the initiative's design §5 anticipated, to be recorded here and fed to
T-0037's `docs/language-tag-status.md` amendment (and decided with the
owner, not silently patched in the harness). The other shift — inlineable
literals always resolve — is already recorded in T-0032's Status and
cannot affect isomorphism.

**5. After the harness is green, the build cleanup this task owns:**
restore `tests/w3c/harness` to `PKGS`; delete the `WIDTHS` matrix from
`test` and `bench` targets (and CI's Windows `test_widths` override with
its comment); remove `-collection:store` from `COLL`, the `store` entry
from `ols.json`, the odin-rdf-store checkout from `ci.yml` (its header
says "Three checkouts" since T-0031 — becomes two, parser + record);
`make bench` should fail with a note naming T-0036 rather than a missing
collection. `bench/` still *textually* imports store — it is outside all
build lists until T-0036, which is why `store:` could not leave at
T-0032.

**6. Gotchas that cost this session time, none in any document:**
(a) a `Test_DB`/`Guard_DB` must never be copied or moved after open — the
writer holds a pointer to the `Mem_FS` inside the struct; returning one
by value segfaults. (b) `tdb_session` pins the head snapshot on first
call — load every document before the first session. (c) `session_term`
borrows (arena or the caller's `Term_Buf`); test code clones via
`test_term` into the temp allocator. (d) `record.store_open` returns
four values, `apply` returns `(epoch, conforms, err)`, and
`Apply_Error{}` is the success value. (e) The suite runner's expected
reports come from `expected_report(tf, e)` — parsed triples, no store
involved.

**7. Process.** The metis CLI works from the repo root
(`metis transition/list/view`); after editing a `.metis` file directly,
run `metis sync`. The owner's loop this session: finish task → report →
they say "transition and commit" → commit to main with the family message
style and the Claude trailer, then continue to the next unblocked task.
The three fork agents used for T-0032's test port worked well (their
files vetted clean on first compile); the same pattern fits nothing left
here — T-0033's remaining work is small enough to do directly.
**2026-08-20 — implemented, all criteria met; awaiting review.**

**The result.** All 98 `core/` entries green against odin-rdf-record, no
skip list, no expected-failure file; `tests/w3c/harness` 23 tests, back in
`PKGS`. `make test` green across the five packages (shacl 109, guards 12,
readme 5, smoke 1, harness 23) under `ODIN_TEST_FAIL_ON_BAD_MEMORY`; `make
check` green; `odin check -target:windows_amd64` clean for every package.
The repository's dependencies are odin-rdf-parser and odin-rdf-record; no
`store:` collection, no LMDB in any link, no width matrix.

**The port, as done.** Three files, as the handoff read: `runner.odin`,
`report_test.odin`, `runner_test.odin`. `Backend`/`backend_name` deleted,
`run_entry(r, dir, e)` — no backend, no `tag`. One package-private
`Graph_DB` (open / load / session / close over `Mem_FS`, the `Guard_DB`
shape) lives in `runner.odin` and serves both the runner and the report
tests rather than being copied into each; `GRAPH_BLANK_PREFIX :: "b_"` is
the one load scope (label characters; begins with neither `r` nor `s`, the
report's two reserved prefixes). The shapes store still lives in a block
that closes before the data store opens — the per-entry model-outlives-
its-store proof is preserved. `gdb_load` returns a three-way
`Load_Outcome` so "failed to parse" (the entry's problem) and "could not be
loaded" (the harness's) stay distinct; an ingest with zero ops loads as
nothing rather than hitting `apply`'s `.Empty`. `base` is
`MANIFEST_BASE + file`, as before. The standardised-apart test is rewritten
as the handoff prescribed: both fixtures label their unrelated blank node
`_:n0`, loaded under the same prefix, so the collision is constructed —
and the engine keeps them apart (`sb_n0` vs `b_n0`).

**Finding 1 — a W3C document that `apply` refuses as written, and the
dedup it forced.** The first run was 97 of 98: `core/complex/shacl-shacl`'s
shapes graph came back "could not be loaded". Probed outside the harness:
`Apply_Error{.Already_Live, op 79}` on `shsh:ShapeShape
sh:targetSubjectsOf sh:qualifiedValueShape`. The source
(`shacl-shacl-data-shapes.ttl` lines 75–76) lists `sh:qualifiedValueShape`
and `sh:qualifiedValueShapesDisjoint` *twice each* in one object list — a
legal Turtle document that states two triples twice. `ingest.turtle` emits
an op per statement, and `apply` judges each assert against the changeset's
own earlier ops by documented rule (`apply.odin` "What a changeset may not
do"; `log.md` §5.3), so the second assert is refused. An RDF graph is a set,
and a document denotes one; the harness's `gdb_load` now deduplicates the
ops of a document before they are a changeset (`distinct_ops`: hash
buckets over `rdf.hash_quad`, verified by `rdf.equal_quad`, first
occurrence kept, order preserved; the kept slice borrows, the original is
destroyed). **This is document set-semantics, not a backend accommodation,
but its permanent home is a question for the record's `ingest`** — a
document loader whose output `apply` refuses for a valid document is a gap
on that side, and `ingest`'s doc comment says nothing about duplicates
either way. Not filed on the record's side: cross-repo changes are raised
with the owner first. The engine's own `tdb_load` (hand-written fixtures)
needs no dedup and got none. odin-rdf-sparql's port will hit the same thing
on any vendored data file with a repeated statement — handoff material for
T-0037.

**Finding 2 — the language-tag corpus check, settled by running (design
§5).** No entry moved. The corpus holds exactly two uppercase-tagged
literals: `"Hill"@en-NZ` (`property/languageIn-001`) and `"G'day"@en-AU`
(`node/datatype-002`), and both *conform* to their constraints, so neither
reaches an expected report as `sh:value`/`sh:focusNode`. The exposure is
real and latent rather than absent: record lowercases tags on intern,
`session_term` hands the lowercased form back, and `rdf.equal_term`
compares `Literal`s structurally (byte-wise `language`), so an entry whose
expected report carried an uppercase-tagged literal would mismatch on
isomorphism. `sh:hasValue`/`sh:in` with tagged literals: none in the corpus.
Feeds T-0037's `docs/language-tag-status.md` amendment, as the task notes
anticipated; nothing patched in the harness. The third shift T-0032 found
(inlineable literals always resolve) cannot affect isomorphism and did not.

**Build cleanup, done here.** `COLL` is `rdf:` + `record:`; `ols.json`
matches; `ci.yml` has two dependency checkouts (parser `v0.1.0`, record
`v0.1.0`), the store checkout gone with a short paragraph recording the
floor history it carried (T-0020/-0028/-0029/-0030) and the Windows
`test_widths` override gone with the matrix; the header's LMDB-linkage
rationale for the platform matrix is replaced by what the three runners
prove now (record compiles without its posix file; suites run over the
memory seam). `WIDTHS` and both width loops deleted from the Makefile;
`make bench`/`build-bench` print a note naming SHACL-T-0036 and exit
non-zero instead of failing on a collection no longer declared; `bench/`
stays outside every build list until T-0036. On the AC's "SHACL-T-0009's
suite-progress instrumentation reports the same totals": the progress floor
was retired at SHACL-T-0019 (`suite.odin`); what survives of it is the
`TOTAL_ENTRIES`/`ENABLED_ENTRIES` pins, and they assert 98/98 as before.

**Left for T-0037 (docs pass), noted so it is not lost:** prose in
`shacl/{shacl,model,value,value_test,intern,result,session}.odin` still
names `Term_ID`, `kvstore` or "both widths"; `README.md` still describes
the LMDB-backed store and the width matrix; `tests/readme`'s
validate-before-commit note points at T-0034.

**Gotcha added to the handoff's list:** `&m[k]` on an Odin map with the key
absent is `nil`, not an inserted zero value — `append` through it segfaults
every test in the package at once. Insert first.

**2026-08-20, later — Finding 1 resolved upstream, the harness dedup
deleted.** The owner chose option A: `ingest` now emits a document's *set*
of statements (odin-rdf-record `RECORD-T-0019`, released as `v0.2.0`).
`distinct_ops` and its justification are gone from `runner.odin`;
`gdb_load` is the plain `ingest` → `apply` the handoff described, and
`core/complex/shacl-shacl` loads through it — all 98 entries green, `make
test`/`make check` green, against the fixed checkout. The CI pin moved to
`odin-rdf-record@v0.2.0` **as a floor** (the comment records why: below it
that one entry cannot load). The sparql port inherits the fix rather than
the trap; the handoff note for T-0037 reduces to "pin `v0.2.0` or later".