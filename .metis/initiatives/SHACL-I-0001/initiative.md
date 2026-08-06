---
id: shacl-core-spine-shapes-model
level: initiative
title: "SHACL Core spine: shapes model, targets, paths, and the validation report"
short_code: "SHACL-I-0001"
created_at: 2026-08-06T13:15:22.298190+00:00
updated_at: 2026-08-06T13:58:01.879894+00:00
parent: SHACL-V-0001
blocked_by: []
archived: false

tags:
  - "#initiative"
  - "#phase/decompose"


exit_criteria_met: false
estimated_complexity: L
initiative_id: shacl-core-spine-shapes-model
---

# SHACL Core spine: shapes model, targets, paths, and the validation report Initiative

## Context **[REQUIRED]**

First initiative under SHACL-V-0001, in a repository that holds only a `Makefile`,
`ols.json`, `LICENSE`, and the vision. Every dependency is complete and tagged v0.1.0
(vision, 2026-08-06): odin-rdf-parser for shapes and report graphs, odin-rdf-store for
the match interface with two conforming backends, odin-rdf-sparql for the later
SHACL-SPARQL phase only.

**The structural fact that decides this initiative's shape.** odin-rdf-sparql could make
its first initiative "the front half" — query text to algebra — because SPARQL has W3C
*syntax* suites: a spec-defined measuring point halfway down the pipeline. SHACL has no
equivalent. Every entry in the W3C SHACL test suite is *data graph + shapes graph →
validation report*, so nothing is measurable until shapes loading, target resolution,
value-node computation through paths, and report emission all exist at once.

That rules out the otherwise-obvious "shapes model first" initiative. The shapes model is
this project's equivalent of the algebra contract — the thing every later initiative
consumes — but the algebra earned its shape by being designed against a suite that could
hold it honest. A shapes model built with no validator consuming it and no suite scoring
it would be a contract designed blind.

So the first initiative is a **spine**: the seven things every suite entry exercises
regardless of which constraint it tests, plus enough of the constraint catalogue to prove
the spine end to end against real suite directories. The catalogue itself — roughly thirty
mechanically similar components, plus the logical and shape-based constraints that need a
recursion policy — is the second initiative, built against a spine whose evidence has
already shaped it. Per-suite-directory progression, the family's established convention,
becomes the incrementality mechanism within each.

**Upstream repositories are read-only from this project (2026-08-06, Greger).** The three
sibling repos are shipped and tagged with large conformance suites and performance
baselines to keep green. Where this initiative needs something from them, it produces
evidence and a written proposal for human review — it does not edit them. Two places in
this initiative are expected to hit that boundary; both are called out in Detailed Design
and gated in the Implementation Plan.

## Goals & Non-Goals **[REQUIRED]**

**Goals:**

- **Repo scaffolding in the family style** — package layout (`shacl` plus per-backend
  instantiation packages), `PKGS` pinned to an explicit list in the `Makefile` (discharging
  its own note that discovery "cannot express intent about what belongs"), a CI workflow
  from odin-rdf-store's template *including* the LMDB platform constraint, and the
  `tests/guards` and `tests/readme` conventions established with the first package rather
  than retrofitted.
- **W3C SHACL test suite vendored and a manifest-driven harness** — pinned upstream commit
  with a provenance README, manifests parsed with the family's own Turtle parser, pinned
  per-directory entry counts, no skip list and no expected-failure file (enabled means
  fully green), and `sht:Failure` entries counted and handled rather than quietly dropped.
- **Shapes graph loading and compilation** — a shapes graph read into a compiled shapes
  model: node shapes and property shapes, target declarations, paths, constraint
  parameters, `sh:severity`, `sh:message`, `sh:deactivated` — with ill-formed shapes
  detected and reported in the family's position-carrying error style.
- **Target resolution** — the SHACL Core target declarations resolved to focus nodes
  through the match interface alone, including implicit class targets and `rdfs:subClassOf`
  reachability.
- **Property paths** — the full Core path grammar compiled and evaluated to value nodes,
  with cycle-safe reachability over `Term_ID`s for the zero-or-more and one-or-more forms.
