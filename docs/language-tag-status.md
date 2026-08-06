# Language-tag case: status at the end of SHACL-I-0001

**From:** odin-rdf-shacl, SHACL-I-0001 (the SHACL Core spine)
**Status:** for review. **odin-rdf-parser was not touched, and the trigger did not fire.**

## The short version

The decision is made, the implementation is designed, the trigger is recorded — and
**nothing was built, because nothing needed it**. The initiative surveyed the entire
vendored W3C SHACL corpus and found the exposure is not merely small but **zero**: no
entry in the suite can fail for this reason, in any directory, enabled or not.

odin-rdf-parser is unchanged. No benchmark was re-run because no hot path was touched.

## The decision (SHACL-I-0001 design phase, 2026-08-06)

**Fold language tags to lowercase at literal construction, in odin-rdf-parser.**

This is what BCP 47 case-insensitivity implies, what RDF 1.1 Concepts §3.3's "the value
space of language tags is always lower case" points at, and what Jena and RDF4J do. It
discharges the question the vision parked in this project.

The rest of term identity was settled by spec rather than by us, and is recorded so it is
not relitigated: IRIs and datatype IRIs are **never** normalized (RDF 1.1 Concepts §3.2,
Simple String Comparison — "further normalization MUST NOT be performed"); lexical forms
compare code-point-wise with no Unicode normalization; and `"1"^^xsd:integer` versus
`"01"^^xsd:integer` is the term/value distinction rather than a normalization question.
Language-tag case was the only open part.

## The designed implementation

Recorded so that if the trigger ever fires, the fix is ready rather than researched under
pressure: **detect in the scanner, fold in the constructor.**

- The scanner already walks every byte of a tag to find its end and validate its
  character class, so case detection is an OR into an accumulator over bytes it is
  already reading — no extra pass, no branch.
- The all-lowercase path, which is essentially all real RDF, keeps its borrowed slice
  with zero copies and zero allocations. RDF-A-0001 and the benchmark baselines are
  intact.
- A tag that does carry uppercase is folded through the existing `rdf.Intern_Table`,
  which already serves expanded prefixed names and synthesized labels.
- **Folding must live in the constructor, not the scanner alone**, because literals are
  also built programmatically — odin-rdf-sparql's `STRLANG`, and SHACL itself — and a
  hand-built `"x"@EN` disagreeing with a parsed one is the exact bug being fixed. The
  scanner passes its detection flag in so the hot path skips work it has already done.

With literals arriving pre-folded, neither store dictionary changes and there is no
on-disk format question. **The cost that remains real:** databases already written with
mixed-case tags hold terms a folded lookup will not find.

## The trigger, and whether it fired

**Trigger (Greger, 2026-08-06):** should a W3C SHACL suite entry fail for this reason,
work stops and the fix is made in odin-rdf-parser at that point — with review, and with
bench numbers showing the hot path unchanged.

**It did not fire.** Two findings, in order of when they were made:

1. **SHACL-T-0002, at vendoring.** Surveying the whole corpus rather than only the
   directories this initiative would enable: exactly **two files** carry an
   uppercase-bearing language tag, and neither depends on folding. One spells the literal
   identically in its target and its data, so any consistent interning agrees. The other
   is a `sh:languageIn` test, and `sh:languageIn` is immune regardless — SHACL defines it
   by BCP 47 *basic filtering*, which RFC 4647 makes case-insensitive and prefix-based,
   independent of how terms are interned. That entry expects `@en-NZ` to conform, and it
   would under any interning scheme.

   This is stronger than the design phase predicted. The design phase expected the
   exposure to sit in the catalogue initiative's `sh:uniqueLang`, `sh:hasValue`, and
   `sh:in`. On this corpus it sits nowhere.

2. **SHACL-T-0007 and SHACL-T-0008, at the green directories.** `core/targets`,
   `core/path`, `core/misc`, and `core/validation-reports` are fully green — all 26
   entries, both backends, both `Term_ID` widths — with no entry failing on term identity
   of any kind. `core/misc` is the interesting one here: it is where the suite tests
   `sh:message` handling, so if language tags were going to matter to the report path,
   that is where it would have shown.

## Where the exposure passes

**Nowhere, on current evidence.** The catalogue initiative inherits the *decision*, not a
problem: it will implement `sh:uniqueLang`, `sh:hasValue`, and `sh:in` against
language-tagged literals, and the corpus survey says none of the entries exercising them
depends on case folding.

That is a statement about this corpus, not about the world. A user's shapes graph writing
`"x"@EN` where their data writes `"x"@en` gets a spurious violation today, and the family
has already decided that is a bug in the parser. What is missing is not a decision but a
reason to spend the change now.

## Recommendation

Leave it. Keep the decision and this design recorded, and keep the trigger — extended, if
you want, from "a suite entry fails" to "a suite entry fails **or** a user reports it",
since the suite has now demonstrated it will not be the one to raise the alarm.

If the family would rather close the question than carry it, the change is small,
designed, and hot-path-neutral by construction — but it belongs in odin-rdf-parser's own
initiative with its own benchmarks, not smuggled in from here.
