// Package readme compiles and asserts the README's examples, so the
// documentation cannot drift from the real API. The family's
// README-as-contract convention, established by odin-rdf-parser's
// tests/readme and carried into odin-rdf-sparql by SPARQL-T-0009.
//
// The bodies below are the README's, verbatim, with two differences and no
// others. The import lines: the README writes them the way a consumer would,
// through the `rdf:` and `store:` collections and its own module path, and this
// package reaches sibling directories instead. And the opening line: the README
// opens a path the reader would have chosen, while these call open_ephemeral,
// which is what a suite wants and what a consumer with a real dataset does not.
// Everything after that line is the README's.
//
// Keeping that true is the whole point. It stopped being true once (the quick
// start lost its `session_init` calls and named a `Sink` field that did not
// exist), because a mirror maintained by hand only verifies what someone
// remembered to copy across. Change one, change the other, in the same commit.
package readme

import "core:testing"

import rdf "rdf:rdf"
import kvstore "store:store/kvstore"

import shacl "../../shacl"
import shacl_kvstore "../../shacl/kvstore"

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
	db, open_err := kvstore.open_ephemeral()
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

@(test)
test_readme_validate_example :: proc(t: ^testing.T) {
	lines: [dynamic]string
	defer delete(lines)

	testing.expect_value(t, validate_example(&lines), shacl.Failure.None)

	// ex:bob has no ex:name, so sh:minCount 1 reports one violation. ex:alice
	// conforms.
	testing.expect_value(t, len(lines), 1)
	if len(lines) == 1 {
		testing.expect_value(t, lines[0], "http://example.org/bob")
	}
}

// The conformance-only form, which is the README's second example: it stops at
// the first violation instead of finding them all.
conforms_example :: proc() -> (bool, shacl.Failure) {
	db, open_err := kvstore.open_ephemeral()
	if open_err != nil {
		return false, .None
	}
	defer kvstore.close(db)

	shapes: shacl.Shapes
	defer shacl.shapes_destroy(&shapes)
	shacl_kvstore.compile_turtle(&shapes, db, transmute([]byte)string(SHAPES))

	kvstore.load_turtle(db, transmute([]byte)string(DATA))
	session: shacl_kvstore.Session
	shacl_kvstore.session_init(&session, db)

	bindings: shacl.Bindings
	shacl_kvstore.bind(&bindings, &shapes, &session)
	defer shacl.bindings_destroy(&bindings)

	return shacl_kvstore.conforms(&shapes, &bindings, &session)
}

@(test)
test_readme_conforms_example :: proc(t: ^testing.T) {
	ok, failure := conforms_example()
	// The Failure must be checked before the boolean: a failure means the
	// processor could not answer, which is not the same as "no".
	testing.expect_value(t, failure, shacl.Failure.None)
	testing.expect(t, !ok)
}

// The report form: the same traversal, folded into an RDF graph. Emitting it is
// odin-rdf-parser's job through any of its four emitters — this produces the
// graph and leaves the format to the caller.
report_example :: proc(r: ^shacl.Report) -> shacl.Failure {
	db, open_err := kvstore.open_ephemeral()
	if open_err != nil {
		return .None
	}
	defer kvstore.close(db)

	shapes: shacl.Shapes
	defer shacl.shapes_destroy(&shapes)
	shacl_kvstore.compile_turtle(&shapes, db, transmute([]byte)string(SHAPES))

	kvstore.load_turtle(db, transmute([]byte)string(DATA))
	session: shacl_kvstore.Session
	shacl_kvstore.session_init(&session, db)

	bindings: shacl.Bindings
	shacl_kvstore.bind(&bindings, &shapes, &session)
	defer shacl.bindings_destroy(&bindings)

	return shacl_kvstore.validate_report(r, &shapes, &bindings, &session)
}

@(test)
test_readme_report_example :: proc(t: ^testing.T) {
	report: shacl.Report
	shacl.report_init(&report)
	// The report owns every term in its graph, so it outlives the store and the
	// model both — but the triples it handed out die with it.
	defer shacl.report_destroy(&report)

	testing.expect_value(t, report_example(&report), shacl.Failure.None)
	testing.expect(t, !shacl.report_conforms(&report))

	results := 0
	for triple in shacl.report_triples(&report) {
		if pred, is_iri := triple.predicate.(rdf.IRI); is_iri && string(pred) == shacl.RESULT {
			results += 1
		}
	}
	testing.expect_value(t, results, 1)
}

