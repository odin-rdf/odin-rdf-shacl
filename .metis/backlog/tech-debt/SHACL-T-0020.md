---
id: pin-the-ci-checkouts-of-odin-rdf
level: task
title: "Pin the CI checkouts of odin-rdf-parser and odin-rdf-store to v0.1.0"
short_code: "SHACL-T-0020"
created_at: 2026-08-07T10:50:22.702881+00:00
updated_at: 2026-08-07T11:49:53.337802+00:00
parent: 
blocked_by: []
archived: false

tags:
  - "#task"
  - "#tech-debt"
  - "#phase/active"


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

## Acceptance Criteria

## Acceptance Criteria

## Acceptance Criteria **[REQUIRED]**

- [x] Both dependency checkout steps in `.github/workflows/ci.yml` carry a `ref:`.
      **Amended in flight (2026-08-07): parser on `v0.1.0`, store on commit `f896b7b`.**
      The criterion originally said `ref: v0.1.0` for both; the Risk Considerations below
      predicted this and it happened. See Status Updates.
- [x] The comment above them is updated to say what the pins are and how to bump them,
      rather than describing a future in which tags exist. It also records *why* the two
      pins are different, so the asymmetry does not read as an oversight.
- [ ] CI green on all three runners (ubuntu, macos, windows) with the pins in place.
      **Cannot be verified without a push** — verified locally instead, as far as one
      machine allows: the full suite passes against the exact pinned pair, and separately
      against `v0.1.0` of *both*, on darwin arm64.

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

- **2026-08-07 — Implemented, with one deviation from the acceptance criteria. Awaiting
  review and a push to confirm CI.**

  **The predicted finding happened, and it is a packaging gap rather than a code
  incompatibility.** This task's Risk Considerations said: *"the pin could reveal that this
  repository depends on unreleased upstream work … if CI goes red on the pinned tags, that
  is the finding, and the fix is upstream releasing rather than this repository
  unpinning."* That is exactly the position.

  **odin-rdf-store `v0.1.0` vendors one LMDB archive.** `liblmdb_darwin_arm64.a`, and
  nothing else. The five-platform vendoring — darwin amd64/arm64, linux amd64/arm64,
  windows amd64 — is STORE-A-0004, five commits *after* the tag. `shacl/kvstore` links
  those archives, and this workflow's own header says so. A `v0.1.0` pin would therefore
  build on macOS and **fail to link on the ubuntu and windows runners**.

  **Verified rather than assumed**, with `git worktree` checkouts at `v0.1.0` of both
  repositories:

  - **The code is fully compatible with `v0.1.0` of both.** All 145 tests pass —
    `shacl` 21, `shacl/memstore` 71, `shacl/kvstore` 14, `tests/guards` 12,
    `tests/readme` 4, `tests/w3c/harness` 23 — on darwin arm64, which is the one platform
    whose archive that tag happens to carry. Nothing here depends on unreleased upstream
    *code*.
  - **The pinned pair actually committed** — parser `v0.1.0`, store `f896b7b` — passes the
    same 145 tests. `f896b7b` is `origin/main`, so CI can fetch it.
  - odin-rdf-parser has two commits after its tag and both are documentation; `v0.1.0` is
    a clean pin there.

  **The deviation, and why it beats the alternatives.** The task asked for `ref: v0.1.0` on
  both. Instead: parser on the tag, store on a commit SHA. `ref:` accepts either, and a SHA
  delivers the objective in full — an upstream commit can no longer break this
  repository's CI without a deliberate bump — today, rather than after an upstream release
  cycle.

  - *Pin both to `v0.1.0`* is what was asked and it breaks CI on two of three runners.
  - *Leave the store unpinned* keeps the exact drift this task exists to remove, and the
    store is the faster-moving of the two.
  - *Wait for odin-rdf-store to release* leaves CI floating for the whole of
    [[SHACL-I-0003]], which is the window [[SHACL-T-0021]] was deliberately sequenced
    behind.

  A SHA pin is uglier than a tag and the comment says so, along with what removes it.

  **The upstream ask, for whenever odin-rdf-store is next opened:** cut a release that
  includes STORE-A-0004's vendored archives. `v0.1.0` is not usable by any consumer that
  links `store/kvstore` on Linux or Windows — which is every consumer that wants
  persistence on a server. This repository is the first to hit it and will not be the last.
  Not filed upstream from here; upstream repositories are read-only from this project.

  **What is not verified:** CI itself. The three-runner matrix needs a push, and that is
  the one acceptance criterion still open.