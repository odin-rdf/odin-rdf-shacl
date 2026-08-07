---
id: the-shacl-core-constraint
level: initiative
title: "The SHACL Core constraint catalogue: the rest of §4"
short_code: "SHACL-I-0002"
created_at: 2026-08-06T19:09:51.760962+00:00
updated_at: 2026-08-07T10:39:45.213399+00:00
parent: SHACL-V-0001
blocked_by: []
archived: false

tags:
  - "#initiative"
  - "#phase/completed"


exit_criteria_met: true
estimated_complexity: XL
initiative_id: the-shacl-core-constraint
---

# The SHACL Core constraint catalogue: the rest of §4 Initiative

## Context **[REQUIRED]**

Second initiative under SHACL-V-0001, and the one SHACL-I-0001 was scoped to make possible.
The spine is complete and tagged done (2026-08-06): shapes compilation, target resolution,
property paths, constraint dispatch, validation results, and `sh:ValidationReport` emission
all work end to end, through the store's match interface alone, against both backends at both
`Term_ID` widths. Four of the W3C suite's seven `core/` directories are green.

What it deliberately did not do is the constraint catalogue. The spine implements **seven**
components — `sh:minCount`, `sh:maxCount`, `sh:class`, `sh:datatype`, `sh:nodeKind`,
`sh:hasValue`, `sh:in` — chosen by measuring what its exit-criteria directories actually
exercise rather than by what looked foundational. This initiative is the other **~23**.

**The scope is measured rather than estimated.** A diagnostic run at the spine's close, with
`core/node` and `core/property` temporarily enabled, found **18 of their 69 entries already
pass** on the spine's seven components. So the work is **51 entries**, not 69, and the spine's
components are already exercised more broadly than the 26 enabled entries prove.

**The structural fact that decides this initiative's shape.** SHACL-I-0001's shape was decided
by SHACL having no syntax suite, so nothing was measurable until a report could be produced.
That constraint is gone — every entry here is gradable the day its components land, and
per-directory enablement gives fine-grained incrementality. What decides *this* initiative's
shape instead is that **the catalogue is not uniform**. Most of it is mechanically similar
value comparison that the existing seam absorbs with four small edits per component. A
minority — the logical combinators and the shape-based constraints — needs two things the
engine does not have, and one of them is an architectural change rather than a feature. Those
two groups should not be planned as though they were the same work.

**Upstream repositories remain read-only from this project.** The store-evidence log
(`docs/store-evidence.md`) and the language-tag status (`docs/language-tag-status.md`) both
carry forward; neither is restarted. The spine's proposal asked odin-rdf-store for nothing,
and the one question that recurs — set membership — has its answer written down.

**The suite target is SHACL 1.0** (Greger, 2026-08-06). SHACL 1.2 is still moving in the W3C;
a suite that goes green against a specification that can change under it is worth less than it
looks. This initiative is scoped against the 1.0 corpus and its remaining entries. Review
trigger in `tests/w3c/README.md`.

## Goals & Non-Goals **[REQUIRED]**

**Goals:**

- **The rest of the SHACL Core constraint catalogue** (§4), in the groups below — value-range,
  string-based, property-pair, logical, shape-based, and `sh:closed`.
- **Shape discovery widened to §2.1.1.** The spine recognises three ways a node becomes a
  shape; the spec also makes one a shape by being the value of `sh:node`, `sh:not`, `sh:and`,
  `sh:or`, `sh:xone`, or `sh:qualifiedValueShape`. Every one of those is a component this
  initiative adds, so this is its **first** task rather than a consequence of the later ones.
- **Conformance without results** — the ability to ask "does this node conform to this shape?"
  as an internal question whose results do not reach the caller. `sh:not`, `sh:or`, `sh:xone`,
  and `sh:qualifiedValueShape` all need it, and the engine has no way to do it today. This is
  the initiative's one architectural change and wants an ADR.
