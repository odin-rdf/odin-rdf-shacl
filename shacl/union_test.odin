package shacl

// Validating the union of a set of graphs (SHACL-T-0039): SHACL-A-0001
// decision 5 generalised, with the single graph as the one-element case.
//
// The consumer is the application's workspace design — a named graph per
// workspace, a shape in workspace B needing to see the control its risk
// links to in ancestor A. Every case here is a thing the single-graph
// session could not express, plus the one thing a union could get wrong
// (the same triple in two graphs counting twice) pinned as not happening.

import "core:testing"

import "rdf:rdf"
import "record:record"
import "record:record/ingest"

@(private = "file")
A :: rdf.IRI("http://example.org/A")
@(private = "file")
B :: rdf.IRI("http://example.org/B")
@(private = "file")
C :: rdf.IRI("http://example.org/C")
@(private = "file")
ONT :: rdf.IRI("http://example.org/ont")

// A risk's mitigation must be a Control.
@(private = "file")
RISK_SHAPE :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix ex: <http://example.org/> .
ex:RiskShape a sh:NodeShape ; sh:targetClass ex:Risk ;
	sh:property [ sh:path ex:mitigatedBy ; sh:class ex:Control ] .
`
@(private = "file")
CONTROL_IN_A :: `@prefix ex: <http://example.org/> . ex:ctrl7 a ex:Control .`
@(private = "file")
RISK_IN_B :: `@prefix ex: <http://example.org/> . ex:risk1 a ex:Risk ; ex:mitigatedBy ex:ctrl7 .`

// tdb_union pins the head snapshot and binds a session over the union of
// `labels`, resolved into `ids`, which the caller owns.
@(private = "file")
tdb_union :: proc(db: ^Test_DB, labels: []rdf.Graph_Label, ids: ^[dynamic]record.Term_ID) -> Session {
	_ = tdb_session(db)
	clear(ids)
	session_resolve_graphs(db.snap, labels, ids)
	se: Session
	session_init_union(&se, db.snap, ids[:])
	return se
}

@(private = "file")
union_conforms :: proc(t: ^testing.T, shapes: ^Shapes, se: Session, loc := #caller_location) -> bool {
	b: Bindings
	bindings_init(&b, shapes, se)
	defer bindings_destroy(&b)
	ok, failure := conforms(shapes, &b, se)
	testing.expect_value(t, failure, Failure.None, loc = loc)
	return ok
}

// The case the design was filed on: under {B} alone the control's type is
// in a graph the session cannot see and sh:class reports a violation; under
// {B, A} it conforms.
@(test)
test_union_sees_an_ancestors_class :: proc(t: ^testing.T) {
	shapes: Shapes
	defer shapes_destroy(&shapes)
	if !tdb_compile(t, &shapes, RISK_SHAPE) {
		return
	}
	db: Test_DB
	defer tdb_close(&db)
	if !tdb_open(t, &db) ||
	   !tdb_load(t, &db, CONTROL_IN_A, A, blank_prefix = "a_") ||
	   !tdb_load(t, &db, RISK_IN_B, B, blank_prefix = "b_") {
		return
	}
	ids: [dynamic]record.Term_ID
	defer delete(ids)

	testing.expect(t, !union_conforms(t, &shapes, tdb_union(&db, []rdf.Graph_Label{B}, &ids)), "under {B} the control is untyped: violation")
	testing.expect(t, union_conforms(t, &shapes, tdb_union(&db, []rdf.Graph_Label{B, A}, &ids)), "under {B, A} the control is a Control")
	// The one-element set is the single-graph session exactly.
	testing.expect(t, !union_conforms(t, &shapes, tdb_session(&db, B)), "session_init over B agrees with the one-element union")
}

// sh:targetClass walks rdfs:subClassOf* in the data graph. With the ontology
// in its own graph, a workspace alone finds no focus node and conforms for
// the uninteresting reason; the union with the ontology graph targets the
// subclass instance and reports its missing owner.
@(test)
test_union_targets_through_an_ontology_graph :: proc(t: ^testing.T) {
	SHAPES :: `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:AssetShape a sh:NodeShape ; sh:targetClass ex:Asset ;
		sh:property [ sh:path ex:owner ; sh:minCount 1 ] .
	`
	ONTOLOGY :: `@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> . @prefix ex: <http://example.org/> . ex:ResourceAsset rdfs:subClassOf ex:Asset .`
	DATA :: `@prefix ex: <http://example.org/> . ex:r1 a ex:ResourceAsset .`

	shapes: Shapes
	defer shapes_destroy(&shapes)
	if !tdb_compile(t, &shapes, SHAPES) {
		return
	}
	db: Test_DB
	defer tdb_close(&db)
	if !tdb_open(t, &db) ||
	   !tdb_load(t, &db, ONTOLOGY, ONT, blank_prefix = "o_") ||
	   !tdb_load(t, &db, DATA, B, blank_prefix = "b_") {
		return
	}
	ids: [dynamic]record.Term_ID
	defer delete(ids)
	testing.expect(t, union_conforms(t, &shapes, tdb_union(&db, []rdf.Graph_Label{B}, &ids)), "without the ontology nothing is an Asset")
	testing.expect(t, !union_conforms(t, &shapes, tdb_union(&db, []rdf.Graph_Label{B, ONT}, &ids)), "with it, r1 is an Asset without an owner")
}

@(private = "file")
count_results :: proc(data: rawptr, result: Result) -> bool {
	(^int)(data)^ += 1
	return true
}

