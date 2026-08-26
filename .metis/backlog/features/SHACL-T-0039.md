---
id: validate-the-union-of-a-graph-set
level: task
title: "Validate the union of a graph set: reopening SHACL-A-0001 decision 5 for workspaces"
short_code: "SHACL-T-0039"
created_at: 2026-08-26T21:10:59.438464+00:00
updated_at: 2026-08-26T21:10:59.438464+00:00
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

# Validate the union of a graph set: reopening SHACL-A-0001 decision 5 for workspaces

## Objective **[REQUIRED]**

Let a session validate against **the union of a set of graphs**, so that
a shape in one workspace can see the data its workspace's ancestors hold
— and reopen `SHACL-A-0001` decision 5 ("one caller-named graph, never a
union") on the trigger that ADR wrote for exactly this.

**The consumer.** The application above this engine is introducing a
**workspace**, decided on 2026-08-26 as **a named graph per workspace**:
a statement's graph is the workspace it was made in; a user in `B` reads
`{B} ∪ ancestors(B)`; siblings never see each other. The case that
validation must handle:

```
graph A:  a:ctrl7  a  control:Control .          — the ancestor's
graph B:  b:risk1  a  risk:Risk ;                 — the workspace's
          b:risk1  risk:mitigatedBy  a:ctrl7 .    — the link, made in B
shape:    risk:mitigatedBy  sh:class  control:Control .
```

**What this engine does today.** Validating `B` reports a violation,
structurally: every read binds **one** graph — `session.odin:155`,
`:179`, `:206` all issue `record.Pattern{…, g = se.graph}` with
`Filter{origin = .Any}` and no `graphs` — `Session` holds one resolved
id, `validator_init` takes one `rdf.Graph_Label`, and
`a:ctrl7 a control:Control` is not in `B`. This is the under-reporting
CLAUDE.md already documents as "the most common way a shapes graph
silently under-reports" (`sh:class` needs the hierarchy in the *data*
graph), made permanent by the workspace design rather than occasional.

**The decision.** `SHACL-A-0001` decision 5 is enforced in one file and
its review trigger reads: *"A consumer needs cross-graph or dataset-wide
validation with a semantics it can defend. That reopens decision 5."*
This is that consumer. The semantics to defend is plain: **the data graph
is the union of the graphs in the set** — an RDF graph, the set-union of
their triples. On the record it is a union rather than a merge, because
blank nodes are global interned terms (scoped at ingest by
`blank_prefix`), so no relabelling question arises. **A one-element set
is today's semantics exactly**, so all 98 suite results keep meaning what
the spec says; decision 5 is generalized with the single graph as its
degenerate case, not reversed. Whether to take it is the owner's call —
the decisions in this repository were made for this repository.

## Design

- **`Session` carries a set** of resolved `record.Term_ID`s. The three
  verbs bind `g = 0` and pass `Filter{origin = .Any, graphs = se.graphs}`
  when a set is present; a single graph keeps today's `g = se.graph`
  (one residual compare, and a prefix once `RECORD-T-0028` lands).
  Nothing above `session.odin` writes a `Pattern` — decision 5's
  "enforced in one file" holds unchanged.
