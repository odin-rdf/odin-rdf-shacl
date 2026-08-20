package shacl

import "core:slice"
import "core:strings"
import "core:testing"

import "rdf:rdf"

// Target resolution.
//
// The fixture keeps the shapes graph and the data graph in **separate
// stores**, which is the arrangement SHACL-A-0001 decision 2 exists for — the
// model holds `rdf.Term` rather than resident ids precisely so a model
// compiled from one store can be bound against another. It is also the only
// way to exercise an unbound focus node: when shapes and data share a
// document, as they do in the W3C suite, every `sh:targetNode` is necessarily
// in the dictionary.

@(private = "file")
SHAPES_GRAPH :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix ex: <http://example.org/> .

ex:S_node      a sh:NodeShape ; sh:targetNode ex:n1, ex:absent_from_data .
ex:S_class     a sh:NodeShape ; sh:targetClass ex:Super .
ex:S_subjects  a sh:NodeShape ; sh:targetSubjectsOf ex:knows .
ex:S_objects   a sh:NodeShape ; sh:targetObjectsOf ex:knows .
ex:S_implicit  a sh:NodeShape, rdfs:Class .
ex:S_multi     a sh:NodeShape ; sh:targetNode ex:n1 ; sh:targetClass ex:Super .
ex:S_absent    a sh:NodeShape ; sh:targetClass ex:NeverDeclared .
ex:S_cyclic    a sh:NodeShape ; sh:targetClass ex:Loop_A .
`

@(private = "file")
DATA_GRAPH :: `
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix ex: <http://example.org/> .

ex:Sub    rdfs:subClassOf ex:Super .
ex:SubSub rdfs:subClassOf ex:Sub .

ex:n1 a ex:Super .
ex:n2 a ex:Sub .
ex:n3 a ex:SubSub .
ex:unrelated a ex:Elsewhere .

ex:s1 ex:knows ex:o1 .
ex:s2 ex:knows ex:o2 .

ex:inst a ex:S_implicit .

