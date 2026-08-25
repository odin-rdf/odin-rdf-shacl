---
id: adopt-odin-rdf-record-v0-4-0-one
level: task
title: "Adopt odin-rdf-record v0.4.0: one unhandled switch case, and the two contracts it falsifies"
short_code: "SHACL-T-0038"
created_at: 2026-08-25T09:31:35.099196+00:00
updated_at: 2026-08-25T09:45:31.259159+00:00
parent: 
blocked_by: []
archived: false

tags:
  - "#task"
  - "#tech-debt"
  - "#phase/completed"


exit_criteria_met: true
initiative_id: NULL
---

# Adopt odin-rdf-record v0.4.0: one unhandled switch case, and the two contracts it falsifies

## Objective **[REQUIRED]**

**odin-rdf-record `v0.4.0` was tagged on 2026-08-25** (`39be085`, `RECORD-I-0004`): RDF 1.2's
two term kinds — triple terms under encoding tag `0x07`, base-direction literals under `0x08` —
and on-disk format version 2. It was cut for **odin-rdf-sparql**, whose port (`SPARQL-I-0003`)
was gated on it and which built against it before the tag; this repository is the other
consumer, and the family's convention is that a release is not done until its consumers'
Current State has been re-read.

This task is that walk. **It is small and it is precisely bounded**, because the adaptation was
measured rather than estimated on 2026-08-25, against a scratch copy of this repository built
against the record at `3692aac` — `v0.4.0` minus one documentation commit, `record/`'s sources
byte-identical to the tag:

- **Exactly one compile error**, and it is one line:

  ```
  shacl/check.odin(1026:3) Unhandled switch case: Triple   Suggestion: Was '#partial switch' wanted?
  ```

- **With that switch handled, everything is green**: `make check` clean across all six
  packages, `make test` green — 125 + 13 + 7 + 1 + 23 tests, all successful, W3C harness
  included. No verdict moves, no read count moves, nothing else in the engine notices.

What makes this a task rather than a one-line commit is the *second* half: the compile error is
the loud consequence of `record.Term_Kind` gaining a fourth member, and the same change quietly
falsifies **two written contracts in this repository** that no compiler will complain about.
Both are stated in comments this repository treats as binding, and one of them guards a leak.

**CI is unaffected today** — `.github/workflows/ci.yml` pins `odin-rdf-record@v0.3.0` and is
green. But the Makefile reaches `../odin-rdf-record` in the family checkout root, so anyone
developing this repository beside a current record checkout **cannot build it today**. That is
what makes this P1 rather than P2.

## Backlog Item Details **[CONDITIONAL: Backlog Item]**

### Type
- [x] Tech Debt - Code improvement or refactoring

### Priority
- [x] P1 - High (should fix soon)

### Technical Debt Impact

- **Current Problems**: three, in descending loudness.

  1. **`node_kind_of` does not compile** (`shacl/check.odin:1026`). Its `switch
     session_kind(v.se, value.id)` covers `.IRI`, `.Blank` and `.Literal`, and
     `record.Term_Kind` now has `.Triple` (`record/read.odin:247`, the direct replacement for
     odin-rdf-store's `id_kind(id) == .Triple`). Odin refuses a non-exhaustive enum switch,
     which is the language doing exactly the job it exists for: this is the one site in the
     engine that had to be told about a new term kind, and it was told.

  2. **The comment above it is now false** (`shacl/check.odin:1017`–`1022`): "*An RDF-star
     triple term is a fourth kind SHACL 1.0's six node kinds do not name; the record store
     cannot hold one at all (its encoder refuses them), so only the unbound arm can ever see
     one*". The first clause is still true and the parenthesis is not — `apply` accepted
     `.Unsupported_Term` for a triple term until v0.4.0 and now commits it. The *conclusion*
     the comment draws is the one that has to change: the bound arm can see one now.

  3. **`session_term`'s ownership contract is no longer total, and the gap leaks**
     (`shacl/session.odin:81`–`89`). It says the term is **borrowed** — "*never destroy it*" —
     and `record.snapshot_term` now returns a **wholly owned** `^rdf.Triple`: the node, and
     every component string, allocated from the caller's allocator (`RECORD-A-0008` decision
     2). `record.snapshot_term_destroy(snap, id, term, allocator)` is the new paired verb and
     is a no-op for the borrowing kinds. Six engine call sites decode through `session_term`
     and none frees: `shacl/intern.odin:92` (`materialize_term`, which interns a copy and drops
     the original), `shacl/compile.odin:320`, `shacl/constraints.odin:814`,
     `shacl/check.odin:429`, `shacl/check.odin:1073`, `shacl/report.odin:252` — plus
     `tests/readme/readme.odin:138`. **The suites pass because no vendored entry carries a
     triple term**, not because the path is safe; with `ODIN_TEST_FAIL_ON_BAD_MEMORY=true` the
     first one that does will fail the run.

