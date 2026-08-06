package shacl_kvstore

import "core:slice"
import "core:strings"
import "core:testing"

import rdf "rdf:rdf"
import kvstore "store:store/kvstore"

import shacl ".."

// Validation against the persistent backend.
//
// The memstore file is the fuller suite, and deliberately so: the engine is
// shared, so re-asserting SHACL semantics here would test the same code twice.
// What this file asserts is what the *backend* changes — that the same shapes
// over the same graph produce the same results through LMDB, that a produced
// report survives the store being closed, and that early exit and recursion
// detection work where a missed one costs an LMDB cursor rather than a pointer
// chase.
//
// The W3C suite runs every enabled entry against both backends, which is the
// broad version of the same claim; these are the assertions that would tell you
// *why* if it ever stopped holding.

VALIDATE_SHAPES :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
@prefix ex: <http://example.org/> .

ex:Cardinality a sh:NodeShape ; sh:targetNode ex:one, ex:three ;
	sh:property [ sh:path ex:p ; sh:minCount 2 ; sh:maxCount 2 ] .

ex:Values a sh:NodeShape ; sh:targetSubjectsOf ex:p ;
	sh:property ex:ValuesP .
ex:ValuesP a sh:PropertyShape ; sh:path ex:p ;
	sh:class ex:C ;
	sh:datatype xsd:string ;
	sh:nodeKind sh:IRI ;
	sh:in ( ex:a ) ;
	sh:hasValue ex:z .
`

VALIDATE_DATA :: `
@prefix ex: <http://example.org/> .