- **Lexical-to-value conversion** for the value-range components — and, with it, the
  well-formedness half of `sh:datatype` that the spine left as recorded debt
  (`core/property/datatype-ill-formed` is the entry that forces it).
- **A decision on unrecognised constraint parameters.** They are silently ignored today. For
  seven-of-thirty that was the only option; for an engine claiming SHACL Core it is a defect,
  and it is what makes "18 entries already pass" softer than it sounds — an engine that does
  nothing also produces a conforming report.
- **`core/node` and `core/property` green**, per-directory, pinned counts, no skip list,
  against both backends at both `Term_ID` widths — the family's rule unchanged: enabled means
  fully green.
- **The store-evidence log continued**, not restarted. The recurring question is set
  membership; `sh:node` and `sh:qualifiedValueShape` will ask it again.

**Non-Goals:**

- **SHACL-SPARQL** — `sh:sparql` and SPARQL-based constraint components, and with them
  `core/complex`, whose two entries need `sh:sparql`, `sh:shapesGraph`, and `sh:entailment`.
  Later phase; do not size this initiative around that directory.
- **SHACL Advanced Features** (rules, functions), inference and entailment regimes, and any
  server or protocol layer — out of scope at the vision level, permanently.
- **SHACL 1.2** — decided above.
- **Editing any upstream repository.** Evidence and proposals for review, as before.
- **Result serialisation.** A report is `[]rdf.Triple`; writing it out is odin-rdf-parser's
  job through any of its four emitters, and that is the "primitives over frameworks" line.

## Architecture **[CONDITIONAL: Technically Complex Initiative]**

### What is inherited and must not be re-decided

Everything structural is settled by SHACL-A-0001 and the spine's implementation, and this
initiative programs against it rather than revisiting it: the flat shapes model with
index-named children and an explicit stack (forced by the Odin compiler's unbounded
instantiation, SPARQL-T-0011); term ownership by the compiled model; one caller-named data
graph; backend binding through a backend-independent core plus thin instantiation packages;
recursion detected and reported as a failure.

**The dispatch seam is four edits per component** and none of them is in the evaluator: a
`Constraint_Kind`, its parameter in `compile_constraints`, its scope in `constraint_scope`,
and a case in `check_value` or `check_node_set`. Plus two vocabulary constants.

**Scope is the edit most likely to be got wrong.** A value-scoped component is asked once per
value node and blames it, so its result carries `sh:value`; a set-scoped component is asked
once about the whole value-node set and carries none. `sh:hasValue` is set-scoped and `sh:in`
is value-scoped despite reading almost identically. The suite catches it immediately, which is
the good news; the bad news is that it produces plausible results in the meantime.

### The two things the engine does not have

**1. Suppressed validation.** The engine streams every result to the caller's visitor as it is
found — that is the design, and it is what makes early exit and flat memory work. But `sh:not`
needs to validate a node against a shape and report *the opposite* of what it found, emitting
none of the inner shape's results. `sh:or` and `sh:xone` need the same for each branch;
`sh:qualifiedValueShape` needs it and a count besides. Retrofitting this into six components
one at a time is how it goes wrong; designing it once, before any of them, is the whole reason
it is called out here. It also interacts with early exit in a way that needs stating: an inner
conformance check wants to stop at its first result, while the outer traversal must not.

**2. Values, not terms.** `sh:minInclusive` and friends compare *values* across numeric
datatypes, where everything in the spine compares terms — by `Term_ID`, which is why the
engine is fast. This is a genuinely different kind of comparison and it is also what
`sh:datatype`'s missing well-formedness check needs. Build it once.

## Detailed Design **[REQUIRED]**

Resolved in the design phase (2026-08-06, decided with Greger). Two are settled below; the
rest stay open for the tasks that reach them, and each says what would settle it.