// The narrow form: does one node conform to one shape? The README's fourth
// example, and the public face of suppressed validation (SHACL-A-0002) — it
// produces no results, and it does not care what the shapes graph targets.
conforms_node_example :: proc() -> (bool, shacl.Failure) {
	db, open_err := kvstore.open_ephemeral()
	if open_err != nil {
		return false, .None
	}
	defer kvstore.close(db)

	shapes: shacl.Shapes
	defer shacl.shapes_destroy(&shapes)
	shacl_kvstore.compile_turtle(&shapes, db, transmute([]byte)string(SHAPES))

	kvstore.load_turtle(db, transmute([]byte)string(DATA))
	session: shacl_kvstore.Session
	shacl_kvstore.session_init(&session, db)

	bindings: shacl.Bindings
	shacl_kvstore.bind(&bindings, &shapes, &session)
	defer shacl.bindings_destroy(&bindings)

	// A shape is named by its index in the compiled model, the same index a
	// Result carries. Shapes with an IRI can be found by it.
	shape_index, _ := shacl.shape_index_of(&shapes, rdf.IRI("http://example.org/PersonShape"))

	return shacl_kvstore.conforms_node(
		&shapes,
		&bindings,
		&session,
		rdf.IRI("http://example.org/alice"),
		shape_index,
	)
}

@(test)
test_readme_conforms_node_example :: proc(t: ^testing.T) {
	ok, failure := conforms_node_example()
	testing.expect_value(t, failure, shacl.Failure.None)
	// ex:alice has an ex:name, so she conforms to ex:PersonShape — while the
	// graph as a whole does not, because ex:bob does not.
	testing.expect(t, ok)
}


// The validate-before-commit form: the candidate is decided against the dataset
// it would produce. The README's fifth example (SHACL-T-0029).

ONE_NAME_SHAPES :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix ex: <http://example.org/> .

ex:OneNameShape a sh:NodeShape ;
	sh:targetClass ex:Person ;
	sh:property [ sh:path ex:name ; sh:maxCount 1 ] .
`

CANDIDATE :: `
@prefix ex: <http://example.org/> .

ex:alice ex:name "Alice Smith" .
`

// Returns whether the candidate was kept.
validate_before_commit_example :: proc() -> (kept: bool, failure: shacl.Failure) {
	db, open_err := kvstore.open_ephemeral()
	if open_err != nil {
		return false, .None
	}
	defer kvstore.close(db)

	shapes: shacl.Shapes
	defer shacl.shapes_destroy(&shapes)
	shacl_kvstore.compile_turtle(&shapes, db, transmute([]byte)string(ONE_NAME_SHAPES))

	// The dataset as it stands: ex:alice is a Person and already has one name.
	kvstore.load_turtle(db, transmute([]byte)string(DATA))

	// 1. Open a write transaction and build the candidate inside it. Nothing is
	//    visible outside the transaction and nothing is durable until commit.
	tx, txn_err := kvstore.txn_begin(db, .Write)
	if txn_err != nil {
		return false, .None
	}
	// A no-op after a successful commit, so this is the whole cleanup story.
	defer kvstore.txn_abort(&tx)

	kvstore.load_turtle_txn(&tx, transmute([]byte)string(CANDIDATE))

	// 2. Validate *through the same transaction*. This is the point: the
	//    validator sees the committed data and the candidate together, which is
	//    the dataset the commit would produce.
	session: shacl_kvstore.Session
	shacl_kvstore.session_init_txn(&session, &tx)

	bindings: shacl.Bindings
	shacl_kvstore.bind(&bindings, &shapes, &session)
	defer shacl.bindings_destroy(&bindings)

	ok, fail := shacl_kvstore.conforms(&shapes, &bindings, &session)
	if fail != .None || shacl_kvstore.session_error(&session) != nil {
		return false, fail
	}

	// 3. Keep or discard the write on the answer. Returning without committing
	//    discards it, because the deferred abort is what runs.
	if !ok {
		return false, .None
	}
	kvstore.txn_commit(&tx)
	return true, .None
}

@(test)
test_readme_validate_before_commit_example :: proc(t: ^testing.T) {
	kept, failure := validate_before_commit_example()
	testing.expect_value(t, failure, shacl.Failure.None)
	// The candidate gives ex:alice a second ex:name, which sh:maxCount 1
	// forbids — and it violates only because the committed data is visible.
	// Validated on its own it would carry no ex:Person target at all and would
	// conform vacuously, which is the answer this pattern exists to avoid.
	testing.expect(t, !kept)
}
