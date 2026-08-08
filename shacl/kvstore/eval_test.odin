package shacl_kvstore

import "core:slice"
import "core:strings"
import "core:testing"

import rdf "rdf:rdf"
import kvstore "store:store/kvstore"

import shacl ".."

// Path evaluation against the persistent backend. The memstore file is the
// fuller suite; this asserts that the same paths over the same graph produce
// the same value nodes through LMDB, and that a step failure is recorded
// rather than read as an empty path.

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
	s: ^shacl.Shapes,
	b: ^shacl.Path_Bindings,
	session: ^Session,
	shape_iri, focus_iri: string,
) -> []string {
	path := -1
	if i, ok := shacl.shape_index_of(s, rdf.IRI(shape_iri)); ok {
		path = s.shapes[i].path
	}
	if !testing.expectf(t, path >= 0, "%s: no compiled path", shape_iri) {
		return nil
	}

	focus, found, find_err := kvstore.find_term(session.db, rdf.IRI(focus_iri))
	testing.expectf(t, find_err == nil, "find_term failed: %v", find_err)
	if !testing.expectf(t, found, "focus node %s is not in the store", focus_iri) {
		return nil
	}

	ids := value_nodes(s, b, session, path, focus)
	defer delete(ids)

	out := make([]string, len(ids))
	for id, i in ids {
		term, err := kvstore.lookup_term(session.db, id)
		defer rdf.destroy_term(term)
		testing.expectf(t, err == nil, "lookup_term failed: %v", err)
		if iri, is_iri := term.(rdf.IRI); is_iri {
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
test_kvstore_path_evaluation_matches_memstore :: proc(t: ^testing.T) {
	st, open_err := kvstore.open_ephemeral()
	if !testing.expectf(t, open_err == nil, "kvstore.open failed: %v", open_err) {
		return
	}
	defer kvstore.close(st)

	_, parse_err, load_err := kvstore.load_turtle(st, transmute([]byte)string(EVAL_GRAPH))
	testing.expectf(t, parse_err.message == "", "parse failed: %s", parse_err.message)
	testing.expectf(t, load_err == nil, "load failed: %v", load_err)

	session: Session
	session_init(&session, st)

	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)
	err := compile(&s, &session)
	testing.expect_value(t, err.kind, shacl.Error_Kind.None)

	b: shacl.Path_Bindings
	defer shacl.path_bindings_destroy(&b)
	bind_paths(&b, &s, &session)

	got := eval_set(t, &s, &b, &session, EX + "P_predicate", EX + "a")
	defer destroy_set(got)
	expect_set(t, got, []string{EX + "b"}, "ex:p from ex:a")

	// The inverse of a sequence, which must evaluate right-to-left.
	inv := eval_set(t, &s, &b, &session, EX + "P_inverse_seq", EX + "y")
	defer destroy_set(inv)
	expect_set(t, inv, []string{EX + "a"}, "^( ex:p ex:q ) from ex:y")

	// Cycle-safe reachability, through LMDB cursors rather than sorted slices.
	zom := eval_set(t, &s, &b, &session, EX + "P_zero_or_more", EX + "a")
	defer destroy_set(zom)
	expect_set(t, zom, []string{EX + "a", EX + "b", EX + "c"}, "ex:p* from ex:a")

	alt := eval_set(t, &s, &b, &session, EX + "P_alternative", EX + "a")
	defer destroy_set(alt)
	expect_set(t, alt, []string{EX + "b", EX + "x"}, "ex:p | ex:q from ex:a")

	testing.expectf(t, session_error(&session) == nil, "store error during evaluation: %v", session_error(&session))
}

// A path that reaches nothing and a store that failed to answer look
// identical from the evaluator. This asserts the clean case really is clean —
// so that a non-nil session error is a genuine signal rather than noise a
// caller learns to ignore.
@(test)
test_kvstore_empty_path_is_not_an_error :: proc(t: ^testing.T) {
	st, open_err := kvstore.open_ephemeral()
	if !testing.expectf(t, open_err == nil, "kvstore.open failed: %v", open_err) {
		return
	}
	defer kvstore.close(st)

	source := `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:lonely ex:other ex:thing .
	ex:P a sh:PropertyShape ; sh:path ex:p .
	`
	_, parse_err, load_err := kvstore.load_turtle(st, transmute([]byte)source)
	testing.expectf(t, parse_err.message == "", "parse failed: %s", parse_err.message)
	testing.expectf(t, load_err == nil, "load failed: %v", load_err)

	session: Session
	session_init(&session, st)

	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)
	testing.expect_value(t, compile(&s, &session).kind, shacl.Error_Kind.None)

	b: shacl.Path_Bindings
	defer shacl.path_bindings_destroy(&b)
	bind_paths(&b, &s, &session)

	got := eval_set(t, &s, &b, &session, EX + "P", EX + "lonely")
	defer destroy_set(got)
	expect_set(t, got, []string{}, "a path that reaches nothing")
	testing.expectf(
		t,
		session_error(&session) == nil,
		"an empty path recorded a store error: %v",
		session_error(&session),
	)
}

// Target resolution against the persistent backend. The memstore file is the
// fuller suite; this asserts the forms whose answer could differ by backend —
// the subclass closure, which walks the store repeatedly, and the two
// predicate scans, which stream through LMDB cursors rather than sorted
// slices.
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
	session: ^Session,
	names:   [dynamic]string,
}