ex:a a ex:C .
ex:one   ex:p ex:a .
ex:three ex:p ex:a ; ex:p ex:b ; ex:p ex:c .
`

@(private = "file")
Fixture :: struct {
	db:       ^kvstore.Store,
	path:     string,
	session:  Session,
	shapes:   shacl.Shapes,
	bindings: shacl.Bindings,
}

// fixture_init compiles the shapes from their own store, closes it, and only
// then opens the data store — so every test here exercises the ownership
// property rather than only the one that names it.
@(private = "file")
fixture_init :: proc(t: ^testing.T, f: ^Fixture, name, shapes_src, data_src: string) -> bool {
	{
		path := temp_path(strings.concatenate({name, "-shapes"}, context.temp_allocator))
		defer remove_store(path)
		db, open_err := kvstore.open(path)
		if !testing.expectf(t, open_err == nil, "shapes store: %v", open_err) {
			return false
		}
		defer kvstore.close(db)

		_, parse_err, load_err := kvstore.load_turtle(db, transmute([]byte)shapes_src)
		if !testing.expectf(t, parse_err.message == "" && load_err == nil, "shapes graph: %s", parse_err.message) {
			return false
		}
		session: Session
		session_init(&session, db)
		err := compile(&f.shapes, &session)
		if !testing.expectf(t, err.kind == .None, "compile: %s", shacl.error_message(err.kind)) {
			return false
		}
		if !testing.expectf(t, session_error(&session) == nil, "store read failed while compiling") {
			return false
		}
	}

	f.path = temp_path(strings.concatenate({name, "-data"}, context.temp_allocator))
	db, open_err := kvstore.open(f.path)
	if !testing.expectf(t, open_err == nil, "data store: %v", open_err) {
		return false
	}
	f.db = db
	_, parse_err, load_err := kvstore.load_turtle(db, transmute([]byte)data_src)
	if !testing.expectf(t, parse_err.message == "" && load_err == nil, "data graph: %s", parse_err.message) {
		return false
	}
	session_init(&f.session, db)
	bind(&f.bindings, &f.shapes, &f.session)
	return true
}

@(private = "file")
fixture_destroy :: proc(f: ^Fixture) {
	shacl.bindings_destroy(&f.bindings)
	shacl.shapes_destroy(&f.shapes)
	if f.db != nil {
		kvstore.close(f.db)
	}
	if f.path != "" {
		remove_store(f.path)
	}
}

@(private = "file")
Seen :: struct {
	session: ^Session,
	lines:   [dynamic]string,
	stop_at: int,
}

@(private = "file")
seen_destroy :: proc(s: ^Seen) {
	for line in s.lines {
		delete(line)
	}
	delete(s.lines)
}

@(private = "file")
record :: proc(data: rawptr, result: shacl.Result) -> bool {
	s := cast(^Seen)data
	sb := strings.builder_make()
	strings.write_string(&sb, local_name(shacl.component_iri(result.component)))
	strings.write_byte(&sb, '|')
	write_node(s, &sb, result.focus)
	strings.write_byte(&sb, '|')
	if result.has_value {
		write_node(s, &sb, result.value)
	} else {
		strings.write_string(&sb, "-")
	}
	append(&s.lines, strings.to_string(sb))
	if s.stop_at > 0 && len(s.lines) >= s.stop_at {
		return false
	}
	return true
}

@(private = "file")
write_node :: proc(s: ^Seen, sb: ^strings.Builder, ref: shacl.Node_Ref) {
	if !ref.bound {
		strings.write_string(sb, "?")
		return
	}
	// kvstore builds terms from the database's bytes, so this one is owned.
	term, err := kvstore.lookup_term(s.session.db, ref.id)
	defer rdf.destroy_term(term)
	if err != nil {
		strings.write_string(sb, "<lookup failed>")
		return
	}
	if iri, is_iri := term.(rdf.IRI); is_iri {
		strings.write_string(sb, local_name(string(iri)))
	} else {
		strings.write_string(sb, "<not an IRI>")
	}
}

@(private = "file")
local_name :: proc(iri: string) -> string {
	if i := strings.last_index_any(iri, "#/"); i >= 0 {
		return iri[i + 1:]
	}
	return iri
}

// The same shapes over the same graph must produce exactly the same results as
// the in-memory backend does — the dual-backend discipline the store's own
// conformance suite established, applied to validation.
@(test)
test_kvstore_validation_matches_memstore :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, "validate", VALIDATE_SHAPES, VALIDATE_DATA) {
		return
	}

	seen := Seen {
		session = &f.session,
	}
	defer seen_destroy(&seen)
	testing.expect_value(t, validate(&f.shapes, &f.bindings, &f.session, record, &seen), shacl.Failure.None)
	testing.expectf(t, session_error(&f.session) == nil, "a store read failed during validation")

	got := slice.clone(seen.lines[:])
	defer delete(got)
	slice.sort(got)
	joined := strings.join(got, "  ")
	defer delete(joined)

	// The same reading `shacl/memstore`'s dispatch test makes, widened to the
	// two focus nodes `sh:targetSubjectsOf` reaches. ex:a is an IRI of class
	// ex:C and a member of the sh:in list, so it fails only sh:datatype; ex:b
	// and ex:c are IRIs too — so no sh:nodeKind result anywhere — but they are
	// of no class and in no list.
	WANT :: "DatatypeConstraintComponent|one|a  DatatypeConstraintComponent|three|a  " +
		"DatatypeConstraintComponent|three|b  DatatypeConstraintComponent|three|c  " +
		"HasValueConstraintComponent|one|-  HasValueConstraintComponent|three|-  " +
		"MaxCountConstraintComponent|three|-  MinCountConstraintComponent|one|-  " +
		"ClassConstraintComponent|three|b  ClassConstraintComponent|three|c  " +
		"InConstraintComponent|three|b  InConstraintComponent|three|c"
	want := strings.split(WANT, "  ")
	defer delete(want)
	slice.sort(want)
	joined_want := strings.join(want, "  ")
	defer delete(joined_want)

	testing.expectf(t, joined == joined_want, "results:\n  got  [%s]\n  want [%s]", joined, joined_want)
}

// A report outlives the store it was produced from. On memstore that is a
// nicety; on kvstore it is the only workable rule, because every term the
// loader hands over is built from database bytes that closing invalidates.
@(test)
test_kvstore_report_outlives_the_store :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, "validate-report", VALIDATE_SHAPES, VALIDATE_DATA) {
		return
	}

	report: shacl.Report
	shacl.report_init(&report)
	defer shacl.report_destroy(&report)

	testing.expect_value(
		t,
		validate_report(&report, &f.shapes, &f.bindings, &f.session),
		shacl.Failure.None,
	)
	testing.expectf(t, session_error(&f.session) == nil, "a store read failed during validation")
	testing.expectf(t, !shacl.report_conforms(&report), "the fixture graph does not conform")

	kvstore.close(f.db)
	f.db = nil

	// Everything below reads the report with the store closed.
	results, conforms_false := 0, 0
	for triple in shacl.report_triples(&report) {
		pred, is_iri := triple.predicate.(rdf.IRI)
		if !is_iri {
			continue
		}
		switch string(pred) {
		case shacl.RESULT:
			results += 1
		case shacl.CONFORMS:
			if lit, is_lit := triple.object.(rdf.Literal); is_lit && lit.lexical == "false" {
				conforms_false += 1
			}
		}
	}
	testing.expect_value(t, results, 12)
	testing.expect_value(t, conforms_false, 1)
}

// Early exit stops the traversal on the persistent backend too, which is where
// it matters most: every step avoided is an LMDB cursor not opened.
@(test)
test_kvstore_early_exit :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, "validate-early", VALIDATE_SHAPES, VALIDATE_DATA) {
		return
	}

	stopped := Seen {
		session = &f.session,
		stop_at = 1,
	}
	defer seen_destroy(&stopped)
	testing.expect_value(
		t,
		validate(&f.shapes, &f.bindings, &f.session, record, &stopped),
		shacl.Failure.None,
	)
	testing.expect_value(t, len(stopped.lines), 1)

	got, failure := conforms(&f.shapes, &f.bindings, &f.session)
	testing.expect_value(t, failure, shacl.Failure.None)
	testing.expectf(t, !got, "a violating graph must not conform")
}

// Recursion is detected on this backend as well, which is not a given: the
// engine is shared but the store is not, and a detection that only worked in
// memory would hang a persistent validation forever on cyclic data.
@(test)
test_kvstore_recursive_shape_is_a_reported_failure :: proc(t: ^testing.T) {
	RECURSIVE :: `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:S a sh:PropertyShape ; sh:targetNode ex:a ; sh:path ex:p ; sh:property ex:S .
	`
	CYCLE :: `
	@prefix ex: <http://example.org/> .
	ex:a ex:p ex:b . ex:b ex:p ex:c . ex:c ex:p ex:a .
	`
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, "validate-recursive", RECURSIVE, CYCLE) {
		return
	}

	seen := Seen {
		session = &f.session,
	}
	defer seen_destroy(&seen)
	testing.expect_value(
		t,
		validate(&f.shapes, &f.bindings, &f.session, record, &seen),
		shacl.Failure.Recursive_Shape,
	)
}
