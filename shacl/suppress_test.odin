package shacl

import "core:testing"

import rdf "rdf:rdf"
import store "store:store"

// Suppressed validation, tested where it lives.
//
// These are the tests SHACL-I-0002 called out as carrying unusual weight, and
// the reason was that **no suite entry reached this code until SHACL-T-0017**.
// The components that consume it were two tasks away, so until then the only
// thing standing between a subtly wrong mechanism and a stranger's report
// containing results for a shape they never targeted was this file.
//
// **Reviewed at SHACL-T-0017, as its acceptance criteria required, and kept.**
// The question was whether a hand-built model still earns its place once real
// consumers exist, and the risk named against it was drift: nothing here checks
// the model against what `compile` actually produces. Two things settled it.
//
// The drift risk is now covered from the other side — `shacl/memstore`'s
// `test_inner_results_do_not_reach_the_caller` and
// `test_an_inner_stop_does_not_truncate_the_outer_traversal` assert the same two
// properties through a compiled shapes graph and a real backend, so a model here
// that stopped resembling a compiled one would no longer be the only evidence.
// And what is left is genuinely unreachable from outside: the assertions below
// name `v.visit`, `v.visit_data`, `v.stopped`, `v.on_stack` and
// `Suppressed_Probe` directly. SHACL-A-0002 records the save/restore as **a
// discipline rather than a type** — a future field belonging to the caller's
// stream must be added to `node_conforms`'s three and nothing in the compiler
// will say so — and these are what would notice. A test that can only see
// results cannot.
//
// They are in package `shacl` rather than in a backend package for that reason:
// `node_conforms` takes an in-flight `Validation`, and a test in
// `shacl/memstore` can only reach the public `conforms_node`, which builds its
// own `Validation` and therefore cannot see the save/restore at all.
//
// The store is a fake: `Access` is a handful of procedure pointers, so a
// hand-built triple list satisfies it, and the model is built field by field
// rather than compiled. That is the point — no shapes graph has to exist for
// this mechanism to be wrong.

// ---- A fake data graph, and a model built by hand -------------------------

@(private = "file")
Fake :: struct {
	triples: [][3]store.Term_ID,
	terms:   []rdf.Term, // parallel to the IDs made by fake_id
}

@(private = "file")
fake_id :: proc(i: int) -> store.Term_ID {
	return store.make_id(.IRI, u64(i))
}

@(private = "file")
fake_scan :: proc(
	data: rawptr,
	subject, predicate, object: store.Term_ID,
	position: int,
	visit: proc(data: rawptr, id: store.Term_ID) -> bool,
	visit_data: rawptr,
) -> bool {
	f := cast(^Fake)data
	for tr in f.triples {
		if subject != store.WILDCARD && tr[0] != subject {
			continue
		}
		if predicate != store.WILDCARD && tr[1] != predicate {
			continue
		}
		if object != store.WILDCARD && tr[2] != object {
			continue
		}
		if !visit(visit_data, tr[position]) {
			return false
		}
	}
	return true
}

@(private = "file")
fake_step :: proc(
	data: rawptr,
	from: store.Term_ID,
	predicate: store.Term_ID,
	inverted: bool,
	out: ^[dynamic]store.Term_ID,
) {
	f := cast(^Fake)data
	for tr in f.triples {
		if tr[1] != predicate {
			continue
		}
		if inverted {
			if tr[2] == from {
				append(out, tr[0])
			}
		} else if tr[0] == from {
			append(out, tr[2])
		}
	}
}

@(private = "file")
fake_load :: proc(
	data: rawptr,
	id: store.Term_ID,
	allocator := context.allocator,
) -> (
	term: rdf.Term,
	owned: bool,
) {
	return nil, false
}

// The finder answers "not in this store" for everything, which is the honest
// answer for a graph with no dictionary: nothing here binds a term, and no test
// below depends on one.
@(private = "file")
fake_find :: proc(data: rawptr, term: rdf.Term) -> (id: store.Term_ID, found: bool) {
	return store.WILDCARD, false
}

@(private = "file")
fake_access :: proc(f: ^Fake) -> Access {
	return Access{scan = fake_scan, step = fake_step, load = fake_load, data = f, load_data = f}
}

// The model: three node shapes and one property shape, none of them targeting
// anything, because a suppressed run is asked about a node the caller names.
//
//	0  SHAPE_VIOLATES — sh:nodeKind sh:Literal, so any IRI focus node fails it
//	1  SHAPE_CONFORMS — sh:nodeKind sh:IRI, which the same focus node satisfies
//	2  SHAPE_NESTED   — no constraints of its own, one sh:property child (3)
//	3                 — a property shape on ex:p with sh:minCount 1
//
// Shape 3 is what makes shape 2 fail: the fake graph holds no ex:p triple, so
// the path reaches nothing and the cardinality violates. It is in the model to
// assert that a suppressed run descends into property shapes rather than
// checking only the named shape's own constraints.
@(private = "file")
SHAPE_VIOLATES :: 0
@(private = "file")
SHAPE_CONFORMS :: 1
@(private = "file")
SHAPE_NESTED :: 2