@(private = "file")
collect_name :: proc(data: rawptr, focus: shacl.Focus_Node) -> bool {
	c := cast(^Names)data
	term, err := kvstore.lookup_term(c.session.db, focus.id)
	defer rdf.destroy_term(term)
	if err != nil {
		return true
	}
	if iri, is_iri := term.(rdf.IRI); is_iri {
		append(&c.names, strings.clone(string(iri)))
	}
	return true
}

@(test)
test_kvstore_target_resolution :: proc(t: ^testing.T) {
	st, open_err := kvstore.open_ephemeral()
	if !testing.expectf(t, open_err == nil, "kvstore.open failed: %v", open_err) {
		return
	}
	defer kvstore.close(st)

	_, parse_err, load_err := kvstore.load_turtle(st, transmute([]byte)string(TARGET_GRAPH))
	testing.expectf(t, parse_err.message == "", "parse failed: %s", parse_err.message)
	testing.expectf(t, load_err == nil, "load failed: %v", load_err)

	session: Session
	session_init(&session, st)

	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)
	testing.expect_value(t, compile(&s, &session).kind, shacl.Error_Kind.None)

	b: shacl.Target_Bindings
	defer shacl.target_bindings_destroy(&b)
	bind_targets(&b, &s, &session)

	expect :: proc(t: ^testing.T, s: ^shacl.Shapes, b: ^shacl.Target_Bindings, session: ^Session, iri: string, want: []string) {
		index, _ := shacl.shape_index_of(s, rdf.IRI(iri))
		if !testing.expectf(t, index >= 0, "%s not compiled", iri) {
			return
		}
		c := Names {
			session = session,
			names   = make([dynamic]string),
		}
		defer {
			for n in c.names {
				delete(n)
			}
			delete(c.names)
		}
		resolve_targets(s, b, index, session, collect_name, &c)
		slice.sort(c.names[:])
		got := strings.join(c.names[:], " ")
		defer delete(got)
		joined := strings.join(want, " ")
		defer delete(joined)
		testing.expectf(t, got == joined, "%s: got {%s}, want {%s}", iri, got, joined)
	}

	// The closure reaches instances of the subclass as well as the class.
	expect(t, &s, &b, &session, EX + "S_class", []string{EX + "n1", EX + "n2"})
	expect(t, &s, &b, &session, EX + "S_subjects", []string{EX + "s1"})
	expect(t, &s, &b, &session, EX + "S_objects", []string{EX + "o1"})

	testing.expectf(t, session_error(&session) == nil, "store error: %v", session_error(&session))
}

// Report building against the persistent backend. The interesting difference
// is that kvstore's lookup_term allocates where memstore's borrows, so this
// asserts the report still owns every term afterwards — by closing the store
// before reading the graph.
@(test)
test_kvstore_report_owns_its_terms :: proc(t: ^testing.T) {
	st, open_err := kvstore.open_ephemeral()
	if !testing.expectf(t, open_err == nil, "kvstore.open failed: %v", open_err) {
		return
	}

	source := `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:S a sh:NodeShape ; sh:targetNode ex:focus ;
		sh:property [ sh:path [ sh:inversePath ex:child ] ; sh:minCount 1 ] .
	ex:focus ex:name "x" .
	`
	_, parse_err, load_err := kvstore.load_turtle(st, transmute([]byte)source)
	testing.expectf(t, parse_err.message == "", "parse failed: %s", parse_err.message)
	testing.expectf(t, load_err == nil, "load failed: %v", load_err)

	session: Session
	session_init(&session, st)

	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)
	testing.expect_value(t, compile(&s, &session).kind, shacl.Error_Kind.None)

	// The property shape, found by having a path.
	index := -1
	for sh, i in s.shapes {
		if sh.path >= 0 {
			index = i
			break
		}
	}
	if !testing.expect(t, index >= 0, "no property shape compiled") {
		kvstore.close(st)
		return
	}

	focus, found, _ := kvstore.find_term(session.db, rdf.IRI(EX + "focus"))
	testing.expect(t, found, "focus node missing")

	r: shacl.Report
	shacl.report_init(&r)
	defer shacl.report_destroy(&r)
	report_add(
		&r,
		&s,
		shacl.Result {
			focus = shacl.Node_Ref{id = focus, bound = true},
			path = s.shapes[index].path,
			shape = index,
			component = .Min_Count,
			severity = rdf.IRI(shacl.VIOLATION),
		},
		&session,
	)
	shacl.report_finish(&r)

	// Every term in the graph came from bytes this invalidates.
	kvstore.close(st)

	testing.expect(t, !shacl.report_conforms(&r), "a violation must break conformance")
	saw_focus := false
	for tr in shacl.report_triples(&r) {
		if pred, is_iri := tr.predicate.(rdf.IRI); is_iri && string(pred) == shacl.FOCUS_NODE {
			if obj, obj_iri := tr.object.(rdf.IRI); obj_iri && string(obj) == EX + "focus" {
				saw_focus = true
			}
		}
	}
	testing.expect(t, saw_focus, "the report lost its focus node when the store closed")
}