// The same triples in two graphs of the set are two facts and one triple:
// one focus node, one value node. maxCount 1 conforms, and a shape that
// always violates reports exactly once.
@(test)
test_union_does_not_count_a_triple_twice :: proc(t: ^testing.T) {
	SHAPES :: `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:PShape a sh:NodeShape ; sh:targetClass ex:P ;
		sh:property [ sh:path ex:name ; sh:maxCount 1 ] ;
		sh:property [ sh:path ex:missing ; sh:minCount 1 ] .
	`
	DATA :: `@prefix ex: <http://example.org/> . ex:x a ex:P ; ex:name "n" .`

	shapes: Shapes
	defer shapes_destroy(&shapes)
	if !tdb_compile(t, &shapes, SHAPES) {
		return
	}
	db: Test_DB
	defer tdb_close(&db)
	if !tdb_open(t, &db) ||
	   !tdb_load(t, &db, DATA, A, blank_prefix = "a_") ||
	   !tdb_load(t, &db, DATA, B, blank_prefix = "b_") {
		return
	}
	ids: [dynamic]record.Term_ID
	defer delete(ids)
	se := tdb_union(&db, []rdf.Graph_Label{A, B}, &ids)
	b: Bindings
	bindings_init(&b, &shapes, se)
	defer bindings_destroy(&b)
	n := 0
	failure := validate(&shapes, &b, se, count_results, &n)
	testing.expect_value(t, failure, Failure.None)
	testing.expect_value(t, n, 1)
}

// An empty set is an empty data graph: a class target finds nothing, and a
// node target's values are absent — never the whole store's.
@(test)
test_union_of_nothing_is_an_empty_data_graph :: proc(t: ^testing.T) {
	SHAPES :: `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:PShape a sh:NodeShape ; sh:targetClass ex:P ;
		sh:property [ sh:path ex:missing ; sh:minCount 1 ] .
	ex:XShape a sh:NodeShape ; sh:targetNode ex:x ;
		sh:property [ sh:path ex:name ; sh:minCount 1 ] .
	`
	DATA :: `@prefix ex: <http://example.org/> . ex:x a ex:P ; ex:name "n" .`

	shapes: Shapes
	defer shapes_destroy(&shapes)
	if !tdb_compile(t, &shapes, SHAPES) {
		return
	}
	db: Test_DB
	defer tdb_close(&db)
	if !tdb_open(t, &db) || !tdb_load(t, &db, DATA, A, blank_prefix = "a_") {
		return
	}
	ids: [dynamic]record.Term_ID
	defer delete(ids)
	// {A}: x is a P without ex:missing (violation), and x has a name.
	// {}: no P at all, and x has no name (violation) — one result each way,
	// but for opposite reasons, which is what tells an empty data graph
	// from the whole store.
	se := tdb_union(&db, []rdf.Graph_Label{rdf.IRI("http://example.org/never")}, &ids)
	testing.expect_value(t, len(ids), 0)
	b: Bindings
	bindings_init(&b, &shapes, se)
	defer bindings_destroy(&b)
	n := 0
	failure := validate(&shapes, &b, se, count_results, &n)
	testing.expect_value(t, failure, Failure.None)
	testing.expect_value(t, n, 1)
}

// A validator wired over a union: a write into B linking to A's control is
// accepted under Enforce, and one linking to a control in C — outside the
// set — is refused, because to the validator it links to nothing typed.
@(test)
test_validator_over_a_union :: proc(t: ^testing.T) {
	shapes: Shapes
	defer shapes_destroy(&shapes)
	if !tdb_compile(t, &shapes, RISK_SHAPE) {
		return
	}
	v: Validator
	validator_init_union(&v, &shapes, []rdf.Graph_Label{B, A})
	defer validator_destroy(&v)

	fs: record.Mem_FS
	defer record.mem_fs_destroy(&fs)
	st: record.Store
	_, err, _, _ := record.store_open(&st, "union", record.mem_file_ops(&fs), validator = validator_hook(&v))
	if !testing.expectf(t, err == .None, "store_open: %v", err) {
		return
	}
	defer record.store_close(&st)

	apply := proc(t: ^testing.T, st: ^record.Store, source: string, graph: rdf.Graph_Label, prefix: string) -> (conforms: bool, err: record.Apply_Error) {
		ops, ierr := ingest.turtle(transmute([]byte)source, graph, context.allocator, blank_prefix = prefix)
		if !testing.expectf(t, ierr.kind == .None, "ingest: %v", ierr) {
			return false, {.Empty, -1}
		}
		defer ingest.ops_destroy(ops, context.allocator)
		_, conforms, err = record.apply(st, {ops = ops, mode = .Enforce})
		return
	}

	ok, aerr := apply(t, &st, CONTROL_IN_A, A, "a_")
	testing.expect_value(t, aerr, record.Apply_Error{})
	testing.expect(t, ok, "a control in A: no risks yet, conforms")
	ok, aerr = apply(t, &st, RISK_IN_B, B, "b_")
	testing.expect_value(t, aerr, record.Apply_Error{})
	testing.expect(t, ok, "a risk in B mitigated by A's control: conforms under {B, A}")
	ok, aerr = apply(t, &st, `@prefix ex: <http://example.org/> . ex:ctrl9 a ex:Control .`, C, "c_")
	testing.expect_value(t, aerr, record.Apply_Error{})
	testing.expect(t, ok, "a control in C: not read, nothing to object to")
	ok, aerr = apply(t, &st, `@prefix ex: <http://example.org/> . ex:risk2 a ex:Risk ; ex:mitigatedBy ex:ctrl9 .`, B, "b2_")
	testing.expect_value(t, aerr, record.Apply_Error{.Rejected, -1})
	testing.expect(t, !ok, "a risk in B mitigated by C's control: C is outside the union, refused")
	testing.expect_value(t, v.checks, 4)
}