@(private = "file")
build_model :: proc(s: ^Shapes) {
	append(&s.paths, Path_Node{kind = .Predicate, predicate = rdf.IRI("http://example.org/p")})

	append(&s.constraints, Constraint{kind = .Node_Kind, node_kind = NODE_KIND_LITERAL})
	append(&s.constraints, Constraint{kind = .Node_Kind, node_kind = NODE_KIND_IRI})
	append(&s.constraints, Constraint{kind = .Min_Count, count = 1})

	append(
		&s.shapes,
		Shape {
			node = rdf.IRI("http://example.org/Violates"),
			kind = .Node,
			path = -1,
			constraints = Span{0, 1},
			severity = rdf.IRI(VIOLATION),
		},
	)
	append(
		&s.shapes,
		Shape {
			node = rdf.IRI("http://example.org/Conforms"),
			kind = .Node,
			path = -1,
			constraints = Span{1, 1},
			severity = rdf.IRI(VIOLATION),
		},
	)
	append(
		&s.shapes,
		Shape {
			node = rdf.IRI("http://example.org/Nested"),
			kind = .Node,
			path = -1,
			properties = Span{0, 1},
			severity = rdf.IRI(VIOLATION),
		},
	)
	append(
		&s.shapes,
		Shape {
			node = rdf.IRI("http://example.org/NestedProperty"),
			kind = .Property,
			path = 0,
			constraints = Span{2, 1},
			severity = rdf.IRI(VIOLATION),
		},
	)
	append(&s.shape_children, 3)
}

// Counting_Sink stands in for the caller's result stream. It never stops, so a
// stop observed after a suppressed run came from the suppressed run.
@(private = "file")
Counting_Sink :: struct {
	count: int,
}

@(private = "file")
counting_visitor :: proc(data: rawptr, result: Result) -> bool {
	sink := cast(^Counting_Sink)data
	sink.count += 1
	return true
}

// harness sets up a validation the way `validate` does, with an outer visitor
// installed, and hands it to the body. The focus node is a bound IRI.
@(private = "file")
with_validation :: proc(t: ^testing.T, body: proc(t: ^testing.T, v: ^Validation, sink: ^Counting_Sink, focus: Focus_Node)) {
	f := Fake{}
	s: Shapes
	defer shapes_destroy(&s)
	build_model(&s)

	b: Bindings
	bindings_init(&b, &s, fake_find, &f)
	defer bindings_destroy(&b)

	sink: Counting_Sink
	v := Validation {
		s          = &s,
		b          = &b,
		access     = fake_access(&f),
		visit      = counting_visitor,
		visit_data = &sink,
	}
	validation_init(&v)
	defer validation_destroy(&v)

	body(t, &v, &sink, Focus_Node{id = fake_id(1), bound = true})
}

// ---- The properties -------------------------------------------------------

// The answer itself, both ways round, and the nested case: a suppressed run
// validates the whole shape, property shapes included.
@(test)
test_suppressed_run_answers_conformance :: proc(t: ^testing.T) {
	with_validation(t, proc(t: ^testing.T, v: ^Validation, sink: ^Counting_Sink, focus: Focus_Node) {
		testing.expect(t, !node_conforms(v, SHAPE_VIOLATES, focus), "an IRI does not satisfy sh:nodeKind sh:Literal")
		testing.expect(t, node_conforms(v, SHAPE_CONFORMS, focus), "an IRI satisfies sh:nodeKind sh:IRI")
		testing.expect(
			t,
			!node_conforms(v, SHAPE_NESTED, focus),
			"a shape whose property shape violates does not conform — a suppressed run "+
			"must descend into sh:property, not check only the named shape",
		)
	})
}

// **Nothing leaks into the caller's report.** The three runs above produced
// results internally; the caller's visitor must not have seen one of them.
@(test)
test_a_suppressed_run_emits_nothing_to_the_caller :: proc(t: ^testing.T) {
	with_validation(t, proc(t: ^testing.T, v: ^Validation, sink: ^Counting_Sink, focus: Focus_Node) {
		node_conforms(v, SHAPE_VIOLATES, focus)
		node_conforms(v, SHAPE_NESTED, focus)
		testing.expectf(
			t,
			sink.count == 0,
			"%d results reached the caller's visitor from a suppressed run — this is the "+
			"failure mode the mechanism exists to prevent",
			sink.count,
		)
	})
}