- **Task order is risk-first (2026-08-06, Greger).** The ADR and its implementation come
  third, before the mechanical families, rather than at task eight. Nothing in value-range,
  string, property-pair, or `sh:closed` needs suppressed validation, so deferring it would
  have delivered entries sooner — the cost is that the architectural change would then arrive
  with five more consumers built against assumptions about it, which is the exact shape this
  document warns about. The visible cost of the choice: **the progress floor barely moves for
  the first three tasks**, so early progress looks slow while the hard part is being retired.
  That is expected, and saying so here is what stops it being read as a stall.

- **How suppressed validation is expressed.** A nested `validate` with a null visitor? A
  `Conformance` sub-run sharing the outer stack? A flag on the frame? The constraint that
  makes it non-obvious: recursion detection is per-shape-on-the-stack, and an inner
  conformance check legitimately re-enters shapes the outer walk has open — or does it? That
  question needs answering before the mechanism is chosen, because the two answers give
  different designs. **Wants an ADR** (SHACL-A-0002).

- **Unrecognised constraint parameters: ignore, but expose — decided.** Compilation records
  every `sh:`-namespace predicate it saw on a shape and did not understand, readable from the
  compiled model; validation continues to ignore them.

  Erroring was rejected, and not narrowly: it would reject `sh:name`, `sh:description`,
  `sh:order`, and `sh:group` — **non-validating annotation properties the spec itself
  defines**, and `core/property` actually uses `sh:name`. Making that work needs a curated
  allow-list of every annotation property, which is a maintenance burden bought for nothing.
  Vendor extensions are the second reason: real shapes graphs carry them.

  Ignoring silently was rejected because it is what makes an incomplete engine look complete.
  Two of the eighteen entries that "already pass" expect a *conforming* report, and an engine
  that does nothing produces one too — so they cannot distinguish validation from inaction.
  Exposing what was ignored is cheap (a list on `Shapes`) and turns that from invisible into
  checkable. **The suite harness should assert it**: an enabled directory whose entries
  compiled with ignored `sh:` parameters is a directory whose green is suspect.

  One nuance the implementation has to carry: the list must distinguish **not implemented**
  from **known and non-validating**. `sh:name`, `sh:description`, `sh:order`, and `sh:group`
  are spec-defined annotations that no engine acts on, and a list that flagged them would cry
  wolf on every real shapes graph. They belong on a recognised-but-inert list, named as such.

- **`sh:pattern` uses `core:text/regex`, with the dialect gap documented — decided by
  measurement.** This looked like the initiative's expensive unknown: SHACL defines
  `sh:pattern` by XPath `fn:matches` (XML Schema regex) with flags `i s m x q`, while Odin's
  package offers `m i x u` — `s` and `q` absent, dialect different. Writing an XSD regex
  engine is a task on its own.

  Then the corpus was read. **The four `sh:pattern` entries use `^[2-8][0-9]*$`, `Aldi`,
  `joh`, and `Joh`, with one `sh:flags "i"`** — anchors, one character class, `*`, and
  case-insensitivity. Every one of those is in the common subset of any regex engine. So the
  gap is real but unmeasured, and building for it would be speculation.

  Ship `core:text/regex`, **document the divergence explicitly** (which flags are unsupported,
  and that the dialect is not XSD), and let a user report or a future suite entry force more.
  This keeps the family's no-external-dependencies constraint intact either way.

- **Numeric comparison across datatypes.** `sh:minInclusive 2` against `"2.0"^^xsd:decimal`,
  `xsd:byte` versus `xsd:integer`, and what happens for non-numeric datatypes. The spec defers
  to SPARQL operator mapping; odin-rdf-sparql has already solved a version of this and should
  be read before anything is written — **without importing it**, since SHACL Core must keep
  zero dependency on the query engine.

- **`sh:detail`: out of scope — decided by measurement.** Shape-based constraints would
  naturally nest a child's results under a parent's, and it looked like a required `Result`
  and `Report` change. It is not: **`sh:detail` appears nowhere in the vendored corpus**, in
  any directory. Since the suite defines done, adding it would be building an unmeasurable
  feature. Recorded as a known omission rather than an oversight; a consumer asking for
  richer reports reopens it.