- **Validation reports** — `sh:ValidationReport` / `sh:ValidationResult` graphs emitted
  through odin-rdf-parser with the spec's result properties, plus the programmatic result
  API for embedding.
- **A constraint-dispatch seam, and the minimal constraint set the target and path suites
  themselves exercise** — cardinality (`sh:minCount`/`sh:maxCount`), `sh:class`,
  `sh:datatype`, `sh:nodeKind` — enough to green whole suite directories and prove the
  spine, with the seam shaped for the catalogue initiative to fill.
- **A store-evidence log**, in the SPARQL-I-0002 pattern: every point where validation
  wants something the match interface cannot answer is recorded with the concrete shape or
  target that wants it, and shaped into a written proposal at the end.

**Non-Goals:**

- **The rest of the SHACL Core constraint catalogue** — value-range, string, and
  property-pair components, `sh:closed`, `sh:in`/`sh:hasValue`, `sh:languageIn`/
  `sh:uniqueLang`, the logical combinators (`sh:and`/`sh:or`/`sh:not`/`sh:xone`), and the
  shape-based constraints (`sh:node`, `sh:qualifiedValueShape`). Second initiative.
- **Editing any upstream repository.** Store-interface gaps and the term-identity fix
  produce evidence and proposals for review; the edits themselves are out of scope here.
- **SHACL-SPARQL** — `sh:sparql` and SPARQL-based constraint components, with the
  `sparql:` collection the `Makefile` reserves a slot for. Later phase, per the vision.
- **SHACL Advanced Features** (rules, functions), inference/entailment, and any server or
  protocol layer — out of scope at the vision level, permanently.

## Architecture **[CONDITIONAL: Technically Complex Initiative]**

### Overview

Two stages with a compiled model between them, mirroring the way the SPARQL project splits
translation from evaluation:

1. **Shapes compilation** — the shapes graph (itself ordinary RDF) is read through the
   match interface and compiled into a shapes model: a flat, indexable representation of
   shapes, their targets, their paths, and their constraint parameters, with well-formedness
   checked during compilation rather than during validation.
2. **Validation** — for each shape, targets resolve to focus nodes; for each focus node, the
   shape's path (if any) produces value nodes; each constraint component is dispatched
   against the focus node and its value nodes. Every read of the data graph is a `match`
   call. Results accumulate into a report, streamed rather than materialized where the
   spec allows.

Backend binding follows the store's procedure-set convention and odin-rdf-sparql's resolved
answer to the same question (SPARQL-T-0011): a backend-independent core package plus thin
per-backend instantiation packages, so a Core-only, in-memory consumer never links LMDB.

The compiled shapes model holds `rdf.Term` values, not `Term_ID`s — the shapes graph and the
data graph may live in different stores with different dictionaries, so binding to the data
store's IDs happens once at validation setup, exactly as odin-rdf-sparql's term-binding
bridge does for algebra constants.

## Detailed Design **[REQUIRED]**

Resolved in the design phase (2026-08-06, decided with Greger). Each item below is settled;
where reopening it is conceivable, what would do so is stated.

- **The data graph is one caller-named graph — decided.** SHACL is specified against a
  single RDF graph; the store holds a quad dataset, so the API must say which graph it
  reads. `validate` takes that graph — the default graph or one named graph — which makes
  the graph position a constant in every `match` call and makes conformance mean what the
  spec says it means. Union-of-all-graphs was rejected: the spec defines no semantics for
  it, which would make suite results indefensible. A union mode stays addable later as an
  explicit, documented opt-in.

  **This retires one of the vision's two predictions.** STORE-T-0017 (a named-graph
  wildcard in the graph position) was predicted here entirely on the assumption of
  dataset-wide validation. Under a single named graph it is not needed, and this initiative
  does not expect to want it.

  **A user-facing consequence to document prominently:** `sh:class` walks
  `rdfs:subClassOf*` **in the data graph**, so a class hierarchy has to live in the graph
  being validated, not in the shapes graph. It is a common surprise, and the single-graph
  decision sharpens it.

