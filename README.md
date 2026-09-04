# odin-rdf-shacl

[![CI](https://github.com/odin-rdf/odin-rdf-shacl/actions/workflows/ci.yml/badge.svg)](https://github.com/odin-rdf/odin-rdf-shacl/actions/workflows/ci.yml)

Shape-based validation for the Odin RDF family: a SHACL implementation that
validates RDF data graphs against shapes graphs. Shapes are themselves RDF,
parsed with [odin-rdf-parser](../odin-rdf-parser); the data graph is a
snapshot of [odin-rdf-record](../odin-rdf-record) — the family's system of
record, an append-only hash-chained log replayed into a memory-resident
projection — read through one file of session verbs and nothing else. Written
in Odin with no external dependencies: the record has none, and nothing here
links native code.

**Status: SHACL Core is complete and the vendored W3C suite is green.** Every
constraint component of §4 that does not need SPARQL is implemented — the
value-type, cardinality, value-range, string-based, property-pair, logical,
shape-based and "other" families, twenty-nine components in all — alongside
shapes compilation, target resolution, property paths, and
`sh:ValidationReport` emission.

**All 98 entries of the W3C SHACL 1.0 suite's `core/` tree pass**, across all
seven directories, against odin-rdf-record over its in-memory file seam.
There is no skip list and no expected-failure file: this repository claims
conformance only for directories where *every* entry passes, and every directory
is now one of them. See `.metis/` for the vision, the initiatives, and the ADRs.

What is left is SHACL-SPARQL — `sh:sparql` and SPARQL-based constraint
components — which is a later phase and the only thing that would add
odin-rdf-sparql as a dependency. SHACL Core does not depend on it and will not.

**A constraint this engine does not implement is ignored, and the compile says
so.** Erroring instead would reject the spec's own non-validating annotations
(`sh:name`, `sh:description`, `sh:order`, `sh:group`, `sh:defaultValue`) and
every vendor extension a real shapes graph carries. But ignoring silently is
how a partial engine comes to look complete, so `shapes_ignored(&shapes)`
returns every `sh:` parameter the compile saw on a shape and skipped. **Check it
before trusting a `sh:conforms true`**: a report with no results and a non-empty
ignored list is not a validated graph.

Now that SHACL Core's catalogue is complete, a non-empty list means a vendor
extension or `sh:sparql` — not a missing Core component. It is empty for all 98
entries of the vendored suite, and the suite runner asserts that rather than
assuming it.

**`sh:datatype` checks the lexical form, but only for the datatypes it
models.** §4.1.2 asks two things — that the datatype IRI matches, and that the
value's lexical form lies in that datatype's lexical space — so
`"abc"^^xsd:integer` and `"300"^^xsd:byte` both violate `sh:datatype` even
though the IRI is right. The lexical spaces this engine knows are xsd:string,
xsd:boolean, the integer tower with its derived ranges, xsd:decimal, xsd:float,
xsd:double, xsd:dateTime, xsd:date, and rdf:langString. **For any other
datatype the check is skipped rather than failed**: an engine may call a
lexical form invalid only when it knows the space, so `sh:datatype rdf:HTML`
accepts whatever it is given. The set grows on evidence.

**`sh:pattern` is not XPath's regular expression dialect, and an unsupported
flag is an error rather than an ignore.** SHACL defines `sh:pattern` by XPath's
`fn:matches`, which is XML Schema's regular expression language with the flags
`i s m x q`. This engine uses Odin's `core:text/regex`, keeping the family's
no-external-dependencies rule, and that is a *different dialect*: the common
subset — literals, anchors, character classes, alternation, the usual
quantifiers — behaves the same, and anything beyond it may not. Of the flags,
`i`, `m`, and `x` map across; **`s` (dot matches newline) and `q` (treat the
pattern as a literal) have no equivalent and are rejected at compile time** with
`Error_Kind.Flags_Unsupported`. A pattern the engine cannot compile is
`Error_Kind.Pattern_Ill_Formed`. Both are refusals rather than silent
downgrades, because validating against a pattern other than the one written and
then reporting conformance is the failure worth avoiding. If you hit the
dialect gap, that is evidence worth filing — the choice was made by measuring
the W3C corpus, whose four patterns all sit in the common subset.

This is a peer of [odin-rdf-sparql](../odin-rdf-sparql) on the same
foundation, not a layer above it. **SHACL Core has no dependency on the query
engine at all** — not at runtime, and not at link time: the `sparql:`
collection is deliberately absent from the `Makefile` until the SHACL-SPARQL
phase begins. Inference and entailment regimes, SHACL Advanced Features
(rules, functions), and any server or protocol layer are out of scope
permanently.

## Packages

| Package | Description                                                                                                 |
| ------- | ----------------------------------------------------------------------------------------------------------- |
| `shacl` | The engine: shapes compilation, targets, paths, constraint dispatch, validation results, the report graph, the `Validator` |

One package, importing `rdf` and `record` and nothing else. **There is no
backend seam, by decision** (SHACL-I-0004, 2026-08-20): odin-rdf-record is the
one and only store this engine reads, now and in future, so the store is
touched in exactly one file — `shacl/session.odin`, six session verbs over a
snapshot — and nowhere is there an abstraction for a second store to bind to.
Until that day the engine was written backend-independent against
odin-rdf-store's match interface with `shacl/kvstore` instantiating it, and
`make check` grepped a built binary for LMDB symbols to prove the core linked
none; the port deleted the instantiation package, the width matrix and the
`purity` target together, and the old shape survives in this repository's
history.

## Performance

Numbers from `make bench`, on the **reference configuration**: 500 focus nodes,
3 property shapes, 4 value nodes each — 6000 value nodes, 20% of them
violating — with predicate paths and `sh:class` constraints, seed `0x5EED0001`.
Measured on Apple M-series, `-o:speed -no-bounds-check`, over odin-rdf-record's
memory seam (SHACL-T-0036, 2026-08-20).

| | odin-rdf-record |
| --- | ---: |
| `compile` (shapes graph → model) | 35 µs |
| `bind` (model → snapshot ids) | 8 µs |
| `validate` | 1.17 ms |
| per focus node | 2.3 µs |
| store reads | 7503 |

**The read count is the integer the old store produced**, here and on every
one of the eight standing configurations. The port expected the counts to
differ and said so in advance; they did not, and that is the strongest
statement it could make about itself: the engine asks the store exactly the
questions it asked before, and only what a question *costs* changed — a read
on odin-rdf-store was an LMDB cursor, on record it is a range over a
memory-resident permutation, and `validate` went from 4.69 ms to 1.17 ms on the
same walk.

`compile` and `bind` are measured **cold, once**, because that is what a process
pays — the deployment this family is designed around is ~200 processes per
machine each compiling a shapes graph at start-up. `validate` is a warm-up plus
the best of five, because the question there is steady-state cost.

**Memory.** Validation's working set is flat in the violation count, and the
benchmark asserts it rather than reporting it: peak is **20868 bytes** on the
identical walk whether 0, 1181, or 6000 results come out of it, over 5518
allocations either way. `conforms` stops at the first result and costs 2148
bytes and 16 allocations. A `Report` is the one consumer meant to grow, and
does — 2 triples for a conforming graph, 9450 for the reference configuration,
48002 when everything violates.

There is no id width to choose any more. The old store made `Term_ID` a
build-time choice and this table used to carry both; record's ids are 32-bit by
design, which is why the peak above is the figure the old **32-bit** build
reported (27076 → 20868 bytes) and not the 64-bit one.

**The odin-rdf-store numbers, for the record** (retired 2026-08-20 by
SHACL-I-0004; same configuration, same machine, kvstore over LMDB, 64-bit
`Term_ID`): `compile` 146 µs, `bind` 27 µs, `validate` 4.69 ms — 9.4 µs per
focus node — 7503 reads; peak 27076 bytes. The in-memory backend it retired in
turn measured 1.3 µs per focus node, the engine's own cost with storage out of
the way; record lands between the two, closer to the engine than to LMDB.

**What these numbers are not.** A synthetic workload this project chose. They
are a regression instrument and a comparative one — the engine against itself
over time, and with a change against without — not a claim about what SHACL
costs in the world. There is no standard SHACL benchmark corpus, and the W3C
suite is 98 files written to exercise semantics, several of them a dozen
triples; benchmarking against it would measure the harness. See `bench/` for the
workload's shape and the seven knobs that vary it.

## Building

The parser and the record are **sibling checkouts**, not vendored copies, and
are reached through Odin collections:

```
../odin-rdf-parser   -collection:rdf=../odin-rdf-parser
../odin-rdf-record   -collection:record=../odin-rdf-record
../odin-rdf-shacl    (this repository)
```

Both collections are required even though this engine only names the record:
the record's own sources import `rdf:`, and a collection is resolved in the
*importing* compilation, not the imported checkout. The `Makefile` and
`ols.json` both declare them. CI pins `odin-rdf-parser@v0.1.1` and
**`odin-rdf-record@v0.4.0`, which is a floor**: `v0.2.0` is where `ingest`
began emitting a document's *set* of statements (below it one W3C entry whose
shapes graph repeats a triple cannot load), `v0.3.0` is where the record's
`Term_ID`, `Fact_ID` and `Epoch` became distinct types, which this engine holds
natively, and `v0.4.0` is where RDF 1.2's triple terms arrived — a fourth
`record.Term_Kind`, which this engine switches on exhaustively, and
`snapshot_term_destroy`, the verb for the two term kinds that own their memory.
It names both, so it does not compile below `v0.4.0`. *(Since 2026-08-27 the pin is **`v0.5.0`**, SHACL-T-0040: `record.Filter` gained `scope`, which every read here states — a fifth floor, for an API change rather than a capability.)* *(And **`v0.6.0`** the same day, SHACL-T-0041: record's seventh order makes every session read a prefix, with nothing here changing.)* *(And **`v0.7.0`** on 2026-09-01, SHACL-T-0042: record's exported surface is 73 names where it was 195 — everything that was not API is `@(private)` now. Nothing here changed, which is the evidence that this engine consumes the published API and nothing else.)* *(And **`v0.8.0`** on 2026-09-04, SHACL-T-0043: the record's permutations are B+trees and a commit there is 0.24 ms where it was 37 — so a validated edit through the `Validator` hook costs the application milliseconds now. Nothing here changed; 7503 as pinned.)* *(And **`v0.9.0`** the same day, SHACL-T-0044: the record gained `snapshot_history`, every generation a pattern ever matched; this engine asks no temporal question and nothing here changed. 7503 as pinned.)*

```
make test    # the full suite, once — there is no width matrix
make check   # vet every package, both bench builds, then the import-alias rule
make bench   # timing build, then the instrumented build (reads, allocation, pins)
make help    # list targets
```

There is no id width to choose. The record's ids are fixed by design (its
inline term encoding is frozen at first write), so the `Term_ID` matrix the old
store's build-time width imposed on this repository's suite is gone, and every
CI runner runs the same `make test`. `make check` ends with a style rule the
vet cannot express: an import alias that repeats the last path component
(`import rdf "rdf:rdf"`) fails the build, because Odin already binds that name
and the alias says nothing. `make bench` builds twice because read counting is
a build-time switch in the engine (`-define:SHACL_COUNT_READS=true`,
`shacl/counting.odin`) that is compiled out of the timing run entirely.

**Platforms: Linux and macOS.** The record's real file operations are POSIX
(`posix_file_ops`, `#+build linux, darwin`); there is no Windows `File_Ops`,
Linux is the production environment and darwin is development. **Windows is not
supported** — dropped 2026-09-01, `RECORD-A-0011`. It had worked in the narrow
sense that the suites open stores over the platform-free memory seam
(`Mem_FS` + `mem_file_ops`) and never touch a real directory, so CI ran a
Windows leg proving this engine passes on a platform its store cannot host on.
That is a capability nobody wanted, and since odin-rdf-record `v0.7.0` the
package does not compile there at all: its in-package test files call
`posix_file_ops`, and Odin's `_test.odin` is a naming convention rather than a
build tag, so those files are part of the package every consumer compiles.
The record's *own* `make test` needs `python3` for its cross-implementation
verifier; a consumer compiling the library does not.

## Quick start

Validation is a compiled shapes model, a binding of that model to the snapshot
holding the data, and a visitor the results stream to: compile once, bind once
per snapshot, validate as often as you like. The examples below are compiled
and asserted by `tests/readme`, so they cannot drift from the API. That package
differs from what you see here in two ways and no others: it reaches sibling
directories where a consumer writes `rdf:` and `record:` collection imports,
and it opens its stores over the memory seam (`record.Mem_FS` +
`record.mem_file_ops`) where these open a directory on disk — see [Scratch
stores](#scratch-stores) below.

```odin
package main

import "core:strings"

import "rdf:rdf"
import "record:record"
import "record:record/ingest"

import "shacl"

SHAPES :: `
@prefix sh:  <http://www.w3.org/ns/shacl#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
@prefix ex:  <http://example.org/> .

ex:PersonShape a sh:NodeShape ;
	sh:targetClass ex:Person ;
	sh:property [
		sh:path ex:name ;
		sh:minCount 1 ;
		sh:datatype xsd:string ;
	] .
`

DATA :: `
@prefix ex: <http://example.org/> .

ex:alice a ex:Person ; ex:name "Alice" .
ex:bob   a ex:Person .
`

// load turns one Turtle document into ops and commits them as one epoch. The
// blank prefix scopes the document's blank nodes, so two documents cannot
// collide on `_:b0`.
load :: proc(db: ^record.Store, source: string, blank_prefix: string) -> bool {
	ops, ingest_err := ingest.turtle(
		transmute([]byte)source,
		nil,
		context.allocator,
		blank_prefix = blank_prefix,
	)
	if ingest_err.kind != .None {
		return false
	}
	defer ingest.ops_destroy(ops, context.allocator)
	_, _, apply_err := record.apply(db, {ops = ops})
	return apply_err == record.Apply_Error{}
}

// Validation is a compiled shapes model, a binding of that model to the
// snapshot holding the data, and a visitor the results stream to.
validate_example :: proc(report: ^[dynamic]string) -> shacl.Failure {
	// 1. Open the store. Shapes and data live in graphs of it; this example
	//    uses one store and loads both into the default graph.
	db: record.Store
	_, open_err, _, _ := record.store_open(&db, "/var/lib/example/rdf", record.posix_file_ops())
	if open_err != .None {
		return .None
	}
	defer record.store_close(&db)

	// 2. Load the two documents — each is one changeset, one epoch.
	if !load(&db, SHAPES, "shapes_") || !load(&db, DATA, "data_") {
		return .None
	}

	// 3. Take a snapshot and bind a session over the graph to read. A
	//    snapshot is a value: acquire, use, release.
	snap, snap_err := record.store_latest(&db)
	if snap_err != .None {
		return .None
	}
	defer record.snapshot_release(&snap)
	se: shacl.Session
	shacl.session_init(&se, snap)

	// 4. Compile the shapes graph. The model owns every term it holds, so the
	//    snapshot may be released afterwards and the model bound to another
	//    store entirely. Compile once and keep the model.
	shapes: shacl.Shapes
	defer shacl.shapes_destroy(&shapes)
	if shacl.compile(&shapes, se).kind != .None {
		return .None
	}

	// 5. Bind the model's terms to this snapshot's ids — once per validation,
	//    not once per check. A model compiled elsewhere binds here just as well.
	bindings: shacl.Bindings
	shacl.bindings_init(&bindings, &shapes, se)
	defer shacl.bindings_destroy(&bindings)

	// 6. Validate. Results are handed to the visitor as they are found and
	//    nothing is buffered, so memory stays flat however bad the data is.
	sink := Sink {
		shapes = &shapes,
		se     = se,
		lines  = report,
	}
	return shacl.validate(&shapes, &bindings, se, on_result, &sink)
}

Sink :: struct {
	shapes: ^shacl.Shapes,
	se:     shacl.Session,
	lines:  ^[dynamic]string,
}

// A Result borrows and owns nothing: it names nodes by id and the shape by
// index, and is valid only for this call. Keep anything you need by copying
// it out — or use `validate_report` and let the report do it for you.
on_result :: proc(data: rawptr, result: shacl.Result) -> bool {
	sink := cast(^Sink)data
	buf: shacl.Term_Buf
	focus, _ := shacl.session_term(sink.se, result.focus.id, buf[:])
	defer shacl.session_term_destroy(sink.se, result.focus.id, focus)
	if iri, is_iri := focus.(rdf.IRI); is_iri {
		append(sink.lines, strings.clone(string(iri), context.temp_allocator))
	}
	// Returning false would stop validation here — no further focus nodes
	// resolved, no further paths walked.
	return true
}
```

`ex:bob` has no `ex:name`, so `sh:minCount 1` reports one violation; `ex:alice`
conforms.

Two things the example shows in passing. **A write is a changeset and an
epoch**: `ingest.turtle` turns a document into ops, `apply` commits them, and
the record refuses rather than ignores a changeset that re-asserts a fact
already live — so a document is loaded once, not "again to be sure".
**`session_term` hands a term out and `session_term_destroy` takes it back**:
most terms live in the record's dictionary arena or in the buffer you passed,
which is why the visitor clones what it keeps — but a triple term and a split
IRI are allocated, so pairing the two is what keeps ownership from being a
question the caller has to answer. The destroy is a no-op for the borrowing
kinds, which is what makes pairing it with *every* call the simple rule.

### Scratch stores

A record store is a directory of log segments, and `record.posix_file_ops()`
is how it reaches one. When the data is scratch — a test, a validation of
something you are about to throw away, a staging graph — open it over the
memory seam instead: `Mem_FS` is an in-memory file system with the same
`File_Ops` contract, and a store over it dies with the value that holds it.

```odin
fs: record.Mem_FS
defer record.mem_fs_destroy(&fs)
db: record.Store
_, open_err, _, _ := record.store_open(&db, "scratch", record.mem_file_ops(&fs))
defer record.store_close(&db)
```

Nothing to name, make unique, or clean up, and it is allocator-backed rather
than filesystem-backed, which is how the suites run on every CI runner without
leaving a directory behind. Every snapshot must be released before `store_close`; the
record asserts it. A `Mem_FS` must stay where it is for the store's lifetime
(the writer holds a pointer to it), so open the store in the scope that owns
the `Mem_FS` rather than returning either by value.

### Three consumers, one traversal

The result stream is the primitive. The other two forms are ordinary consumers
of it, and each is one call:

```odin
// Just the answer. Stops at the first result of any severity rather than
// finding them all — which at ~200 processes per machine is the difference
// worth having. A warning breaks conformance exactly as a violation does (§3.1).
ok, failure := shacl.conforms(&shapes, &bindings, se)

// The sh:ValidationReport graph, finished and ready to serialise. Emitting it
// is odin-rdf-parser's job, through any of its four emitters.
report: shacl.Report
shacl.report_init(&report)
defer shacl.report_destroy(&report)
failure := shacl.validate_report(&report, &shapes, &bindings, se)
```

**Check the `Failure` before the answer.** It is the spec's *failure* (§3.3),
not a result: `.None` means the traversal completed or your visitor stopped it,
and anything else means the processor could not answer — which is not the same
as "no".

**Reading blank nodes back out of a report.** A report names nodes in three
graphs at once, so their blank-node labels are kept apart — otherwise a data
graph's blank node and a shapes graph's blank node that happen to share a label
would merge into one node in the report:

| Label        | Comes from                                             |
| ------------ | ------------------------------------------------------ |
| *as loaded*  | the **data graph**, exactly as the store holds it — `sh:focusNode`, `sh:value` |
| `_:s…`       | the **shapes graph**, its store label prefixed with `s` — `sh:sourceShape` |
| `_:r…`       | the **report itself**: the report node, each result, and blank-node `sh:resultPath` structures |

The record interns blank-node labels as `ingest` hands them over — the
document's own label under the `blank_prefix` you gave it (`data_` and
`shapes_` in the quick start) — so `sh:value _:data_b0` is the data graph's
`_:data_b0` and can be looked up there directly, which is the point: it is how
a result says *which* unnamed node failed. A blank-node `sh:sourceShape
_:sshapes_b3` is the shapes graph's `_:shapes_b3`, with the `s` stripped. The
one rule this asks of you: **a `blank_prefix` must be label characters, and must
not begin with `r`** (nor, for a data graph, `s`), because the prefix is what
keeps the three namespaces apart. `data_` and `shapes_` are fine; `r1_` is not.

There is a fourth, narrower question: **does one node conform to one shape?**

```odin
// A shape is named by its index in the compiled model — the same index a
// Result carries in `result.shape`. Shapes with an IRI can be found by it; a
// focus node is named by term, through `node_focus`.
shape_index, _ := shacl.shape_index_of(&shapes, rdf.IRI("http://example.org/PersonShape"))

ok, failure := shacl.conforms_node(
	&shapes, &bindings, se,
	shape_index, shacl.node_focus(se, rdf.IRI("http://example.org/alice")),
)
```

It produces no results — the question is the boolean — and it validates the
named shape and every `sh:property` shape below it (§3.4). Unlike `conforms`, it
does not care what the shapes graph targets: the caller names both the node and
the shape. This is also the mechanism `sh:not`, `sh:or`, `sh:xone`, `sh:node`,
and `sh:qualifiedValueShape` are built on, which is why it exists before they do
(SHACL-A-0002).

When you need to say *why not*, `validate_node` is the same question with the
results:

```odin
failure := shacl.validate_node(
	&shapes, &bindings, se,
	shape_index, shacl.node_focus(se, rdf.IRI("http://example.org/alice")),
	visit, visit_data,
)

// Or straight to a sh:ValidationReport about that one node:
failure = shacl.validate_node_report(
	&report, &shapes, &bindings, se,
	rdf.IRI("http://example.org/alice"), shape_index,
)
```

This is what a write path wants: accept a resource, check it, and tell whoever
submitted it which constraint it broke. **Reach for it rather than filtering
`validate`'s results by focus node** — that works, and it validates every
targeted node in the dataset to answer about one, so asking about a single
resource costs the data around it.

The two are one walk, not two evaluators: `conforms_node` is `validate_node`
with a probe that records the first result and stops. A node the data graph
never mentions is a perfectly good focus node in both — validated as unbound,
with every path from it reaching nothing, which is emptiness and violates
`sh:minCount 1`. (One record detail shows here: a small canonical integer or
date is *always* resolvable, because the record's inline encoding gives it an
id without the dictionary, so such a focus node is bound even when the data
never mentions it. The verdict is the same either way — every path from it
still reaches nothing.)

### Deciding whether a write may join the dataset

The record store has one write entrance, `apply`, and one validator per store,
wired at `store_open` and consulted on every changeset before a byte is
written (`RECORD-A-0006`). A `Validator` is a compiled shapes model in that role:
`apply` hands it **the dataset the write would produce** — head plus changeset,
as an ordinary snapshot at the new epoch — and it is validated like any other
snapshot.

```odin
// 1. Compile the shapes once, from wherever they live. The model owns every
//    term it holds, so the store it came from may be closed — here it is.
shapes: shacl.Shapes
defer shacl.shapes_destroy(&shapes)
compile_shapes(&shapes, SHAPES)

// 2. Make a validator of the model and open the data store with it wired in.
//    One validator per store; it must stay where it is until the store closes.
v: shacl.Validator
shacl.validator_init(&v, &shapes)
defer shacl.validator_destroy(&v)

db: record.Store
_, open_err, _, _ := record.store_open(
	&db,
	"data",
	record.posix_file_ops(),
	validator = shacl.validator_hook(&v),
)
if open_err != .None {
	return
}
defer record.store_close(&db)

// 3. Every apply is validated against the dataset it would produce. Under
//    Enforce a violation is refused and nothing is written; under Record it
//    commits and `conforms` carries the verdict.
ops, _ := ingest.turtle(transmute([]byte)string(CANDIDATE), nil, context.allocator, blank_prefix = "c_")
defer ingest.ops_destroy(ops, context.allocator)
_, conforms, err := record.apply(&db, {ops = ops, mode = .Enforce})

// 4. The validator holds the last apply's report — valid until the next apply.
if err.kind == .Rejected {
	report := shacl.validator_report(&v)
	// report_triples(report): the sh:ValidationReport, ready for any emitter
}
```

**The obvious alternative is wrong, not merely slow.** Building the candidate in
a store of its own and validating *that* makes every constraint which must
consult existing data read an empty world and pass: a `sh:maxCount` over a
property the dataset already carries values for, a `sh:class` against a
hierarchy that lives only in the committed graph, uniqueness across the
dataset. A validator that cannot fail is worse than one that is absent.

Four things the binding decides, each stated in `validator.odin`:

- **The verdict's effect is the changeset's `Mode`, not the validator's.** Enforce
  refuses (`apply` returns `.Rejected`, the store is exactly as it was);
  Record commits and reports. **The log does not record that a validator
  objected** — a Record-mode epoch whose changeset did not conform is
  byte-for-byte the epoch a conforming one would have written. A consumer
  that wants the verdict durable writes the report as facts.
- **Reset per apply.** The validator's report and verdict are always the *last*
  apply's; keep a report by emitting or copying it before applying again.
  `validator_init(…, reporting = false)` keeps no report at all and allocates
  nothing per result — the shape a gate that only needs yes or no should take.
- **A `Failure` is a refusal.** When the engine cannot answer (a recursive
  shape), the verdict is false and `v.failure` says why; a validator that
  cannot answer does not let a write through.
- **Whole graph, one graph.** Each check validates every target of every
  shape in the validator's graph (`validator_init`'s `graph`; the default graph by
  default), not only the nodes the changeset touched — a change to one node
  can make another violate. The candidate snapshot is never retained past
  the check, which is record's contract for it.
  *(Or the whole union: `validator_init_union` reads a set of graphs, resolved
  against each candidate — SHACL-T-0039.)*

