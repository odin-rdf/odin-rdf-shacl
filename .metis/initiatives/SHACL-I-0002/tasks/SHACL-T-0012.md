---
id: lexical-to-value-conversion-and
level: task
title: "Lexical-to-value conversion, and the sh:datatype well-formedness debt"
short_code: "SHACL-T-0012"
created_at: 2026-08-06T19:26:54.267245+00:00
updated_at: 2026-08-07T05:43:23.756434+00:00
parent: SHACL-I-0002
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: SHACL-I-0002
---

# Lexical-to-value conversion, and the sh:datatype well-formedness debt

## Parent Initiative

[[SHACL-I-0002]]

## Objective **[REQUIRED]**

Teach the engine to compare **values**, not just terms — and discharge the `sh:datatype`
well-formedness debt the spine recorded, which needs exactly the same machinery. Everything in
the spine compares terms by `Term_ID`, which is why it is fast; the value-range components
cannot, and neither can a check that `"300"^^xsd:byte` is out of range.

## Acceptance Criteria

## Acceptance Criteria **[REQUIRED]**

- [x] Lexical form to value for the XSD datatypes the suite exercises, with well-formedness as
      a first-class answer: `"abc"^^xsd:integer` is not "zero", it is ill-formed.
- [x] **`sh:datatype` gains the §4.3.1 well-formedness check** the spine left as recorded debt.
      `core/property/datatype-ill-formed` is the entry that forces it: `"300"^^xsd:byte` is out
      of range and `"c"^^xsd:byte` is not a number, and both must violate `sh:datatype
      xsd:byte` even though the datatype IRI matches exactly.
- [x] Cross-datatype numeric comparison, per SPARQL's operator mapping, which SHACL defers to —
      `xsd:byte` against `xsd:integer`, `xsd:decimal` against `xsd:double`.
- [x] Comparison of non-comparable values answers "incomparable" rather than an arbitrary
      order. What a constraint does with that is the constraint's business, but the primitive
      must not lie.
- [x] **odin-rdf-sparql is read, not imported.** It has solved a version of this; SHACL Core
      keeps zero dependency on the query engine, at runtime and at link time, and
      `tests/purity` plus the absent `sparql:` collection both still hold.
- [x] Pure unit tests — this is non-generic, store-free code, so it is tested directly rather
      than through a backend.
- [x] `make test` and `make check` green.

## Implementation Notes

### Technical Approach

Non-generic, allocation-free where possible, in the style of `query.odin`'s value decoders.
The shape to aim for is a `Value` union over the numeric tower plus the "not a value" case,
with a decoder per datatype family and one comparison entry point.

Deliberately not general: this serves SHACL's needs, not XSD's whole type system. Datatypes no
suite entry exercises are ill-formed-by-default rather than silently accepted, and the list
grows on evidence.

### Dependencies

None. Independent of SHACL-T-0010 and SHACL-T-0011, and can run in parallel with them.

### Risk Considerations

**Scope creep is the risk here, not difficulty.** XSD's numeric tower plus dates, durations,
and their comparison rules is a large surface, and only a fraction is measured. Bound it by
the corpus: implement what suite entries exercise, and make everything else fail loudly rather
than approximately.

**Fixing `sh:datatype` changes behaviour in already-green directories.** They exercise
`sh:datatype` only with `xsd:string`, whose lexical space is every string, so nothing should
move — but it is a change to a shipped component, so the enabled suite is the guard and it
must stay green.

## Status Updates **[REQUIRED]**

