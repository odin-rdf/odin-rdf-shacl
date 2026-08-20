---
id: as-of-validation-on-record-the
level: task
title: "As-of validation on record: the SHACL-T-0030 scenarios via store_at"
short_code: "SHACL-T-0035"
created_at: 2026-08-20T15:20:22+00:00
updated_at: 2026-08-20T17:46:14.273244+00:00
parent: SHACL-I-0004
blocked_by: [SHACL-T-0033]
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: SHACL-I-0004
---

# As-of validation on record: the SHACL-T-0030 scenarios via store_at

## Parent Initiative

[[SHACL-I-0004]]

## Objective

Preserve the capability SHACL-T-0030 established on the store:
validating a past dataset. On record it needs no dedicated API at
all — `store_at(s, epoch)` returns a `Snapshot` pinned at that
epoch, `session_init` binds it like any other, and every read
through the session answers about that moment. The task is the
proof, not machinery.

Why the capability exists at all (owner discussion, 2026-08-20 — the
record is immutable, so remediation is never the purpose): validating
past data under the *current* model explains the present (bisect for
the epoch that introduced a violation, `snapshot_epoch_meta` names
who and why) and reports exposure windows for newly adopted rules;
validating past data under the *then-current* model is the
accountability question ("did it conform to the rules in force at
the time") — and, sharper, it is the recomputation that
`RECORD-A-0006` decision 5 relies on: the log deliberately does not
record that a judge objected, so a verdict about the past is
recoverable only by recomputing it over the epoch-pinned dataset.
As-of validation is what keeps conformance claims about the past
independently checkable, which is the record's value proposition
extended.

## Acceptance Criteria

- [ ] The as-of scenario tests (the `as_of_test.odin` set before the
      port) re-expressed over record: build epochs through `apply`,
      validate at a historical epoch via `store_at` + `session_init`,
      and at head via `store_latest` — a violation introduced in a
      later epoch is absent at the earlier one, and vice versa for a
      violation later retracted.
- [ ] A retracted-graph case: a graph whose quads were all retracted
      validates as empty at head and as populated at the earlier
      epoch (record's retraction is logical — `Filter{origin = .Any}`
      at a pinned epoch is the read).
- [ ] Epoch metadata is the audit trail: a test reads
      `snapshot_epoch_meta` (actor, reason, wall) for the epoch it
      validates, demonstrating the who/when/why alongside the
      verdict.
- [ ] **Shapes-as-of-then**: shapes stored in the same store evolve
      across epochs; compile a model from a session over
      `store_at(E)`'s shapes graph, validate `store_at(E)`'s data
      graph with it, and show the verdict differs from validating
      the same pinned data under the head shapes — the decision-5
      recomputation, and time-consistency for free since one
      snapshot feeds both sessions (`SHACL-A-0001` releases it after
      compile). This scenario is expected to be **test code only** —
      compile already reads through a session, so no library change
      is in its scope; if implementation finds otherwise, stop and
      report rather than rewriting code T-0035 would not otherwise
      touch.
- [ ] Documented: the as-of coordinate is the **epoch**, not a
      wall-clock time — record deliberately has no `epoch_at(wall)`
      (an application-side ask, per RECORD-I-0003's non-goals), so a
      caller holding a time finds its epoch by its own bookkeeping or
      via epoch metadata.

## Implementation Notes

The suppressed-validation path (`SHACL-A-0002`) and the ordinary
report path should both appear in at least one as-of scenario, since
both ride the same session.

## Status Updates

**2026-08-20 — implemented, all criteria met; awaiting review.** Test code
and documentation only, as the objective predicted: no library change.
`store_at` is the one as-of call; everything below the session is head
validation's code.

**The scenarios** (`shacl/as_of_test.odin`, five tests, a `History` store
built one `apply` per epoch, every verdict paired with the visible quad
count so a vacuous pass cannot impersonate a real one):

- *The dataset as it was* — the T-0030 handover: epoch 1 one owner
  (conforms, 2 visible), epoch 2 two owners (violates, 3 visible; one
  result on the report path), epoch 3 the old owner retracted (conforms, 2
  visible), epoch 0 the empty world (conforms vacuously, 0 visible); head
  via `store_latest` agrees with epoch 3 and disagrees with epoch 2;
  `store_at(4)` is `.Future_Epoch`, refused rather than clamped.
- *A retracted class hierarchy* — the reverse direction, on the report
  path: epoch 1 conforms with 0 results, epoch 2 (the `rdfs:subClassOf`
  edge retracted, data untouched) violates with 1.
- *A retracted graph* — a named graph loaded and then wholly retracted:
  populated and violating at epoch 1, empty and vacuously conforming at
  head; the label still resolves at head, so it is an empty graph, not an
  absent one.
- *Epoch metadata beside the verdict* — a hand bisect finds the first
  violating epoch (2); `snapshot_epoch_meta` on the pinned snapshot yields
  `wall > 0`, and actor and reason decode through the session to the IRIs
  the changeset named (`ex:ops`, `ex:handover-2026-08`); epoch 1's reason
  is 0, "none", as the log records it.
- *Shapes-as-of-then* — shapes in a graph of the same store, tightened from
  `sh:maxCount 2` to `1` across epochs 3–4 (property shape named by IRI so a
  parameter can be retracted and re-asserted); `conforms_node` (the
  suppressed path) over one pinned snapshot feeding both sessions: the data
  at epoch 2 conforms under epoch 2's shapes, violates under head's, and
  head violates under head's; at epoch 0 the shapes graph compiles to zero
  shapes. **Test code only, as expected** — compile reads through a
  session, and SHACL-A-0001 releases the shapes snapshot the moment it
  returns.

Both paths the notes asked for are present: `conforms_node` carries the
shapes-as-of-then scenario and `validate_report` the hierarchy one (and
epoch 2 of the handover).

**One record fact learned, recorded in the file header and the README:
terms are not epoch-scoped; facts are.** A pinned snapshot bounds which
facts are visible, not which terms resolve — a term resolves at every
epoch, including before it was first written (as the old store's
dictionary did, STORE-A-0008 §7). My first assertion expected the
shapes-graph label *not* to resolve at epoch 0; it does, and reads an empty
graph. This is the right semantics and is what lets one compiled model bind
at any epoch without re-binding by hand.

**Documented** (AC 5): the as-of coordinate is the epoch, not a wall-clock
time — no `epoch_at(wall)`, the wall is advisory, a caller holding a time
finds its epoch by its own bookkeeping or by walking `snapshot_epoch_meta`.
Stated in the test header, the package doc (`shacl.odin`, after the
`Validator` paragraph), and a new README subsection "Validating the past"
with a compile-verified example in `tests/readme` (`as_of_example`: epoch 1
conforms, epoch 2 does not, the metadata's wall is set). The README
paragraph also carries the owner's three reasons to validate the past and
names decision 5's recomputation.

`tdb_compile` (compile a shapes document from a scratch store and close it)
moved from `validator_test.odin` into the shared `harness_test.odin`, used
by both. `make test`/`make check` green; `windows_amd64` check clean.