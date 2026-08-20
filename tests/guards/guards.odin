// Package guards holds allocation-guard tests: tracking-allocator assertions
// that the validator honours the memory contract it publishes.
//
// The pattern comes from odin-rdf-parser's tests/guards by way of
// odin-rdf-sparql's. What it guards here is different, though, and worth
// stating: odin-rdf-parser's guards assert that parsing allocates *nothing* in
// steady state, because its terms borrow the caller's buffer (RDF-A-0001).
// A shapes model deliberately does the opposite — it interns and owns every
// term so it can outlive the store it was compiled from (SHACL-A-0001
// decision 3). So the promise under test is not "no allocation" but "every
// allocation is owned and returned": compile then destroy must be net zero,
// and must free exactly what it allocated.
//
// The store under everything here is odin-rdf-record over the memory seam
// (SHACL-I-0004), opened with the tracked allocator — so the guards cover the
// engine *and* the store lifecycle it drives: a stranded byte in either fails
// the same assertion.
package guards

import "core:log"
import "core:mem"
import "core:testing"

import "rdf:rdf"
import "record:record"
import "record:record/ingest"

import "../../shacl"

// A cyclic graph with every path form over it, for the evaluation guard.
PATHS :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix ex: <http://example.org/> .
ex:a ex:p ex:b . ex:b ex:p ex:c . ex:c ex:p ex:a . ex:b ex:q ex:y .
ex:P1 a sh:PropertyShape ; sh:path ex:p .
ex:P2 a sh:PropertyShape ; sh:path [ sh:inversePath ex:p ] .
ex:P3 a sh:PropertyShape ; sh:path ( ex:p ex:q ) .
ex:P4 a sh:PropertyShape ; sh:path [ sh:alternativePath ( ex:p ex:q ) ] .
ex:P5 a sh:PropertyShape ; sh:path [ sh:zeroOrMorePath ex:p ] .
ex:P6 a sh:PropertyShape ; sh:path [ sh:oneOrMorePath ex:p ] .
ex:P7 a sh:PropertyShape ; sh:path [ sh:zeroOrOnePath ex:p ] .
`

// A class hierarchy with a cycle in it, plus every target form, for the
// resolution guard. The cycle makes the closure allocate more than one round.
TARGETS :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix ex: <http://example.org/> .
ex:Sub rdfs:subClassOf ex:Super . ex:SubSub rdfs:subClassOf ex:Sub .
ex:A rdfs:subClassOf ex:B . ex:B rdfs:subClassOf ex:A .
ex:n1 a ex:Super . ex:n2 a ex:SubSub . ex:n3 a ex:B .
ex:s1 ex:knows ex:o1 .
ex:T1 a sh:NodeShape ; sh:targetClass ex:Super .
ex:T2 a sh:NodeShape ; sh:targetClass ex:A .
ex:T3 a sh:NodeShape ; sh:targetSubjectsOf ex:knows ; sh:targetObjectsOf ex:knows .
ex:T4 a sh:NodeShape ; sh:targetNode ex:n1, ex:never_mentioned_elsewhere .
ex:T5 a sh:NodeShape, rdfs:Class .
`

SHAPES :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
@prefix ex: <http://example.org/> .