- **Benefits of Fixing**: the engine builds in the family checkout root again; the pin moves to
  a tag both consumers share; and **the split-IRI caveat closes as a side effect**.
  `session_term`'s contract has carried an admitted hole since the port — "*an IRI stored in the
  split encoding joins in one allocation, which this contract would leak*" — excused on the
  grounds that no `apply`-written store contains one. v0.4.0 is the first release that gives
  that leak a verb to close it with, and the same verb closes both.

- **Risk Assessment**: low risk, low effort, and one trap (see *Risk Considerations*). The
  measured blast radius is one line of code plus documentation; the leak is latent rather than
  live, since nothing in the vendored corpus can reach it.

## Acceptance Criteria

**[REQUIRED]**

- [x] **`node_kind_of` handles `.Triple` explicitly** — `case .Triple: return {}` — **and not
      with `#partial switch`.** The empty set is the right answer and it is already the answer
      the *unbound* arm gives for `^rdf.Triple`: a triple term satisfies none of SHACL 1.0's
      six node kinds, and the caller's intersection turns an empty set into a violation. Both
      arms then agree, which is what the comment above them claims.
- [x] **The falsified comment at `shacl/check.odin:1017` is amended, not deleted** — the family
      convention: the old sentence stands with a dated note saying what moved (record `v0.4.0`
      stores triple terms, so the bound arm sees them now).
- [x] **`session_term`'s contract states which kinds own** (`shacl/session.odin:81`): a triple
      term is wholly owned, a split IRI is joined in one allocation, everything else borrows —
      and `record.snapshot_term_destroy` is named as how a caller frees whatever it got without
      having to know which case it is in.
- [x] **Every `session_term` call site is leak-free for a triple term**, either by pairing the
      decode with `record.snapshot_term_destroy` or by a stated reason it need not. Six engine
      sites, listed above, plus `tests/readme`. `materialize_term` is the one that matters most
      — it is the path every term a compiled model keeps goes through, and it already makes a
      copy, so freeing the original is what the intern was always for.
- [x] **A unit test carries a triple term in the data graph** and pins two things: the
      `sh:nodeKind` violation (no node kind matches), and **no leak** under
      `ODIN_TEST_FAIL_ON_BAD_MEMORY=true`. The parser expands RDF 1.2's reifying syntax, so
      `<< :a :b :c >> :q :z` ingests as `_:b rdf:reifies <<( :a :b :c )>> . _:b :q :z .` — the
      triple term arrives in the **object** position, which is the only position the corpus
      obliges. No vendored suite entry has this shape, which is exactly why it must be written.
- [x] **The CI pin moves `v0.3.0` → `v0.4.0`** (`.github/workflows/ci.yml`, the
      `odin-rdf/odin-rdf-record` checkout `ref:`), **as a floor**, with the comment block above
      it extended in the style it already has — it explains the `v0.1.0` → `v0.2.0` → `v0.3.0`
      history, and this is the fourth reason. State the reason precisely: **not** that the
      engine needs triple terms, but that `Term_Kind` gained a member the engine switches on.
- [x] **W3C suite still 98 of 98**, `make check` green, and **the read counts do not move** —
      7503 on the reference configuration and every other pin. v0.4.0 changes nothing about
      what this engine asks the store; a pin that moves here means something else did.
- [x] **The record pin is refreshed everywhere it is written, not only in CI**: `README.md:171`,
      `.metis/vision.md:92`, `:151` and `:299`. Amended with a dated note rather than rewritten.

## Implementation Notes **[CONDITIONAL: Technical Task]**

### Technical Approach

One line of code, then the documentation. In the measured run the whole engine change was:

```odin
switch session_kind(v.se, value.id) {
case .IRI:     return NODE_KIND_IRI
case .Blank:   return NODE_KIND_BLANK_NODE
case .Literal: return NODE_KIND_LITERAL
case .Triple:  return {}      // ← the new arm
}
```

**The rest of record v0.4.0's API surface was checked against this repository and does not
touch it** — recorded here so nobody re-derives it:

