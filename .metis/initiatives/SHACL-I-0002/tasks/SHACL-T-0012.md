---
id: lexical-to-value-conversion-and
level: task
title: "Lexical-to-value conversion, and the sh:datatype well-formedness debt"
short_code: "SHACL-T-0012"
created_at: 2026-08-06T19:26:54.267245+00:00
updated_at: 2026-08-06T19:26:54.267245+00:00
parent: SHACL-I-0002
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/todo"


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

## Acceptance Criteria **[REQUIRED]**

- [ ] Lexical form to value for the XSD datatypes the suite exercises, with well-formedness as
      a first-class answer: `"abc"^^xsd:integer` is not "zero", it is ill-formed.
- [ ] **`sh:datatype` gains the §4.3.1 well-formedness check** the spine left as recorded debt.
      `core/property/datatype-ill-formed` is the entry that forces it: `"300"^^xsd:byte` is out
      of range and `"c"^^xsd:byte` is not a number, and both must violate `sh:datatype
      xsd:byte` even though the datatype IRI matches exactly.
- [ ] Cross-datatype numeric comparison, per SPARQL's operator mapping, which SHACL defers to —
      `xsd:byte` against `xsd:integer`, `xsd:decimal` against `xsd:double`.
- [ ] Comparison of non-comparable values answers "incomparable" rather than an arbitrary
      order. What a constraint does with that is the constraint's business, but the primitive
      must not lie.
- [ ] **odin-rdf-sparql is read, not imported.** It has solved a version of this; SHACL Core
      keeps zero dependency on the query engine, at runtime and at link time, and
      `tests/purity` plus the absent `sparql:` collection both still hold.
- [ ] Pure unit tests — this is non-generic, store-free code, so it is tested directly rather
      than through a backend.
- [ ] `make test` and `make check` green.

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

*To be added during implementation*