- **Shapes are compiled from a store, through `match` — decided.** Shapes compilation is
  random-access by nature: follow `sh:property` to a blank node, then read that node's
  `sh:path`, `sh:minCount`, `sh:class`. A streaming parser delivers document order, so
  compiling from the stream means buffering the whole graph and building an index — a store,
  reimplemented worse. Compilation is generic over the backend, so a shapes graph persisted
  in kvstore compiles; the convenience path (Turtle file → memstore → compile) lives in
  `shacl/memstore`, keeping the core package free of any backend dependency.

- **The shapes model owns its terms — decided, and coupled to the above.** The model holds
  `rdf.Term` values rather than `Term_ID`s, because the shapes graph and the data graph may
  be different stores with different dictionaries. Since the shapes store may be destroyed
  after compilation, and `lookup_term` borrows on memstore but allocates on kvstore, the
  model **interns** every term it holds and frees them at `shapes_destroy`. Shapes graphs
  are small and bounded, so ownership costs little and removes a lifetime coupling that
  would otherwise be load-bearing. Binding to the data store's `Term_ID`s happens once at
  validation setup, as odin-rdf-sparql's term-binding bridge does for algebra constants.

  One asymmetry with SPARQL, stated before it is discovered the hard way: a constant absent
  from the data store means the *opposite* thing for a constraint than for a pattern. SPARQL
  short-circuits an absent term to an empty result; a `sh:class ex:Foo` whose class term is
  absent makes every value node **violate**. Absence is not emptiness here.

- **Recursion: detect and report failure — decided.** The spec leaves recursive shapes
  undefined and permits a processor to signal a failure rather than support them. Detection
  is nearly free — the explicit-stack evaluator below already carries the set of shapes
  currently on the stack. Cycle-breaking ("assume valid on re-entry") stays addable later
  without redesign if evidence asks for it.

  Recorded because the project's first real use case invites the confusion: shapes over
  assets that point at assets (`iso:partOf`, `iso:hostedOn`). Those are `sh:class`
  constraints — plain type checks that never re-enter a shape — so **cycles in the data are
  not recursion**. The day someone rewrites one as `sh:node`, they get a reported failure
  rather than a hang. That is the intended behaviour and belongs in the docs, not just here.

- **Reports carry only the messages a shape declares — decided.** No processor-generated
  `sh:message` triples in the report graph, which keeps suite comparison exact blank-node
  isomorphism with no fuzzy-match policy anywhere in the harness. Human-readable explanation
  belongs to the programmatic result API, where it costs nothing and misleads no comparison.

- **Results stream; the report graph is a pass over them — decided.** The programmatic API
  delivers results as they are found and holds no violation set; report-graph emission is
  built on top. This keeps the family's streaming preference, keeps memory flat exactly when
  the data is worst, and admits early exit — "does this conform?" stops at the first
  violation, which matters at ~200 processes per machine.