ex:PersonShape a sh:NodeShape, rdfs:Class ;
	sh:targetClass ex:Person ;
	sh:targetSubjectsOf ex:knows ;
	sh:severity sh:Warning ;
	sh:message "a message"@en ;
	sh:message "eine Nachricht"@de ;
	sh:property [
		sh:path [ sh:inversePath ex:child ] ;
		sh:minCount 1 ;
		sh:maxCount 3 ;
		sh:datatype xsd:string ;
	] ;
	sh:property [
		sh:path ( ex:a [ sh:alternativePath ( ex:b ex:c ) ] ex:d ) ;
		sh:class ex:C ;
		sh:nodeKind sh:BlankNodeOrIRI ;
		sh:hasValue ex:v ;
		sh:in ( ex:one ex:two "three"@en ) ;
	] ;
	# The qualified family, on a property shape because that is the only place
	# it is well-formed. It allocates a suppressed run per value node and counts
	# the answers, and sh:qualifiedValueShapesDisjoint walks the sibling shapes
	# besides — the most intricate thing in SHACL Core, and so the one most
	# worth watching here.
	sh:property [
		sh:path ex:q ;
		sh:qualifiedValueShape ex:Nested ;
		sh:qualifiedMinCount 1 ;
		sh:qualifiedMaxCount 2 ;
		sh:qualifiedValueShapesDisjoint true ;
	] ;
	# SHACL-T-0010's two additions, both of which allocate: the shape-expecting
	# parameters discover further shapes (through a list and directly), and the
	# ignored-parameter record interns a term per unimplemented parameter it
	# finds. sh:name is inert and sh:sparql is unimplemented — SHACL-SPARQL, a
	# later phase — so the record has to distinguish them without leaking
	# either.
	#
	# All six shape-expecting parameters appear here, which is the point of the
	# fixture rather than a flourish: each one allocates a nested suppressed
	# walk per value node (SHACL-A-0002), and six of them nesting through each
	# other is the easiest place in the engine to strand memory.
	sh:node ex:Nested ;
	sh:and ( ex:Nested ex:AlsoNested ) ;
	sh:or ( ex:Nested ex:AlsoNested ) ;
	sh:xone ( ex:Nested ex:AlsoNested ) ;
	sh:name "an annotation" ;
	sh:sparql "not implemented, and not going to be here" .