### Validating the past

The record never erases: a retraction ends a fact's lifetime and leaves it
readable at every earlier epoch. So a past dataset is validated exactly as the
present one is — `record.store_at` where the examples above say
`store_latest`, and nothing below the session changes:

```odin
// A snapshot pinned at `epoch` — 0 is the empty world before the first
// commit, and the future is refused (Snapshot_Error.Future_Epoch), not clamped.
snap, snap_err := record.store_at(&db, epoch)
if snap_err != .None {
	return
}
defer record.snapshot_release(&snap)
se: shacl.Session
shacl.session_init(&se, snap)

bindings: shacl.Bindings
shacl.bindings_init(&bindings, &shapes, se)
defer shacl.bindings_destroy(&bindings)

conforms, failure := shacl.conforms(&shapes, &bindings, se)

// Who committed that epoch, why, and when — decoded like any other term.
meta := record.snapshot_epoch_meta(snap, epoch)
```

**The coordinate is the epoch, not a time.** The record has no `epoch_at(wall)`:
its wall clock is advisory evidence, not an index. A caller holding a time finds
the epoch by its own bookkeeping, or by walking `snapshot_epoch_meta`, whose
`wall` is there to be compared against. Terms are not epoch-scoped — a term
resolves at every epoch, including before it was first written — only facts
are, so one compiled model binds at any epoch.

