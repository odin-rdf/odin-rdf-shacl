package shacl

import "core:slice"
import "core:strings"
import "core:testing"

import "rdf:rdf"
import "record:record"

// Path evaluation against a data graph.
//
// The fixture is deliberately cyclic — ex:a → ex:b → ex:c → ex:a — because
// that is the case a reachability walk gets wrong, and because it is an
// ordinary modelling situation rather than an exotic one. Shapes over assets
// that point at assets produce exactly this shape of graph.
//
// The shapes graph and the data graph are the same document here, which is
// also how the W3C suite is written: `sht:dataGraph <>` and
// `sht:shapesGraph <>` both name the test file.
@(private = "file")
GRAPH :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix ex: <http://example.org/> .

ex:a ex:p ex:b .
ex:b ex:p ex:c .
ex:c ex:p ex:a .

ex:a ex:q ex:x .
ex:b ex:q ex:y .

ex:P_predicate    a sh:PropertyShape ; sh:path ex:p .
ex:P_inverse      a sh:PropertyShape ; sh:path [ sh:inversePath ex:p ] .
ex:P_sequence     a sh:PropertyShape ; sh:path ( ex:p ex:q ) .
ex:P_alternative  a sh:PropertyShape ; sh:path [ sh:alternativePath ( ex:p ex:q ) ] .
ex:P_zero_or_more a sh:PropertyShape ; sh:path [ sh:zeroOrMorePath ex:p ] .
ex:P_one_or_more  a sh:PropertyShape ; sh:path [ sh:oneOrMorePath ex:p ] .
ex:P_zero_or_one  a sh:PropertyShape ; sh:path [ sh:zeroOrOnePath ex:p ] .
ex:P_inverse_seq  a sh:PropertyShape ; sh:path [ sh:inversePath ( ex:p ex:q ) ] .
ex:P_unknown      a sh:PropertyShape ; sh:path ex:never_used_in_data .
ex:P_alt_overlap  a sh:PropertyShape ; sh:path [ sh:alternativePath ( ex:p ex:p ) ] .
`

@(private = "file")
Fixture :: struct {
	db:       Test_DB,
	se:       Session,
	shapes:   Shapes,
	bindings: Path_Bindings,
}

@(private = "file")
fixture_init :: proc(t: ^testing.T, f: ^Fixture, source: string) -> bool {
	if !tdb_open(t, &f.db) {
		return false
	}
	if !tdb_load(t, &f.db, source) {
		return false
	}
	f.se = tdb_session(&f.db)
	err := compile(&f.shapes, f.se)
	if !testing.expectf(t, err.kind == .None, "compile failed: %s", error_message(err.kind)) {
		return false
	}
	path_bindings_init(&f.bindings, &f.shapes, f.se)
	return true
}

@(private = "file")
fixture_destroy :: proc(f: ^Fixture) {
	path_bindings_destroy(&f.bindings)
	shapes_destroy(&f.shapes)
	tdb_close(&f.db)
}

// eval returns the value nodes of the named property shape from the named
// focus node, as sorted IRI strings — a set comparison that reads in the test
// rather than an ID comparison that does not.
@(private = "file")
eval :: proc(t: ^testing.T, f: ^Fixture, shape_iri, focus_iri: string) -> []string {
	path := -1
	for sh in f.shapes.shapes {
		if got, is_iri := sh.node.(rdf.IRI); is_iri && string(got) == shape_iri {
			path = sh.path
			break
		}
	}
	if !testing.expectf(t, path >= 0, "%s: no compiled path", shape_iri) {
		return nil
	}

	focus, found := session_resolve(f.se, rdf.IRI(focus_iri))
	if !testing.expectf(t, found, "focus node %s is not in the store", focus_iri) {
		return nil
	}

	ids := value_nodes(&f.shapes, &f.bindings, path, focus, f.se)
	defer delete(ids)

	out := make([]string, len(ids))
	for id, i in ids {
		term := test_term(f.se, id)
		if iri, is_iri := term.(rdf.IRI); is_iri {
			out[i] = string(iri)
		} else {
			out[i] = "<not an IRI>"
		}
	}
	slice.sort(out)
	return out
}

@(private = "file")
expect_eval_set :: proc(t: ^testing.T, got: []string, want: []string, what: string) {
	joined_got := strings.join(got, " ")
	defer delete(joined_got)
	joined_want := strings.join(want, " ")
	defer delete(joined_want)
	testing.expectf(t, joined_got == joined_want, "%s: got {%s}, want {%s}", what, joined_got, joined_want)
}

@(test)
test_path_predicate_and_inverse :: proc(t: ^testing.T) {
	f: Fixture
	if !fixture_init(t, &f, GRAPH) {
		fixture_destroy(&f)
		return
	}
	defer fixture_destroy(&f)

	got := eval(t, &f, EX + "P_predicate", EX + "a")
	defer delete(got)
	expect_eval_set(t, got, []string{EX + "b"}, "ex:p from ex:a")

	// ex:c ex:p ex:a, so the inverse of ex:p from ex:a is ex:c.
	inv := eval(t, &f, EX + "P_inverse", EX + "a")
	defer delete(inv)
	expect_eval_set(t, inv, []string{EX + "c"}, "^ex:p from ex:a")
}

@(test)
test_path_sequence :: proc(t: ^testing.T) {
	f: Fixture
	if !fixture_init(t, &f, GRAPH) {
		fixture_destroy(&f)
		return
	}
	defer fixture_destroy(&f)

	// ( ex:p ex:q ) from ex:a: ex:p reaches ex:b, ex:q from ex:b reaches ex:y.
	got := eval(t, &f, EX + "P_sequence", EX + "a")
	defer delete(got)
	expect_eval_set(t, got, []string{EX + "y"}, "( ex:p ex:q ) from ex:a")
}

// The inverse of a sequence is the reversed sequence of inverses. Evaluating
// it forwards would silently give the wrong answer on any graph where the two
// predicates are not symmetric, so it gets its own test.
@(test)
test_path_inverse_of_sequence_reverses :: proc(t: ^testing.T) {
	f: Fixture
	if !fixture_init(t, &f, GRAPH) {
		fixture_destroy(&f)
		return
	}
	defer fixture_destroy(&f)

	// ^( ex:p ex:q ) from ex:y: inverse of ex:q reaches ex:b, inverse of ex:p
	// from ex:b reaches ex:a.
	got := eval(t, &f, EX + "P_inverse_seq", EX + "y")
	defer delete(got)
	expect_eval_set(t, got, []string{EX + "a"}, "^( ex:p ex:q ) from ex:y")

	// And it is genuinely directional: nothing comes back the other way.
	empty := eval(t, &f, EX + "P_inverse_seq", EX + "a")
	defer delete(empty)
	expect_eval_set(t, empty, []string{}, "^( ex:p ex:q ) from ex:a")
}

@(test)
test_path_alternative :: proc(t: ^testing.T) {
	f: Fixture
	if !fixture_init(t, &f, GRAPH) {
		fixture_destroy(&f)
		return
	}
	defer fixture_destroy(&f)

	got := eval(t, &f, EX + "P_alternative", EX + "a")
	defer delete(got)
	expect_eval_set(t, got, []string{EX + "b", EX + "x"}, "ex:p | ex:q from ex:a")

	// Value nodes are a set: an alternative whose branches overlap yields
	// each node once.
	overlap := eval(t, &f, EX + "P_alt_overlap", EX + "a")
	defer delete(overlap)
	expect_eval_set(t, overlap, []string{EX + "b"}, "ex:p | ex:p from ex:a")
}

// The reachability forms over cyclic data. Without a visited set these do not
// terminate; with a wrong one they return the wrong set.
@(test)
test_path_reachability_is_cycle_safe :: proc(t: ^testing.T) {
	f: Fixture
	if !fixture_init(t, &f, GRAPH) {
		fixture_destroy(&f)
		return
	}
	defer fixture_destroy(&f)

	// zeroOrMore includes the focus node itself, then everything reachable —
	// which around this cycle is all three nodes.
	zom := eval(t, &f, EX + "P_zero_or_more", EX + "a")
	defer delete(zom)
	expect_eval_set(t, zom, []string{EX + "a", EX + "b", EX + "c"}, "ex:p* from ex:a")

	// oneOrMore excludes the focus node *unless it is genuinely reachable* —
	// and here it is, because the cycle comes back to ex:a. That is the
	// distinction a naive "drop the input" implementation gets wrong.
	oom := eval(t, &f, EX + "P_one_or_more", EX + "a")
	defer delete(oom)
	expect_eval_set(t, oom, []string{EX + "a", EX + "b", EX + "c"}, "ex:p+ from ex:a")

	// zeroOrOne is the focus node plus one step, and no further.
	zoo := eval(t, &f, EX + "P_zero_or_one", EX + "a")
	defer delete(zoo)
	expect_eval_set(t, zoo, []string{EX + "a", EX + "b"}, "ex:p? from ex:a")
}

// oneOrMore on an acyclic graph must *not* include the focus node — the
// counterpart to the test above, and the reason that one is not vacuous.
@(test)
test_one_or_more_excludes_unreachable_focus :: proc(t: ^testing.T) {
	f: Fixture
	acyclic := `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:a ex:p ex:b . ex:b ex:p ex:c .
	ex:P_one_or_more a sh:PropertyShape ; sh:path [ sh:oneOrMorePath ex:p ] .
	ex:P_zero_or_more a sh:PropertyShape ; sh:path [ sh:zeroOrMorePath ex:p ] .
	`
	if !fixture_init(t, &f, acyclic) {
		fixture_destroy(&f)
		return
	}
	defer fixture_destroy(&f)

	oom := eval(t, &f, EX + "P_one_or_more", EX + "a")
	defer delete(oom)
	expect_eval_set(t, oom, []string{EX + "b", EX + "c"}, "ex:p+ from ex:a, acyclic")

	zom := eval(t, &f, EX + "P_zero_or_more", EX + "a")
	defer delete(zom)
	expect_eval_set(t, zom, []string{EX + "a", EX + "b", EX + "c"}, "ex:p* from ex:a, acyclic")
}

// A predicate the data store has never seen. Absence is emptiness on a path —
// the opposite of what it means to a constraint, where an absent sh:class
// term makes every value node violate.
@(test)
test_unbound_predicate_yields_nothing :: proc(t: ^testing.T) {
	f: Fixture
	if !fixture_init(t, &f, GRAPH) {
		fixture_destroy(&f)
		return
	}
	defer fixture_destroy(&f)

	got := eval(t, &f, EX + "P_unknown", EX + "a")
	defer delete(got)
	expect_eval_set(t, got, []string{}, "a predicate absent from the data")
}

// A focus node with no outgoing triples at all: every form must return
// cleanly rather than reaching into an empty index.
@(test)
test_focus_node_with_no_edges :: proc(t: ^testing.T) {
	f: Fixture
	if !fixture_init(t, &f, GRAPH) {
		fixture_destroy(&f)
		return
	}
	defer fixture_destroy(&f)

	for shape in ([]string{"P_predicate", "P_sequence", "P_alternative", "P_one_or_more"}) {
		got := eval(t, &f, strings.concatenate({EX, shape}, context.temp_allocator), EX + "x")
		defer delete(got)
		expect_eval_set(t, got, []string{}, shape)
	}
	// ...except the reflexive forms, which always yield the focus node.
	zom := eval(t, &f, EX + "P_zero_or_more", EX + "x")
	defer delete(zom)
	expect_eval_set(t, zom, []string{EX + "x"}, "ex:p* from a node with no edges")
}

// Deep nesting: ^( ex:p ex:q ) inside an alternative inside a sequence. The
// evaluator recurses over the path, so this is the case that would break if
// direction were not carried down properly.
@(test)
test_deeply_nested_path :: proc(t: ^testing.T) {
	f: Fixture
	nested := `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:a ex:p ex:b .
	ex:b ex:q ex:y .
	ex:z ex:r ex:a .
	ex:P a sh:PropertyShape ;
		sh:path ( [ sh:alternativePath ( ex:p [ sh:inversePath ex:r ] ) ] ex:q ) .
	`
	if !fixture_init(t, &f, nested) {
		fixture_destroy(&f)
		return
	}
	defer fixture_destroy(&f)

	// From ex:a: the alternative reaches ex:b (via ex:p) and ex:z (via ^ex:r);
	// then ex:q from those reaches ex:y from ex:b, and nothing from ex:z.
	got := eval(t, &f, EX + "P", EX + "a")
	defer delete(got)
	expect_eval_set(t, got, []string{EX + "y"}, "( (ex:p | ^ex:r) ex:q ) from ex:a")
}

@(test)
test_value_nodes_of_a_node_shape_is_empty :: proc(t: ^testing.T) {
	f: Fixture
	if !fixture_init(t, &f, GRAPH) {
		fixture_destroy(&f)
		return
	}
	defer fixture_destroy(&f)

	focus, _ := session_resolve(f.se, rdf.IRI(EX + "a"))
	// -1 is what a node shape carries: it has no path, and its value node is
	// its focus node, which is the caller's business rather than this one's.
	ids := value_nodes(&f.shapes, &f.bindings, -1, focus, f.se)
	defer delete(ids)
	testing.expect_value(t, len(ids), 0)
	testing.expect_value(t, session_kind(f.se, focus), record.Term_Kind.IRI)
}