- **Duplicate results.** A shape that is both a root and another shape's `sh:property` value
  is validated twice at the same focus node and reports twice. No enabled entry exercises it.
  §3.4 arguably makes results a set. If a catalogue entry disagrees, this is where to settle
  it; if none does, record that it stays open.

- **One initiative, not two — decided.** The split was considered: the mechanical families
  are wide and shallow, the structural ones narrow and deep, and separating them would give
  the ADR its own design phase. Rejected for now because it buys process and costs coherence —
  `core/node` and `core/property` are one suite goal, and splitting them across two
  initiatives means neither goes green until the second closes anyway. The decomposition below
  isolates the ADR as its own task instead, which is the thing the split was really protecting.
  Reversible: tasks can be reassigned to a second initiative if this one proves unwieldy.

## Testing Strategy **[CONDITIONAL: Separate Testing Initiative]**

Inherited from the spine unchanged, which is the point of having built it:

- **The W3C SHACL 1.0 suite defines done.** Already vendored at a pinned commit with
  provenance. Directories are enabled one at a time with pinned entry counts; **enabled means
  fully green** — no skip list, no expected-failure file. `ENABLED_ENTRIES` is pinned and
  asserted against both the table and the number the runner actually ran, so a silently
  skipped entry fails.
- **Dual-backend and dual-width** — every enabled entry runs against memstore and kvstore, at
  64- and 32-bit `Term_ID`, from the existing runner.
- **Unit tests per component** in `shacl/memstore`, in the pattern
  `validate_test.odin` established: the behaviours the suite either cannot reach or would
  report as one opaque report mismatch.
- **Allocation guards** — the new machinery to watch is suppressed validation, which allocates
  a nested walk per branch per value node and is the easiest place in the engine to strand
  memory. The existing guard over the abnormal exits is the template.
- **README-as-contract** — `tests/readme` compiles the README's examples; adding components
  should not change them, and if it does the README is wrong.

## Alternatives Considered **[REQUIRED]**

- **Follow §4's section order.** Rejected. The spec groups components by what they mean; this
  initiative should group them by what machinery they share, because the machinery is where
  the risk is. Value-range and `sh:datatype`'s well-formedness look unrelated in the spec and
  are the same task.
- **Add components until the directories go green, and design suppressed validation when
  `sh:not` arrives.** Rejected, and it is the tempting one: it defers an ADR and shows progress
  sooner. It also guarantees the mechanism gets shaped by whichever of the six needing it
  happens to land first, and retrofitted into the other five.
- **Fold the catalogue into the SHACL-SPARQL phase**, since `core/complex` needs both.
  Rejected: `core/complex` is two entries, and letting them drag a whole initiative's scope
  is the tail wagging the dog.
- **Take SHACL 1.2's larger suite now** and implement against it. Rejected by decision above.
- **Skip `sh:closed`** as low-value. Rejected: it is the one component that asks the store a
  question the spine never asked — the predicates a focus node actually *uses* — so it is the
  most likely source of new store evidence in this initiative, which makes it more interesting
  than its entry count suggests.

## Implementation Plan **[REQUIRED]**

**Risk-first order** (Greger, 2026-08-06): the architectural change is retired before the
mechanical families are built on assumptions about it. Eleven tasks.

1. **Suite progress instrumentation** — a non-gating per-entry floor for the disabled
   directories. Harness work, not engine work, and it goes first because without it this
   initiative has no incremental signal at all (see the Status Update below). Floor starts at
   18 of 69.
2. **Widened shape discovery** (§2.1.1), and the recognised-but-not-implemented parameter
   record. Prerequisite for everything that nests shapes.
3. **Suppressed validation, and SHACL-A-0002** — the one architectural change, designed and
   guarded before any consumer of it exists.
4. **Lexical-to-value conversion**, and the `sh:datatype` well-formedness debt it discharges.
5. **Value-range components** — `sh:minInclusive`, `sh:maxInclusive`, `sh:minExclusive`,
   `sh:maxExclusive`.