Three reasons to ask, since the record is immutable and remediation is never
one of them: validating past data under the *current* shapes explains the
present (bisect for the epoch that introduced a violation; the metadata names
who and why) and reports exposure windows for newly adopted rules; validating
past data under the *then-current* shapes is the accountability question —
compile the model from the pinned snapshot's shapes graph and validate the same
snapshot's data graph with it, one moment feeding both sessions. That second
form is the recomputation `RECORD-A-0006` decision 5 leans on: the log does not
record that a validator objected, so a verdict about the past is recoverable
only by recomputing it over the epoch-pinned dataset.

## Memory contract

The family's discipline is borrow-by-default (RDF-A-0001). This project
deviates in exactly two places, both so that a lifetime rule does not depend on
the store's arena:

| Object     | Owns                              | Valid until          |
| ---------- | --------------------------------- | -------------------- |
| `Shapes`   | every term it holds               | `shapes_destroy`     |
| `Report`   | every term in the graph           | `report_destroy`     |
| `Result`   | **nothing** — IDs and indices     | the visitor call     |
| `Bindings` | IDs only, borrowed from neither   | `bindings_destroy`   |

A compiled model owning its terms is what lets **the store a shapes graph was
compiled from be closed immediately afterwards**, and a report owning its
terms is what lets it outlive the store it describes. That is not a nicety: a
term the record hands out is decoded from its dictionary arena, which closing
the store frees, and the W3C runner closes every entry's shapes store before it
opens the data store.

