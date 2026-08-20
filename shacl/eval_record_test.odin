package shacl

import "core:slice"
import "core:strings"
import "core:testing"

import rdf "rdf:rdf"

// Path evaluation, target resolution, and report ownership against the
// record store — the assertions that exercised backend-facing behaviour when
// there was a seam, kept because they exercise the session verbs end to end.

EVAL_GRAPH :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix ex: <http://example.org/> .

ex:a ex:p ex:b .
ex:b ex:p ex:c .
ex:c ex:p ex:a .
ex:a ex:q ex:x .
ex:b ex:q ex:y .

ex:P_predicate    a sh:PropertyShape ; sh:path ex:p .
ex:P_inverse_seq  a sh:PropertyShape ; sh:path [ sh:inversePath ( ex:p ex:q ) ] .
ex:P_zero_or_more a sh:PropertyShape ; sh:path [ sh:zeroOrMorePath ex:p ] .
ex:P_alternative  a sh:PropertyShape ; sh:path [ sh:alternativePath ( ex:p ex:q ) ] .
`

EX :: "http://example.org/"

@(private = "file")
eval_set :: proc(
	t: ^testing.T,
	s: ^Shapes,
	b: ^Path_Bindings,
	se: Session,
	shape_iri, focus_iri: string,
) -> []string {
	path := -1
	if i, ok := shape_index_of(s, rdf.IRI(shape_iri)); ok {
		path = s.shapes[i].path
	}
	if !testing.expectf(t, path >= 0, "%s: no compiled path", shape_iri) {
		return nil
	}

	focus, found := session_resolve(se, rdf.IRI(focus_iri))
	if !testing.expectf(t, found, "focus node %s is not in the store", focus_iri) {
		return nil
	}

	ids := value_nodes(s, b, path, focus, se)
	defer delete(ids)

	out := make([]string, len(ids))
	for id, i in ids {
		if iri, is_iri := test_term(se, id).(rdf.IRI); is_iri {
			out[i] = strings.clone(string(iri))
		} else {
			out[i] = strings.clone("<not an IRI>")
		}
	}
	slice.sort(out)
	return out
}

@(private = "file")
destroy_set :: proc(set: []string) {
	for s in set {
		delete(s)
	}
	delete(set)
}

@(private = "file")
expect_set :: proc(t: ^testing.T, got: []string, want: []string, what: string) {
	joined_got := strings.join(got, " ")
	defer delete(joined_got)
	joined_want := strings.join(want, " ")
	defer delete(joined_want)
	testing.expectf(t, joined_got == joined_want, "%s: got {%s}, want {%s}", what, joined_got, joined_want)
}

@(test)
test_record_path_evaluation :: proc(t: ^testing.T) {
	db: Test_DB
	defer tdb_close(&db)
	if !tdb_open(t, &db) {
		return
	}
	if !tdb_load(t, &db, EVAL_GRAPH) {
		return
	}
	se := tdb_session(&db)

	s: Shapes
	defer shapes_destroy(&s)
	testing.expect_value(t, compile(&s, se).kind, Error_Kind.None)

	b: Path_Bindings
	defer path_bindings_destroy(&b)
	path_bindings_init(&b, &s, se)

	got := eval_set(t, &s, &b, se, EX + "P_predicate", EX + "a")
	defer destroy_set(got)
	expect_set(t, got, []string{EX + "b"}, "ex:p from ex:a")

	// The inverse of a sequence, which must evaluate right-to-left.
	inv := eval_set(t, &s, &b, se, EX + "P_inverse_seq", EX + "y")
	defer destroy_set(inv)
	expect_set(t, inv, []string{EX + "a"}, "^( ex:p ex:q ) from ex:y")

	// Cycle-safe reachability over the permutation scans.
	zom := eval_set(t, &s, &b, se, EX + "P_zero_or_more", EX + "a")
	defer destroy_set(zom)
	expect_set(t, zom, []string{EX + "a", EX + "b", EX + "c"}, "ex:p* from ex:a")

	alt := eval_set(t, &s, &b, se, EX + "P_alternative", EX + "a")
	defer destroy_set(alt)
	expect_set(t, alt, []string{EX + "b", EX + "x"}, "ex:p | ex:q from ex:a")
}

// A path that reaches nothing is an ordinary empty answer.
@(test)
test_record_empty_path_is_not_an_error :: proc(t: ^testing.T) {
	db: Test_DB
	defer tdb_close(&db)
	if !tdb_open(t, &db) {
		return
	}
	source := `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:lonely ex:other ex:thing .
	ex:P a sh:PropertyShape ; sh:path ex:p .
	`
	if !tdb_load(t, &db, source) {
		return
	}
	se := tdb_session(&db)

	s: Shapes
	defer shapes_destroy(&s)
	testing.expect_value(t, compile(&s, se).kind, Error_Kind.None)

	b: Path_Bindings
	defer path_bindings_destroy(&b)
	path_bindings_init(&b, &s, se)

	got := eval_set(t, &s, &b, se, EX + "P", EX + "lonely")
	defer destroy_set(got)
	expect_set(t, got, []string{}, "a path that reaches nothing")
}

// Target resolution: the subclass closure, which walks the store repeatedly,
// and the two predicate scans.
TARGET_GRAPH :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix ex: <http://example.org/> .

ex:Sub rdfs:subClassOf ex:Super .
ex:n1 a ex:Super . ex:n2 a ex:Sub .
ex:s1 ex:knows ex:o1 .

ex:S_class    a sh:NodeShape ; sh:targetClass ex:Super .
ex:S_subjects a sh:NodeShape ; sh:targetSubjectsOf ex:knows .
ex:S_objects  a sh:NodeShape ; sh:targetObjectsOf ex:knows .
`