6. **String components** — `sh:minLength`, `sh:maxLength`, `sh:pattern`/`sh:flags`,
   `sh:languageIn`, `sh:uniqueLang`. Carries the regex divergence documentation.
7. **Property-pair components** — `sh:equals`, `sh:disjoint`, `sh:lessThan`,
   `sh:lessThanOrEquals`. Needs a second path evaluation from the focus node.
8. **`sh:closed` and `sh:ignoredProperties`** — the one component that asks the store a
   question the spine never asked, and so the likeliest source of new store evidence.
9. **Logical combinators** — `sh:and`, `sh:or`, `sh:not`, `sh:xone`.
10. **Shape-based constraints** — `sh:node`, `sh:qualifiedValueShape` and its three
    companions. `sh:node` gives the spine's recursion failure its first real exercise.
11. **Close** — `core/node` and `core/property` enabled and green, docs and README updated,
    store-evidence and language-tag write-ups refreshed for review, handover notes for the
    SHACL-SPARQL phase.

Tasks 4–8 are independent of each other and of 3, so they can run in parallel once 2 is in.
Tasks 9 and 10 both need 3. Task 11 needs everything.

**Exit criteria:** `core/node` (32) and `core/property` (38) green with pinned entry counts
and zero unexpected failures, against both backends at both `Term_ID` widths; every SHACL Core
constraint component of §4 implemented except those requiring SPARQL; validation still reads
the data graph exclusively through the published match interface; still zero dependency on
odin-rdf-sparql; public API documented to the family contract standard; the store-evidence and
language-tag write-ups brought to review.

## Status Updates

