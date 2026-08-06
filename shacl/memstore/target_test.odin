package shacl_memstore

import "core:slice"
import "core:strings"
import "core:testing"

import rdf "rdf:rdf"
import store "store:store"
import memstore "store:store/memstore"

import shacl ".."

// Target resolution.
//
// The fixture keeps the shapes graph and the data graph in **separate
// stores**, which is the arrangement SHACL-A-0001 decision 2 exists for — the
// model holds `rdf.Term` rather than `Term_ID` precisely so a model compiled
// from one store can be bound against another. It is also the only way to
// exercise an unbound focus node: when shapes and data share a document, as
// they do in the W3C suite, every `sh:targetNode` is necessarily in the
// dictionary.

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
	shapes_dict: memstore.Dictionary,
	shapes_data: memstore.Dataset,
	data_dict:   memstore.Dictionary,
	data_data:   memstore.Dataset,
	shapes:      shacl.Shapes,
	targets:     shacl.Target_Bindings,
}

@(private = "file")
split_init :: proc(t: ^testing.T, f: ^Split) -> bool {
	memstore.dictionary_init(&f.shapes_dict)
	memstore.dataset_init(&f.shapes_data)
	memstore.dictionary_init(&f.data_dict)
	memstore.dataset_init(&f.data_data)

	_, e1 := memstore.load_turtle(&f.shapes_dict, &f.shapes_data, transmute([]byte)string(SHAPES_GRAPH))
	if !testing.expectf(t, e1.message == "", "shapes graph: %s", e1.message) {
		return false
	}
	_, e2 := memstore.load_turtle(&f.data_dict, &f.data_data, transmute([]byte)string(DATA_GRAPH))
	if !testing.expectf(t, e2.message == "", "data graph: %s", e2.message) {
		return false
	}

	err := compile(&f.shapes, &f.shapes_dict, &f.shapes_data)
	if !testing.expectf(t, err.kind == .None, "compile: %s", shacl.error_message(err.kind)) {
		return false
	}
	// Bound against the *data* dictionary, not the one the model came from.
	bind_targets(&f.targets, &f.shapes, &f.data_dict)
	return true
}

@(private = "file")
split_destroy :: proc(f: ^Split) {
	shacl.target_bindings_destroy(&f.targets)
	shacl.shapes_destroy(&f.shapes)
	memstore.dataset_destroy(&f.data_data)
	memstore.dictionary_destroy(&f.data_dict)
	memstore.dataset_destroy(&f.shapes_data)
	memstore.dictionary_destroy(&f.shapes_dict)
}

@(private = "file")
Collector :: struct {
	dictionary: ^memstore.Dictionary,
	names:      [dynamic]string,
	unbound:    int,
	limit:      int, // stop after this many; 0 means no limit
}

@(private = "file")
collect :: proc(data: rawptr, focus: shacl.Focus_Node) -> bool {
	c := cast(^Collector)data
	term: rdf.Term
	if focus.bound {
		term = memstore.lookup_term(c.dictionary, focus.id)
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
		dictionary = &f.data_dict,
		names      = make([dynamic]string),
		limit      = limit,
	}
	if !testing.expectf(t, index >= 0, "%s: shape not compiled", shape_iri) {
		return c, true
	}
	completed := resolve_targets(&f.shapes, &f.targets, index, &f.data_data, collect, &c)
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

EX_T :: "http://example.org/"

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

	c, _ := resolve(t, &f, EX_T + "S_node")
	defer destroy_collector(&c)
	expect_names(t, &c, []string{EX_T + "absent_from_data", EX_T + "n1"}, "sh:targetNode")
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

	c, _ := resolve(t, &f, EX_T + "S_class")
	defer destroy_collector(&c)
	expect_names(t, &c, []string{EX_T + "n1", EX_T + "n2", EX_T + "n3"}, "sh:targetClass ex:Super")
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

	subjects, _ := resolve(t, &f, EX_T + "S_subjects")
	defer destroy_collector(&subjects)
	expect_names(t, &subjects, []string{EX_T + "s1", EX_T + "s2"}, "sh:targetSubjectsOf")

	objects, _ := resolve(t, &f, EX_T + "S_objects")
	defer destroy_collector(&objects)
	expect_names(t, &objects, []string{EX_T + "o1", EX_T + "o2"}, "sh:targetObjectsOf")
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

	c, _ := resolve(t, &f, EX_T + "S_implicit")
	defer destroy_collector(&c)
	expect_names(t, &c, []string{EX_T + "inst"}, "implicit class target")
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

	c, _ := resolve(t, &f, EX_T + "S_multi")
	defer destroy_collector(&c)
	// ex:n1 is named directly *and* is an instance of ex:Super.
	expect_names(t, &c, []string{EX_T + "n1", EX_T + "n2", EX_T + "n3"}, "union of two targets")
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

	c, _ := resolve(t, &f, EX_T + "S_absent")
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

	c, _ := resolve(t, &f, EX_T + "S_cyclic")
	defer destroy_collector(&c)
	expect_names(t, &c, []string{EX_T + "looper"}, "sh:targetClass over a class cycle")
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

	c, completed := resolve(t, &f, EX_T + "S_class", 1)
	defer destroy_collector(&c)
	testing.expect(t, !completed, "resolve_targets should report that it stopped early")
	testing.expect_value(t, len(c.names), 1)
}

// A shape with no targets is reached through sh:property from one that has
// them; its focus nodes are its parent's value nodes, resolved elsewhere.
@(test)
test_shape_without_targets_yields_nothing :: proc(t: ^testing.T) {
	dict: memstore.Dictionary
	memstore.dictionary_init(&dict)
	defer memstore.dictionary_destroy(&dict)
	ds: memstore.Dataset
	memstore.dataset_init(&ds)
	defer memstore.dataset_destroy(&ds)

	source := `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:P a sh:PropertyShape ; sh:path ex:p .
	`
	_, load_err := memstore.load_turtle(&dict, &ds, transmute([]byte)source)
	testing.expectf(t, load_err.message == "", "load: %s", load_err.message)

	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)
	testing.expect_value(t, compile(&s, &dict, &ds).kind, shacl.Error_Kind.None)

	b: shacl.Target_Bindings
	defer shacl.target_bindings_destroy(&b)
	bind_targets(&b, &s, &dict)

	c := Collector {
		dictionary = &dict,
		names      = make([dynamic]string),
	}
	defer destroy_collector(&c)
	completed := resolve_targets(&s, &b, 0, &ds, collect, &c)
	testing.expect(t, completed, "a shape with no targets should complete")
	testing.expect_value(t, len(c.names), 0)
	testing.expect_value(t, len(s.roots), 0)
	testing.expect_value(t, store.DEFAULT_GRAPH, store.DEFAULT_GRAPH)
}