ex:Nested sh:path ex:p ; sh:minCount 1 ; sh:maxLength 5 .
ex:AlsoNested sh:not ex:Nested .
`

// Guard_DB is one record store over the memory seam, opened with the guard's
// tracked allocator so its whole lifecycle is under the same assertion.
// Never copied after open: the writer points at the Mem_FS inside.
@(private)
Guard_DB :: struct {
	fs:       record.Mem_FS,
	st:       record.Store,
	snap:     record.Snapshot,
	has_snap: bool,
	ok:       bool,
}

@(private)
gdb_open :: proc(db: ^Guard_DB, allocator: mem.Allocator) {
	_, err, _, _ := record.store_open(&db.st, "guards", record.mem_file_ops(&db.fs), allocator = allocator)
	db.ok = err == .None
}

@(private)
gdb_load :: proc(db: ^Guard_DB, source: string, allocator: mem.Allocator) {
	if !db.ok {
		return
	}
	ops, ierr := ingest.turtle(transmute([]byte)source, nil, allocator, blank_prefix = "g_")
	if ierr.kind != .None {
		return
	}
	defer ingest.ops_destroy(ops, allocator)
	_, _, _ = record.apply(&db.st, {ops = ops}, allocator)
}

@(private)
gdb_session :: proc(db: ^Guard_DB) -> shacl.Session {
	if !db.has_snap {
		snap, serr := record.store_latest(&db.st)
		assert(serr == .None)
		db.snap = snap
		db.has_snap = true
	}
	se: shacl.Session
	shacl.session_init(&se, db.snap)
	return se
}

@(private)
gdb_close :: proc(db: ^Guard_DB) {
	if db.has_snap {
		record.snapshot_release(&db.snap)
		db.has_snap = false
	}
	if db.ok {
		record.store_close(&db.st)
		db.ok = false
	}
	record.mem_fs_destroy(&db.fs)
}

// gdb_compile is open + load + compile in one call — what compile_turtle was.
@(private)
gdb_compile :: proc(db: ^Guard_DB, s: ^shacl.Shapes, source: string, allocator: mem.Allocator) -> shacl.Error {
	gdb_open(db, allocator)
	gdb_load(db, source, allocator)
	if !db.ok {
		return shacl.Error{}
	}
	return shacl.compile(s, gdb_session(db), allocator)
}

// track runs body under a tracking allocator and reports what it leaked.
@(private)
track :: proc(t: ^testing.T, name: string, body: proc(allocator: mem.Allocator)) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)

	body(mem.tracking_allocator(&tracker))

	testing.expectf(
		t,
		len(tracker.allocation_map) == 0,
		"%s: %d allocations were not freed",
		name,
		len(tracker.allocation_map),
	)
	for _, entry in tracker.allocation_map {
		log.errorf("%s: leaked %d bytes at %v", name, entry.size, entry.location)
	}
	testing.expectf(
		t,
		len(tracker.bad_free_array) == 0,
		"%s: %d bad frees",
		name,
		len(tracker.bad_free_array),
	)
	for entry in tracker.bad_free_array {
		log.errorf("%s: bad free of %v at %v", name, entry.memory, entry.location)
	}
}

// A compiled model must return every byte it took. This is the guard that
// makes the ownership decision safe rather than merely convenient: the model
// clones terms precisely so it can outlive its store, and a clone that is
// never freed is a leak per compile.
@(test)
test_compile_then_destroy_is_net_zero :: proc(t: ^testing.T) {
	track(t, "compile/destroy", proc(allocator: mem.Allocator) {
		context.allocator = allocator
		s: shacl.Shapes
		db: Guard_DB
		defer gdb_close(&db)
		_ = gdb_compile(&db, &s, SHAPES, allocator)
		shacl.shapes_destroy(&s)
	})
}

// A failed compile still returns a model, because the error's terms borrow
// from its table — so the failure path has to free like the success path. It
// is also the path least likely to be exercised by ordinary use, which is
// exactly why it gets a guard.
@(test)
test_failed_compile_then_destroy_is_net_zero :: proc(t: ^testing.T) {
	track(t, "failed compile/destroy", proc(allocator: mem.Allocator) {
		context.allocator = allocator
		BAD :: `
		@prefix sh: <http://www.w3.org/ns/shacl#> .
		@prefix ex: <http://example.org/> .
		ex:S a sh:NodeShape ; sh:targetNode ex:n ;
			sh:property [ sh:path ex:p ; sh:minCount "not a number" ] .
		`
		s: shacl.Shapes
		db: Guard_DB
		defer gdb_close(&db)
		_ = gdb_compile(&db, &s, BAD, allocator)
		shacl.shapes_destroy(&s)
	})
}

// Path evaluation is the innermost thing validation does — once per focus
// node per property shape — so what it must not do is strand memory per call.
// The cyclic fixture matters here beyond correctness: a reachability walk that
// leaked its frontier would leak once per cycle traversal rather than once per
// call, which is the difference between a slow leak and a fast one.
@(test)
test_path_evaluation_is_net_zero :: proc(t: ^testing.T) {
	track(t, "path evaluation", proc(allocator: mem.Allocator) {
		context.allocator = allocator

		db: Guard_DB
		defer gdb_close(&db)
		s: shacl.Shapes
		defer shacl.shapes_destroy(&s)
		_ = gdb_compile(&db, &s, PATHS, allocator)
		se := gdb_session(&db)

		b: shacl.Path_Bindings
		defer shacl.path_bindings_destroy(&b)
		shacl.path_bindings_init(&b, &s, se, allocator)

		focus, _ := shacl.session_resolve(se, rdf.IRI("http://example.org/a"))
		for sh in s.shapes {
			if sh.path < 0 {
				continue
			}
			for _ in 0 ..< 4 {
				nodes := shacl.value_nodes(&s, &b, sh.path, focus, se, allocator)
				delete(nodes)
			}
		}
	})
}

// Target resolution keeps a set of the focus nodes it has yielded, which is
// unavoidable — §2.1.3 makes them a union — but it must not keep anything
// else. The subclass closure in particular allocates a frontier per round.
@(test)
test_target_resolution_is_net_zero :: proc(t: ^testing.T) {
	track(t, "target resolution", proc(allocator: mem.Allocator) {
		context.allocator = allocator

		db: Guard_DB
		defer gdb_close(&db)
		s: shacl.Shapes
		defer shacl.shapes_destroy(&s)
		_ = gdb_compile(&db, &s, TARGETS, allocator)
		se := gdb_session(&db)

		b: shacl.Target_Bindings
		defer shacl.target_bindings_destroy(&b)
		shacl.target_bindings_init(&b, &s, se, allocator)

		count := 0
		visit :: proc(data: rawptr, focus: shacl.Focus_Node) -> bool {
			n := cast(^int)data
			n^ += 1
			return true
		}
		for _, i in s.shapes {
			for _ in 0 ..< 4 {
				shacl.resolve_targets(&s, &b, i, se, visit, &count, allocator)
			}
		}
	})
}

// A report is the one thing in the engine that is *supposed* to grow with the
// violation count — it is a graph. What it must not do is strand any of it.
@(test)
test_report_build_then_destroy_is_net_zero :: proc(t: ^testing.T) {
	track(t, "report build/destroy", proc(allocator: mem.Allocator) {
		context.allocator = allocator

		db: Guard_DB
		defer gdb_close(&db)
		s: shacl.Shapes
		defer shacl.shapes_destroy(&s)
		_ = gdb_compile(&db, &s, PATHS, allocator)
		se := gdb_session(&db)

		focus, _ := shacl.session_resolve(se, rdf.IRI("http://example.org/a"))

		r: shacl.Report
		shacl.report_init(&r, allocator)
		defer shacl.report_destroy(&r)
		// Every path form, so the RDF-list and blank-node structures the
		// serialiser builds are all exercised.
		for sh, i in s.shapes {
			for _ in 0 ..< 8 {
				shacl.report_add(
					&r,
					&s,
					shacl.Result {
						focus = shacl.Node_Ref{id = focus, bound = true},
						path = sh.path,
						shape = i,
						component = .Min_Count,
						severity = rdf.IRI(shacl.VIOLATION),
					},
					se,
				)
			}
		}
		shacl.report_finish(&r)
	})
}

// The conformance-only consumer is the case where memory really must stay
// flat: it answers a boolean, so no number of results may cost it anything.
@(test)
test_conformance_consumer_allocates_nothing :: proc(t: ^testing.T) {
	track(t, "conformance consumer", proc(allocator: mem.Allocator) {
		context.allocator = allocator
		c: shacl.Conformance
		shacl.conformance_init(&c)
		result := shacl.Result {
			severity = rdf.IRI(shacl.WARNING),
		}
		for _ in 0 ..< 10_000 {
			if !shacl.conformance_visitor(&c, result) {
				break
			}
		}
	})
}

// A shapes graph exercising every path form, every target form, and all seven
// constraint components at once, over data with a cycle in it — the widest
// single validation the spine can be asked to run.
VALIDATION_SHAPES :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
@prefix ex: <http://example.org/> .

ex:S a sh:NodeShape ; sh:targetClass ex:Super ; sh:targetSubjectsOf ex:p ;
	sh:targetNode ex:a, ex:never_mentioned_anywhere ;
	sh:class ex:Super ;
	sh:property [ sh:path ex:p ; sh:minCount 2 ; sh:maxCount 1 ] ;
	sh:property [ sh:path [ sh:inversePath ex:p ] ; sh:nodeKind sh:Literal ] ;
	sh:property [ sh:path ( ex:p ex:q ) ; sh:datatype xsd:string ] ;
	sh:property [ sh:path [ sh:alternativePath ( ex:p ex:q ) ] ; sh:hasValue ex:never ] ;
	sh:property [ sh:path [ sh:zeroOrMorePath ex:p ] ; sh:class ex:Missing ] ;
	sh:property [ sh:path [ sh:oneOrMorePath ex:p ] ; sh:in ( ex:a ) ] ;
	sh:property [ sh:path [ sh:zeroOrOnePath ex:p ] ; sh:minCount 9 ] ;
	# All six shape-expecting parameters, over data that reaches them, because
	# each one runs a suppressed sub-walk per node it is asked about
	# (SHACL-A-0002) and that is a whole allocation path this fixture did not
	# cover until SHACL-T-0019. The other guard on suppression asks
	# conforms_node directly, which is the top-level entry point; this is the
	# nested case, where a sub-walk unwinds inside a walk that carries on.
	#
	# Deliberately no cycle among these: a shape reaching itself ends the
	# traversal in Failure.Recursive_Shape, which would quietly shrink what this
	# guard covers. That path has its own test.
	sh:node ex:Inner ;
	sh:not ex:Unsatisfiable ;
	sh:and ( ex:Inner ex:Other ) ;
	sh:or ( ex:Inner ex:Other ) ;
	sh:xone ( ex:Inner ex:Other ) ;
	# Two sibling qualified shapes rather than one, so
	# sh:qualifiedValueShapesDisjoint has a sibling to walk — with one, the
	# disjointness test allocates nothing and the guard covers the cheap half.
	sh:property [
		sh:path ex:p ;
		sh:qualifiedValueShape ex:Inner ;
		sh:qualifiedMinCount 1 ;
		sh:qualifiedValueShapesDisjoint true ;
	] ;
	sh:property [
		sh:path ex:p ;
		sh:qualifiedValueShape ex:Other ;
		sh:qualifiedMaxCount 1 ;
		sh:qualifiedValueShapesDisjoint true ;
	] .

ex:Inner a sh:NodeShape ; sh:property [ sh:path ex:p ; sh:minCount 1 ; sh:nodeKind sh:IRI ] .
ex:Other a sh:NodeShape ; sh:property [ sh:path ex:q ; sh:datatype xsd:string ] .
ex:Unsatisfiable a sh:NodeShape ; sh:property [ sh:path ex:p ; sh:minCount 99 ] .
`