- **2026-08-07 — Completed. SHACL Core is done and the vendored corpus is 98 of 98.**

  Every exit criterion met, and two exceeded. Eleven tasks, SHACL-T-0009 through
  SHACL-T-0019, in the risk-first order decided at design.

  **What shipped.** All twenty-nine of §4's non-SPARQL constraint components; shape
  discovery widened to §2.1.1; suppressed validation and SHACL-A-0002; lexical-to-value
  conversion and the `sh:datatype` well-formedness debt the spine left; the
  ignored-parameter record. Validation still reads the data graph through the published
  match interface alone, and still has zero dependency on odin-rdf-sparql — asserted by
  `tests/purity`, not trusted.

  **The exit criteria said `core/node` and `core/property`. The suite is all seven
  directories, 98 of 98**, both backends, both `Term_ID` widths, no skip list. Two
  surprises took it past the target, and both are SHACL-T-0019's:

  1. **`core/property` and `core/complex` were blocked by the same defect, and it was
     neither a component nor the harness.** A report merges blank nodes from three graphs —
     its own, the data graph's, the shapes graph's — and both stores label loaded blank
     nodes densely from `b0`, *per store*. The emitter merged all three namespaces. One
     half the suite caught (`property/nodeKind-001` asserting `_:b3 sh:sourceShape _:b3`);
     the other half it structurally could not, because every `core/` entry names one file
     as both graphs, so conflating them is accidentally correct. Both fixed.
  2. **`core/complex` was never a SHACL-SPARQL directory**, contrary to this document's
     Non-Goals. `sh:sparql`, `sh:shapesGraph`, and `sh:entailment` appear in
     `shacl-shacl-data-shapes.ttl` only as *targeted vocabulary* — objects of
     `sh:targetSubjectsOf` and `sh:targetObjectsOf` — not as constraint parameters. The
     belief survived discovery, design, decomposition, and ten task write-ups because each
     was reading the previous one; nobody read the file until the closing task. Enabled,
     with its green measured rather than asserted: the ignored record is empty for both
     entries, and breaking `sh:datatype` or `sh:nodeKind` turns both red.

  **What the initiative's own design got right, and it is worth recording.** Two calls
  decided at design paid off exactly as argued:

  - **Risk-first ordering.** SHACL-A-0002 landed third, before any of its six consumers
    existed. Its cost was visible — the progress floor barely moved for three tasks — and
    the payoff is that no component was retrofitted onto it. SHACL-T-0017 moved the floor
    by twelve entries in one task, the largest single move of the initiative.
  - **The progress floor itself.** Built as SHACL-T-0009 because per-directory enablement
    gave this initiative no signal until nearly every component existed. It moved 18 → 21 →
    31 → 42 → 49 → 51 → 63 and did exactly what it was for. **Retired at SHACL-T-0019**,
    with no disabled directories left to measure; the SHACL-SPARQL phase restores it from
    `git show SHACL-T-0019~1 -- tests/w3c/harness/floor_test.odin`.

  **Where the design was wrong, recorded rather than absorbed.** `core/complex` above is
  the big one. Smaller: the seam was documented as four edits and is five — `bindings_init`
  resolves a constraint's parameter to a data-store ID from a kind-switch, and a component
  missing from it reads its parameter as unbound and silently reports nothing
  (SHACL-T-0015, four components affected). And `sh:closed` needed a fourth `Access` verb,
  which the store served with one ordinary `match`.

  **The two write-ups, both refreshed for review.** `docs/store-evidence.md`: two findings
  in eleven tasks, neither a capability gap, and **no proposal to odin-rdf-store**. The
  second is the first that is about the store at all — a *contract* rather than a missing
  verb: blank-node labels are dense from `b0` per dictionary, so two dictionaries collide
  by construction, and any consumer merging terms from both must standardise them apart.
  Documented only in the store's own `load.odin`; one sentence of upstream documentation is
  the only thing on offer, and it is a suggestion, not a proposal.
  `docs/language-tag-status.md`: the trigger did not fire and now cannot — the corpus runs
  in full, and the two components that read a tag fold at comparison because SHACL requires
  it. Residual exposure is `sh:hasValue` and `sh:in`, which compare terms. **Recommendation
  changed** to extending the trigger to "a suite entry fails *or* a user reports it".

  **Left open, deliberately.** No benchmark — `bench/` does not exist, so SHACL-A-0002's
  memoisation review trigger (*measured* cost) still cannot be pulled, and the qualified
  family provably asks the same `(shape, node)` question twice. Duplicate results are not
  deduplicated, and no entry in all 98 exercises it. `sh:detail` is absent and appears
  nowhere in the corpus. All three are in `docs/handover-sparql.md`.

  **Handover.** `docs/handover-sparql.md` — what the SPARQL phase inherits, where the
  `sparql:` collection goes in all three places, the seam as it actually is, and the two
  practices that paid: read the corpus entries before writing the component, and confirm
  the tests bite by breaking the implementation.

- **2026-08-06 — Transitioned to active; SHACL-T-0009 implemented and awaiting review.**
  The progress floor exists and is pinned, so every task after this one has a number that
  must move. The initiative's 18 of 69 reproduced exactly and now splits per directory:
  **`core/node` 7 of 32, `core/property` 11 of 38**, identical on both backends at both
  widths. `make test` and `make check` green; nothing under `shacl/` was touched.

  One thing decomposition did not anticipate: **`core/complex` passes 1 of its 2 entries
  today**, and it is pinned at 0 rather than 1. `shacl-shacl` expects `sh:conforms true` and
  needs `sh:sparql`, `sh:shapesGraph`, and `sh:entailment` — so what it demonstrates is
  ignoring, not validating. It is the sharpest instance of the hazard this document already
  named around `property/minCount-002` and `property/uniqueLang-002`, and it is fragile the
  other way too: as components land, that shapes graph starts producing real results and the
  entry may go red before it goes green for the right reason. Counted and printed,
  deliberately not pinned. The floor total therefore prints as 19 of 72 against a pinned 18;
  the catalogue's number is still 18 of 69.