- **2026-08-07 — Implemented; awaiting review.** `shacl/value.odin` (the machinery),
  `shacl/value_test.odin` (13 tests), the `sh:datatype` fix in `check.odin`, README and
  package-doc contract entries, and a harness defect the work uncovered. `make test` and
  `make check` green at both `Term_ID` widths. **Progress floor 18 → 21**:
  `core/node` 7 → 9, `core/property` 11 → 12.

  **The shape that was built.** `Value` is an Odin union over `i64`, `f64`, `bool`,
  `string`, and `Instant`, with nil as the "not a value" case; `compare_values` is the
  single comparison entry point and answers `.Less/.Equal/.Greater/.Incomparable`.
  Everything is `@(private)` — the four consumers are all in package `shacl`, so the
  public API did not have to grow to serve them.

  **The one place this departs from the task's written approach, and it needs a
  decision.** Implementation Notes say datatypes no suite entry exercises should be
  "ill-formed-by-default rather than silently accepted". That is right for the *value*
  and wrong for `sh:datatype`, so `Lexical_Status` has **three** cases rather than two.
  `.Unchecked` is the answer for a datatype this engine does not model, and
  `sh:datatype` treats it as satisfied. Making it violate instead would fail
  `sh:datatype rdf:HTML` on a perfectly good HTML literal — which `core/node/datatype-002`
  carries, and which passes today. The principle written into the code: **an engine may
  call a lexical form invalid only against a space it knows.** Neither is "silent": the
  status is a distinct case a caller can read, and the README and `shacl.odin` both say
  which datatypes are covered.

  Relatedly, the two questions a literal raises are genuinely independent and are kept
  apart: `"99999999999999999999999"^^xsd:integer` is well-formed (xsd:integer is unbounded)
  and has no value here, while `"<span>x</span>"^^rdf:HTML` has no value for the opposite
  reason — nothing is wrong with it.

  **A finding the corpus forced, and it is not the rule anyone guesses.**
  `minInclusive-002` and `-003` pin XSD's *partial* order over dateTimes: a value written
  without a timezone denotes a 28-hour window, not an instant, so it orders against a
  timezoned value only when the window clears it entirely. `-003` expects
  `"2002-10-10T12:00:01-05:00"` to **violate** a bound of `"2002-10-10T12:00:00"` — a
  value an implicit-UTC reading calls *later* and would report as conforming. So the
  implicit-timezone approach is wrong for this suite. Both entries are pinned as unit
  tests rather than left for SHACL-T-0013 to rediscover.

  **The scope call.** Interpreted: xsd:string, xsd:boolean, the integer tower with all
  thirteen derived ranges, xsd:decimal/float/double, xsd:dateTime, xsd:date,
  rdf:langString. The derived integer ranges are the only place the table is wider than
  the corpus (which uses `xsd:byte` alone); they are thirteen lines of spec fact, and the
  alternative is a special case for the one type the suite happens to name. Stated
  limitations, all in the file header: integers beyond `i64` are well-formed and valueless,
  a mixed numeric comparison goes through `f64`, `xsd:unsignedLong`'s upper bound is not
  enforced above `i64`'s (a value in that gap is already valueless), and whitespace is
  trimmed rather than collapsed.

  One late simplification, after checking what `strconv.parse_f64` actually accepts: it
  reads XSD's `INF`, `-INF`, `+INF`, and `NaN` exactly as spelled, so the special-case
  decoder they had was redundant and is gone. The specials are now matched *before* the
  sign is stripped, which is also more correct — XSD signs the infinities and not `NaN`,
  so `"-NaN"^^xsd:double` is ill-formed where it was previously accepted. Pinned in
  `value_test.odin`.

  **A harness defect found on the way, and the item that most needs a second opinion.**
  After the `sh:datatype` fix, `core/node/datatype-001` still failed — and not because of
  the engine. `expected_report` builds the expected graph as the transitive closure of the
  entry's result node, stopping at IRIs but not at blank nodes. An entry whose focus node
  is a **blank node in the data** (`_:b30507`, found by `sh:targetClass`) therefore drags
  `_:b30507 rdf:type ex:TestClass` into the expected report through `sh:focusNode`, and no
  produced report can ever contain a data triple.

  The fix is three predicates: the closure no longer follows a blank node through
  `sh:focusNode`, `sh:value`, or `sh:sourceShape`, which **name** a node living elsewhere,
  while every other predicate — nested `sh:result`, and the blank-node property paths in
  `sh:resultPath` that `core/path` depends on — **structures** one and is still followed.
  It can only shrink an expected graph, and any entry passing today has expected == actual,
  so no green entry could be affected; `make test` confirms the four enabled directories
  are untouched.

  This matters beyond this task: **every `core/node` value-range entry has a blank-node
  focus node**, so SHACL-T-0013 would have read it as an engine failure across its whole
  target. Two of the four entries the floor gained are this fix rather than the engine
  (`node/class-002`, and the rest of `node/datatype-001`), and `suite.odin` says so where
  the floor is pinned.

  **Not done, deliberately:** no backend-level unit test for the `sh:datatype` change. The
  suite already exercises it end to end on both backends at both widths through the three
  datatype entries now in the floor, and a hand-written duplicate would assert less.

  **Carried in this change but unrelated to the task: the Windows CI break** (run
  31130428710). `make check` fails on windows-latest at the `purity` target — Odin rejects
  `-out:build/purity` there with "Output path ... must have an appropriate extension".
  Nothing to do with SHACL-T-0011's content: this is the repo's **first CI run**, and the
  extensionless `-out:` has been in the Makefile since the scaffolding commit. ubuntu and
  macos passed. Fixed with an `EXE` variable set from `Windows_NT`, applied to both built
  binaries (`purity` and the bench), and the previous commit's `.gitignore` entries gained
  their `.exe` counterparts — including `/shacl.exe`, which is safe where `/shacl` is not,
  since on Windows there is no directory collision to prevent the binary being written.

  **This is not a claim that the Windows job is now green.** `make check` failed before
  `make test` ran, so the whole suite is still unmeasured on that platform and a second
  failure may sit behind this one. It cannot be verified from here.

  Nothing under the upstream repos was touched, and nothing new was asked of the store.
  Not committed — awaiting review.