- **Language-tag case: fold to lowercase at literal construction in odin-rdf-parser —
  decided; the edit is deferred behind an explicit trigger.** This discharges the question
  the vision parked here. Folding is what BCP 47 case-insensitivity implies, what §3.3's
  "the value space of language tags is always lower case" points at, and what Jena and RDF4J
  do.

  **Trigger (Greger, 2026-08-06): should a W3C SHACL suite entry fail for this reason, work
  stops and the fix is made in odin-rdf-parser at that point.** Until then the decision is
  recorded and nothing upstream is touched. The exposure sits entirely in the catalogue
  initiative — `sh:uniqueLang`, `sh:hasValue`, `sh:in` — and cannot reach this initiative's
  exit criteria. `sh:languageIn` is immune either way: SHACL defines it by BCP 47 basic
  filtering, which RFC 4647 makes case-insensitive regardless of how terms are interned. The
  trigger matters more than the entry count, because under "enabled means fully green" a
  single entry disables its whole suite directory.

  **The implementation shape, established now so the proposal is ready rather than
  researched under pressure: detect in the scanner, fold in the constructor.** The scanner
  already walks every byte of a tag to find its end and validate its character class, so
  case detection is an OR into an accumulator over bytes it is already reading — no extra
  pass, no branch, and the all-lowercase path (essentially all real RDF) keeps its borrowed
  slice with zero copies and zero allocations, leaving RDF-A-0001 and the benchmark
  baselines intact. A tag that does carry uppercase is folded through the existing
  `rdf.Intern_Table`, which already serves expanded prefixed names and synthesized labels.
  Folding must live in the *constructor*, not the scanner alone, because literals are also
  built programmatically — odin-rdf-sparql's `STRLANG`, and SHACL itself — and a hand-built
  `"x"@EN` disagreeing with a parsed one is the exact bug being fixed; the scanner passes
  its detection flag in so the hot path skips work it has already done. With literals
  arriving pre-folded, neither store dictionary changes and there is no on-disk format
  question. The cost that remains real: databases already written with mixed-case tags hold
  terms a folded lookup will not find.

  Settled by spec rather than by us, and recorded so it is not relitigated — language-tag
  case was the *only* open part of term identity. IRIs and datatype IRIs are **never**
  normalized (RDF 1.1 Concepts §3.2, Simple String Comparison: "further normalization MUST
  NOT be performed"); lexical forms compare code-point-wise with no Unicode normalization;
  and `"1"^^xsd:integer` versus `"01"^^xsd:integer` is the term/value distinction, not a
  normalization question — it surfaces in SHACL (`sh:hasValue` compares terms,
  `sh:minInclusive` compares values) but offers nothing to choose.

- **Backend binding — inherited, not re-decided.** SPARQL-T-0011 resolved this against the
  same store: a backend-independent core plus thin instantiation packages, with the hot path
  monomorphized through compile-time `$`-procedure constants. Its decisive finding applies
  unchanged — kvstore `foreign import`s a static LMDB archive, so a core that imported it
  would put LMDB into the link of every Core-only consumer. Package layout: `shacl`,
  `shacl/memstore`, `shacl/kvstore`; `find_term` reaches the core as an ordinary procedure
  pointer, as it does there.

- **Evaluator shape — flat array, explicit stack, adopted deliberately.** SPARQL-T-0011
  found that a generic procedure taking `$`-procedure constants and calling itself sends the
  Odin compiler (dev-2026-07) into unbounded instantiation — it hangs rather than failing,
  and a self-referencing parametric struct does the same. SHACL's evaluator is naturally
  recursive where SPARQL's operator tree was not, so the precedent (`sparql/plan.odin`) is
  adopted from the first line rather than discovered at `sh:node`: children named by index
  in a flat array, and a stack-driven walk. That same stack carries the recursion detection
  above at no extra cost.

- **Memory and lifetime contract.** The family contract: `*_init` takes a trailing
  `allocator := context.allocator`, the object owns what it allocates until `*_destroy`, and
  borrowed slices are documented as such. The shapes model's ownership is settled above; the
  streaming result path is the one to hold to a stated per-result allocation budget, enforced
  by `tests/guards`.

- **Store capabilities — one prediction retired, one still a hypothesis.** STORE-T-0017 is
  not needed, per the single-graph decision. STORE-T-0016 (dataset introspection) stays a
  hypothesis the evidence log tests rather than a dependency to pre-commit to: Core target
  resolution looks like ordinary match patterns — `sh:targetSubjectsOf` and
  `sh:targetObjectsOf` are predicate-position matches, class targeting is `rdf:type` plus
  `rdfs:subClassOf` reachability. Whatever the log finds becomes a written proposal for
  review, not an edit and not a ticket filed upstream.

- **SHACL-A-0001 records the shapes model** — representation, term ownership, and graph
  scoping — as a standing decision with review triggers, outliving this initiative because
  initiatives 2 and 3 both program against it. The family's ADR practice is split
  (odin-rdf-store four, odin-rdf-parser two, odin-rdf-sparql none), and the shapes model is
  judged to warrant one.

## Testing Strategy **[CONDITIONAL: Separate Testing Initiative]**

Suite-driven, inheriting the sibling projects' mechanics verbatim:

- **The W3C SHACL test suite defines done.** Vendored under `tests/w3c/<suite>/` from
  `w3c/data-shapes` at a pinned commit, with a provenance README recording commit, license,
  directory mapping, and exclusions. Manifests are parsed with the family's own Turtle
  parser. Suite directories are enabled one at a time with pinned entry counts; enabled
  means fully green. The directory inventory and its exact names are confirmed at vendoring,
  which is the first task's job.
- **Dual-backend discipline** — every enabled suite runs against memstore *and* kvstore,
  asserting identical results, extending the store's own conformance pattern.
- **Dual-width discipline** — the `Makefile`'s 64/32 `Term_ID` matrix covers everything;
  validation is width-sensitive by nature.
- **Unit tests** — path evaluation against hand-built stores including cyclic data; target
  resolution per declaration form; shapes compilation error cases asserting exact positions;
  report structure.
- **Allocation guards** — `mem.Tracking_Allocator` guards over the validation paths, holding
  whatever the memory contract promises.
- **README-as-contract** — `tests/readme` compiles the README's examples, per SPARQL-T-0009.

## Alternatives Considered **[REQUIRED]**

- **Shapes-loading only (the odin-rdf-sparql-shaped "front half" split)**: rejected. It is
  the natural analogue of SPARQL-I-0001, but the analogy breaks on the one fact that matters
  — SHACL has no syntax suite, so a shapes-model-only initiative has nothing to define done
  and would ship the project's central contract with no consumer and no score. The suite
  cannot grade any part of SHACL until it can grade a report.
- **Scaffolding and harness only**: rejected as too thin, the same judgement SPARQL-I-0001
  made. Vendoring and the harness skeleton are the natural first tasks *inside* an
  initiative, not a deliverable on their own.
- **All of SHACL Core in one initiative**: rejected. One design phase is attractive and the
  suite directories would give incrementality, but the catalogue is roughly thirty components
  plus a recursion policy, which is XXL — and more to the point, the catalogue's design is
  better made against a spine that has already produced evidence than guessed alongside it.
- **Defer the validation report to a later initiative**: rejected. It sounds like a clean
  separable layer, and it is the one thing that makes the spine measurable — the suite
  compares reports. Without it the initiative's exit criteria could only be self-asserted.
- **The full path grammar deferred, predicate paths only in the spine**: rejected. It would
  shrink the initiative, but value-node computation *is* the property-shape mechanism, the
  suite has a directory dedicated to paths, and splitting path support across two
  initiatives means designing the value-node interface twice.

## Implementation Plan **[REQUIRED]**

Rough phasing; proper decomposition happens at the decompose phase. Eight tasks are the
expected shape:

1. **Scaffolding** — package layout, pinned `PKGS`, CI from the store's template with the
   LMDB platform constraint, `tests/guards` and `tests/readme` skeletons.
2. **Suite vendoring + harness** — pinned commit, provenance README, manifest reader,
   per-directory enablement with pinned counts, report comparison by blank-node isomorphism.
3. **Shapes model + compilation** — the model types and the shapes-graph loader, with
   ill-formed-shape detection. Carries **SHACL-A-0001** (shapes model: representation, term
   ownership, graph scoping), written alongside the model rather than after it.
4. **Paths** — compilation and value-node evaluation, cycle-safe reachability.
5. **Target resolution** — all Core target declarations, including implicit class targets
   and `rdfs:subClassOf` reachability.
6. **Validation report** — result graph emission and the programmatic result API.
7. **Constraint dispatch + the minimal set** — cardinality, `sh:class`, `sh:datatype`,
   `sh:nodeKind`; first suite directories green against both backends at both widths.
8. **API, docs, and the evidence write-ups** — public API documented to the family contract
   standard, README example under `tests/readme`, and the two review-gated write-ups below.

**Two items are explicitly gated on human review and must not be executed unilaterally:**

- **The language-tag fix in odin-rdf-parser.** The decision is made (fold to lowercase at
  literal construction) and the implementation shape is designed, but the edit lands only on
  its trigger: a W3C SHACL suite entry failing for this reason, at which point work stops and
  the fix is made — with review, and with bench numbers showing the hot path unchanged. No
  suite entry in *this* initiative can trigger it.
- **The store-evidence log** is consolidated into a written proposal. It is brought to
  review; it is not filed into odin-rdf-store's Metis and not worked around locally.

**Exit criteria:** the suite's target and path directories green with pinned entry counts
and zero unexpected failures, against both backends at both `Term_ID` widths; validation
reads the data graph exclusively through the published match interface; reports verified by
blank-node isomorphism against the suite's expected graphs; zero dependency on
odin-rdf-sparql; public API documented to the family contract standard with a
README-as-contract test; the two review-gated write-ups delivered.

## Status Updates

- **2026-08-06 — Decomposed into 8 tasks** (SHACL-T-0001 … SHACL-T-0008): scaffolding →
  suite vendoring + harness → shapes model + SHACL-A-0001 → paths → targets → results and
  report → constraint dispatch and first green directories → API, docs, and evidence
  write-ups.

  **Dependency shape.** T-0001 gates everything. T-0002 (suite) and T-0003 (model) are
  independent of each other and can run in parallel. T-0004, T-0005, and T-0006 all depend
  only on T-0003 and can run in parallel with one another. T-0007 is the join point — it
  needs T-0002, T-0004, T-0005, and T-0006 — and is where the exit criteria are actually
  tested. T-0008 closes.

  **Two refinements found during decomposition, recorded rather than silently absorbed:**

  1. **"Position-carrying error style" does not transfer to shapes.** The Goals section
     inherits that phrase from the family's parsers, where an error has a byte offset, line,
     and column. A shapes graph arrives as triples in a store — the text is gone, and may
     never have existed if the graph was built programmatically. The equivalent precision is
     graph-shaped: name the shape node, the parameter at fault, and the spec section
     violated, keeping the family's other error conventions (flat `Error_Kind`, no message
     string in the struct, static allocation-free `error_message`). Carried in SHACL-T-0003.
  2. **Recursion detection is proven in T-0007, not deferred with `sh:node`.** `sh:node` is
     a catalogue constraint, but the detection mechanism belongs to the spine's evaluator, so
     the spine tests it with a self-referencing shape even though the constraint that reaches
     it lands later.

  Both review-gated items are acceptance criteria rather than closing notes: the
  store-evidence write-up and the language-tag status are checkboxes in SHACL-T-0008, and
  T-0005 starts the evidence log that feeds the first. SHACL-A-0001 is finalised inside
  SHACL-T-0003, alongside the model it describes, rather than after it.

  Awaiting human review before transition to active.