- **2026-08-06 — Design decisions resolved with Greger; transitioned through design and ready
  to decompose.** Both open decisions settled, written into Detailed Design:

  1. **Unrecognised constraint parameters: ignore, but expose.** Compilation records the
     `sh:`-namespace predicates it did not understand; validation still ignores them. Erroring
     was rejected because it would reject the spec's own annotation properties — `sh:name` is
     used by `core/property`. Silence was rejected because it is what lets an incomplete
     engine look complete.
  2. **One initiative, not two.** The ADR is isolated as its own task instead, which is what
     the split was really protecting. Reversible by reassigning tasks later.

  **One thing the decomposition had to solve that the spine did not have.** The family's
  incrementality mechanism is per-suite-directory progression, and it does not work here: only
  two directories remain, and under "enabled means fully green" **neither can be enabled until
  nearly every component exists**. A ten-task initiative with no suite signal until task nine
  is exactly the shape that goes wrong quietly.

  So the first task is harness work rather than engine work: a **non-gating per-entry progress
  floor** for the disabled directories — how many of their entries pass today, pinned, asserted
  to only ever go up. It gates nothing and enables nothing, so the "enabled means fully green"
  rule is untouched, but every task after it has a number that must move. The floor starts at
  **18 of 69**, measured at SHACL-I-0001's close.

- **2026-08-06 — Decomposed into 11 tasks** (SHACL-T-0009 … SHACL-T-0019), in the risk-first
  order decided above.

  **Dependency shape.** T-0009 (progress floor) and T-0010 (widened discovery) are independent
  and gate nothing between them. T-0011 (suppressed validation + SHACL-A-0002) needs T-0010,
  because nesting is unreachable until the parameters that nest make their values shapes.
  T-0012 (lexical-to-value) is independent of all three and can run alongside them. Then four
  families run in parallel — T-0013 value-range (needs T-0012), T-0014 string, T-0015
  property-pair (needs T-0012 for the ordering pair), T-0016 `sh:closed`. T-0017 (logical) and
  T-0018 (shape-based) both need T-0011. T-0019 closes and needs the six component tasks.

  **Three things found during decomposition, recorded rather than absorbed:**

  1. **`sh:detail` is not in the corpus at all**, so it is a non-goal rather than a design
     item. It looked like a required `Result` and `Report` change for the shape-based
     constraints; the suite says otherwise, and building it would be building something
     unmeasurable.
  2. **The regex question is far smaller than it looked.** The four `sh:pattern` entries use
     `^[2-8][0-9]*$`, `Aldi`, `joh`, `Joh` and one `sh:flags "i"` — the common subset of any
     engine. `core:text/regex` ships with Odin, so the no-external-dependencies constraint
     holds, and what is left is documenting the dialect gap rather than closing it.
  3. **T-0014 is the only task that can fire the language-tag trigger**, through
     `sh:languageIn` and `sh:uniqueLang`. It is an acceptance criterion there rather than a
     note, so it cannot be absorbed quietly. The corpus survey says it cannot fire; if it
     does, that survey was wrong and work stops.

  **Two tasks carry more risk than their size suggests.** T-0011 is the ADR and has no suite
  entry exercising it until T-0017 — its unit tests over hand-built models carry unusual
  weight, and the failure mode is silent leakage into a caller's report. T-0018's
  `sh:qualifiedValueShapesDisjoint` is the most intricate thing in SHACL Core and should be
  split out if it starts to swallow its task.

  Awaiting human review before transition to active.


- **2026-08-06 — Created in discovery.** Scope drafted from `docs/handover-catalogue.md` and
  the measurements taken at SHACL-I-0001's close: 51 entries of real work across `core/node`
  and `core/property`, ~23 components, two pieces of machinery the engine does not have.

  The judgement this document rests on: **the catalogue is not uniform**, and planning it as
  thirty similar components would bury an architectural change (suppressed validation) inside
  a list of small ones. The Implementation Plan front-loads the two prerequisites — widened
  discovery and lexical-to-value — and isolates the ADR.

  Awaiting human review of scope, and of the decision list in Detailed Design. Two of those
  are worth deciding early because they change what "green" means: **unrecognised constraint
  parameters** (ignore, error, or expose), and **whether this stays one initiative or becomes
  two**.