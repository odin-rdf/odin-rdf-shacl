---
id: the-shacl-core-constraint
level: initiative
title: "The SHACL Core constraint catalogue: the rest of §4"
short_code: "SHACL-I-0002"
created_at: 2026-08-06T19:09:51.760962+00:00
updated_at: 2026-08-06T19:09:51.760962+00:00
parent: SHACL-V-0001
blocked_by: []
archived: false

tags:
  - "#initiative"
  - "#phase/discovery"


exit_criteria_met: false
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

**Discovery phase: not yet designed.** What follows is the decision list the design phase
should settle with Greger, in the pattern SHACL-I-0001 used.

- **How suppressed validation is expressed.** A nested `validate` with a null visitor? A
  `Conformance` sub-run sharing the outer stack? A flag on the frame? The constraint that
  makes it non-obvious: recursion detection is per-shape-on-the-stack, and an inner
  conformance check legitimately re-enters shapes the outer walk has open — or does it? That
  question needs answering before the mechanism is chosen, because the two answers give
  different designs. **Wants an ADR** (SHACL-A-0002).

- **Unrecognised constraint parameters: ignore, or ill-formed?** The spec is not loud about
  this. Ignoring is what the spine does and what makes an incomplete engine look complete;
  erroring is honest but rejects shapes graphs that carry vendor extensions, which real ones
  do. A third option — ignore, but expose what was ignored — may be the useful one. Decide
  before the components land, because the answer changes what "green" means.

- **The regex engine for `sh:pattern`.** Odin ships `core:text/regex`, so no external
  dependency is needed and the family's constraint holds. But SHACL defines `sh:pattern` by
  XPath `fn:matches` — XML Schema regex — and `sh:flags` are `i s m x q`. Odin's package
  offers `m i x u`; `s` and `q` are absent and the dialect differs. Shim, documented subset,
  or a small own implementation is a real decision with a real cost, and it should be taken
  with the suite entries in front of it rather than in the abstract.

- **Numeric comparison across datatypes.** `sh:minInclusive 2` against `"2.0"^^xsd:decimal`,
  `xsd:byte` versus `xsd:integer`, and what happens for non-numeric datatypes. The spec defers
  to SPARQL operator mapping; odin-rdf-sparql has already solved a version of this and should
  be read before anything is written — **without importing it**, since SHACL Core must keep
  zero dependency on the query engine.

- **`sh:detail` in the report.** Shape-based constraints want to nest a child's results under
  a parent's. That is a `Result` field and a `Report` change, not an evaluator change — but it
  is a public API change, so it belongs in the design list.

- **Duplicate results.** A shape that is both a root and another shape's `sh:property` value
  is validated twice at the same focus node and reports twice. No enabled entry exercises it.
  §3.4 arguably makes results a set. If a catalogue entry disagrees, this is where to settle
  it; if none does, record that it stays open.

- **One initiative or two.** Recorded as a decision rather than assumed: the mechanical
  families (value-range, string, property-pair, `sh:closed`) need no evaluator change and are
  wide and shallow; the structural ones (logical, shape-based) need widened discovery and
  suppressed validation and are narrow and deep. Splitting gives each its own design phase and
  keeps an XL initiative from hiding an ADR inside it. Not splitting keeps one suite goal and
  one decomposition. **Greger's call at the design phase**; the goals above are written so
  either reading works.

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

Rough phasing for the discovery phase; proper decomposition happens at decompose. The shape
below assumes one initiative; if the design phase splits it, the line falls after item 4.

1. **Widened shape discovery** (§2.1.1) — prerequisite for everything shape-nesting. Small,
   contained, and blocking.
2. **Lexical-to-value conversion**, plus the `sh:datatype` well-formedness debt it discharges.
3. **Value-range and string components** — `sh:minInclusive`/`maxInclusive`/`minExclusive`/
   `maxExclusive`, `sh:minLength`/`maxLength`, `sh:pattern`/`sh:flags`, `sh:languageIn`,
   `sh:uniqueLang`. Wide, shallow, greens entries steadily. Carries the regex decision.
4. **Property-pair components** — `sh:equals`, `sh:disjoint`, `sh:lessThan`,
   `sh:lessThanOrEquals`. Needs a second path evaluation from the focus node.
5. **`sh:closed` and `sh:ignoredProperties`** — and the store-evidence note that comes with it.
6. **Suppressed validation, and SHACL-A-0002** — the architectural change, designed and
   guarded before any consumer of it lands.
7. **Logical combinators** — `sh:and`, `sh:or`, `sh:not`, `sh:xone`.
8. **Shape-based constraints** — `sh:node`, `sh:qualifiedValueShape` and its three companions.
   `sh:node` is what makes recursion detection reachable in practice, so the spine's failure
   mode gets its first real exercise here.
9. **Close** — `core/node` and `core/property` enabled and green, docs and README updated,
   store-evidence and language-tag write-ups refreshed for review, handover notes for the
   SHACL-SPARQL phase.

**Exit criteria:** `core/node` (32) and `core/property` (38) green with pinned entry counts
and zero unexpected failures, against both backends at both `Term_ID` widths; every SHACL Core
constraint component of §4 implemented except those requiring SPARQL; validation still reads
the data graph exclusively through the published match interface; still zero dependency on
odin-rdf-sparql; public API documented to the family contract standard; the store-evidence and
language-tag write-ups brought to review.

## Status Updates

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