VALIDATION_DATA :: `
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix ex: <http://example.org/> .
ex:Sub rdfs:subClassOf ex:Super .
ex:a a ex:Sub ; ex:p ex:b . ex:b ex:p ex:c ; ex:q "s" . ex:c ex:p ex:a .
`

// Validation is what the engine is for, and the allocations it makes are the
// ones that repeat: a value-node set per focus node per property shape, a
// frontier per reachability round, a stack frame per shape entered. Each is
// bounded and each must be returned, or a long-running validator leaks in
// proportion to the data rather than to the shapes.
//
// The cyclic data matters for the same reason it does in the path guard: a walk
// that leaked its frontier would leak once per traversal of the cycle.
@(test)
test_validation_is_net_zero :: proc(t: ^testing.T) {
	track(t, "validation", proc(allocator: mem.Allocator) {
		context.allocator = allocator

		s: shacl.Shapes
		defer shacl.shapes_destroy(&s)
		shapes_db: Guard_DB
		defer gdb_close(&shapes_db)
		_ = gdb_compile(&shapes_db, &s, VALIDATION_SHAPES, allocator)

		db: Guard_DB
		defer gdb_close(&db)
		gdb_open(&db, allocator)
		gdb_load(&db, VALIDATION_DATA, allocator)
		se := gdb_session(&db)

		b: shacl.Bindings
		shacl.bindings_init(&b, &s, se, allocator)
		defer shacl.bindings_destroy(&b)

		count := 0
		visit :: proc(data: rawptr, result: shacl.Result) -> bool {
			n := cast(^int)data
			n^ += 1
			return true
		}
		// Repeated, because a per-validation leak and a per-result leak look the
		// same after one run.
		for _ in 0 ..< 4 {
			_ = shacl.validate(&s, &b, se, visit, &count, allocator)
		}
	})
}

