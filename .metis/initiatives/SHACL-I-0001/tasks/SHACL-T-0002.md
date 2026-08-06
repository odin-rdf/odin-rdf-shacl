---
id: vendor-the-w3c-shacl-test-suite
level: task
title: "Vendor the W3C SHACL test suite and build the manifest-driven harness"
short_code: "SHACL-T-0002"
created_at: 2026-08-06T13:58:06.773159+00:00
updated_at: 2026-08-06T14:27:44.449792+00:00
parent: SHACL-I-0001
blocked_by: [SHACL-T-0001]
archived: false

tags:
  - "#task"
  - "#phase/active"


exit_criteria_met: false
initiative_id: SHACL-I-0001
---

# Vendor the W3C SHACL test suite and build the manifest-driven harness

## Parent Initiative

[[SHACL-I-0001]]

## Objective **[REQUIRED]**

Land the thing that defines "done" for this project: the official W3C SHACL test suite,
vendored at a pinned commit for hermetic offline runs, plus a manifest-driven harness that can
read it. Because SHACL has no syntax suite, every entry is *data graph + shapes graph →
validation report*, so the harness needs graph comparison by blank-node isomorphism from the
outset rather than as a later addition.

Deliverable is a harness that reads manifests, pins entry counts per directory, and compares
report graphs — with **zero directories enabled**, since nothing can validate yet. It also
produces two survey findings the initiative depends on: the real directory inventory, and the
language-tag exposure.

## Acceptance Criteria **[REQUIRED]**

- [x] W3C SHACL test suite vendored verbatim under `tests/w3c/` from `w3c/data-shapes` at a
      pinned commit (its own pin — a different repository from the `w3c/rdf-tests` commit the
      sibling projects share).
- [x] `tests/w3c/README.md` provenance record in odin-rdf-parser's shape: upstream repo,
      pinned commit, retrieval date, license, local-directory → upstream-path table, and
      explicit exclusions (the `sparql/` portions of the suite are out of scope until the
      SHACL-SPARQL phase).
- [x] Harness parses suite manifests with the family's own Turtle parser via the `rdf:`
      collection, walks entries preserving order, and asserts a pinned entry count per
      directory as the circularity guard.
- [x] Report comparison by **blank-node isomorphism**, reusing odin-rdf-parser's eval-harness
      technique; verified against hand-written report pairs (isomorphic, and
      non-isomorphic-but-similar) before any suite entry uses it.
- [x] `sht:Failure` expectations are recognised as a distinct outcome and counted, never
      silently dropped. An unhandled entry type fails hard — no skip list, no
      expected-failure file. **Criterion was written on a wrong assumption, corrected in the
      log below:** `sht:Failure` is an `mf:result` *value*, not an entry type, and it does not
      occur in `core/` at all. It is modelled anyway (`Expectation.Failure`) so an entry
      carrying it is recognised rather than read as an empty report; the fail-hard-on-unknown
      rule is implemented and tested on entry *type* and *status*.
- [x] Directory inventory recorded in the task log: which directories exist at the pinned
      commit, their entry counts, and which this initiative targets (the target and path
      directories) versus which belong to the catalogue initiative.
- [x] **Language-tag exposure survey recorded**: grep the vendored corpus for language tags
      containing uppercase, and report which entries and which directories would be affected
      by the folding decision. This is the evidence behind the deferral in SHACL-I-0001's
      Detailed Design, and the thing that would fire its trigger. **Result: zero exposure.**
- [x] `make test` / `make check` green at both widths with the harness present and no suite
      directories enabled.

## Implementation Notes

### Technical Approach

Mirror `tests/w3c/harness/` from odin-rdf-parser and odin-rdf-sparql (`manifest.odin`
pattern, `MANIFEST_BASE`, plain `odin test`, no custom runner). The SHACL manifest vocabulary
differs from `mf:`-style query manifests — entries carry a shapes graph and a data graph and
an expected report — so manifest reading needs its own shape here, but per-directory
enablement, pinned counts, and fail-hard-on-unknown carry over unchanged.

Blank-node isomorphism is the piece with no precedent in this repo but a working precedent
next door: odin-rdf-parser's eval harness compares graphs that way for its `*-eval` suites.
Validation reports are blank-node-heavy (each `sh:ValidationResult` is typically a blank
node), so this is load-bearing rather than incidental.

### Dependencies

SHACL-T-0001 (package layout, `tests/w3c/` reserved, green build).

### Risk Considerations

The suite's exact directory names and layout are confirmed *here*, not assumed — SHACL-I-0001
names the target and path directories as its exit criteria on the expectation that they exist
as separable directories. If the layout differs materially from that expectation, say so in
the task log and raise it before SHACL-T-0007 depends on it: the exit criteria may need
restating in terms of whatever the suite actually offers.

## Status Updates **[REQUIRED]**

