# odin-rdf-shacl

[![CI](https://github.com/odin-rdf/odin-rdf-shacl/actions/workflows/ci.yml/badge.svg)](https://github.com/odin-rdf/odin-rdf-shacl/actions/workflows/ci.yml)

Shape-based validation for the Odin RDF family: a SHACL implementation that
validates RDF data graphs against shapes graphs. Shapes are themselves RDF,
parsed with [odin-rdf-parser](../odin-rdf-parser); the data graph is read
through [odin-rdf-store](../odin-rdf-store)'s match interface alone, so the
same shapes validate against any backend the store offers. Written in
Odin with no external dependencies.

**Status: SHACL Core is complete and the vendored W3C suite is green.** Every
constraint component of §4 that does not need SPARQL is implemented — the
value-type, cardinality, value-range, string-based, property-pair, logical,
shape-based and "other" families, twenty-nine components in all — alongside
shapes compilation, target resolution, property paths, and
`sh:ValidationReport` emission.

**All 98 entries of the W3C SHACL 1.0 suite's `core/` tree pass**, across all
seven directories, against the LMDB-backed store, at both `Term_ID` widths.
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

| Package          | Description                                                     |
| ---------------- | --------------------------------------------------------------- |
| `shacl`          | The backend-independent core: shapes compilation, targets, paths, constraint dispatch, validation results |
| `shacl/kvstore`  | The validator instantiated against the persistent (LMDB) backend |

`shacl` names no storage backend and imports none. That split was originally
what kept LMDB out of the link of a program that only wanted an in-memory
store; odin-rdf-store retired that backend (STORE-A-0006), so today it is the
seam a future backend would bind to rather than a linkage guarantee. `make
check` still builds a core-only consumer and fails if the binary carries LMDB
symbols, which now catches a stray backend import in the core rather than
protecting a consumer.

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

The parser and the store are **sibling checkouts**, not vendored copies, and
are reached through Odin collections:

```
../odin-rdf-parser   -collection:rdf=../odin-rdf-parser
../odin-rdf-store    -collection:store=../odin-rdf-store
../odin-rdf-shacl    (this repository)
```

Both collections are required even though SHACL Core only names the store: the
store's own sources import `rdf:`, and a collection is resolved in the
*importing* compilation, not the imported checkout. The `Makefile` and
`ols.json` both declare them.

```
make test    # the full suite at both Term_ID widths (64-bit default, 32-bit opt-in)
make check   # vet every package, then assert the core links no LMDB
make bench   # build and run benchmarks with release flags (once bench/ exists)
make help    # list targets
```

`Term_ID` width is a build-time choice in odin-rdf-store (STORE-A-0001) and
this project compiles the store's sources into its own binaries, so validation
code must not assume 64-bit IDs. `make test` runs the whole matrix rather than
one configuration.

## Quick start

Validation is three objects and three steps: compile a shapes graph once, bind
the model to the store holding the data once, then validate as often as you
like. The examples below are compiled and asserted by `tests/readme`, so they
cannot drift from the API. That package differs from what you see here in two
ways and no others: it reaches sibling directories where a consumer writes
`rdf:` and `store:` collection imports, and it calls `kvstore.open_ephemeral`
where these open a path you would have chosen — see [Scratch
datasets](#scratch-datasets) below.

```odin
package main

import rdf "rdf:rdf"
import kvstore "store:store/kvstore"

import shacl "shacl"
import shacl_kvstore "shacl/kvstore"

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

// Validation is a compiled shapes model, a binding of that model to the store
// holding the data, and a visitor the results stream to.
validate_example :: proc(report: ^[dynamic]string) -> shacl.Failure {
	// 1. Open the store. It is a directory on disk, opened once and kept.
	//    Shapes and data live in graphs of it; this example uses one store and
	//    loads both into the default graph.
	db, open_err := kvstore.open("/var/lib/example/rdf")
	if open_err != nil {
		return .None
	}
	defer kvstore.close(db)

	// 2. Compile the shapes graph. The model owns every term it holds, so the
	//    store may be closed afterwards and the model bound to another one.
	//    Compile once and keep the model: loading a shapes graph twice does not
	//    dedupe, because each load mints fresh blank nodes.
	shapes: shacl.Shapes
	defer shacl.shapes_destroy(&shapes)

	err, parse_err, _ := shacl_kvstore.compile_turtle(&shapes, db, transmute([]byte)string(SHAPES))
	if parse_err.message != "" || err.kind != .None {
		return .None
	}

	// 3. Load the data graph.
	kvstore.load_turtle(db, transmute([]byte)string(DATA))
	session: shacl_kvstore.Session
	shacl_kvstore.session_init(&session, db)

	// 4. Bind the model's terms to this store's IDs — once per validation, not
	//    once per check. A model compiled elsewhere binds here just as well.
	bindings: shacl.Bindings
	shacl_kvstore.bind(&bindings, &shapes, &session)
	defer shacl.bindings_destroy(&bindings)

	// 5. Validate. Results are handed to the visitor as they are found and
	//    nothing is buffered, so memory stays flat however bad the data is.
	sink := Sink {
		shapes  = &shapes,
		session = &session,
		lines   = report,
	}
	return shacl_kvstore.validate(&shapes, &bindings, &session, on_result, &sink)
}

Sink :: struct {
	shapes:  ^shacl.Shapes,
	session: ^shacl_kvstore.Session,
	lines:   ^[dynamic]string,
}

// A Result borrows and owns nothing: it names nodes by Term_ID and the shape
// by index, and is valid only for this call. Keep anything you need by copying
// it out — or use `validate_report` and let the report do it for you.
on_result :: proc(data: rawptr, result: shacl.Result) -> bool {
	sink := cast(^Sink)data
	focus, _ := kvstore.lookup_term(sink.session.db, result.focus.id, context.temp_allocator)
	if iri, is_iri := focus.(rdf.IRI); is_iri {
		append(sink.lines, string(iri))
	}
	// Returning false would stop validation here — no further focus nodes
	// resolved, no further paths walked.
	return true
}
```

`ex:bob` has no `ex:name`, so `sh:minCount 1` reports one violation; `ex:alice`
conforms.

### Scratch datasets

Every dataset is a filesystem path, because LMDB has no in-memory mode. When the
data is scratch — a test, a validation of something you are about to throw away,
a staging graph — `kvstore.open_ephemeral()` gives you a store with no path to
name, make unique, or clean up, and which does not outlive the process:

```odin
db, err := kvstore.open_ephemeral()   // same contract, same procedure set as open
defer kvstore.close(db)               // no directory to remove afterwards
```

On POSIX the file is unlinked as soon as it is open, so it is invisible for the
store's whole life and reclaimed on close *or on crash*. Windows has no
unlink-while-open, so an abnormal termination leaks one file in the temp
directory.

The reason to reach for it is not only tidiness. Its default map is 16 MiB
rather than `open`'s 1 GiB, and on Windows LMDB has no sparse-file handling, so
**every `open` there materializes the full map size on disk**. A suite that
opens a store per test spends minutes writing files it never reads. This
repository's own suites use it throughout, with two deliberate exceptions: the
LMDB linkage proof, which is worth running against the durable constructor, and
the test that reopens a store read-only, which needs a path to reopen.

### Three consumers, one traversal

The result stream is the primitive. The other two forms are ordinary consumers
of it, and each is one call:

```odin
// Just the answer. Stops at the first result of any severity rather than
// finding them all — which at ~200 processes per machine is the difference
// worth having. A warning breaks conformance exactly as a violation does (§3.1).
ok, failure := shacl_kvstore.conforms(&shapes, &bindings, &session)

// The sh:ValidationReport graph, finished and ready to serialise. Emitting it
// is odin-rdf-parser's job, through any of its four emitters.
report: shacl.Report
shacl.report_init(&report)
defer shacl.report_destroy(&report)
failure := shacl_kvstore.validate_report(&report, &shapes, &bindings, &session)
```

**Check the `Failure` before the answer.** It is the spec's *failure* (§3.3),
not a result: `.None` means the traversal completed or your visitor stopped it,
and anything else means the processor could not answer — which is not the same
as "no".

**Reading blank nodes back out of a report.** A report names nodes in three
graphs at once, so their blank-node labels are kept apart — otherwise the data
graph's first blank node and the shapes graph's first blank node, both `_:b0` as
the store labels them, would merge into one node in the report:

| Label   | Comes from                                             |
| ------- | ------------------------------------------------------ |
| `_:b…`  | the **data graph**, exactly as the store labelled it — `sh:focusNode`, `sh:value` |
| `_:s…`  | the **shapes graph**, its store label prefixed with `s` — `sh:sourceShape` |
| `_:r…`  | the **report itself**: the report node, each result, and blank-node `sh:resultPath` structures |

So `sh:value _:b0` is the data graph's `_:b0` and can be looked up there
directly, which is the point — it is how a result says *which* unnamed node
failed. A blank-node `sh:sourceShape _:sb3` is the shapes graph's `_:b3`, with
the `s` stripped.

There is a fourth, narrower question: **does one node conform to one shape?**

```odin
// A shape is named by its index in the compiled model — the same index a
// Result carries in `result.shape`. Shapes with an IRI can be found by it.
shape_index, _ := shacl.shape_index_of(&shapes, rdf.IRI("http://example.org/PersonShape"))

ok, failure := shacl_kvstore.conforms_node(
	&shapes, &bindings, &session,
	rdf.IRI("http://example.org/alice"), shape_index,
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
failure := shacl_kvstore.validate_node(
	&shapes, &bindings, &session,
	rdf.IRI("http://example.org/alice"), shape_index,
	visit, visit_data,
)

// Or straight to a sh:ValidationReport about that one node:
failure = shacl_kvstore.validate_node_report(
	&report, &shapes, &bindings, &session,
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
`sh:minCount 1`.

`shacl/kvstore` has the same entry points against the persistent backend, taking
a `Session` where these take a dictionary and a dataset.

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
which backend you chose:

| Object     | Owns                              | Valid until          |
| ---------- | --------------------------------- | -------------------- |
| `Shapes`   | every term it holds               | `shapes_destroy`     |
| `Report`   | every term in the graph           | `report_destroy`     |
| `Result`   | **nothing** — IDs and indices     | the visitor call     |
| `Bindings` | IDs only, borrowed from neither   | `bindings_destroy`   |

A compiled model owning its terms is what lets **the store a shapes graph was
compiled from be destroyed immediately afterwards**, and a report owning its
terms is what lets it outlive the store it describes. On the persistent backend
that is not a nicety: terms come from mapped database pages that closing the
store invalidates.

A `Result` allocating nothing is what keeps memory flat as the violation count
grows. Copy out what you need, or fold it into a `Report`.

## Four things to know before writing shapes

The first two are decided in SHACL-A-0001, the rest are the spec's, and every
one of them surprises someone.

**Validation reads one graph.** SHACL is specified against a single RDF graph;
odin-rdf-store holds a quad dataset. The validator takes the graph to
read — the default graph, or one named graph — and never a union of them.

**`sh:class` needs the class hierarchy in the data graph.** It walks
`rdfs:subClassOf*` in the graph being validated, not in the shapes graph. A
shape that says `sh:class ex:Asset` will not see that `ex:ResourceAsset` is a
subclass of `ex:Asset` unless that triple is in the data graph. This is the
most common way a shapes graph silently under-reports, and it follows from the
single-graph decision above. `sh:targetClass` walks the same closure, so a
target that unexpectedly finds nothing usually has the same cause.

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