// The guard above covers whatever the walk reached, and says nothing about how
// much that was — `track` hands its body an allocator and no `testing.T`, so a
// validation that ended two shapes in has no way to complain. That is a real
// hazard rather than a hypothetical one: `Failure.Recursive_Shape` abandons the
// traversal, and a fixture edit that accidentally made a shape reach itself
// would shrink the guard's coverage to nothing while leaving it green.
//
// So the same fixture is walked once more, outside the tracking allocator, and
// the two things that would make the guard vacuous are asserted: the walk ran
// to completion, and it produced results. Cheap, and it is the difference
// between "nothing leaked" and "nothing leaked, over the shapes we think it
// covered".
@(test)
test_the_validation_guard_fixture_is_fully_walked :: proc(t: ^testing.T) {
	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)
	shapes_db: Guard_DB
	defer gdb_close(&shapes_db)
	err := gdb_compile(&shapes_db, &s, VALIDATION_SHAPES, context.allocator)
	if !testing.expectf(t, err.kind == .None, "compile: %s", shacl.error_message(err.kind)) {
		return
	}

	db: Guard_DB
	defer gdb_close(&db)
	gdb_open(&db, context.allocator)
	if !testing.expect(t, db.ok, "data store failed to open") {
		return
	}
	gdb_load(&db, VALIDATION_DATA, context.allocator)
	se := gdb_session(&db)

	b: shacl.Bindings
	shacl.bindings_init(&b, &s, se)
	defer shacl.bindings_destroy(&b)

	count := 0
	visit :: proc(data: rawptr, result: shacl.Result) -> bool {
		n := cast(^int)data
		n^ += 1
		return true
	}
	failure := shacl.validate(&s, &b, se, visit, &count)
	testing.expectf(
		t,
		failure == .None,
		"the validation guard's fixture no longer completes (%s) — whatever it "+
		"stopped at is no longer guarded",
		shacl.failure_message(failure),
	)
	testing.expect(t, count > 0, "the validation guard's fixture produced no results at all")
}

