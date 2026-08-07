# Handover to the SHACL-SPARQL phase

Written at the close of SHACL-I-0002 (the SHACL Core constraint catalogue), in
the shape of [`handover-catalogue.md`](handover-catalogue.md), which SHACL-I-0001
wrote for this initiative and which is still worth reading for the seam and for
what the spine deliberately left open.

**Where the project stands.** SHACL Core is complete: all twenty-nine constraint
components of §4 that do not need SPARQL, shape discovery to §2.1.1, all five
target forms, all seven path forms, suppressed validation (SHACL-A-0002), and
`sh:ValidationReport` emission. **All 98 entries of the vendored W3C SHACL 1.0
`core/` suite pass**, against both backends, at both `Term_ID` widths, with no
skip list and an empty ignored-parameter record throughout.

## Read this first: `core/complex` is already green

The single most important correction this initiative produced, and it changes
what the SPARQL phase is for.

SHACL-I-0002 declared `core/complex` a non-goal, on the documented belief that
its two entries need `sh:sparql`, `sh:shapesGraph`, and `sh:entailment` — and
that `shacl-shacl` passed only because an engine that ignores a constraint
produces the conforming report it expects. **All of that was wrong**, and reading
the corpus at SHACL-T-0019 is what said so:

- `sh:sparql` occurs exactly once in `shacl-shacl-data-shapes.ttl`, as an object
  of `sh:targetSubjectsOf`. `sh:shapesGraph` and `sh:entailment` occur as objects
  of `sh:targetObjectsOf`. All three are *targeted vocabulary* — SHACL's own
  shapes saying "anything that is the subject of a `sh:sparql` triple is a
  shape" — not constraint parameters. Nothing in that file asks for a query
  engine.
- The green is not inaction, and this is measured rather than argued. The
  ignored-parameter record is empty for both entries, and breaking `sh:datatype`
  or `sh:nodeKind` in the evaluator turns **both** of them red. An engine that
  was doing nothing would leave `shacl-shacl` green under any breakage at all.

So the SPARQL phase does **not** inherit a red directory. What it inherits is
`data-shapes-test-suite/tests/sparql/`, which is not vendored yet, and which is
therefore the phase's first task rather than its last.

The lesson is more general than the fact: the belief survived a discovery phase,
a design phase, a decomposition, and ten task write-ups, because every one of
them was reading the previous one. Nobody read the file until the closing task.

## Where the `sparql:` collection goes

Three places, and the `Makefile` says so at the line that defines `COLL`:

```make
COLL := -collection:rdf=../odin-rdf-parser -collection:store=../odin-rdf-store
```

1. **`Makefile`** — append `-collection:sparql=../odin-rdf-sparql` to `COLL`.
2. **`ols.json`** — mirror it, or the language server stops resolving imports.
3. **`tests/purity`** — the linkage property check. Today it asserts that a
   core-plus-memstore consumer carries no LMDB symbols. The SPARQL phase's
   equivalent question is whether SHACL **Core** still links no query engine, and
   that is a property worth asserting the same way rather than trusting: put the
   SPARQL-based components behind their own package, the way `shacl/kvstore`
   holds LMDB, so that `import "shacl"` never pulls the query engine in.

The vision's constraint is unchanged and is the reason for all three: **SHACL
Core must have zero dependency on odin-rdf-sparql**, at runtime and at link time.

## The seam, as it actually is now

`handover-catalogue.md` described adding a constraint component as four edits.
That was true of the spine's seven and is not true in general. The current count
is in the header of `shacl/check.odin`, kept there because that is where someone
adding a component will be looking:

1. `Constraint_Kind` in `shacl/model.odin`.
2. Its parameter in `compile_constraints` (`shacl/constraints.odin`).
3. Its scope in `constraint_scope` (`shacl/check.odin`).
4. A case in `check_value` or `check_node_set`.
5. **`bindings_init` in `validate.odin`**, for any component comparing its
   parameter by `Term_ID`. SHACL-T-0015 found this the hard way: a component
   missing from that kind-switch does not fail, it reads its parameter as unbound
   and reports nothing. Four components compiled, dispatched, ran, and found an
   empty set on every focus node.
6. And, rarely, a new read verb on `Access` — `sh:closed` needed the predicate
   and object of one triple together, which none of the three existing verbs
   could express.

Plus two vocabulary constants in `shacl/vocab.odin`.

**Scope and blame are two questions, not one.** A value-scoped component is asked
once per value node; a set-scoped one is asked once about the whole set. What a
result *names* in `sh:value` is separate: `sh:equals` is set-scoped and emits one
result per member of the symmetric difference, each naming a node that is not a
value node at all.

## Two practices worth carrying, both of which paid

**Read the corpus entries before writing the component.** Every component family
this initiative added had exactly one detail that contradicted the obvious
implementation, and in each case the obvious version passed every test written
for it. Five families, five traps; they are enumerated in `shacl/check.odin`'s
header. The entries take a few minutes to read and the alternative is a component
that looks right.

**Confirm the tests bite by breaking the implementation.** Every component task
from SHACL-T-0016 onward deliberately broke what it had just built and checked
that the right tests failed. It found a genuinely weak test in SHACL-T-0018 — one
that passed with *both* of its guards removed — and the corpus entry it was
modelled on turned out to share the weakness. SHACL-T-0019 used the same
technique to establish that `core/complex`'s green is real. It is cheap and it is
the only thing that distinguishes a test from a comment.