- **2026-08-06 — Design decisions resolved with Greger; transitioned to design.** Seven
  decisions settled, written into Detailed Design:

  1. **Data graph = one caller-named graph** (not a dataset union) — and this retires the
     vision's STORE-T-0017 prediction, since the named-graph wildcard was only wanted for
     union semantics.
  2. **Shapes compile from a store through `match`**, generic over the backend, with the
     Turtle-file convenience path in `shacl/memstore`.
  3. **The shapes model interns and owns its terms**, so it outlives the store it was
     compiled from.
  4. **Recursion: detect and report failure** — spec-sanctioned, and nearly free given the
     explicit-stack evaluator.
  5. **Reports carry only shape-declared `sh:message`**, keeping suite comparison exact.
  6. **Results stream**, with report-graph emission as a pass over them; early exit
     supported.
  7. **Language-tag case: fold to lowercase at literal construction in odin-rdf-parser** —
     the vision's parked question, discharged. Implementation shape designed (detect in the
     scanner, fold in the constructor, hot path unchanged); the edit waits on an explicit
     trigger, below.

  **Upstream boundary, restated with the trigger Greger set:** should a W3C SHACL suite
  entry fail on language-tag case, work stops and the fix is made in odin-rdf-parser then —
  not before, and with review. Nothing in this initiative's scope can trigger it; the
  exposure is in the catalogue initiative.

  Also decided: **SHACL-A-0001** will record the shapes model (representation, ownership,
  scoping), against the family's split ADR practice — the store has four, the parser two,
  odin-rdf-sparql none.

  Next: write SHACL-A-0001, then transition to ready for decomposition.

- **2026-08-06 — Created in discovery.** Scope drafted: the SHACL Core spine — scaffolding,
  suite harness, shapes compilation, paths, targets, reports, and the minimum constraint set
  that proves them — with the full Core catalogue and SHACL-SPARQL as later initiatives. The
  scope boundary rests on one structural fact: SHACL has no syntax suite, so nothing is
  measurable until a report can be produced, which makes a spine the smallest gradable first
  deliverable. Upstream repos are read-only from this project; the term-identity decision and
  the store-evidence log produce proposals for review rather than edits. Awaiting human
  review of scope and the design-phase decision list.