// The abnormal exits have to free like the normal one, and they are the paths
// ordinary use never takes: a visitor that stops leaves frames on the stack,
// and a recursive shape abandons the walk mid-flight. Both unwind by hand
// rather than by returning, which is exactly the code most likely to strand a
// value-node set.
@(test)
test_early_exit_and_recursion_unwind_cleanly :: proc(t: ^testing.T) {
	track(t, "abnormal unwind", proc(allocator: mem.Allocator) {
		context.allocator = allocator

		RECURSIVE :: `
		@prefix sh: <http://www.w3.org/ns/shacl#> .
		@prefix ex: <http://example.org/> .
		ex:R a sh:PropertyShape ; sh:targetNode ex:a ; sh:path ex:p ; sh:property ex:R .
		`
		// The first source stops at the first result; the second fails on
		// recursion. Both leave the walk mid-flight.
		sources := [2]string{VALIDATION_SHAPES, RECURSIVE}
		for source in sources {
			s: shacl.Shapes
			defer shacl.shapes_destroy(&s)
			shapes_db: Guard_DB
			defer gdb_close(&shapes_db)
			_ = gdb_compile(&shapes_db, &s, source, allocator)

			db: Guard_DB
			defer gdb_close(&db)
			gdb_open(&db, allocator)
			gdb_load(&db, VALIDATION_DATA, allocator)
			se := gdb_session(&db)

			b: shacl.Bindings
			shacl.bindings_init(&b, &s, se, allocator)
			defer shacl.bindings_destroy(&b)

			stop :: proc(data: rawptr, result: shacl.Result) -> bool {
				return false
			}
			for _ in 0 ..< 4 {
				_ = shacl.validate(&s, &b, se, stop, nil, allocator)
			}
		}
	})
}

// The conformance answer must cost nothing beyond the traversal: it is the
// consumer that exists for the deployment shape — ~200 processes per machine,
// each answering "does this conform?" — and a per-result allocation there is a
// per-result allocation everywhere.
@(test)
test_conformance_validation_is_net_zero :: proc(t: ^testing.T) {
	track(t, "conformance validation", proc(allocator: mem.Allocator) {
		context.allocator = allocator

		s: shacl.Shapes
		defer shacl.shapes_destroy(&s)
		shapes_db: Guard_DB
		defer gdb_close(&shapes_db)
		_ = gdb_compile(&shapes_db, &s, VALIDATION_SHAPES, allocator)

		db: Guard_DB
		defer gdb_close(&db)
		gdb_open(&db, allocator)
		gdb_load(&db, VALIDATION_DATA, allocator)
		se := gdb_session(&db)

		b: shacl.Bindings
		shacl.bindings_init(&b, &s, se, allocator)
		defer shacl.bindings_destroy(&b)

		for _ in 0 ..< 4 {
			_, _ = shacl.conforms(&s, &b, se, allocator)
		}
	})
}

// Compiling the same graph twice into the same model must not accumulate:
// compile re-initialises, so the second call's model is the only one alive
// and the first one's storage is not stranded.
@(test)
test_repeated_compiles_do_not_accumulate :: proc(t: ^testing.T) {
	track(t, "repeated compile", proc(allocator: mem.Allocator) {
		context.allocator = allocator
		for _ in 0 ..< 8 {
			s: shacl.Shapes
			db: Guard_DB
			defer gdb_close(&db)
			_ = gdb_compile(&db, &s, SHAPES, allocator)
			shacl.shapes_destroy(&s)
		}
	})
}

