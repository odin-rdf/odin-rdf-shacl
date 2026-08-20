// Package readme compiles and asserts the README's examples, so the
// documentation cannot drift from the real API. The family's
// README-as-contract convention, established by odin-rdf-parser's
// tests/readme and carried into odin-rdf-sparql by SPARQL-T-0009.
//
// The bodies below are the README's, verbatim, with two differences and no
// others. The import lines: the README writes them the way a consumer would,
// through the `rdf:` and `record:` collections and its own module path, and
// this package reaches sibling directories instead. And the opening line: the
// README opens a directory on disk with `record.posix_file_ops()`, while
// these open over the memory seam (`Mem_FS` + `mem_file_ops`), which is what
// a suite wants and what a consumer with a real dataset does not. Everything
// after that line is the README's.
//
// Keeping that true is the whole point. It stopped being true once (the quick
// start lost its `session_init` calls and named a `Sink` field that did not
// exist), because a mirror maintained by hand only verifies what someone
// remembered to copy across. Change one, change the other, in the same commit.
//
// The validate-before-commit example is the `Validator` one (SHACL-T-0034); like
// the others it opens over the memory seam where the README opens a directory.
package readme

import "core:strings"
import "core:testing"

import "rdf:rdf"
import "record:record"
import "record:record/ingest"

