# Handover to the catalogue initiative

Written at the close of SHACL-I-0001 (the Core spine). What the seam looks like,
what the suite says is left, and what the spine deliberately did not settle.

## The seam: adding a constraint component

Four edits, none of them in the evaluator.

1. **`Constraint_Kind`** in `shacl/model.odin` — one case.
2. **`compile_constraints`** in `shacl/constraints.odin` — read the parameter off
   the shape node and append a `Constraint`. The struct already carries `count`,
   `term`, `node_kind`, and a `values` span; a component needing something else
   adds a field there.
3. **`constraint_scope`** in `shacl/check.odin` — value-scoped or set-scoped.
4. **`check_value`** or **`check_node_set`** in the same file — one case.

Plus the two vocabulary constants (`SH:...` and `...ConstraintComponent`) in
`shacl/vocab.odin`.

**Scope is the edit most likely to be got wrong**, and it is the one the suite
punishes hardest. A value-scoped component is asked once per value node and
blames it, so its result carries `sh:value`. A set-scoped component is asked once
about the whole value-node set and carries none. `sh:hasValue` is set-scoped and
`sh:in` is value-scoped despite reading almost identically, and the suite pins
both: `path-complex-001` expects an `sh:hasValue` violation with no `sh:value`,
`targetClassImplicit-001` expects an `sh:in` violation that names one.

Dispatch is a switch, not a table of procedure pointers. SPARQL-T-0011's finding
is the reason and also the escape hatch: procedure pointers measured as noise
once a call does real work, so if a catalogue component ever justifies one, the
precedent exists.

## What the spine does *not* implement, and where it will bite

**Shape discovery is narrower than §2.1.1.** Three cases are recognised: a node
typed `sh:NodeShape` or `sh:PropertyShape`, a node carrying a target declaration,
and a value of `sh:property`. The spec also makes a node a shape by being the
value of any shape-expecting parameter — `sh:node`, `sh:not`, `sh:and`, `sh:or`,
`sh:xone`, `sh:qualifiedValueShape`. **Every one of those is a catalogue
component, so widening discovery is the catalogue's first job**, not an
afterthought once the components are written. `compile.odin`'s discovery block
is where it goes, and the worklist already handles shapes found late.

**`sh:datatype` does not check the lexical form.** §4.3.1 requires the value's
lexical form to be well-formed for its datatype, so `"abc"^^xsd:integer` should
violate even though the datatype IRI matches. The spine compares datatype IRIs
only. This needs the same lexical-to-value machinery the value-range components
(`sh:minInclusive` and friends) need, which is why it was left — build it once,
use it in both. `core/node`'s `datatype-002` is the entry that forces it.

**No `sh:detail`, `sh:sourceConstraint`, or `sh:resultMessage` beyond the
shape's own.** `Result` carries what §3.1 needs for the components that exist.
The shape-based constraints will want `sh:detail` to nest a child's results
under a parent's, which is a `Result` field and a `Report` change, not an
evaluator change.

## Suite inventory: what is left

98 entries total, **26 enabled**, 72 remaining.

| Directory | Entries | State | What it needs |
| --- | --- | ---: | --- |
| `core/targets` | 7 | **green** | — |
| `core/path` | 13 | **green** | — |
| `core/misc` | 5 | **green** | — |
| `core/node` | 32 | disabled | `sh:and` `sh:or` `sh:not` `sh:xone` `sh:node` `sh:closed` `sh:ignoredProperties` `sh:pattern` `sh:flags` `sh:languageIn` `sh:minLength` `sh:maxLength` `sh:minInclusive` `sh:maxInclusive` `sh:minExclusive` `sh:maxExclusive` `sh:equals` `sh:disjoint` `sh:qualifiedMinCount` `sh:qualifiedMaxCount` `sh:qualifiedValueShapesDisjoint` |
| `core/property` | 38 | disabled | the above minus `sh:closed`, plus `sh:qualifiedValueShape` `sh:lessThan` `sh:lessThanOrEquals` `sh:uniqueLang` `sh:name` |
| `core/complex` | 2 | disabled | nearly the whole catalogue at once, plus `sh:sparql`, `sh:shapesGraph`, `sh:entailment` |
| `core/validation-reports` | 1 | **green** | — |

**`core/complex` needs `sh:sparql`** and is therefore the *SHACL-SPARQL* phase's,
not the catalogue's. Do not size the catalogue initiative around it: the
catalogue's real target is `core/node` (32) and `core/property` (38), 70 entries
between them.

**A live question the catalogue initiative must answer before it is scoped:** the
upstream repository also carries a **SHACL 1.2 test suite** — 138 core entries
against 1.0's 98, plus `node-expr/` and `rules/`. The family ships RDF 1.2 and
SPARQL 1.2, so 1.2 is plausibly the consistent long-run target. 1.0 was vendored
because it is the Recommendation and this initiative's exit criteria were stated
against it. Recorded in `tests/w3c/README.md` and still undecided.

## Things the spine left deliberately open

- **Recursion is detection, not support.** Cycle-breaking ("assume valid on
  re-entry") is addable without redesign. `sh:node` is what will make users meet
  the limit, so the catalogue initiative is where the pressure will show up.
- **Duplicate results are not deduplicated.** A shape that is both a root and
  another shape's `sh:property` value is validated twice at the same focus node
  and reports twice. No enabled entry exercises it. §3.4 arguably makes results a
  set; if a catalogue entry disagrees, that is where to settle it.
- **`sh:severity` is any IRI** and **`sh:conforms` is false for any result at
  all** — both settled by `core/misc` during the spine's verification pass, both
  easy to re-break. `misc/severity-001` and `severity-002` are the guards.
- **The store-evidence log stays open.** `docs/store-proposal.md` proposes no
  change to odin-rdf-store and explains why the two predicted items were retired.
  The catalogue initiative should keep the log rather than restart it: the one
  question that recurs is set membership (`sh:node`, `sh:qualifiedValueShape`),
  and the answer that worked for `sh:class` is written down there.
- **Language-tag folding did not trigger.** `docs/language-tag-status.md` has the
  decision, the designed fix, and the corpus survey saying no suite entry can
  force it. `sh:uniqueLang` and `sh:languageIn` are catalogue components and were
  expected to be the exposure; the survey says they are not.

## Where to read the design

- `.metis/adrs/SHACL-A-0001.md` — the shapes model, term ownership, graph
  scoping, with two "As Built" sections recording what the implementation
  changed.
- `shacl/shacl.odin` — the package contract: the memory rules and the four
  things a caller has to know.
- `shacl/check.odin` — the seam, with the scope reasoning at the top.
- `shacl/validate.odin` — the walk, the bindings, and recursion detection.
