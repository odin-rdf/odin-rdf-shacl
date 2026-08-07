---
id: tag-v0-1-0
level: task
title: "Tag v0.1.0"
short_code: "SHACL-T-0021"
created_at: 2026-08-07T10:50:26.006066+00:00
updated_at: 2026-08-07T13:14:13.695581+00:00
parent: 
blocked_by: [SHACL-T-0020, SHACL-T-0025]
archived: false

tags:
  - "#task"
  - "#feature"
  - "#phase/completed"


exit_criteria_met: true
initiative_id: NULL
---

# Tag v0.1.0

## Objective **[REQUIRED]**

Tag `v0.1.0`, bringing this repository into line with its three siblings — odin-rdf-parser,
odin-rdf-store, and odin-rdf-sparql are each released at `v0.1.0` and this one is untagged.

## Backlog Item Details **[CONDITIONAL: Backlog Item]**

### Type
- [x] Feature - New functionality or enhancement

### Priority
- [x] P2 - Medium (nice to have)

### Business Justification **[CONDITIONAL: Feature]**

- **User Value**: A consumer can depend on a tag rather than on `main`. Today the only way
  to use this library is to track a moving branch, which is the same problem
  [[SHACL-T-0020]] fixes for this repository's own CI — one level up.
- **Business Value**: SHACL Core is complete and the whole vendored W3C corpus is green
  (98 of 98, both backends, both `Term_ID` widths). That is the claim a release exists to
  pin, and it is true now.
- **Effort Estimate**: S — the work is the decision and the release notes, not the tag.

## Acceptance Criteria **[REQUIRED]**

- [x] `v0.1.0` tagged on a green `main` **and published as a GitHub Release**, with notes
      stating the conformance position: 98 of 98 `core/` entries, all twenty-nine
      non-SPARQL constraint components of §4, both backends, both `Term_ID` widths, no
      skip list. The criterion originally said only "tagged"; the family convention is an
      annotated tag *and* a Release, and all three siblings have both.
- [x] The notes name the scope boundary plainly — SHACL-SPARQL is a later phase and SHACL
      Core has zero dependency on odin-rdf-sparql — and the known omissions: `sh:detail`,
      duplicate results undeduplicated, and the `sh:pattern` dialect divergence.
- [x] The README's status section agrees with the notes.

## Implementation Notes **[CONDITIONAL: Technical Task]**

### Technical Approach

Whatever the siblings did for their `v0.1.0`; match it rather than invent a release
process here.

### Dependencies

**Both sequencing questions are settled (Greger, 2026-08-07).**

1. **After [[SHACL-I-0003]].** The tag waits for the benchmark. Every sibling that shipped
   `v0.1.0` shipped it *with* performance evidence — odin-rdf-parser's headline claim is a
   benchmark result — and this repository's first release should not be the family's only
   one with no numbers in it. The cost, accepted: nobody can depend on a tag until the
   benchmark initiative closes.
2. **After [[SHACL-T-0020]].** A tag whose CI floated against two moving upstream branches
   does not pin what was actually tested.

So this is the last of the three backlog items. [[SHACL-T-0020]] and [[SHACL-T-0022]] are
**not** held for it and were released to proceed immediately.

### Risk Considerations

**The version number implies a compatibility promise.** `v0.1.0` matches the family and
signals "usable, not yet stable", which is the honest reading — the API is documented to
the family contract standard but has had no external consumer. Worth being deliberate
rather than defaulting.

## Status Updates **[REQUIRED]**

- **2026-08-07 — Released. https://github.com/odin-rdf/odin-rdf-shacl/releases/tag/v0.1.0**

  Annotated tag on `1bbcd52`, matching the siblings' style, plus a GitHub Release. **All
  four repositories of the family are now released**: parser `v0.1.0`, store `v0.1.1`,
  sparql `v0.1.0`, shacl `v0.1.0`.

  **Sequenced as decided.** The tag waited for [[SHACL-I-0003]], because every sibling
  shipped `v0.1.0` *with* performance evidence — odin-rdf-parser's headline claim is a
  benchmark result — and this repository's first release should not have been the family's
  only one without numbers. It waited for [[SHACL-T-0020]] too, so that what CI verified is
  what the tag pins. Both dependencies were complete and the target commit was green on all
  three runners before the tag was cut.

  **One amendment to the acceptance criteria.** The first criterion said "tagged"; the
  family convention is an annotated tag **and** a GitHub Release, which only became visible
  when odin-rdf-store's `v0.1.1` was cut and the sibling releases were checked. Corrected
  above rather than silently satisfied.

  **What the notes say**, per the remaining criteria: the conformance position; that
  SHACL-SPARQL is a later phase and SHACL Core has zero dependency on odin-rdf-sparql; and
  the three known omissions named as deliberate — `sh:detail` absent because it appears
  nowhere in the corpus, duplicate results undeduplicated and open with a consumer-report
  trigger, and the `sh:pattern` dialect divergence with `s` and `q` rejected rather than
  ignored. Also the performance figures and the flat-memory promise, stated in the
  allocator-independent form SHACL-T-0025's correction produced.

  The README's status section agrees with the notes; both were written from the same
  measurements rather than from each other.