import "../../shacl"

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
	fs: record.Mem_FS // suites and scratch; record.posix_file_ops() for a directory on disk
	defer record.mem_fs_destroy(&fs)
	db: record.Store
	_, open_err, _, _ := record.store_open(&db, "readme", record.mem_file_ops(&fs))
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
	if iri, is_iri := focus.(rdf.IRI); is_iri {
		append(sink.lines, strings.clone(string(iri), context.temp_allocator))
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
	fs: record.Mem_FS
	defer record.mem_fs_destroy(&fs)
	db: record.Store
	_, open_err, _, _ := record.store_open(&db, "readme", record.mem_file_ops(&fs))
	if open_err != .None {
		return false, .None
	}
	defer record.store_close(&db)
	if !load(&db, SHAPES, "shapes_") || !load(&db, DATA, "data_") {
		return false, .None
	}
	snap, snap_err := record.store_latest(&db)
	if snap_err != .None {
		return false, .None
	}
	defer record.snapshot_release(&snap)
	se: shacl.Session
	shacl.session_init(&se, snap)

	shapes: shacl.Shapes
	defer shacl.shapes_destroy(&shapes)
	shacl.compile(&shapes, se)

	bindings: shacl.Bindings
	shacl.bindings_init(&bindings, &shapes, se)
	defer shacl.bindings_destroy(&bindings)

	return shacl.conforms(&shapes, &bindings, se)
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
	fs: record.Mem_FS
	defer record.mem_fs_destroy(&fs)
	db: record.Store
	_, open_err, _, _ := record.store_open(&db, "readme", record.mem_file_ops(&fs))
	if open_err != .None {
		return .None
	}
	defer record.store_close(&db)
	if !load(&db, SHAPES, "shapes_") || !load(&db, DATA, "data_") {
		return .None
	}
	snap, snap_err := record.store_latest(&db)
	if snap_err != .None {
		return .None
	}
	defer record.snapshot_release(&snap)
	se: shacl.Session
	shacl.session_init(&se, snap)

	shapes: shacl.Shapes
	defer shacl.shapes_destroy(&shapes)
	shacl.compile(&shapes, se)

	bindings: shacl.Bindings
	shacl.bindings_init(&bindings, &shapes, se)
	defer shacl.bindings_destroy(&bindings)

	return shacl.validate_report(r, &shapes, &bindings, se)
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
	fs: record.Mem_FS
	defer record.mem_fs_destroy(&fs)
	db: record.Store
	_, open_err, _, _ := record.store_open(&db, "readme", record.mem_file_ops(&fs))
	if open_err != .None {
		return false, .None
	}
	defer record.store_close(&db)
	if !load(&db, SHAPES, "shapes_") || !load(&db, DATA, "data_") {
		return false, .None
	}
	snap, snap_err := record.store_latest(&db)
	if snap_err != .None {
		return false, .None
	}
	defer record.snapshot_release(&snap)
	se: shacl.Session
	shacl.session_init(&se, snap)

	shapes: shacl.Shapes
	defer shacl.shapes_destroy(&shapes)
	shacl.compile(&shapes, se)

	bindings: shacl.Bindings
	shacl.bindings_init(&bindings, &shapes, se)
	defer shacl.bindings_destroy(&bindings)

	// A shape is named by its index in the compiled model, the same index a
	// Result carries. Shapes with an IRI can be found by it; a focus node is
	// named by term, through `node_focus`.
	shape_index, _ := shacl.shape_index_of(&shapes, rdf.IRI("http://example.org/PersonShape"))

	return shacl.conforms_node(
		&shapes,
		&bindings,
		se,
		shape_index,
		shacl.node_focus(se, rdf.IRI("http://example.org/alice")),
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

// The same question with the results: `validate_node_report`. The README's
// answer to "which constraint did this resource break?" (SHACL-T-0027).
validate_node_example :: proc(r: ^shacl.Report, node: string) -> shacl.Failure {
	fs: record.Mem_FS
	defer record.mem_fs_destroy(&fs)
	db: record.Store
	_, open_err, _, _ := record.store_open(&db, "readme", record.mem_file_ops(&fs))
	if open_err != .None {
		return .None
	}
	defer record.store_close(&db)
	if !load(&db, SHAPES, "shapes_") || !load(&db, DATA, "data_") {
		return .None
	}
	snap, snap_err := record.store_latest(&db)
	if snap_err != .None {
		return .None
	}
	defer record.snapshot_release(&snap)
	se: shacl.Session
	shacl.session_init(&se, snap)

	shapes: shacl.Shapes
	defer shacl.shapes_destroy(&shapes)
	shacl.compile(&shapes, se)

	bindings: shacl.Bindings
	shacl.bindings_init(&bindings, &shapes, se)
	defer shacl.bindings_destroy(&bindings)

	shape_index, _ := shacl.shape_index_of(&shapes, rdf.IRI("http://example.org/PersonShape"))

	return shacl.validate_node_report(r, &shapes, &bindings, se, rdf.IRI(node), shape_index)
}

@(test)
test_readme_validate_node_example :: proc(t: ^testing.T) {
	{
		report: shacl.Report
		shacl.report_init(&report)
		defer shacl.report_destroy(&report)
		testing.expect_value(t, validate_node_example(&report, "http://example.org/alice"), shacl.Failure.None)
		testing.expect(t, shacl.report_conforms(&report))
	}
	{
		// ex:bob is the one the graph-wide report blames, and asking about him
		// alone gives the same result — which is the property that makes the
		// narrow entry point trustworthy.
		report: shacl.Report
		shacl.report_init(&report)
		defer shacl.report_destroy(&report)
		testing.expect_value(t, validate_node_example(&report, "http://example.org/bob"), shacl.Failure.None)
		testing.expect(t, !shacl.report_conforms(&report))

		results := 0
		for triple in shacl.report_triples(&report) {
			if pred, is_iri := triple.predicate.(rdf.IRI); is_iri && string(pred) == shacl.RESULT {
				results += 1
			}
		}
		testing.expect_value(t, results, 1)
	}
}

CANDIDATE :: `
@prefix ex: <http://example.org/> .

ex:alice a ex:Person ; ex:name "Alice" ; ex:name "Alicia" .
`

MAX_ONE_NAME :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix ex: <http://example.org/> .

ex:PersonShape a sh:NodeShape ;
	sh:targetClass ex:Person ;
	sh:property [ sh:path ex:name ; sh:maxCount 1 ] .
`

// compile_shapes compiles a shapes document from a scratch store and closes
// it — the model owns its terms and does not need the store afterwards.
compile_shapes :: proc(shapes: ^shacl.Shapes, source: string) -> bool {
	fs: record.Mem_FS
	defer record.mem_fs_destroy(&fs)
	db: record.Store
	_, open_err, _, _ := record.store_open(&db, "shapes", record.mem_file_ops(&fs))
	if open_err != .None {
		return false
	}
	defer record.store_close(&db)
	if !load(&db, source, "shapes_") {
		return false
	}
	snap, snap_err := record.store_latest(&db)
	if snap_err != .None {
		return false
	}
	defer record.snapshot_release(&snap)
	se: shacl.Session
	shacl.session_init(&se, snap)
	return shacl.compile(shapes, se).kind == .None
}

// Validate-before-commit: the README's fifth example. Returns what apply
// returned and how many results the validator's report holds.
validator_example :: proc() -> (refused: bool, results: int) {
	// 1. Compile the shapes once, from wherever they live. The model owns every
	//    term it holds, so the store it came from may be closed — here it is.
	shapes: shacl.Shapes
	defer shacl.shapes_destroy(&shapes)
	compile_shapes(&shapes, MAX_ONE_NAME)

	// 2. Make a validator of the model and open the data store with it wired in.
	//    One validator per store; it must stay where it is until the store closes.
	v: shacl.Validator
	shacl.validator_init(&v, &shapes)
	defer shacl.validator_destroy(&v)

	fs: record.Mem_FS // the README opens a directory with record.posix_file_ops()
	defer record.mem_fs_destroy(&fs)
	db: record.Store
	_, open_err, _, _ := record.store_open(
		&db,
		"data",
		record.mem_file_ops(&fs),
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
		for triple in shacl.report_triples(report) {
			if pred, is_iri := triple.predicate.(rdf.IRI); is_iri && string(pred) == shacl.RESULT {
				results += 1
			}
		}
	}
	return err.kind == .Rejected && !conforms, results
}

@(test)
test_readme_validator_example :: proc(t: ^testing.T) {
	refused, results := validator_example()
	// Two ex:name values against sh:maxCount 1: refused before a byte was
	// written, with one result in the validator's report.
	testing.expect(t, refused)
	testing.expect_value(t, results, 1)
}

// Validating the past: the README's sixth example. The data gains a second
// name at epoch 2, so the verdict at epoch 1 and at epoch 2 differ.
as_of_example :: proc(epoch: record.Epoch) -> (conforms: bool, failure: shacl.Failure, actor_set: bool) {
	shapes: shacl.Shapes
	defer shacl.shapes_destroy(&shapes)
	compile_shapes(&shapes, MAX_ONE_NAME)

	fs: record.Mem_FS
	defer record.mem_fs_destroy(&fs)
	db: record.Store
	_, open_err, _, _ := record.store_open(&db, "history", record.mem_file_ops(&fs))
	if open_err != .None {
		return
	}
	defer record.store_close(&db)
	if !load(&db, `@prefix ex: <http://example.org/> . ex:alice a ex:Person ; ex:name "Alice" .`, "e1_") {
		return
	}
	if !load(&db, `@prefix ex: <http://example.org/> . ex:alice ex:name "Alicia" .`, "e2_") {
		return
	}

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

	conforms, failure = shacl.conforms(&shapes, &bindings, se)

	// Who committed that epoch, why, and when — decoded like any other term.
	meta := record.snapshot_epoch_meta(snap, epoch)
	return conforms, failure, meta.wall > 0
}

@(test)
test_readme_as_of_example :: proc(t: ^testing.T) {
	then, f1, wall1 := as_of_example(1)
	testing.expect_value(t, f1, shacl.Failure.None)
	testing.expect(t, then, "at epoch 1 alice has one name")
	testing.expect(t, wall1, "an epoch carries its wall time")

	now, f2, _ := as_of_example(2)
	testing.expect_value(t, f2, shacl.Failure.None)
	testing.expect(t, !now, "at epoch 2 alice has two names against sh:maxCount 1")
}
