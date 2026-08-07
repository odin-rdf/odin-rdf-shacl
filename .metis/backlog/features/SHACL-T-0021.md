---
id: tag-v0-1-0
level: task
title: "Tag v0.1.0"
short_code: "SHACL-T-0021"
created_at: 2026-08-07T10:50:26.006066+00:00
updated_at: 2026-08-07T10:50:26.006066+00:00
parent: 
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/backlog"
  - "#feature"


exit_criteria_met: false
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

- [ ] `v0.1.0` tagged on a green `main`, with release notes stating the conformance
      position: 98 of 98 `core/` entries, all twenty-nine non-SPARQL constraint components
      of §4, both backends, both `Term_ID` widths, no skip list.
- [ ] The notes name the scope boundary plainly — SHACL-SPARQL is a later phase and SHACL
      Core has zero dependency on odin-rdf-sparql — and the known omissions: `sh:detail`,
      duplicate results undeduplicated, and the `sh:pattern` dialect divergence.
- [ ] The README's status section agrees with the notes.

## Implementation Notes **[CONDITIONAL: Technical Task]**

### Technical Approach

Whatever the siblings did for their `v0.1.0`; match it rather than invent a release
process here.

### Dependencies

None hard. Two sequencing questions, both judgement calls for a human:

1. **Before or after [[SHACL-I-0003]]?** The siblings all shipped `v0.1.0` *with*
   performance evidence — odin-rdf-parser's headline claim is a benchmark result. Tagging
   first means this repository's first release is the one in the family with no numbers in
   it. Tagging after means the release waits on a week or two of benchmark work for a claim
   nobody has asked for yet.
2. **After [[SHACL-T-0020]]**, ideally. A tag whose CI floated against two moving upstream
   branches does not pin what was actually tested.

### Risk Considerations

**The version number implies a compatibility promise.** `v0.1.0` matches the family and
signals "usable, not yet stable", which is the honest reading — the API is documented to
the family contract standard but has had no external consumer. Worth being deliberate
rather than defaulting.

## Status Updates **[REQUIRED]**

*To be added during implementation*