- `Load_Error` gained `.Term_Order` — this engine never switches on it.
- `term_encode` gained `resolve_component: Resolve_Term_ID = nil` and `term_decode` gained
  `resolve_term: Resolve_Term = nil`, **both inserted before `allocator`** — defaulted, so a
  named-argument caller is unaffected and a positional one is not; this engine calls neither
  (they are the record's pure codec layer).
- `snapshot_kind` now **panics** on an encoding tag it does not define, where it used to fall
  through to `.Literal`. Unreachable from here — the ids this engine passes come from the same
  snapshot.
- `apply` no longer refuses triple terms and base-direction literals with `.Unsupported_Term`,
  and `record/ingest` recurses `blank_prefix` into a triple term's components. Both widen what
  can arrive; neither changes a signature.
- Purely additive and available if wanted: `snapshot_triple_parts` (a triple term's three
  component ids — a tag check and three arena reads, no allocation and no decode),
  `snapshot_term_destroy`, `term_refs`, `term_order_ok`.
- **Format version 2 does not read version 1 and there is no migration.** Irrelevant to this
  repository's suites, which open every store over `Mem_FS`, and worth one line for anyone
  holding a durable record directory.

**Things to check rather than assume:**

- **Base-direction literals are the other half of v0.4.0** and they can now be stored:
  `"x"@en--ltr`, datatype `rdf:dirLangString`. Ask what `sh:datatype`, `sh:languageIn` and
  `sh:uniqueLang` do with one. The engine's standing contract — a datatype whose value space it
  does not model skips the lexical check rather than failing it — probably covers it, and
  `language` is populated as usual, so the expected answer is "nothing to do". Confirm it; do
  not assume it.
- **Whether `sh:nodeKind` is the only place a kind is switched on.** `shacl/path.odin:52`, `:55`,
  `:78`, `:83` and `shacl/compile.odin:380`, `:403`, `:423` compare `session_kind(...) == .IRI`
  or `== .Literal` — equality, not a switch, so they compile and behave sensibly on a triple
  term (it is neither). Worth reading once with the fourth kind in mind rather than trusting
  that comparisons are automatically safe.
- **`rdf.clone_term` on a `^rdf.Triple`** — `shacl/intern.odin`'s `intern` clones what it keeps,
  and `SHACL-A-0001` says the model owns every term it holds. Confirm the clone is deep and that
  `term_key` distinguishes two triple terms (`write_term_key` must recurse), or the model will
  hold a term pointing into freed store memory — the exact failure `SHACL-A-0001` exists to
  prevent, and one the port made *more* dangerous, not less.

### Dependencies

**odin-rdf-record `v0.4.0`, tagged 2026-08-25 at `39be085`** — already published; nothing
blocks this. No odin-rdf-sparql dependency: that repository is the release's other consumer,
not this task's.

### Risk Considerations

**The trap is `#partial switch`.** It compiles, it passes every test, and it silently discards
the exhaustiveness check that caught this break in the first place — the next term kind the
record adds would then reach `node_kind_of` and be classified by falling off the end. The
explicit `case .Triple` costs one line and keeps the compiler as the thing that notices. This
is the one place this task can be wrong while looking entirely right.

**The leak is invisible to the current corpus.** All 98 W3C entries pass with the switch fixed
and nothing else touched, so a green suite is *not* evidence that the ownership half was done.
Only the new unit test can show it, which is why it is an acceptance criterion rather than a
suggestion.

**Do not let this become RDF 1.2 support.** Nothing here asks the engine to validate triple
terms meaningfully, model `rdf:reifies`, or take a position on assert-versus-mention — the
record's own initiative declined all three as non-goals. The task is: build against the tag,
classify a fourth kind honestly, and own what the store now hands back.

## Status Updates **[REQUIRED]**

**2026-08-25 — filed, with the adaptation already measured.** Written after odin-rdf-record cut
`v0.4.0` for the sparql port. The compile break, the green run behind it, and the two falsified
contracts were established by building a scratch copy of this repository against the record at
`3692aac` (`record/` byte-identical to the tag): one error, one line, then `make check` clean
across six packages and `make test` green at 125 + 13 + 7 + 1 + 23. **No file in this repository
has been changed** — the probe was a copy outside it. Nothing pushed.
**2026-08-25 — implemented, and every criterion met.** The engine change is the
one line the filing predicted; the rest is the half a compiler cannot see.

**The fourth kind.** `node_kind_of` has `case .Triple: return {}` — explicit,
not `#partial`, so the next term kind the record adds is a compile error here
again rather than a silent misclassification. Both arms now answer the same way:
`{}`, no node kind matched, the caller's intersection violates. The comment that
said the store "cannot hold one at all" stands with a dated note saying what
moved.

**The ownership half, which was the actual work.** `session_term_destroy` wraps
record's `snapshot_term_destroy`, and every decode is paired with it — seven
sites in the engine plus the harness helper and the README example. `materialize`
got a paired `materialize_destroy` so the five value-path call sites are one
deferred line each. The contract in `shacl/session.odin` now says which kinds own
(a triple term wholly, a split IRI its joined string) rather than claiming they
all borrow, and **the split-IRI caveat is closed rather than restated** — it had
been an admitted leak since the port with no verb to fix it.

**The pairings are load-bearing, and that was checked rather than asserted.**
Removing each one in turn and re-running:

| pairing | the test that catches it |
| --- | --- |
| `check.odin` × 4 (datatype, range, string, languageIn) | `test_triple_term_through_the_value_paths` — 12 leaks |
| `check.odin` `pair_ordered`, left and right | `test_triple_term_through_the_pairwise_and_set_paths` — 4 leaks each |
| `check.odin` `uniqueLang`'s value-set loop | same test — 4 leaks |
| `intern.odin` `materialize_term` | `test_a_shapes_graph_may_name_a_triple_term` — 8 leaks |
| `report.odin` `node_term` | `test_triple_term_renders_into_a_report` — 4 leaks |

The right-hand side of `sh:lessThan` is the one that nearly slipped: it decodes
through `session_term` directly rather than through `materialize`, so with a
literal on that side the pairing passed every test while doing nothing. The
test's `ex:q` carries a triple term for exactly that reason.

**Three pairings cannot be reached and are stated rather than tested.**
`record_ignored_parameters` decodes a shape node's *predicates*, `compile.odin`
decodes `sh:message` objects, and `test_term` renders a result — an IRI or a
literal in each case, and the only owning kinds are the triple term and the split
IRI (which `record.apply`'s encoder never writes). They are paired anyway,
because the rule is "pair every decode", not "pair the ones that leak today".

**On the three things the task said to check rather than assume:**

- **Base-direction literals need nothing.** A `"chat"@fr--ltr` is a literal with
  a language, which is what the engine already reads: `sh:nodeKind sh:Literal`
  holds, `sh:languageIn ( "fr" )` matches on the tag, and `sh:datatype
  rdf:langString` correctly does *not* hold — the datatype is
  `rdf:dirLangString`. `write_term_key` already wrote the direction byte, so the
  model interns two directions of one lexical form apart. Pinned, not assumed.
- **The seven `session_kind(…) == .IRI` / `== .Literal` equality sites are
  safe.** A triple term is neither, so `path.odin`'s node-or-literal split and
  `compile.odin`'s literal checks behave as they did. Read with the fourth kind
  in mind; nothing to change.
- **The model side was already total.** `rdf.clone_term` deep-clones a
  `^rdf.Triple`, `write_term_key` recurses, and `term_table_destroy` frees with
  `rdf.destroy_term`, which deep-frees. `test_a_shapes_graph_may_name_a_triple_term`
  proves it end to end — `sh:hasValue <<( ex:a ex:b ex:c )>>` compiles into the
  model, and `bindings_init` resolves it against a *different* store's dictionary
  (record's `snapshot_resolve` recursing through the components), so the
  comparison is the integer one it is for every other kind.

**Measured.** `make test` green: 133 in the engine package (125 + 8 new), 13
guards, 7 readme, 1 smoke, **23 W3C harness — 98 of 98 entries, unchanged**.
`make check` clean across all six packages. `make bench`: every read pin holds —
**7503 on the reference configuration**, 9003 on the three that were 9003 — and
peak memory is the same 20868 B. Nothing about what this engine asks the store
moved, which is what a pin bump for a *type* rather than a capability should look
like.

**What was amended rather than rewritten**, per the family convention: the
`node_kind_of` and `session_term` comments, the CI pin block (a fourth reason
added to its history), `README.md`'s pin paragraph and its borrow paragraph,
`bench/consumers.odin`'s "borrows again" note, the vision in three places,
`docs/handover-sparql.md` (its triple-term backend limit is gone), and
[[SHACL-T-0037]] — the port's handoff, which the family root points the
odin-rdf-sparql port at and which carried two claims this release falsifies.

**The new file is `shacl/rdf12_term_test.odin`** (8 tests), which is where RDF
1.2 lives in this repository: the corpus has no triple terms and never will —
SHACL 1.0 predates RDF 1.2 — so this is the only place the behaviour is written
down. Nothing pushed; the commit is local.