- **2026-08-06 — Complete, awaiting review.** All eight criteria met. `make check` clean,
  `make test` green at both widths; the harness package runs 14 tests. **Three findings below
  change work outside this task — two of them change SHACL-T-0007 and the initiative's stated
  non-goals.**

  **Vendored.** `w3c/data-shapes` at `ae99300e2e2c16a39dae0160a057158e81ef2050` (2026-07-29),
  `data-shapes-test-suite/tests/core/` → `tests/w3c/core/`. 98 entries in seven directories:
  targets 7, path 13, node 32, property 38, misc 5, complex 2, validation-reports 1. Every
  entry is `sht:Validate` with `mf:status sht:approved` — no proposed entries, no other type.
  Provenance, inventory, exclusions and both surveys are in `tests/w3c/README.md`. Nothing is
  enabled, and a test asserts that.

  **Finding 1 — the suite is shaped unlike the query suites, and it interacts with
  SHACL-A-0001.** Each entry is one self-contained Turtle file holding the data graph, the
  shapes graph, its own `mf:Manifest`, *and* the expected `sh:ValidationReport`.
  `sht:dataGraph <>` and `sht:shapesGraph <>` both point at the file itself, so the data graph
  and the shapes graph are usually **the same graph** — which also contains the manifest and
  the expected report. That is sound (shapes target specific nodes; manifest triples are not
  among them) and it fits the single-graph decision without strain, but it is worth knowing
  before SHACL-T-0007 loads anything. A handful of entries use `*-data.ttl` / `*-shapes.ttl`
  side files, so both action properties are resolved rather than assumed. `mf:result` is a
  blank node whose transitive closure *is* the expected report — there is no result file to
  open, which is why `expected_report` extracts a closure and stops at IRIs (following them
  would drag in the data graph).

  **Finding 2 — SHACL-T-0007's minimal constraint set is short by two.** The exit-criteria
  directories need more than the five components the initiative named. Measured across
  `core/targets` and `core/path`:

  | Component | Entries | In the planned set? |
  |---|---|---|
  | `sh:minCount` | 7 | yes |
  | `sh:maxCount` | 6 | yes |
  | `sh:class` | 5 | yes |
  | `sh:datatype` | 2 | yes |
  | `sh:nodeKind` | 1 | yes |
  | **`sh:in`** | 2 | **no — listed as a non-goal** |
  | **`sh:hasValue`** | 1 | **no — listed as a non-goal** |

  `sh:in` is wanted by `targets/multipleTargets-001` and `targets/targetClassImplicit-001`;
  `sh:hasValue` by `path/path-complex-001`. Under "enabled means fully green" these cannot be
  skipped, so the spine's constraint set grows from five components to seven. Both are simple
  value comparisons with no new machinery — the change is to scope, not to design.
  SHACL-T-0007's criteria are updated; SHACL-I-0001's Non-Goals list still names them and is
  corrected in its status log.

  **Finding 3 — the language-tag exposure is zero, which is stronger than the initiative
  predicted.** SHACL-I-0001 expected the exposure to sit in the catalogue initiative
  (`sh:uniqueLang`, `sh:hasValue`, `sh:in`). Surveying the whole vendored corpus: only two
  files carry a language tag with uppercase in it, and **neither depends on case folding**.
  `core/node/datatype-002.ttl` uses `sh:targetNode "G'day"@en-AU`, spelled identically in the
  target declaration and the data, so it is term equality with itself.
  `core/property/languageIn-001.ttl` matches `"Hill"@en-NZ` against `sh:languageIn ("en"
  "mi")` and expects it to **conform** — that is BCP 47 basic filtering, which RFC 4647 makes
  case-insensitive *and* prefix-based regardless of interning.

  So the real requirement is implementing basic filtering correctly in `sh:languageIn`, which
  is catalogue work touching nothing upstream. **On this corpus the trigger cannot fire — not
  for the spine, and not for the catalogue initiative either.** The recorded decision (fold to
  lowercase at literal construction) still stands as the family's answer; this project simply
  has no evidence forcing it, and odin-rdf-parser stays untouched.

  **Decision — the isomorphism comparison is ported, not imported.** odin-rdf-parser's
  `tests/w3c/harness/compare.odin` is battle-tested across 1045 tests and is reachable through
  the `rdf:` collection, but importing it was rejected twice over: it is a *test* package with
  no stability contract, so this repo's CI would break on a refactor nobody would think to
  coordinate; and a test build that imported it would drag the parser's own 1045-test harness
  into this binary, because `_test.odin` files come along in a test compilation. Copied with
  attribution instead — the same judgement odin-rdf-sparql made about the family's Error type.
  Two deliberate changes: it operates on `rdf.Triple` rather than `rdf.Quad` (a report is a
  graph; there is no graph position), and the entry point is `report_isomorphic`.

  Its nine tests are written as pairs of Turtle documents rather than hand-built arrays, which
  exercises the real parse path and gives blank-node relabelling for free. They cover the
  cases a weaker comparison would pass: same-skeleton-no-bijection, nested blank-node
  structures (`sh:resultPath [ sh:inversePath ex:child ]`, which the suite really uses), an
  ordering that forces backtracking, and set-semantics duplicate collapse.

  **Open question raised, not decided — SHACL 1.2.** The upstream repository also carries
  `shacl12-test-suite/`, substantially larger (138 core entries against 1.0's 98, plus
  `node-expr/` and `rules/`). The family ships RDF 1.2 and SPARQL 1.2 support, so 1.2 is
  plausibly the consistent long-run target. SHACL 1.0 was vendored because it is the
  Recommendation and the spine's exit criteria are stated against it — the same order
  odin-rdf-sparql used (1.1 suites first, 1.2 as a later task). Recorded in
  `tests/w3c/README.md` as a live question rather than a settled exclusion. **This wants a
  decision before the catalogue initiative is scoped.**

  Nothing about the upstream repositories was touched.