// Suppressed validation is the newest machinery and the easiest place in the
// engine to strand memory: every ask builds a fresh frame stack and a value-node
// set per shape it enters, and the runs that matter are the ones that end
// abnormally — the probe stops at its first result, which unwinds by hand, and
// a recursive shape abandons the walk mid-flight.
//
// Repeated asks rather than one: a leak of a stack per ask is what would
// otherwise hide inside a single call's noise.
@(test)
test_suppressed_validation_is_net_zero :: proc(t: ^testing.T) {
	track(t, "suppressed validation", proc(allocator: mem.Allocator) {
		context.allocator = allocator

		SUPPRESS :: `
		@prefix sh: <http://www.w3.org/ns/shacl#> .
		@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
		@prefix ex: <http://example.org/> .
		ex:Nested a sh:NodeShape ;
			sh:property [ sh:path ex:p ; sh:minCount 1 ; sh:datatype xsd:string ] ;
			sh:property [ sh:path [ sh:zeroOrMorePath ex:p ] ; sh:nodeKind sh:IRI ] .
		# A shape that reaches itself: the ask cannot answer and unwinds mid-walk.
		ex:R a sh:PropertyShape ; sh:path ex:p ; sh:property ex:R .
		`
		s: shacl.Shapes
		defer shacl.shapes_destroy(&s)
		shapes_db: Guard_DB
		defer gdb_close(&shapes_db)
		_ = gdb_compile(&shapes_db, &s, SUPPRESS, allocator)

		db: Guard_DB
		defer gdb_close(&db)
		gdb_open(&db, allocator)
		gdb_load(&db, VALIDATION_DATA, allocator)
		se := gdb_session(&db)

		b: shacl.Bindings
		shacl.bindings_init(&b, &s, se, allocator)
		defer shacl.bindings_destroy(&b)

		node := rdf.Term(rdf.IRI("http://example.org/a"))
		for shape_index in 0 ..< len(s.shapes) {
			for _ in 0 ..< 4 {
				_, _ = shacl.conforms_node(
					&s,
					&b,
					se,
					shape_index,
					shacl.node_focus(se, node),
					allocator,
				)
			}
		}
	})
}

// A validator runs once per apply for the life of a store, so what it must not
// do is strand memory per check: the bindings and the validation's
// transients come from apply's scratch, the report is rebuilt on the validator's
// allocator every time, and both refusal and commit must return everything.
// Four applies alternating verdicts, under the same tracker as the store.
@(test)
test_validator_is_net_zero :: proc(t: ^testing.T) {
	track(t, "validator", proc(allocator: mem.Allocator) {
		context.allocator = allocator

		SHAPES :: `
		@prefix sh: <http://www.w3.org/ns/shacl#> .
		@prefix ex: <http://example.org/> .
		ex:PersonShape a sh:NodeShape ; sh:targetClass ex:Person ;
			sh:property [ sh:path ex:email ; sh:maxCount 1 ] .
		`
		s: shacl.Shapes
		defer shacl.shapes_destroy(&s)
		shapes_db: Guard_DB
		defer gdb_close(&shapes_db)
		_ = gdb_compile(&shapes_db, &s, SHAPES, allocator)

		v: shacl.Validator
		shacl.validator_init(&v, &s, allocator = allocator)
		defer shacl.validator_destroy(&v)

		fs: record.Mem_FS
		defer record.mem_fs_destroy(&fs)
		st: record.Store
		_, err, _, _ := record.store_open(&st, "judged", record.mem_file_ops(&fs), validator = shacl.validator_hook(&v), allocator = allocator)
		if err != .None {
			return
		}
		defer record.store_close(&st)

		docs := [4]string {
			`@prefix ex: <http://example.org/> . ex:a a ex:Person ; ex:email "a@x" .`,
			`@prefix ex: <http://example.org/> . ex:a ex:email "a2@x" .`, // refused under Enforce
			`@prefix ex: <http://example.org/> . ex:b a ex:Person ; ex:email "b@x" .`,
			`@prefix ex: <http://example.org/> . ex:b ex:email "b2@x" .`, // commits under Record
		}
		modes := [4]record.Mode{.Enforce, .Enforce, .Record, .Record}
		for doc, i in docs {
			ops, ierr := ingest.turtle(transmute([]byte)doc, nil, allocator, blank_prefix = "g_")
			if ierr.kind != .None {
				continue
			}
			_, _, _ = record.apply(&st, {ops = ops, mode = modes[i]}, allocator)
			ingest.ops_destroy(ops, allocator)
		}
	})
}