A `Result` allocating nothing is what keeps memory flat as the violation count
grows. Copy out what you need, or fold it into a `Report`.

## Four things to know before writing shapes

The first two are decided in SHACL-A-0001, the rest are the spec's, and every
one of them surprises someone.

**Validation reads one graph.** SHACL is specified against a single RDF graph;
the record holds a quad dataset. The validator takes the graph to read — the
default graph, or one named graph — and never a union of them; the graph is
bound into every pattern `shacl/session.odin` issues.

*(Amended 2026-08-27, SHACL-T-0039: **or the union of a set of graphs.**
`session_init_union` / `validator_init_union` take a set of graph labels and
validate the set-union of their triples as the data graph — a workspace and
its ancestors, an instance graph and its ontology. The single graph is the
one-element case and is read exactly as before; an empty set is an empty data
graph, never the whole store; the same triple in two graphs of the set counts
once. Every read in the package — the session verbs and the compiler's
`reader_match` — takes its filter from the session.)*

**`sh:class` needs the class hierarchy in the data graph.** It walks
`rdfs:subClassOf*` in the graph being validated, not in the shapes graph. A
shape that says `sh:class ex:Asset` will not see that `ex:ResourceAsset` is a
subclass of `ex:Asset` unless that triple is in the data graph. This is the
most common way a shapes graph silently under-reports, and it follows from the
single-graph decision above. `sh:targetClass` walks the same closure, so a
target that unexpectedly finds nothing usually has the same cause.