// **The inner stop does not stop the outer.** The probe returns false at its
// first result, which is the same mechanism a caller uses to abandon a
// traversal; if that value survived, one inner violation would silently
// truncate the outer validation and the report would look complete.
@(test)
test_a_suppressed_run_restores_the_callers_stream :: proc(t: ^testing.T) {
	with_validation(t, proc(t: ^testing.T, v: ^Validation, sink: ^Counting_Sink, focus: Focus_Node) {
		// A run that certainly stops internally.
		testing.expect(t, !node_conforms(v, SHAPE_VIOLATES, focus), "fixture: this shape must violate")
		testing.expect(t, !v.stopped, "the inner stop leaked into the outer traversal")
		testing.expect(t, v.visit == counting_visitor, "the caller's visitor was not restored")
		testing.expect(t, v.visit_data == rawptr(sink), "the caller's visitor data was not restored")

		// And the outer stream still works afterwards: emit one result through
		// the restored visitor and see it arrive.
		emit_result(v, SHAPE_CONFORMS, focus, {}, false, .Node_Kind)
		testing.expect_value(t, sink.count, 1)
	})
}

// A caller that had already stopped stays stopped: the restore puts back what
// was there rather than clearing the flag.
@(test)
test_a_suppressed_run_does_not_resurrect_a_stopped_traversal :: proc(t: ^testing.T) {
	with_validation(t, proc(t: ^testing.T, v: ^Validation, sink: ^Counting_Sink, focus: Focus_Node) {
		v.stopped = true
		node_conforms(v, SHAPE_CONFORMS, focus)
		testing.expect(t, v.stopped, "a stopped traversal must stay stopped across a suppressed run")
	})
}

// The recursion set is shared, and a shape already open in the outer walk is
// recursion when a suppressed run re-enters it (SHACL-A-0002). Setting the bit
// by hand is exactly what `push_frame` does for the outer walk, which is what
// makes this the real case rather than a simulation of one.
//
// The alternative — a fresh recursion set per suppressed run — would not give a
// different answer here, it would give none: `ex:S sh:not [ sh:node ex:S ]`
// would nest forever.
@(test)
test_recursion_through_a_suppressed_run_is_a_failure :: proc(t: ^testing.T) {
	with_validation(t, proc(t: ^testing.T, v: ^Validation, sink: ^Counting_Sink, focus: Focus_Node) {
		v.on_stack[SHAPE_CONFORMS] = true // the outer walk is inside this shape
		conforms := node_conforms(v, SHAPE_CONFORMS, focus)
		testing.expect_value(t, v.failure, Failure.Recursive_Shape)
		testing.expect(
			t,
			!conforms || v.failure != .None,
			"a run that could not answer must not report a conformance it did not establish",
		)
	})
}

// Every on-stack bit a suppressed run set is cleared again, including on the
// abnormal exit. A leaked bit is a false recursion failure later in the same
// validation — the kind of bug that appears only under nesting and blames the
// wrong shape.
@(test)
test_a_suppressed_run_leaves_the_recursion_set_clean :: proc(t: ^testing.T) {
	with_validation(t, proc(t: ^testing.T, v: ^Validation, sink: ^Counting_Sink, focus: Focus_Node) {
		node_conforms(v, SHAPE_VIOLATES, focus) // stops internally at its first result
		node_conforms(v, SHAPE_NESTED, focus) // pushes a child frame before failing
		for on, i in v.on_stack {
			testing.expectf(t, !on, "shape %d is still marked on-stack after a suppressed run", i)
		}
		// The same shape is therefore askable again, which it would not be if a
		// bit had leaked.
		testing.expect(t, !node_conforms(v, SHAPE_NESTED, focus), "a leaked on-stack bit would make this a failure")
		testing.expect_value(t, v.failure, Failure.None)
	})
}

// Nesting: a suppressed run started from inside a suppressed run unwinds in the
// order it entered. Done by hand here — the components that nest naturally
// arrive in SHACL-T-0017 — and it is the property that makes the save/restore
// correct rather than merely working once.
@(test)
test_suppressed_runs_nest :: proc(t: ^testing.T) {
	with_validation(t, proc(t: ^testing.T, v: ^Validation, sink: ^Counting_Sink, focus: Focus_Node) {
		outer_probe: Suppressed_Probe
		saved_visit := v.visit
		saved_data := v.visit_data

		// Stand where a constraint check inside a suppressed run stands.
		v.visit = suppressed_visitor
		v.visit_data = &outer_probe
		v.stopped = false

		testing.expect(t, !node_conforms(v, SHAPE_VIOLATES, focus), "the inner run answers on its own")
		testing.expect(t, v.visit == suppressed_visitor, "the enclosing suppressed run's probe was not restored")
		testing.expect(t, v.visit_data == rawptr(&outer_probe), "the wrong probe was restored")
		testing.expect(t, !outer_probe.found, "the inner run's results reached the enclosing probe")

		v.visit = saved_visit
		v.visit_data = saved_data
		testing.expect_value(t, sink.count, 0)
	})
}
