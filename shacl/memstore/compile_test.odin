package shacl_memstore

import "core:strings"
import "core:testing"

import rdf "rdf:rdf"
import store "store:store"
import memstore "store:store/memstore"

import shacl ".."

// Compilation is tested here rather than in the core package for the reason
// the core exists: `shacl` names no backend, so it cannot build a store to
// compile from. `shacl/kvstore` runs the same assertions against the
// persistent backend — the two files are meant to stay recognizably parallel.

PREFIX :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
@prefix ex: <http://example.org/> .
`

@(private = "file")
compile_source :: proc(t: ^testing.T, s: ^shacl.Shapes, source: string) -> bool {
	err, load_err := compile_turtle(s, transmute([]byte)source)
	if !testing.expectf(t, load_err.message == "", "shapes graph did not parse: %s", load_err.message) {
		return false
	}
	return testing.expectf(
		t,
		err.kind == .None,
		"compile failed: %s (shape %v, parameter %v)",
		shacl.error_message(err.kind),
		err.shape,
		err.parameter,
	)
}

@(private = "file")
find_shape :: proc(s: ^shacl.Shapes, iri: string) -> (shacl.Shape, bool) {
	for sh in s.shapes {
		if got, is_iri := sh.node.(rdf.IRI); is_iri && string(got) == iri {
			return sh, true
		}
	}
	return {}, false
}

@(test)
test_compile_node_and_property_shape :: proc(t: ^testing.T) {
	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)
	if !compile_source(
		t,
		&s,
		PREFIX +
		`
		ex:PersonShape a sh:NodeShape ;
			sh:targetClass ex:Person ;
			sh:property [
				sh:path ex:email ;
				sh:minCount 1 ;
				sh:maxCount 3 ;
				sh:datatype xsd:string ;
			] .
		`,
	) {
		return
	}

	person, found := find_shape(&s, "http://example.org/PersonShape")
	if !testing.expect(t, found, "ex:PersonShape was not compiled") {
		return
	}
	testing.expect_value(t, person.kind, shacl.Shape_Kind.Node)
	testing.expect_value(t, person.path, -1)
	testing.expect_value(t, person.severity, rdf.Term(rdf.IRI(shacl.VIOLATION)))
	testing.expect_value(t, person.deactivated, false)

	targets := shacl.shape_targets(&s, person)
	if testing.expect_value(t, len(targets), 1) {
		testing.expect_value(t, targets[0].kind, shacl.Target_Kind.Class)
		testing.expect_value(t, targets[0].term, rdf.Term(rdf.IRI("http://example.org/Person")))
	}

	// The shape carries a target, so it is a root.
	testing.expect_value(t, len(s.roots), 1)

	props := shacl.shape_properties(&s, person)
	if !testing.expect_value(t, len(props), 1) {
		return
	}
	prop := s.shapes[props[0]]
	testing.expect_value(t, prop.kind, shacl.Shape_Kind.Property)
	if !testing.expect(t, prop.path >= 0, "property shape has no compiled path") {
		return
	}
	path := s.paths[prop.path]
	testing.expect_value(t, path.kind, shacl.Path_Kind.Predicate)
	testing.expect_value(t, path.predicate, rdf.Term(rdf.IRI("http://example.org/email")))

	kinds: map[shacl.Constraint_Kind]int
	defer delete(kinds)
	for c in shacl.shape_constraints(&s, prop) {
		kinds[c.kind] += 1
	}
	testing.expect_value(t, kinds[.Min_Count], 1)
	testing.expect_value(t, kinds[.Max_Count], 1)
	testing.expect_value(t, kinds[.Datatype], 1)
	for c in shacl.shape_constraints(&s, prop) {
		#partial switch c.kind {
		case .Min_Count:
			testing.expect_value(t, c.count, 1)
		case .Max_Count:
			testing.expect_value(t, c.count, 3)
		case .Datatype:
			testing.expect_value(
				t,
				c.term,
				rdf.Term(rdf.IRI("http://www.w3.org/2001/XMLSchema#string")),
			)
		}
	}
}

// SHACL-A-0001 decision 3: the model owns its terms, so it outlives the store
// it was compiled from. compile_turtle destroys its store before returning, so
// every assertion below reads a model whose source is already gone — the
// property is exercised on every call, not only here.
@(test)
test_model_outlives_the_store :: proc(t: ^testing.T) {
	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)

	// Compile from a store this test owns, then destroy it explicitly before
	// touching the model, so the assertion is unambiguous.
	dictionary: memstore.Dictionary
	memstore.dictionary_init(&dictionary)
	dataset: memstore.Dataset
	memstore.dataset_init(&dataset)

	source := PREFIX + `ex:S a sh:NodeShape ; sh:targetNode ex:n ; sh:property [ sh:path ex:p ] .`
	_, load_err := memstore.load_turtle(&dictionary, &dataset, transmute([]byte)source)
	testing.expectf(t, load_err.message == "", "load failed: %s", load_err.message)

	err := compile(&s, &dictionary, &dataset)
	testing.expect_value(t, err.kind, shacl.Error_Kind.None)

	memstore.dataset_destroy(&dataset)
	memstore.dictionary_destroy(&dictionary)

	sh, found := find_shape(&s, "http://example.org/S")
	if !testing.expect(t, found, "shape not found after the store was destroyed") {
		return
	}
	targets := shacl.shape_targets(&s, sh)
	if testing.expect_value(t, len(targets), 1) {
		testing.expect_value(t, targets[0].term, rdf.Term(rdf.IRI("http://example.org/n")))
	}
	props := shacl.shape_properties(&s, sh)
	if testing.expect_value(t, len(props), 1) {
		testing.expect_value(
			t,
			s.paths[s.shapes[props[0]].path].predicate,
			rdf.Term(rdf.IRI("http://example.org/p")),
		)
	}
}

@(test)
test_compile_all_target_kinds :: proc(t: ^testing.T) {
	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)
	if !compile_source(
		t,
		&s,
		PREFIX +
		`
		ex:S a sh:NodeShape ;
			sh:targetNode ex:n ;
			sh:targetClass ex:C ;
			sh:targetSubjectsOf ex:p ;
			sh:targetObjectsOf ex:q .
		ex:Implicit a sh:NodeShape, rdfs:Class .
		`,
	) {
		return
	}

	sh, _ := find_shape(&s, "http://example.org/S")
	seen: map[shacl.Target_Kind]bool
	defer delete(seen)
	for tgt in shacl.shape_targets(&s, sh) {
		seen[tgt.kind] = true
	}
	testing.expect(t, seen[.Node], "sh:targetNode not compiled")
	testing.expect(t, seen[.Class], "sh:targetClass not compiled")
	testing.expect(t, seen[.Subjects_Of], "sh:targetSubjectsOf not compiled")
	testing.expect(t, seen[.Objects_Of], "sh:targetObjectsOf not compiled")

	// An implicit class target stores the shape node itself as the class, so
	// target resolution needs no special case.
	implicit, found := find_shape(&s, "http://example.org/Implicit")
	if !testing.expect(t, found, "implicit-class shape not compiled") {
		return
	}
	tgts := shacl.shape_targets(&s, implicit)
	if testing.expect_value(t, len(tgts), 1) {
		testing.expect_value(t, tgts[0].kind, shacl.Target_Kind.Implicit_Class)
		testing.expect_value(t, tgts[0].term, rdf.Term(rdf.IRI("http://example.org/Implicit")))
	}
}

@(test)
test_compile_path_forms :: proc(t: ^testing.T) {
	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)
	if !compile_source(
		t,
		&s,
		PREFIX +
		`
		ex:S a sh:NodeShape ; sh:targetNode ex:n ;
			sh:property [ sh:path [ sh:inversePath ex:child ] ] ;
			sh:property [ sh:path ( ex:a ex:b ex:c ) ] ;
			sh:property [ sh:path [ sh:alternativePath ( ex:a ex:b ) ] ] ;
			sh:property [ sh:path [ sh:zeroOrMorePath ex:r ] ] ;
			sh:property [ sh:path [ sh:oneOrMorePath ex:r ] ] ;
			sh:property [ sh:path [ sh:zeroOrOnePath ex:r ] ] ;
			sh:property [ sh:path [ sh:inversePath [ sh:zeroOrMorePath ex:deep ] ] ] .
		`,
	) {
		return
	}

	sh, _ := find_shape(&s, "http://example.org/S")
	props := shacl.shape_properties(&s, sh)
	if !testing.expect_value(t, len(props), 7) {
		return
	}

	kinds: map[shacl.Path_Kind]int
	defer delete(kinds)
	for pi in props {
		kinds[s.paths[s.shapes[pi].path].kind] += 1
	}
	testing.expect_value(t, kinds[.Inverse], 2)
	testing.expect_value(t, kinds[.Sequence], 1)
	testing.expect_value(t, kinds[.Alternative], 1)
	testing.expect_value(t, kinds[.Zero_Or_More], 1)
	testing.expect_value(t, kinds[.One_Or_More], 1)
	testing.expect_value(t, kinds[.Zero_Or_One], 1)

	// The sequence keeps its operands in document order, which matters:
	// ( ex:a ex:b ex:c ) is not the same path as ( ex:c ex:b ex:a ).
	for pi in props {
		node := s.paths[s.shapes[pi].path]
		if node.kind != .Sequence {
			continue
		}
		operands := shacl.path_operands(&s, node)
		if !testing.expect_value(t, len(operands), 3) {
			return
		}
		expected := [3]string{"http://example.org/a", "http://example.org/b", "http://example.org/c"}
		for want, i in expected {
			testing.expect_value(t, s.paths[operands[i]].predicate, rdf.Term(rdf.IRI(want)))
		}
	}

	// Nesting reaches through: inverse of zeroOrMore of a predicate.
	for pi in props {
		node := s.paths[s.shapes[pi].path]
		if node.kind != .Inverse {
			continue
		}
		operands := shacl.path_operands(&s, node)
		if !testing.expect_value(t, len(operands), 1) {
			return
		}
		inner := s.paths[operands[0]]
		if inner.kind == .Zero_Or_More {
			deep := shacl.path_operands(&s, inner)
			if testing.expect_value(t, len(deep), 1) {
				testing.expect_value(t, s.paths[deep[0]].predicate, rdf.Term(rdf.IRI("http://example.org/deep")))
			}
		}
	}
}

// A node carrying two path forms at once is ill-formed and §2.3.1 says nothing
// about it, but the suite does: `path-strange-001` writes a node that is both a
// sequence and an `sh:inversePath`, and its expected report carries
// `sh:resultPath ( ex:p ex:q )` — the sequence. So the precedence is measured
// rather than chosen, and this pins it, because the natural reading order (the
// named forms first, the bare list as a fallback) gets it backwards and would
// fail one entry of an otherwise green directory.
@(test)
test_sequence_wins_over_a_named_path_form :: proc(t: ^testing.T) {
	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)
	if !compile_source(
		t,
		&s,
		PREFIX +
		`
		@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
		ex:S a sh:PropertyShape ; sh:targetNode ex:n ;
			sh:path [ rdf:first ex:p ; rdf:rest ( ex:q ) ; sh:inversePath ex:p ] .
		`,
	) {
		return
	}

	sh, found := find_shape(&s, "http://example.org/S")
	if !testing.expect(t, found) {
		return
	}
	node := s.paths[sh.path]
	if !testing.expect_value(t, node.kind, shacl.Path_Kind.Sequence) {
		return
	}
	operands := shacl.path_operands(&s, node)
	if !testing.expect_value(t, len(operands), 2) {
		return
	}
	testing.expect_value(t, s.paths[operands[0]].predicate, rdf.Term(rdf.IRI("http://example.org/p")))
	testing.expect_value(t, s.paths[operands[1]].predicate, rdf.Term(rdf.IRI("http://example.org/q")))
}

@(test)
test_compile_constraint_components :: proc(t: ^testing.T) {
	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)
	if !compile_source(
		t,
		&s,
		PREFIX +
		`
		ex:S a sh:NodeShape ; sh:targetNode ex:n ;
			sh:class ex:C ;
			sh:nodeKind sh:IRI ;
			sh:hasValue ex:v ;
			sh:in ( ex:one ex:two "three" ) .
		`,
	) {
		return
	}

	sh, _ := find_shape(&s, "http://example.org/S")
	constraints := shacl.shape_constraints(&s, sh)
	testing.expect_value(t, len(constraints), 4)

	for c in constraints {
		#partial switch c.kind {
		case .Class:
			testing.expect_value(t, c.term, rdf.Term(rdf.IRI("http://example.org/C")))
		case .Node_Kind:
			testing.expect_value(t, c.node_kind, shacl.NODE_KIND_IRI)
		case .Has_Value:
			testing.expect_value(t, c.term, rdf.Term(rdf.IRI("http://example.org/v")))
		case .In:
			values := shacl.constraint_values(&s, c)
			if testing.expect_value(t, len(values), 3) {
				testing.expect_value(t, values[0], rdf.Term(rdf.IRI("http://example.org/one")))
				testing.expect_value(t, values[1], rdf.Term(rdf.IRI("http://example.org/two")))
				lit, is_lit := values[2].(rdf.Literal)
				if testing.expect(t, is_lit, "third sh:in member should be a literal") {
					testing.expect_value(t, lit.lexical, "three")
				}
			}
		}
	}
}

@(test)
test_compile_severity_message_deactivated :: proc(t: ^testing.T) {
	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)
	if !compile_source(
		t,
		&s,
		PREFIX +
		`
		ex:S a sh:NodeShape ; sh:targetNode ex:n ;
			sh:severity sh:Warning ;
			sh:deactivated true ;
			sh:message "in English"@en .
		ex:Plain a sh:NodeShape ; sh:targetNode ex:m .
		`,
	) {
		return
	}

	sh, _ := find_shape(&s, "http://example.org/S")
	testing.expect_value(t, sh.severity, rdf.Term(rdf.IRI(shacl.WARNING)))
	testing.expect_value(t, sh.deactivated, true)
	messages := shacl.shape_messages(&s, sh)
	if testing.expect_value(t, len(messages), 1) {
		testing.expect_value(t, messages[0].text, "in English")
		testing.expect_value(t, messages[0].language, "en")
	}

	// The defaults, asserted so a change to them is visible.
	plain, _ := find_shape(&s, "http://example.org/Plain")
	testing.expect_value(t, plain.severity, rdf.Term(rdf.IRI(shacl.VIOLATION)))
	testing.expect_value(t, plain.deactivated, false)
	testing.expect_value(t, len(shacl.shape_messages(&s, plain)), 0)
}

// Ill-formed shapes. Each asserts the kind *and* that the error names the
// shape and the parameter — the graph-shaped substitute for the family's
// line/column, which a shapes graph cannot carry.
@(test)
test_ill_formed_shapes :: proc(t: ^testing.T) {
	Case :: struct {
		name:   string,
		source: string,
		kind:   shacl.Error_Kind,
		param:  string,
	}
	cases := []Case {
		{
			"property shape with no path",
			`ex:S a sh:PropertyShape ; sh:minCount 1 .`,
			.Path_Missing,
			shacl.PATH,
		},
		{
			"two paths on one shape",
			`ex:S a sh:NodeShape ; sh:targetNode ex:n ; sh:property [ sh:path ex:a ; sh:path ex:b ] .`,
			.Path_Multiple,
			shacl.PATH,
		},
		{
			"unknown node kind",
			`ex:S a sh:NodeShape ; sh:targetNode ex:n ; sh:nodeKind ex:Nonsense .`,
			.Node_Kind_Unknown,
			shacl.NODE_KIND,
		},
		{
			"non-integer cardinality",
			`ex:S a sh:NodeShape ; sh:targetNode ex:n ; sh:property [ sh:path ex:p ; sh:minCount "many" ] .`,
			.Count_Not_Integer,
			shacl.MIN_COUNT,
		},
		{
			"negative cardinality",
			`ex:S a sh:NodeShape ; sh:targetNode ex:n ; sh:property [ sh:path ex:p ; sh:maxCount -1 ] .`,
			.Count_Negative,
			shacl.MAX_COUNT,
		},
		{
			// Not "unknown severity": any IRI is one. A *literal* is not.
			"non-IRI severity",
			`ex:S a sh:NodeShape ; sh:targetNode ex:n ; sh:severity "loud" .`,
			.Severity_Not_IRI,
			shacl.SEVERITY,
		},
		{
			"non-boolean sh:deactivated",
			`ex:S a sh:NodeShape ; sh:targetNode ex:n ; sh:deactivated "yes" .`,
			.Deactivated_Not_Boolean,
			shacl.DEACTIVATED,
		},
		{
			"alternative path with one member",
			`ex:S a sh:NodeShape ; sh:targetNode ex:n ;
			 sh:property [ sh:path [ sh:alternativePath ( ex:only ) ] ] .`,
			.Path_List_Too_Short,
			shacl.PATH,
		},
		{
			"sh:in that is not a list",
			`ex:S a sh:NodeShape ; sh:targetNode ex:n ; sh:in ex:notAList .`,
			.In_Not_A_List,
			shacl.IN,
		},
		{
			"literal where a shape was required",
			`ex:S a sh:NodeShape ; sh:targetNode ex:n ; sh:property "not a shape" .`,
			.Shape_Expected,
			shacl.PROPERTY,
		},
	}

	for c in cases {
		s: shacl.Shapes
		source := strings.concatenate({PREFIX, c.source})
		defer delete(source)
		err, load_err := compile_turtle(&s, transmute([]byte)source)
		testing.expectf(t, load_err.message == "", "%s: fixture did not parse: %s", c.name, load_err.message)
		testing.expectf(
			t,
			err.kind == c.kind,
			"%s: got %v (%s), expected %v",
			c.name,
			err.kind,
			shacl.error_message(err.kind),
			c.kind,
		)
		testing.expectf(t, err.shape != nil, "%s: error does not name the shape", c.name)
		if param, is_iri := err.parameter.(rdf.IRI); testing.expectf(
			t,
			is_iri,
			"%s: error does not name the parameter",
			c.name,
		) {
			testing.expectf(
				t,
				string(param) == c.param,
				"%s: error names parameter %q, expected %q",
				c.name,
				string(param),
				c.param,
			)
		}
		// The model is still returned on failure, because the error's terms
		// borrow from its table — so it still has to be destroyed.
		shacl.shapes_destroy(&s)
	}
}

// A shapes graph the compiler should read as empty rather than fail on: no
// SHACL vocabulary at all, so every vocabulary term is absent from the
// dictionary and every query is skipped rather than run.
@(test)
test_graph_with_no_shapes :: proc(t: ^testing.T) {
	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)
	if !compile_source(t, &s, PREFIX + `ex:a ex:p ex:b . ex:b ex:q "literal" .`) {
		return
	}
	testing.expect_value(t, len(s.shapes), 0)
	testing.expect_value(t, len(s.roots), 0)
}

// A cyclic RDF list must be reported, not looped on. Nothing in a shapes
// graph prevents one.
@(test)
test_cyclic_list_is_rejected :: proc(t: ^testing.T) {
	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)
	source :=
		PREFIX +
		`
		ex:S a sh:NodeShape ; sh:targetNode ex:n ; sh:in _:cell .
		_:cell <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> ex:x ;
		       <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> _:cell .
		`
	err, load_err := compile_turtle(&s, transmute([]byte)source)
	testing.expectf(t, load_err.message == "", "fixture did not parse: %s", load_err.message)
	testing.expect_value(t, err.kind, shacl.Error_Kind.In_Not_A_List)
}

// Compiling reads: it must never assign a Term_ID, or querying a persistent
// store would be a write. find_term is the non-interning lookup, and this
// asserts the dictionary is the same size afterwards.
@(test)
test_compilation_does_not_intern :: proc(t: ^testing.T) {
	dictionary: memstore.Dictionary
	memstore.dictionary_init(&dictionary)
	defer memstore.dictionary_destroy(&dictionary)
	dataset: memstore.Dataset
	memstore.dataset_init(&dataset)
	defer memstore.dataset_destroy(&dataset)

	source := PREFIX + `ex:S a sh:NodeShape ; sh:targetClass ex:C ; sh:property [ sh:path ex:p ] .`
	_, load_err := memstore.load_turtle(&dictionary, &dataset, transmute([]byte)source)
	testing.expectf(t, load_err.message == "", "load failed: %s", load_err.message)

	// A term the shapes graph never mentions. If compilation interned
	// anything, this ID would move.
	before, _ := memstore.find_term(&dictionary, rdf.IRI("http://example.org/S"))
	quads_before := memstore.count(&dataset)

	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)
	err := compile(&s, &dictionary, &dataset)
	testing.expect_value(t, err.kind, shacl.Error_Kind.None)

	after, still := memstore.find_term(&dictionary, rdf.IRI("http://example.org/S"))
	testing.expect(t, still, "the shape's own term went missing")
	testing.expect_value(t, after, before)
	testing.expect_value(t, memstore.count(&dataset), quads_before)
	testing.expect_value(t, store.id_kind(after), store.Term_Kind.IRI)
}

// §2.1.1: a node is a shape by being the value of a shape-expecting parameter.
// Six of them, three naming a shape directly and three naming a list whose
// members are shapes — and the list forms are where an implementation that
// enqueued the value instead of its members would compile the list head as a
// shape and never find the branches.
//
// None of the six validates anything yet (SHACL-T-0017, SHACL-T-0018). This is
// the discovery half, and it is deliberately first: every one of those
// components is unreachable until its operands are compiled shapes.
@(test)
test_shape_expecting_parameters_are_shapes :: proc(t: ^testing.T) {
	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)
	if !compile_source(
		t,
		&s,
		PREFIX +
		`
		ex:Root a sh:NodeShape ;
			sh:targetNode ex:n ;
			sh:node ex:ViaNode ;
			sh:not ex:ViaNot ;
			sh:qualifiedValueShape ex:ViaQualified ;
			sh:and ( ex:ViaAnd1 ex:ViaAnd2 ) ;
			sh:or ( ex:ViaOr ) ;
			sh:xone ( ex:ViaXone ) .
		`,
	) {
		return
	}

	for iri in ([]string {
			"http://example.org/ViaNode",
			"http://example.org/ViaNot",
			"http://example.org/ViaQualified",
			"http://example.org/ViaAnd1",
			"http://example.org/ViaAnd2",
			"http://example.org/ViaOr",
			"http://example.org/ViaXone",
		}) {
		_, found := find_shape(&s, iri)
		testing.expectf(t, found, "%s is the value of a shape-expecting parameter but was not compiled", iri)
	}

	// The root plus the seven it reaches, and nothing else: the list cells are
	// not shapes, and neither is anything the parameters do not name.
	testing.expect_value(t, len(s.shapes), 8)

	// Only the root carries a target, so only the root is a root. A discovered
	// shape validates when something references it, not on its own.
	testing.expect_value(t, len(s.roots), 1)
}

// A discovered shape is classified by its own sh:path, not by the parameter
// that found it: discovery guesses node shape, and a value carrying a path is
// a property shape regardless.
@(test)
test_a_discovered_shape_with_a_path_is_a_property_shape :: proc(t: ^testing.T) {
	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)
	if !compile_source(
		t,
		&s,
		PREFIX +
		`
		ex:Root a sh:NodeShape ; sh:targetNode ex:n ; sh:node ex:Child .
		ex:Child sh:path ex:p ; sh:minCount 1 .
		`,
	) {
		return
	}
	child, found := find_shape(&s, "http://example.org/Child")
	if !testing.expect(t, found, "ex:Child was not compiled") {
		return
	}
	testing.expect_value(t, child.kind, shacl.Shape_Kind.Property)
	testing.expect(t, child.path >= 0, "a property shape must have a compiled path")
}

// Shape references may form a cycle, and widening discovery is what makes that
// reachable: `sh:property` alone could only nest downwards through fresh blank
// nodes, while `ex:S sh:node ex:S` is a shapes graph anyone might write.
// Compilation must terminate and compile each shape once — the worklist's
// dedupe by Term_ID is what does it.
//
// This is compilation, not validation. A shape that reaches itself is still
// reported as Failure.Recursive_Shape when it is *validated* (§3.4); nothing
// here changes that.
@(test)
test_shape_reference_cycles_terminate :: proc(t: ^testing.T) {
	{
		s: shacl.Shapes
		defer shacl.shapes_destroy(&s)
		if !compile_source(
			t,
			&s,
			PREFIX + `ex:S a sh:NodeShape ; sh:targetNode ex:n ; sh:node ex:S .`,
		) {
			return
		}
		testing.expect_value(t, len(s.shapes), 1)
	}
	{
		// Mutual, and through two different parameters, so a dedupe that keyed
		// on the parameter rather than the node would loop.
		s: shacl.Shapes
		defer shacl.shapes_destroy(&s)
		if !compile_source(
			t,
			&s,
			PREFIX +
			`
			ex:A a sh:NodeShape ; sh:targetNode ex:n ; sh:node ex:B .
			ex:B sh:not ex:A ; sh:or ( ex:A ex:B ) .
			`,
		) {
			return
		}
		testing.expect_value(t, len(s.shapes), 2)
	}
}

// A literal cannot be a shape (§2.1.1), and the six parameters are held to the
// rule sh:property already was.
@(test)
test_a_literal_is_not_a_shape :: proc(t: ^testing.T) {
	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)
	source := PREFIX + `ex:S a sh:NodeShape ; sh:targetNode ex:n ; sh:node "not a shape" .`
	err, load_err := compile_turtle(&s, transmute([]byte)source)
	testing.expectf(t, load_err.message == "", "fixture did not parse: %s", load_err.message)
	testing.expect_value(t, err.kind, shacl.Error_Kind.Shape_Expected)
}

// The ignored-parameter record: what an incomplete engine says about itself.
//
// Three groups have to come apart correctly, and getting any of them wrong
// makes the record worse than useless — a record that cried wolf would be
// switched off, and one that stayed silent would certify an engine that did
// nothing.
@(test)
test_ignored_parameters_are_recorded :: proc(t: ^testing.T) {
	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)
	if !compile_source(
		t,
		&s,
		PREFIX +
		`
		ex:S a sh:NodeShape ;
			sh:targetNode ex:n ;
			sh:name "a name" ;
			sh:description "inert" ;
			sh:order 1 ;
			rdfs:label "not a sh: predicate at all" ;
			sh:minCount 1 ;
			sh:minInclusive 2 ;
			sh:pattern "^a" ;
			sh:property [ sh:path ex:p ; sh:maxLength 5 ; sh:minInclusive 2 ] .
		`,
	) {
		return
	}

	ignored := shacl.shapes_ignored(&s)
	got: map[string]bool
	defer delete(got)
	for term in ignored {
		iri, is_iri := term.(rdf.IRI)
		if testing.expect(t, is_iri, "an ignored parameter must be an IRI") {
			got[string(iri)] = true
		}
	}

	// Unimplemented components are recorded, from every shape and not only the
	// root — sh:maxLength is on the property shape.
	for iri in ([]string{shacl.NS + "minInclusive", shacl.NS + "pattern", shacl.NS + "maxLength"}) {
		testing.expectf(t, got[iri], "%s is not implemented and should have been recorded", iri)
	}

	// Implemented components and the spec's inert annotations are not, nor is a
	// predicate outside the SHACL namespace.
	for iri in ([]string {
			shacl.NS + "minCount",
			shacl.NS + "targetNode",
			shacl.NS + "property",
			shacl.NS + "path",
			shacl.NAME,
			shacl.DESCRIPTION,
			shacl.ORDER,
			"http://www.w3.org/2000/01/rdf-schema#label",
		}) {
		testing.expectf(t, !got[iri], "%s should not be recorded as ignored", iri)
	}

	// sh:minInclusive appears on two shapes and is recorded once: the record is
	// a property of the compile, not a list of occurrences.
	testing.expect_value(t, len(ignored), len(got))
	testing.expect_value(t, len(got), 3)
}

// A shape-expecting parameter is recognised by discovery and still recorded as
// unimplemented, because nothing validates against it yet. This is the case the
// record exists for: the engine understood the graph well enough to compile
// six more shapes and would still have reported `sh:conforms true` for a node
// violating every one of them.
@(test)
test_shape_expecting_parameters_are_recorded_as_unimplemented :: proc(t: ^testing.T) {
	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)
	if !compile_source(
		t,
		&s,
		PREFIX + `ex:S a sh:NodeShape ; sh:targetNode ex:n ; sh:node ex:C . ex:C sh:minCount 1 .`,
	) {
		return
	}
	ignored := shacl.shapes_ignored(&s)
	if !testing.expect_value(t, len(ignored), 1) {
		return
	}
	testing.expect_value(t, ignored[0], rdf.Term(rdf.IRI(shacl.NODE)))
}

// A shapes graph using nothing unimplemented records nothing. Stated as its own
// test because "empty" is what every enabled suite directory has to produce,
// and an always-non-empty record would have been caught here first.
@(test)
test_a_fully_implemented_shapes_graph_records_nothing :: proc(t: ^testing.T) {
	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)
	if !compile_source(
		t,
		&s,
		PREFIX +
		`
		ex:S a sh:NodeShape ;
			sh:targetClass ex:C ;
			sh:severity sh:Warning ;
			sh:message "m" ;
			sh:property [ sh:path ex:p ; sh:minCount 1 ; sh:maxCount 2 ; sh:datatype xsd:string ] ;
			sh:nodeKind sh:IRI ;
			sh:in ( ex:a ex:b ) ;
			sh:hasValue ex:a ;
			sh:class ex:C .
		`,
	) {
		return
	}
	testing.expect_value(t, len(shacl.shapes_ignored(&s)), 0)
}