# An ill-advised but permitted class cycle: the closure must terminate.
ex:Loop_A rdfs:subClassOf ex:Loop_B .
ex:Loop_B rdfs:subClassOf ex:Loop_A .
ex:looper a ex:Loop_B .
`

@(private = "file")
Split :: struct {
	data_db: Test_DB,
	data_se: Session,
	shapes:  Shapes,
	targets: Target_Bindings,
}

@(private = "file")
split_init :: proc(t: ^testing.T, f: ^Split) -> bool {
	// The shapes store is opened, compiled from, and closed before the data
	// store exists, so nothing the model holds can be borrowing from it.
	{
		shapes_db: Test_DB
		defer tdb_close(&shapes_db)
		if !tdb_open(t, &shapes_db) {
			return false
		}
		if !tdb_load(t, &shapes_db, SHAPES_GRAPH) {
			return false
		}
		err := compile(&f.shapes, tdb_session(&shapes_db))
		if !testing.expectf(t, err.kind == .None, "compile: %s", error_message(err.kind)) {
			return false
		}
	}

	if !tdb_open(t, &f.data_db) {
		return false
	}
	if !tdb_load(t, &f.data_db, DATA_GRAPH) {
		return false
	}
	f.data_se = tdb_session(&f.data_db)
	// Bound against the *data* store, not the one the model came from.
	target_bindings_init(&f.targets, &f.shapes, f.data_se)
	return true
}

@(private = "file")
split_destroy :: proc(f: ^Split) {
	target_bindings_destroy(&f.targets)
	shapes_destroy(&f.shapes)
	tdb_close(&f.data_db)
}

@(private = "file")
Collector :: struct {
	se:      Session,
	names:   [dynamic]string,
	unbound: int,
	limit:   int, // stop after this many; 0 means no limit
}

@(private = "file")
collect :: proc(data: rawptr, focus: Focus_Node) -> bool {
	c := cast(^Collector)data
	term: rdf.Term
	if focus.bound {
		term = test_term(c.se, focus.id)
	} else {
		c.unbound += 1
		term = focus.term
	}
	if iri, is_iri := term.(rdf.IRI); is_iri {
		append(&c.names, strings.clone(string(iri)))
	} else {
		append(&c.names, strings.clone("<not an IRI>"))
	}
	if c.limit > 0 && len(c.names) >= c.limit {
		return false
	}
	return true
}

@(private = "file")
resolve :: proc(t: ^testing.T, f: ^Split, shape_iri: string, limit := 0) -> (Collector, bool) {
	index := -1
	for sh, i in f.shapes.shapes {
		if got, is_iri := sh.node.(rdf.IRI); is_iri && string(got) == shape_iri {
			index = i
			break
		}
	}
	c := Collector {
		se    = f.data_se,
		names = make([dynamic]string),
		limit = limit,
	}
	if !testing.expectf(t, index >= 0, "%s: shape not compiled", shape_iri) {
		return c, true
	}
	completed := resolve_targets(&f.shapes, &f.targets, index, f.data_se, collect, &c)
	slice.sort(c.names[:])
	return c, completed
}

@(private = "file")
destroy_collector :: proc(c: ^Collector) {
	for n in c.names {
		delete(n)
	}
	delete(c.names)
}

@(private = "file")
expect_names :: proc(t: ^testing.T, c: ^Collector, want: []string, what: string) {
	got := strings.join(c.names[:], " ")
	defer delete(got)
	joined := strings.join(want, " ")
	defer delete(joined)
	testing.expectf(t, got == joined, "%s: got {%s}, want {%s}", what, got, joined)
}

// sh:targetNode, including one naming a term the data graph never mentions.
// That is still a focus node — the spec targets the node, not its
// appearances — and a property shape with sh:minCount 1 must report it.
@(test)
test_target_node_including_absent :: proc(t: ^testing.T) {
	f: Split
	if !split_init(t, &f) {
		split_destroy(&f)
		return
	}
	defer split_destroy(&f)

	c, _ := resolve(t, &f, EX + "S_node")
	defer destroy_collector(&c)
	expect_names(t, &c, []string{EX + "absent_from_data", EX + "n1"}, "sh:targetNode")
	testing.expectf(t, c.unbound == 1, "expected exactly one unbound focus node, got %d", c.unbound)
}

// sh:targetClass follows rdf:type plus rdfs:subClassOf* *down* the hierarchy:
// an instance of a subclass is a focus node of the superclass's shape.
@(test)
test_target_class_follows_subclasses :: proc(t: ^testing.T) {
	f: Split
	if !split_init(t, &f) {
		split_destroy(&f)
		return
	}
	defer split_destroy(&f)

	c, _ := resolve(t, &f, EX + "S_class")
	defer destroy_collector(&c)
	expect_names(t, &c, []string{EX + "n1", EX + "n2", EX + "n3"}, "sh:targetClass ex:Super")
	testing.expect_value(t, c.unbound, 0)
}

@(test)
test_target_subjects_and_objects_of :: proc(t: ^testing.T) {
	f: Split
	if !split_init(t, &f) {
		split_destroy(&f)
		return
	}
	defer split_destroy(&f)

	subjects, _ := resolve(t, &f, EX + "S_subjects")
	defer destroy_collector(&subjects)
	expect_names(t, &subjects, []string{EX + "s1", EX + "s2"}, "sh:targetSubjectsOf")

	objects, _ := resolve(t, &f, EX + "S_objects")
	defer destroy_collector(&objects)
	expect_names(t, &objects, []string{EX + "o1", EX + "o2"}, "sh:targetObjectsOf")
}

// A shape that is also an rdfs:Class targets its own instances. The compiler
// stores the shape node itself as the class, so resolution has no special
// case — this asserts that shortcut actually works end to end.
@(test)
test_implicit_class_target :: proc(t: ^testing.T) {
	f: Split
	if !split_init(t, &f) {
		split_destroy(&f)
		return
	}
	defer split_destroy(&f)

	c, _ := resolve(t, &f, EX + "S_implicit")
	defer destroy_collector(&c)
	expect_names(t, &c, []string{EX + "inst"}, "implicit class target")
}

// Focus nodes are the *union* of a shape's targets: a node reached twice is
// validated once. This is `multipleTargets-001` in the suite.
@(test)
test_focus_nodes_are_a_set :: proc(t: ^testing.T) {
	f: Split
	if !split_init(t, &f) {
		split_destroy(&f)
		return
	}
	defer split_destroy(&f)

	c, _ := resolve(t, &f, EX + "S_multi")
	defer destroy_collector(&c)
	// ex:n1 is named directly *and* is an instance of ex:Super.
	expect_names(t, &c, []string{EX + "n1", EX + "n2", EX + "n3"}, "union of two targets")
}

// A class the data store has never seen has no instances, so the shape
// applies to nothing. Emptiness, not failure — the opposite of what an absent
// sh:class term will mean to a constraint.
@(test)
test_absent_target_class_resolves_to_nothing :: proc(t: ^testing.T) {
	f: Split
	if !split_init(t, &f) {
		split_destroy(&f)
		return
	}
	defer split_destroy(&f)

	c, _ := resolve(t, &f, EX + "S_absent")
	defer destroy_collector(&c)
	expect_names(t, &c, []string{}, "sh:targetClass naming an unknown class")
}

// rdfs:subClassOf cycles are ill-advised but not prevented, and a class
// hierarchy that loops would otherwise not terminate.
@(test)
test_subclass_closure_is_cycle_safe :: proc(t: ^testing.T) {
	f: Split
	if !split_init(t, &f) {
		split_destroy(&f)
		return
	}
	defer split_destroy(&f)

	c, _ := resolve(t, &f, EX + "S_cyclic")
	defer destroy_collector(&c)
	expect_names(t, &c, []string{EX + "looper"}, "sh:targetClass over a class cycle")
}

// Early exit reaches the store layer rather than being simulated above it: a
// visitor that stops makes resolve_targets return false, and the scan stops
// mid-iteration.
@(test)
test_visitor_can_stop_resolution :: proc(t: ^testing.T) {
	f: Split
	if !split_init(t, &f) {
		split_destroy(&f)
		return
	}
	defer split_destroy(&f)

	c, completed := resolve(t, &f, EX + "S_class", 1)
	defer destroy_collector(&c)
	testing.expect(t, !completed, "resolve_targets should report that it stopped early")
	testing.expect_value(t, len(c.names), 1)
}

// A shape with no targets is reached through sh:property from one that has
// them; its focus nodes are its parent's value nodes, resolved elsewhere.
@(test)
test_shape_without_targets_yields_nothing :: proc(t: ^testing.T) {
	db: Test_DB
	defer tdb_close(&db)
	if !tdb_open(t, &db) {
		return
	}

	source := `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:P a sh:PropertyShape ; sh:path ex:p .
	`
	if !tdb_load(t, &db, source) {
		return
	}
	se := tdb_session(&db)

	s: Shapes
	defer shapes_destroy(&s)
	testing.expect_value(t, compile(&s, se).kind, Error_Kind.None)

	b: Target_Bindings
	defer target_bindings_destroy(&b)
	target_bindings_init(&b, &s, se)

	c := Collector {
		se    = se,
		names = make([dynamic]string),
	}
	defer destroy_collector(&c)
	completed := resolve_targets(&s, &b, 0, se, collect, &c)
	testing.expect(t, completed, "a shape with no targets should complete")
	testing.expect_value(t, len(c.names), 0)
	testing.expect_value(t, len(s.roots), 0)
}
