# W3C SHACL test suite — provenance

Vendored verbatim for hermetic, offline, reproducible runs, in the family's
established style (odin-rdf-parser's `tests/w3c/README.md` is the template).

| | |
| --- | --- |
| Upstream repository | [`w3c/data-shapes`](https://github.com/w3c/data-shapes) |
| Pinned commit | `ae99300e2e2c16a39dae0160a057158e81ef2050` (2026-07-29) |
| Retrieved | 2026-08-06 |
| Upstream path | `data-shapes-test-suite/tests/core/` |
| Local path | `tests/w3c/core/` |
| License | [W3C Software and Document License](http://www.w3.org/Consortium/Legal/copyright-software) — copy in `UPSTREAM-LICENSE.md` |

This is a **different upstream repository** from the `w3c/rdf-tests` commit
odin-rdf-parser and odin-rdf-sparql share, so it carries its own pin.

## Directory inventory

98 entries across seven directories, every one `sht:Validate` with
`mf:status sht:approved` — no proposed entries, no other entry type.

| Directory | Entries | State | Owner |
| --- | ---: | --- | --- |
| `core/targets/` | 7 | **enabled** (SHACL-T-0007) | **SHACL-I-0001** (spine exit criteria) |
| `core/path/` | 13 | **enabled** (SHACL-T-0007) | **SHACL-I-0001** (spine exit criteria) |
| `core/node/` | 32 | disabled, floor 7 | **SHACL-I-0002** (catalogue) |
| `core/property/` | 38 | disabled, floor 11 | **SHACL-I-0002** (catalogue) |
| `core/misc/` | 5 | **enabled** (SHACL-T-0008) | **SHACL-I-0001** |
| `core/complex/` | 2 | disabled, floor 0 | SHACL-SPARQL phase |
| `core/validation-reports/` | 1 | **enabled** (SHACL-T-0008) | **SHACL-I-0001** |

**26 entries enabled.** The family's rule holds — enabled means fully green, no
skip list, no expected-failure file — and `ENABLED_ENTRIES` is pinned against
both the table and the number the runner actually ran.

### The progress floor

The three disabled directories additionally carry a **floor**: how many of their
entries pass today, pinned as a *minimum* and asserted to only ever go up
(SHACL-T-0009). It exists because per-directory enablement gives the catalogue
initiative no signal at all until nearly every constraint component of §4 is
built — two directories remain, and neither can be enabled before then.

It **enables nothing and excuses nothing**: a directory in the floor is still
disabled, and the only conformance claim this repository makes is the set of
enabled directories. Raising a floor is a deliberate edit, exactly as enabling a
directory is, and the counts are printed on every run whether they pass or not.

**A floor is not a scoreboard**, and the reason is worth carrying with the
number: an entry expecting `sh:conforms true` passes whether it was validated or
merely ignored. `core/complex/shacl-shacl` is the clearest case — it needs
`sh:sparql`, `sh:shapesGraph`, and `sh:entailment`, none of which exist here, and
it passes anyway — which is why that directory is counted but pinned at 0.

## Exclusions

- **`data-shapes-test-suite/tests/sparql/`** — SHACL-SPARQL (`sh:sparql` and
  SPARQL-based constraint components). Out of scope until that phase, which is
  where the `sparql:` collection gets added.
- **`shacl12-test-suite/`** — the SHACL 1.2 suite, which exists at this commit
  and is substantially larger (138 core entries against 1.0's 98, plus
  `node-expr/` and `rules/` directories). Not vendored, and **this is now a
  settled exclusion rather than a live question** (Greger, 2026-08-06): SHACL
  1.2 is still moving in the W3C, so targeting it would mean chasing a
  specification that can change under a green suite. **This project sits at
  SHACL 1.0 for the foreseeable future.**

  It is worth recording why the question was raised at all, so the decision is
  not mistaken for inattention: the family ships RDF 1.2 and SPARQL 1.2, which
  makes 1.2 look like the consistent long-run target. The difference is
  maturity, not consistency — RDF 1.2 and SPARQL 1.2 were stable enough to
  implement against; SHACL 1.2 is not yet. odin-rdf-sparql took the same shape
  from the other side, vendoring 1.1 first and adding 1.2 once it was worth
  pinning.

  **Review trigger:** SHACL 1.2 reaching Proposed Recommendation, or a consumer
  needing something only 1.2 defines. Until then the 1.0 corpus is the whole
  scoreboard, and the catalogue initiative is scoped against its 98 entries.
- Everything else in the upstream repository: specification sources,
  `data-shapes-ucr/`, `shacl-af/`, `shacl-js/`, `shacl-compact-syntax/`,
  `unmaintained/`.

## How a test is shaped

Worth knowing before reading the harness, because it differs from the query
suites the sibling projects run.

Each entry is **one self-contained Turtle file** holding the data graph, the
shapes graph, its own `mf:Manifest` with an `mf:entries` list, and the expected
`sh:ValidationReport` — all in the same document:

```turtle
<>
  rdf:type mf:Manifest ;
  mf:entries ( <path-inverse-001> ) .

<path-inverse-001>
  rdf:type sht:Validate ;
  mf:action [ sht:dataGraph <> ; sht:shapesGraph <> ] ;
  mf:result [ a sh:ValidationReport ; sh:conforms false ; sh:result [ … ] ] ;
  mf:status sht:approved .
```

`sht:dataGraph <>` and `sht:shapesGraph <>` both point at the file itself, so
**the data graph and the shapes graph are usually the same graph** — and that
graph also contains the manifest triples and the expected report. That is
sound because shapes target specific nodes, and the manifest and report
triples are not among them. A handful of entries instead use side files
(`*-data.ttl` / `*-shapes.ttl`), so the harness must resolve both action
properties rather than assume `<>`.

The directory `manifest.ttl` is an index: it lists `mf:include <test-file.ttl>`
and holds no entries of its own.

Two consequences for the harness:

- **Report comparison must be blank-node isomorphism.** Every
  `sh:ValidationResult` is a blank node, and `sh:resultPath` can itself be a
  blank-node structure (`[ sh:inversePath ex:child ]`), so nested bijection is
  required, not a top-level label match.
- **`sht:Failure` is a `mf:result` *value*, not an entry type**, and it does
  not occur in `core/` at all — only in `sparql/pre-binding/`, which is
  excluded. Nothing in the vendored corpus expects a processor failure.

## Language-tag exposure survey

SHACL-I-0001 defers the language-tag folding fix to odin-rdf-parser behind a
trigger: *should a W3C SHACL suite entry fail for this reason, work stops and
the fix is made then*. This is the survey that sizes that risk.

**Result: no entry in the vendored Core suite depends on language-tag case
folding.** Two files carry a tag with uppercase in it, and neither is exposed:

| File | Tag | Why it does not depend on folding |
| --- | --- | --- |
| `core/node/datatype-002.ttl` | `@en-AU` | `sh:targetNode "G'day"@en-AU` — the literal is spelled identically in the target declaration and the data, so it is term equality with itself. |
| `core/property/languageIn-001.ttl` | `@en-NZ` | `"Hill"@en-NZ` against `sh:languageIn ("en" "mi")`. SHACL defines `sh:languageIn` by BCP 47 **basic filtering**, which RFC 4647 makes case-insensitive *and* prefix-based, independent of how terms are interned. The entry expects `@en-NZ` to conform. |

So the requirement here is not term identity at all — it is **implementing
basic filtering correctly in `sh:languageIn`**, which is catalogue work and
touches nothing upstream. On this corpus the trigger cannot fire, for the
spine or for the catalogue initiative.

The decision recorded in SHACL-I-0001 (fold to lowercase at literal
construction) still stands as the family's answer; this survey says only that
this project has no evidence forcing it.