*(Since SHACL-T-0039 the answer is a union: put the ontology's graph in the
session's set and the closure is there.)*

**`sh:conforms` is false whenever there is any result at all**, whatever its
severity. A warning sounds like it should not count against conformance, and
does not in some other systems, but §3.1 makes conformance a question about
whether the report has results rather than about what they say. Relatedly,
**`sh:severity` is any IRI**: `sh:Violation`, `sh:Warning`, and `sh:Info` are
built-ins, not the whole set, and a shape declaring `sh:severity ex:MySeverity`
compiles and reports under it.

**Recursive shapes are reported as a failure, not validated.** §3.4 leaves
recursion undefined and explicitly permits a processor to signal a failure,
which is what this does: `validate` returns `Failure.Recursive_Shape` at the
first re-entry of a shape already being validated. Cycle-breaking ("assume
valid on re-entry") stays addable later if evidence asks for it.

**Cycles in *data* are not recursion**, and this is the distinction to hold on
to. A graph where `ex:a` is `ex:partOf` `ex:b` which is `ex:partOf` `ex:a` is
ordinary, and validates: recursion is a property of the *shapes*, detected on
the set of shapes currently being validated. What triggers it is a shape that
reaches itself — through `sh:property`, through any of the logical combinators,
through `sh:node`, or through `sh:qualifiedValueShape`. **`sh:node` is how you
write one by accident**, on data where an asset points at an asset. Every
property-path form is separately cycle-safe over data, so `sh:zeroOrMorePath`
over the graph above terminates.

## License

See [LICENSE](LICENSE).