- **`session_init` and `validator_init` take `[]rdf.Graph_Label`.** The
  validator copies the labels (it copies one today,
  `validator.odin:81-95`, per `SHACL-A-0001`'s ownership rule) and
  resolves them against the **candidate** at each `validate`
  (`validator.odin:165-168`), so a graph the changeset itself creates
  resolves. A label the store has never seen **contributes nothing and
  is dropped** — `GRAPH_ABSENT`'s reasoning (`session.odin:37-47`) applied
  per element; `0` must never enter the set, since in a `Filter.graphs`
  set `0` is the default graph (`record/read.odin:53`);
  `MATCH_DEFAULT_GRAPH` names the default graph deliberately. Keep the
  single-label form as a convenience if the owner wants it; the public
  `validate*` procedures take a `Session` and do not change.
- **An empty set is an empty data graph, never the whole store.** record
  treats `nil` and an empty slice identically (Odin: `make([]T, 0) ==
  nil` is true, verified 2026-08-26); record's own fix is
  **`RECORD-T-0029`**, a stated `Graph_Scope` beside `Origin`, sequenced
  ahead of this task — if it has landed, the three verbs state
  `scope = .Set` and bump the floor. This engine already has the right
  tool regardless: an empty scoped set binds `GRAPH_ABSENT`, which matches nothing
  — class targets find no focus nodes, `sh:targetNode` is unbound — with
  no special case downstream. Pin it.
- **Duplicates are already handled — verified, not assumed.** Under a
  union the same triple in two graphs of the set is two facts. Focus
  nodes dedupe by id in `resolve_targets` (`target.odin:109-118`);
  `value_nodes` returns a set (`path_eval.odin:67`); `sh:closed` reads
  `session_outgoing` as a membership test. A test should pin this all
  the same (a triple asserted in both graphs → one focus node,
  `sh:maxCount 1` conforms), because it is the one place a union could
  change a count.
- **Nothing else moves**: the report has no graph per result; `sh:value`
  rendering is unchanged; the single-graph read path keeps its pins
  (7503 on the reference configuration); the set path gets its own pin.
- **Documents**: amend `SHACL-A-0001` decision 5 with a dated note (the
  union semantics, the one-element case as today's behaviour, and that
  the `STORE-T-0017` reference stays moot); re-read the vision's Current
  State for "validation reads one graph" claims and `docs/` for the
  `sh:class`-needs-the-hierarchy note, which gets a real answer — put the
  ontology graph in the set.

## Acceptance Criteria **[REQUIRED]**

- [ ] The case above: session set `{B, A}` conforms; set `{B}` reports
      the violation it reports today — both pinned.
- [ ] `sh:targetClass` with `rdfs:subClassOf` held in an ontology graph
      in the set: subclass instances are focus nodes.
- [ ] A triple asserted in two graphs of the set: one focus node, one
      value node, `sh:maxCount 1` conforms.
- [ ] An empty scoped set validates as an empty data graph — never the
      whole store — independent of record's `nil`/empty conflation
      (`RECORD-T-0029`).
- [ ] 98/98 W3C `core/` entries unchanged; single-graph read pins
      unchanged; a pin for the set path.
- [ ] `SHACL-A-0001` decision 5 amended with a dated note, not rewritten;
      the vision's Current State re-read; the record floor unchanged
      (`v0.4.0` suffices — `Filter.graphs` has been on the read API since
      `RECORD-I-0002`).
- [ ] `make test` and `make check` green.

## Implementation Notes

### Dependencies

- None hard on the record or on odin-rdf-sparql. `RECORD-T-0029` is
  sequenced ahead and changes `Filter`'s shape; if it lands first, this
  task raises the record floor and states scope at the three verbs.
  Related: `RECORD-T-0028`
  (a `GPOS` order — makes the single-graph prefix reads exact, needs
  nothing from here) and `SPARQL-T-0044` (the same set as a ceiling on
  the query side). Note for a SHACL-SPARQL phase: a `sh:sparql`
  constraint would have to run its query under the **same** set the
  session holds, or it could see more than the validation it serves.

### Effort

S in code — three verbs, one struct, two init procedures, the label
copies. The ADR amendment, the tests and the document re-reads are the
rest; M with those.

## Status Updates **[REQUIRED]**

- **2026-08-26 — Filed** from the workspace design discussion with the
  owner, with agreement to file cross-repository. The finding: a shape
  in a workspace cannot see an ancestor's data because every read binds
  one graph by decision, and the workspace design makes that the common
  case rather than the corner. Not started; reopening decision 5 is the
  owner's call.
