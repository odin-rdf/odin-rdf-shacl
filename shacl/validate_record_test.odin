package shacl

import "core:slice"
import "core:strings"
import "core:testing"

import "rdf:rdf"

// Validation end to end against the record store.
//
// The engine's semantics have their own suites; what this file asserts is the
// full stack through the session verbs — that the shapes over the graph
// produce exactly the expected results, that a produced report survives the
// store being closed, and that early exit and recursion detection work where
// a missed one costs a live scan rather than a pointer chase.
//
// The W3C suite runs every enabled entry against the same stack, which is the
// broad version of the same claim; these are the assertions that would tell
// you *why* if it ever stopped holding.

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
	db:       Test_DB,
	se:       Session,
	shapes:   Shapes,
	bindings: Bindings,
}

// fixture_init compiles the shapes from their own store, closes it, and only
// then opens the data store — so every test here exercises the ownership
// property rather than only the one that names it.
@(private = "file")
fixture_init :: proc(t: ^testing.T, f: ^Fixture, shapes_src, data_src: string) -> bool {
	{
		sdb: Test_DB
		defer tdb_close(&sdb)
		if !tdb_open(t, &sdb) {
			return false
		}
		if !tdb_load(t, &sdb, shapes_src) {
			return false
		}
		err := compile(&f.shapes, tdb_session(&sdb))
		if !testing.expectf(t, err.kind == .None, "compile: %s", error_message(err.kind)) {
			return false
		}
	}

	if !tdb_open(t, &f.db) {
		return false
	}
	if !tdb_load(t, &f.db, data_src) {
		return false
	}
	f.se = tdb_session(&f.db)
	bindings_init(&f.bindings, &f.shapes, f.se)
	return true
}

@(private = "file")
fixture_destroy :: proc(f: ^Fixture) {
	bindings_destroy(&f.bindings)
	shapes_destroy(&f.shapes)
	tdb_close(&f.db)
}

@(private = "file")
Seen :: struct {
	se:      Session,
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
record_result :: proc(data: rawptr, result: Result) -> bool {
	s := cast(^Seen)data
	sb := strings.builder_make()
	strings.write_string(&sb, local_name(component_iri(result.component)))
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
write_node :: proc(s: ^Seen, sb: ^strings.Builder, ref: Node_Ref) {
	if !ref.bound {
		strings.write_string(sb, "?")
		return
	}
	if iri, is_iri := test_term(s.se, ref.id).(rdf.IRI); is_iri {
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

// The same shapes over the same graph must produce exactly these results —
// the dispatch reading, asserted through the whole stack.
@(test)
test_record_validation_results :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, VALIDATE_SHAPES, VALIDATE_DATA) {
		return
	}

	seen := Seen {
		se = f.se,
	}
	defer seen_destroy(&seen)
	testing.expect_value(t, validate(&f.shapes, &f.bindings, f.se, record_result, &seen), Failure.None)

	got := slice.clone(seen.lines[:])
	defer delete(got)
	slice.sort(got)
	joined := strings.join(got, "  ")
	defer delete(joined)

	// ex:a is an IRI of class ex:C and a member of the sh:in list, so it fails
	// only sh:datatype; ex:b and ex:c are IRIs too — so no sh:nodeKind result
	// anywhere — but they are of no class and in no list.
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

// A report outlives the store it was produced from: every term the report
// interned was decoded from arena bytes that closing the store frees.
@(test)
test_record_report_outlives_the_store :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, VALIDATE_SHAPES, VALIDATE_DATA) {
		return
	}

	report: Report
	report_init(&report)
	defer report_destroy(&report)

	testing.expect_value(
		t,
		validate_report(&report, &f.shapes, &f.bindings, f.se),
		Failure.None,
	)
	testing.expectf(t, !report_conforms(&report), "the fixture graph does not conform")

	tdb_close(&f.db)

	// Everything below reads the report with the store closed.
	results, conforms_false := 0, 0
	for triple in report_triples(&report) {
		pred, is_iri := triple.predicate.(rdf.IRI)
		if !is_iri {
			continue
		}
		switch string(pred) {
		case RESULT:
			results += 1
		case CONFORMS:
			if lit, is_lit := triple.object.(rdf.Literal); is_lit && lit.lexical == "false" {
				conforms_false += 1
			}
		}
	}
	testing.expect_value(t, results, 12)
	testing.expect_value(t, conforms_false, 1)
}

// Early exit stops the traversal where it matters: every step avoided is a
// scan not run.
@(test)
test_record_early_exit :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, VALIDATE_SHAPES, VALIDATE_DATA) {
		return
	}

	stopped := Seen {
		se      = f.se,
		stop_at = 1,
	}
	defer seen_destroy(&stopped)
	testing.expect_value(
		t,
		validate(&f.shapes, &f.bindings, f.se, record_result, &stopped),
		Failure.None,
	)
	testing.expect_value(t, len(stopped.lines), 1)

	got, failure := conforms(&f.shapes, &f.bindings, f.se)
	testing.expect_value(t, failure, Failure.None)
	testing.expectf(t, !got, "a violating graph must not conform")
}