@(private = "file")
Names :: struct {
	se:    Session,
	names: [dynamic]string,
}

@(private = "file")
collect_name :: proc(data: rawptr, focus: Focus_Node) -> bool {
	c := cast(^Names)data
	if iri, is_iri := test_term(c.se, focus.id).(rdf.IRI); is_iri {
		append(&c.names, strings.clone(string(iri)))
	}
	return true
}

@(test)
test_record_target_resolution :: proc(t: ^testing.T) {
	db: Test_DB
	defer tdb_close(&db)
	if !tdb_open(t, &db) {
		return
	}
	if !tdb_load(t, &db, TARGET_GRAPH) {
		return
	}
	se := tdb_session(&db)

	s: Shapes
	defer shapes_destroy(&s)
	testing.expect_value(t, compile(&s, se).kind, Error_Kind.None)

	b: Target_Bindings
	defer target_bindings_destroy(&b)
	target_bindings_init(&b, &s, se)

	expect :: proc(t: ^testing.T, s: ^Shapes, b: ^Target_Bindings, se: Session, iri: string, want: []string) {
		index, _ := shape_index_of(s, rdf.IRI(iri))
		if !testing.expectf(t, index >= 0, "%s not compiled", iri) {
			return
		}
		c := Names {
			se    = se,
			names = make([dynamic]string),
		}
		defer {
			for n in c.names {
				delete(n)
			}
			delete(c.names)
		}
		resolve_targets(s, b, index, se, collect_name, &c)
		slice.sort(c.names[:])
		got := strings.join(c.names[:], " ")
		defer delete(got)
		joined := strings.join(want, " ")
		defer delete(joined)
		testing.expectf(t, got == joined, "%s: got {%s}, want {%s}", iri, got, joined)
	}

	// The closure reaches instances of the subclass as well as the class.
	expect(t, &s, &b, se, EX + "S_class", []string{EX + "n1", EX + "n2"})
	expect(t, &s, &b, se, EX + "S_subjects", []string{EX + "s1"})
	expect(t, &s, &b, se, EX + "S_objects", []string{EX + "o1"})
}

// Report building: the report interns every term it is given, so it owns the
// graph — asserted by closing the store before reading it.
@(test)
test_record_report_owns_its_terms :: proc(t: ^testing.T) {
	db: Test_DB
	defer tdb_close(&db)
	if !tdb_open(t, &db) {
		return
	}
	source := `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:S a sh:NodeShape ; sh:targetNode ex:focus ;
		sh:property [ sh:path [ sh:inversePath ex:child ] ; sh:minCount 1 ] .
	ex:focus ex:name "x" .
	`
	if !tdb_load(t, &db, source) {
		return
	}
	se := tdb_session(&db)

	s: Shapes
	defer shapes_destroy(&s)
	testing.expect_value(t, compile(&s, se).kind, Error_Kind.None)

	// The property shape, found by having a path.
	index := -1
	for sh, i in s.shapes {
		if sh.path >= 0 {
			index = i
			break
		}
	}
	if !testing.expect(t, index >= 0, "no property shape compiled") {
		return
	}

	focus, found := session_resolve(se, rdf.IRI(EX + "focus"))
	testing.expect(t, found, "focus node missing")

	r: Report
	report_init(&r)
	defer report_destroy(&r)
	report_add(
		&r,
		&s,
		Result {
			focus = Node_Ref{id = focus, bound = true},
			path = s.shapes[index].path,
			shape = index,
			component = .Min_Count,
			severity = rdf.IRI(VIOLATION),
		},
		se,
	)
	report_finish(&r)

	// Every term in the graph came from arena bytes this invalidates.
	tdb_close(&db)

	testing.expect(t, !report_conforms(&r), "a violation must break conformance")
	saw_focus := false
	for tr in report_triples(&r) {
		if pred, is_iri := tr.predicate.(rdf.IRI); is_iri && string(pred) == FOCUS_NODE {
			if obj, obj_iri := tr.object.(rdf.IRI); obj_iri && string(obj) == EX + "focus" {
				saw_focus = true
			}
		}
	}
	testing.expect(t, saw_focus, "the report lost its focus node when the store closed")
}
