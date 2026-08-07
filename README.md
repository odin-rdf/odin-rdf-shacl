# odin-rdf-shacl

[![CI](https://github.com/odin-rdf/odin-rdf-shacl/actions/workflows/ci.yml/badge.svg)](https://github.com/odin-rdf/odin-rdf-shacl/actions/workflows/ci.yml)

Shape-based validation for the Odin RDF family: a SHACL implementation that
validates RDF data graphs against shapes graphs. Shapes are themselves RDF,
parsed with [odin-rdf-parser](../odin-rdf-parser); the data graph is read
through [odin-rdf-store](../odin-rdf-store)'s match interface alone, so the
same shapes validate in-memory and LMDB-backed data identically. Written in
Odin with no external dependencies.

**Status: SHACL Core's constraint catalogue is complete.** Every constraint
component of §4 that does not need SPARQL is implemented — the value-type,
cardinality, value-range, string-based, property-pair, logical, shape-based and
"other" families, twenty-nine components in all — alongside shapes compilation,
target resolution, property paths, and `sh:ValidationReport` emission.

Five of the W3C SHACL suite's seven `core/` directories are green:
`core/targets`, `core/path`, `core/misc`, `core/validation-reports`, and
`core/node`, every entry, against both storage backends, at both `Term_ID`
widths. `core/property` stands at 37 of 38 and `core/complex` needs
SHACL-SPARQL, so both remain disabled — this repository claims conformance only
for directories where *every* entry passes. See `.metis/` for the vision, the
initiative, and the ADRs.

**A constraint this engine does not implement is ignored, and the compile says
so.** Erroring instead would reject the spec's own non-validating annotations
(`sh:name`, `sh:description`, `sh:order`, `sh:group`, `sh:defaultValue`) and
every vendor extension a real shapes graph carries. But ignoring silently is
how a partial engine comes to look complete, so `shapes_ignored(&shapes)`
returns every `sh:` parameter the compile saw on a shape and skipped. **Check it
before trusting a `sh:conforms true`**: a report with no results and a non-empty
ignored list is not a validated graph.

Now that SHACL Core's catalogue is complete, a non-empty list means a vendor
extension or a SHACL-SPARQL parameter (`sh:sparql`, `sh:shapesGraph`,
`sh:entailment`) — not a missing Core component.

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
| `shacl/memstore` | The validator instantiated against the in-memory backend        |
| `shacl/kvstore`  | The validator instantiated against the persistent (LMDB) backend |

`shacl` names no storage backend and imports none, so a program that only
wants an in-memory store never links LMDB. That property is asserted rather
than trusted — `make check` builds a core-plus-memstore consumer and fails if
the binary carries LMDB symbols.

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
cannot drift from the API.

```odin
package main

import rdf "rdf:rdf"
import memstore "store:store/memstore"

import shacl "shacl"
import shacl_memstore "shacl/memstore"

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

validate_example :: proc(report: ^[dynamic]string) -> shacl.Failure {
	// 1. Compile the shapes graph. The model owns every term it holds, so the
	//    private store `compile_turtle` built is already gone by the time it
	//    returns — the model outlives it.
	shapes: shacl.Shapes
	defer shacl.shapes_destroy(&shapes)
	err, parse_err := shacl_memstore.compile_turtle(&shapes, transmute([]byte)string(SHAPES))
	if parse_err.message != "" || err.kind != .None {
		return .None
	}

	// 2. Load the data graph.
	dictionary: memstore.Dictionary
	memstore.dictionary_init(&dictionary)
	defer memstore.dictionary_destroy(&dictionary)
	dataset: memstore.Dataset
	memstore.dataset_init(&dataset)
	defer memstore.dataset_destroy(&dataset)
	memstore.load_turtle(&dictionary, &dataset, transmute([]byte)string(DATA))

	// 3. Bind the model's terms to this store's IDs — once per validation, not
	//    once per check. A model compiled elsewhere binds here just as well.
	bindings: shacl.Bindings
	shacl_memstore.bind(&bindings, &shapes, &dictionary)
	defer shacl.bindings_destroy(&bindings)

	// 4. Validate. Results are handed to the visitor as they are found and
	//    nothing is buffered, so memory stays flat however bad the data is.
	sink := Sink{shapes = &shapes, dictionary = &dictionary, lines = report}
	return shacl_memstore.validate(&shapes, &bindings, &dictionary, &dataset, on_result, &sink)
}

Sink :: struct {
	shapes:     ^shacl.Shapes,
	dictionary: ^memstore.Dictionary,
	lines:      ^[dynamic]string,
}

// A Result borrows and owns nothing: it names nodes by Term_ID and the shape
// by index, and is valid only for this call. Keep anything you need by copying
// it out — or use `validate_report` and let the report do it for you.
on_result :: proc(data: rawptr, result: shacl.Result) -> bool {
	sink := cast(^Sink)data
	focus := memstore.lookup_term(sink.dictionary, result.focus.id)
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

### Three consumers, one traversal

The result stream is the primitive. The other two forms are ordinary consumers
of it, and each is one call:

```odin
// Just the answer. Stops at the first result of any severity rather than
// finding them all — which at ~200 processes per machine is the difference
// worth having. A warning breaks conformance exactly as a violation does (§3.1).
ok, failure := shacl_memstore.conforms(&shapes, &bindings, &dictionary, &dataset)

// The sh:ValidationReport graph, finished and ready to serialise. Emitting it
// is odin-rdf-parser's job, through any of its four emitters.
report: shacl.Report
shacl.report_init(&report)
defer shacl.report_destroy(&report)
failure := shacl_memstore.validate_report(&report, &shapes, &bindings, &dictionary, &dataset)
```

**Check the `Failure` before the answer.** It is the spec's *failure* (§3.3),
not a result: `.None` means the traversal completed or your visitor stopped it,
and anything else means the processor could not answer — which is not the same
as "no".

There is a fourth, narrower question: **does one node conform to one shape?**

```odin
// shape_index names a shape by its position in the compiled model — the same
// index a Result carries in `result.shape`.
ok, failure := shacl_memstore.conforms_node(
	&shapes, &bindings, &dictionary, &dataset,
	rdf.IRI("http://example.org/alice"), shape_index,
)
```

It produces no results — the question is the boolean — and it validates the
named shape and every `sh:property` shape below it (§3.4). Unlike `conforms`, it
does not care what the shapes graph targets: the caller names both the node and
the shape. This is also the mechanism `sh:not`, `sh:or`, `sh:xone`, `sh:node`,
and `sh:qualifiedValueShape` are built on, which is why it exists before they do
(SHACL-A-0002).

`shacl/kvstore` has the same entry points against the persistent backend, taking
a `Session` where these take a dictionary and a dataset.

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
reaches itself — through `sh:property` today, and through `sh:node` once the
catalogue initiative adds it. Every property-path form is separately cycle-safe
over data, so `sh:zeroOrMorePath` over the graph above terminates.

## License

See [LICENSE](LICENSE).