// Recursion is detected through the whole stack: a detection that failed here
// would hang a validation forever on cyclic data.
@(test)
test_record_recursive_shape_is_a_reported_failure :: proc(t: ^testing.T) {
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
	if !fixture_init(t, &f, RECURSIVE, CYCLE) {
		return
	}

	seen := Seen {
		se = f.se,
	}
	defer seen_destroy(&seen)
	testing.expect_value(
		t,
		validate(&f.shapes, &f.bindings, f.se, record_result, &seen),
		Failure.Recursive_Shape,
	)
}

// conforms_node through the whole stack: the mechanism is the same walk with
// the visitor swapped, so what this checks is that it answers the same over a
// real store as over the hand-built model in suppress_test.odin.

@(private = "file")
SUPPRESS_SHAPES :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
@prefix ex: <http://example.org/> .

ex:Targeted a sh:NodeShape ; sh:targetNode ex:a ; sh:nodeKind sh:Literal .
ex:KindShape a sh:NodeShape ; sh:nodeKind sh:IRI .
ex:Nested a sh:NodeShape ;
	sh:property [ sh:path ex:p ; sh:minCount 1 ; sh:datatype xsd:string ] .
`

@(private = "file")
SUPPRESS_DATA :: `
@prefix ex: <http://example.org/> .

ex:a ex:p "x" .
ex:b ex:q "y" .
`

@(private = "file")
shape_index :: proc(s: ^Shapes, iri: string) -> int {
	i, _ := shape_index_of(s, rdf.IRI(iri))
	return i
}

@(test)
test_record_conforms_node :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, SUPPRESS_SHAPES, SUPPRESS_DATA) {
		return
	}

	kind := shape_index(&f.shapes, "http://example.org/KindShape")
	nested := shape_index(&f.shapes, "http://example.org/Nested")
	if !testing.expect(t, kind >= 0 && nested >= 0, "fixture: both shapes must compile") {
		return
	}
	a := rdf.Term(rdf.IRI("http://example.org/a"))
	b := rdf.Term(rdf.IRI("http://example.org/b"))

	does, failure := conforms_node(&f.shapes, &f.bindings, f.se, kind, node_focus(f.se, a))
	testing.expect_value(t, failure, Failure.None)
	testing.expect(t, does, "ex:a is an IRI")

	does, failure = conforms_node(&f.shapes, &f.bindings, f.se, nested, node_focus(f.se, a))
	testing.expect_value(t, failure, Failure.None)
	testing.expect(t, does, "ex:a has one ex:p string value")

	does, failure = conforms_node(&f.shapes, &f.bindings, f.se, nested, node_focus(f.se, b))
	testing.expect_value(t, failure, Failure.None)
	testing.expect(t, !does, "ex:b has no ex:p, so sh:minCount 1 violates")
}