## What SHACL-I-0002 left open

- **Duplicate results are not deduplicated — deliberately open, with a trigger**
  (Greger, 2026-08-07). A shape that is both a root and another shape's
  `sh:property` value is validated twice at the same focus node and reports twice.
  §3.4 arguably makes results a set. **No entry in all 98 exercises it**, which is
  a stronger statement than the spine could make — the corpus is now fully run.

  That is exactly why it needed a decision rather than another deferral: there is
  no forcing evidence in this corpus and there never will be, so left alone it
  would have stayed open by default forever while reading like an oversight.
  **Trigger: a consumer reporting it, or a SHACL 1.2 / SHACL-SPARQL suite entry
  that distinguishes the two readings.** Until then the behaviour is what it is,
  and it is a recorded decision rather than a gap.
- **`sh:detail` is not implemented, and is a known omission rather than an
  oversight.** It appears nowhere in the vendored corpus, in any directory. The
  shape-based constraints would naturally nest a child's results under a
  parent's; a consumer asking for richer reports reopens it, and it is a `Result`
  field plus a `Report` change.
- **Conformance answers are not memoised — settled, and no longer open.**
  SHACL-A-0002 deferred this until measured cost justified it; SHACL-I-0003 built
  `bench/` and SHACL-T-0025 pulled the trigger. **The answer is no cache**, and
  the ADR's *As Measured* section carries the numbers. The duplicate is real —
  a property shape with both bounds walks its value nodes twice, costing +1000
  reads, +1.2 MB of total allocation, and ~11% of validation on a 500-focus-node
  configuration — but a `(shape, node)` cache is the wrong instrument for it.
- **What replaces it, and it is the one open engine change this project leaves
  behind.** Both bounds share one `sh:qualifiedValueShape` and one value-node
  set, so they could **share one walk**: compile them into a single constraint,
  count once, test the count twice. That removes the reads *and* the bytes with
  no hot-path lookup and no live memory, and it dominates a cache on every axis
  under every allocator. Deliberately not implemented — SHACL-T-0025 was scoped
  to decide the cache — and recorded with its numbers already taken, which is
  what a future task needs to act on it. `compile_constraints` and
  `check_qualified` are the two procedures involved.
- **The `sh:pattern` dialect gap.** `core:text/regex` is not XML Schema's regex
  language. `s` and `q` are rejected at compile time rather than ignored, and the
  common subset is what the corpus uses. Unmeasured beyond that, deliberately.
- **Language-tag case.** `docs/language-tag-status.md`, refreshed here. The
  trigger did not fire and now cannot: the whole corpus runs green, and the two
  components that read language tags (`sh:languageIn`, `sh:uniqueLang`) fold at
  the point of comparison because SHACL requires it of them. The residual
  exposure is `sh:hasValue` and `sh:in`, which compare terms; no entry exercises
  that combination. **The recommendation changed**: extend the trigger to "a suite
  entry fails **or** a user reports it", because the suite has demonstrated it
  will not raise the alarm.
- **The store-evidence log stays open**, and has now produced two findings in
  eleven tasks — neither of them a capability gap. `docs/store-evidence.md` has
  both. The one thing that may be worth offering upstream is a sentence of
  documentation: the store's blank-node labels are dense from `b0` per
  dictionary, so two dictionaries collide by construction, and any consumer
  merging terms from both into one graph must standardise them apart.

## The progress floor, and getting it back

SHACL-T-0009 built a non-gating per-entry floor for the disabled directories,
because per-directory enablement gave this initiative no signal until nearly
every component existed. It moved 18 → 21 → 31 → 42 → 49 → 51 → 63 across the
component tasks and did exactly what it was for.

**SHACL-T-0019 retired it** — `floor_test.odin`, the `floor` field on `Suite`,
and `PROGRESS_FLOOR` — because a floor measures disabled directories and there
are none left.

**The SPARQL phase will want it back the day it vendors `sparql/`**, and should
restore rather than reinvent it:

```
git show SHACL-T-0019~1 -- tests/w3c/harness/floor_test.odin
```

What must come back with it is the caveat it printed on every run: a count is a
direction of travel, not a conformance claim, because an entry expecting
`sh:conforms true` passes whether it was validated or ignored.

## Where to read the design

- `.metis/adrs/SHACL-A-0001.md` — the shapes model, term ownership, graph
  scoping.
- `.metis/adrs/SHACL-A-0002.md` — suppressed validation, and why a sub-run shares
  the outer walk's stack.
- `shacl/shacl.odin` — the package contract: the memory rules and the nine things
  a caller has to know.
- `shacl/check.odin` — the seam, with the scope reasoning and the corpus-reading
  habit at the top.
- `shacl/report.odin` — the report graph, and the three blank-node namespaces it
  keeps apart.
- `tests/w3c/README.md` — the corpus, its provenance, and what the suite can and
  cannot see.
- `bench/` — the synthetic workload, its seven knobs, and the two measurement
  modes. Its package doc says plainly what the numbers are not: a workload this
  project chose, so a regression instrument rather than a claim about the world.
