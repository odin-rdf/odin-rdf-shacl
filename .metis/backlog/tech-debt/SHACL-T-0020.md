---
id: pin-the-ci-checkouts-of-odin-rdf
level: task
title: "Pin the CI checkouts of odin-rdf-parser and odin-rdf-store to v0.1.0"
short_code: "SHACL-T-0020"
created_at: 2026-08-07T10:50:22.702881+00:00
updated_at: 2026-08-07T10:50:22.702881+00:00
parent: 
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/backlog"
  - "#tech-debt"


exit_criteria_met: false
initiative_id: NULL
---

# Pin the CI checkouts of odin-rdf-parser and odin-rdf-store to v0.1.0

## Objective **[REQUIRED]**

Pin the two dependency checkouts in `.github/workflows/ci.yml` to `v0.1.0` with `ref:`,
which is what the workflow's own comment says to do once the family publishes tags. It
has: odin-rdf-parser, odin-rdf-store, and odin-rdf-sparql are all tagged `v0.1.0`.

## Backlog Item Details **[CONDITIONAL: Backlog Item]**

### Type
- [x] Tech Debt - Code improvement or refactoring

### Priority
- [x] P1 - High (important for user experience)

### Technical Debt Impact

- **Current Problems**: The workflow checks out `odin-rdf/odin-rdf-parser` and
  `odin-rdf/odin-rdf-store` at their default branch, so **a commit to either upstream
  `main` can turn this repository's CI red without anyone here changing a line**. The
  comment above those two steps already anticipates this: *"Both track their main. Once the
  family publishes tags on these, pin them with `ref:` so an upstream change cannot break
  this repo's CI without a deliberate bump."*
- **Benefits of Fixing**: A red build means this repository broke. Upstream moves become a
  deliberate bump with a diff behind it, which is also the only way to tell an upstream
  regression from a local one.
- **Risk Assessment**: Low severity, moderate annoyance, and it gets worse the moment
  either upstream starts moving again. It is also a prerequisite for the release
  ([[SHACL-T-0021]]) being reproducible: a tag whose CI floated against two moving targets
  does not pin what was actually tested.

## Acceptance Criteria **[REQUIRED]**

- [ ] Both dependency checkout steps in `.github/workflows/ci.yml` carry `ref: v0.1.0`.
- [ ] The comment above them is updated to say what the pins are and how to bump them,
      rather than describing a future in which tags exist.
- [ ] CI green on all three runners (ubuntu, macos, windows) with the pins in place —
      which also confirms `v0.1.0` of both is what this repository has actually been
      building against.

## Implementation Notes **[CONDITIONAL: Technical Task]**

### Technical Approach

Two `ref: v0.1.0` lines on the existing `actions/checkout@v5` steps. The platform matrix,
the collection layout, and everything else stay as they are.

### Dependencies

None. Independent of [[SHACL-I-0003]] and of the other two backlog items.

### Risk Considerations

**The pin could reveal that this repository depends on unreleased upstream work** — a
commit to parser or store `main` made after `v0.1.0` that something here relies on. If CI
goes red on the pinned tags, that is the finding, and the fix is upstream releasing rather
than this repository unpinning.

## Status Updates **[REQUIRED]**

*To be added during implementation*
