# Language-tag case: status at the end of SHACL-I-0002

**From:** odin-rdf-shacl, SHACL-I-0002 (the SHACL Core constraint catalogue)
**Status:** for review. **odin-rdf-parser was not touched, and the trigger did not fire.**

> **Amended 2026-08-20 (SHACL-I-0004, the port to odin-rdf-record — SHACL-T-0033's
> finding, recorded by SHACL-T-0037).** Everything below was written against
> odin-rdf-store, which this repository no longer reads. The record changes the
> exposure this document tracks in two opposite directions, and neither moved a
> corpus entry:
>
> - **Term identity is resolved on this backend.** odin-rdf-record lowercases
>   language tags on intern — its canonical term encoding's rule — so `"x"@EN`
>   and `"x"@en` are *one term* in every snapshot. The residual exposure named
>   below, `sh:hasValue` and `sh:in` comparing terms, is therefore closed here
>   without any change to odin-rdf-parser: a shapes graph writing
>   `sh:hasValue "x"@EN` against data writing `"x"@en` no longer gets a spurious
>   violation. The sentence "a user's shapes graph … gets a spurious violation
>   today" under *Where the exposure passes* is no longer true of this repository.
> - **Report rendering is the new latent exposure.** `session_term` hands back
>   the lowercased tag, and `rdf.equal_term` compares a `Literal`'s `language`
>   byte-wise, so a produced report renders `"Hill"@en-nz` where the document
>   said `@en-NZ` — and a report compared by isomorphism against an expected
>   report parsed from such a document would mismatch. It did not, because the
>   corpus holds exactly two uppercase-tagged literals (`property/languageIn-001`'s
>   `@en-NZ`, `node/datatype-002`'s `@en-AU`) and both *conform*, so neither reaches
>   an expected report as `sh:value` or `sh:focusNode`. Nothing was patched in the
>   harness to make that so. This is the one place where the parser-side fold
>   would still do work for this repository: with literals arriving pre-folded,
>   an expected report and a produced one would agree on the tag's case.
>
> **The family decision is not rescinded here.** "Fold language tags to lowercase
> at literal construction, in odin-rdf-parser" was taken for the family, and the
> record's intern rule makes it moot *for this repository's term identity* while
> leaving the rendering half and every other consumer as they were —
> odin-rdf-sparql's corpus is larger and its results formats render tags. It is
> flagged for family discussion, with the widened trigger below carried unchanged
> until then. The paragraph "neither store dictionary changes" under *The designed
> implementation* is also no longer accurate: the record's dictionary already
> folds, so a parser-side fold would change nothing on disk there and would only
> align the rest of the family with it.

Refreshed at SHACL-T-0019. The verdict is unchanged from SHACL-I-0001's, and it is now
unchanged *with the components that were supposed to change it built* — which is the
only thing this revision adds and the reason it was an acceptance criterion rather
than a note.

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

3. **SHACL-T-0014, the only task that could have fired it.** The string components
   landed — `sh:languageIn` and `sh:uniqueLang` among them — and the trigger stayed
   silent. This is the finding the decomposition asked for by name, because the corpus
   survey above is a prediction until the components that read language tags exist.

   Two of them read a tag, and **neither reads it as a term**:

   - `sh:languageIn` implements RFC 4647 §3.3.1 basic filtering (`language_matches` in
     `shacl/check.odin`), which is case-insensitive and prefix-based *by specification*.
     It is immune to interning by construction, not by luck, and `property/languageIn-001`
     — `"Hill"@en-NZ` against the range `en` — is the entry that would catch a
     case-sensitive implementation of it.
   - `sh:uniqueLang` compares tags to each other with `strings.equal_fold`, for the same
     reason and stated at the same place in the code. Two literals whose tags differ only
     in case *are* the same language, and this component has to say so whatever the
     parser interns.

   So the two components that touch language tags both fold at the point of comparison,
   because SHACL requires it of them. That is worth stating plainly, because it means the
   suite's silence is not evidence about the parser at all in these two cases — they
   would pass under either interning scheme.

4. **SHACL-T-0019, at the whole corpus.** All 98 entries of `core/` are green, both
   backends, both widths. Every directory the design phase named as the likely site of
   exposure — the ones exercising `sh:hasValue`, `sh:in`, `sh:uniqueLang`, and
   `sh:languageIn` against language-tagged literals — now runs, and none of them
   depends on folding.

## Where the exposure passes

**Nowhere in the corpus, and the corpus is now fully run.** SHACL-I-0001's answer was a
prediction about components that did not exist; this is the same answer with all of them
built and every entry green. The prediction held.

Where the exposure does still sit is `sh:hasValue` and `sh:in`, which compare **terms**
and therefore would see `"x"@EN` and `"x"@en` as different. No suite entry exercises that
combination, so nothing here fails — but that is a fact about the corpus rather than
about the semantics, and it is the exact case the parser-side fix would settle.

That is a statement about this corpus, not about the world. A user's shapes graph writing
`sh:hasValue "x"@EN` where their data writes `"x"@en` gets a spurious violation today,
and the family has already decided that is a bug in the parser. What is missing is not a
decision but a reason to spend the change now.

## Recommendation

Leave it. Keep the decision and this design recorded, and **the trigger is now widened**
— from "a suite entry fails" to "a suite entry fails **or** a user reports it"
(**ratified by Greger, 2026-08-07**). At SHACL-I-0001 that was offered as an option and at
SHACL-T-0019 it was a recommendation; it is now the trigger. The reasoning it rests on:
the whole corpus runs green, so the suite has demonstrated it will not be the one to raise
the alarm, and a trigger that can only be pulled by something that cannot happen is not a
trigger.

**This is a family-level change, not a local one**, because the fix it gates lands in
odin-rdf-parser. Anyone carrying this question into that repository should carry the
widened form.

If the family would rather close the question than carry it, the change is small,
designed, and hot-path-neutral by construction — but it belongs in odin-rdf-parser's own
initiative with its own benchmarks, not smuggled in from here.
