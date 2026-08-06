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
package guards

import "core:log"
import "core:mem"
import "core:testing"

import rdf "rdf:rdf"
import store "store:store"
import memstore "store:store/memstore"

import shacl "../../shacl"
import shacl_memstore "../../shacl/memstore"

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
	# SHACL-T-0010's two additions, both of which allocate: the shape-expecting
	# parameters discover further shapes (through a list and directly), and the
	# ignored-parameter record interns a term per unimplemented parameter it
	# finds. sh:minInclusive is unimplemented and sh:name is inert, so the
	# record has to distinguish them without leaking either.
	sh:node ex:Nested ;
	sh:and ( ex:Nested ex:AlsoNested ) ;
	sh:name "an annotation" ;
	sh:minInclusive 2 .

ex:Nested sh:path ex:p ; sh:minCount 1 ; sh:maxLength 5 .
ex:AlsoNested sh:not ex:Nested .
`

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
		_, _ = shacl_memstore.compile_turtle(&s, transmute([]byte)string(SHAPES), "", allocator)
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
		_, _ = shacl_memstore.compile_turtle(&s, transmute([]byte)string(BAD), "", allocator)
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

		dictionary: memstore.Dictionary
		memstore.dictionary_init(&dictionary, allocator)
		defer memstore.dictionary_destroy(&dictionary)
		dataset: memstore.Dataset
		memstore.dataset_init(&dataset, allocator)
		defer memstore.dataset_destroy(&dataset)

		_, _ = memstore.load_turtle(&dictionary, &dataset, transmute([]byte)string(PATHS), "", nil, allocator)

		s: shacl.Shapes
		defer shacl.shapes_destroy(&s)
		_ = shacl_memstore.compile(&s, &dictionary, &dataset, store.DEFAULT_GRAPH, allocator)

		b: shacl.Path_Bindings
		defer shacl.path_bindings_destroy(&b)
		shacl_memstore.bind_paths(&b, &s, &dictionary, allocator)

		focus, _ := memstore.find_term(&dictionary, rdf.IRI("http://example.org/a"))
		for sh in s.shapes {
			if sh.path < 0 {
				continue
			}
			for _ in 0 ..< 4 {
				nodes := shacl_memstore.value_nodes(
					&s,
					&b,
					&dictionary,
					&dataset,
					sh.path,
					focus,
					store.DEFAULT_GRAPH,
					allocator,
				)
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

		dictionary: memstore.Dictionary
		memstore.dictionary_init(&dictionary, allocator)
		defer memstore.dictionary_destroy(&dictionary)
		dataset: memstore.Dataset
		memstore.dataset_init(&dataset, allocator)
		defer memstore.dataset_destroy(&dataset)

		_, _ = memstore.load_turtle(&dictionary, &dataset, transmute([]byte)string(TARGETS), "", nil, allocator)

		s: shacl.Shapes
		defer shacl.shapes_destroy(&s)
		_ = shacl_memstore.compile(&s, &dictionary, &dataset, store.DEFAULT_GRAPH, allocator)

		b: shacl.Target_Bindings
		defer shacl.target_bindings_destroy(&b)
		shacl_memstore.bind_targets(&b, &s, &dictionary, allocator)

		count := 0
		visit :: proc(data: rawptr, focus: shacl.Focus_Node) -> bool {
			n := cast(^int)data
			n^ += 1
			return true
		}
		for _, i in s.shapes {
			for _ in 0 ..< 4 {
				shacl_memstore.resolve_targets(
					&s,
					&b,
					i,
					&dataset,
					visit,
					&count,
					store.DEFAULT_GRAPH,
					allocator,
				)
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

		dictionary: memstore.Dictionary
		memstore.dictionary_init(&dictionary, allocator)
		defer memstore.dictionary_destroy(&dictionary)
		dataset: memstore.Dataset
		memstore.dataset_init(&dataset, allocator)
		defer memstore.dataset_destroy(&dataset)
		_, _ = memstore.load_turtle(&dictionary, &dataset, transmute([]byte)string(PATHS), "", nil, allocator)

		s: shacl.Shapes
		defer shacl.shapes_destroy(&s)
		_ = shacl_memstore.compile(&s, &dictionary, &dataset, store.DEFAULT_GRAPH, allocator)

		focus, _ := memstore.find_term(&dictionary, rdf.IRI("http://example.org/a"))

		r: shacl.Report
		shacl.report_init(&r, allocator)
		defer shacl.report_destroy(&r)
		// Every path form, so the RDF-list and blank-node structures the
		// serialiser builds are all exercised.
		for sh, i in s.shapes {
			for _ in 0 ..< 8 {
				shacl_memstore.report_add(
					&r,
					&s,
					shacl.Result {
						focus = shacl.Node_Ref{id = focus, bound = true},
						path = sh.path,
						shape = i,
						component = .Min_Count,
						severity = rdf.IRI(shacl.VIOLATION),
					},
					&dictionary,
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
	sh:property [ sh:path [ sh:zeroOrOnePath ex:p ] ; sh:minCount 9 ] .
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
		_, _ = shacl_memstore.compile_turtle(&s, transmute([]byte)string(VALIDATION_SHAPES), "", allocator)

		dictionary: memstore.Dictionary
		memstore.dictionary_init(&dictionary, allocator)
		defer memstore.dictionary_destroy(&dictionary)
		dataset: memstore.Dataset
		memstore.dataset_init(&dataset, allocator)
		defer memstore.dataset_destroy(&dataset)
		_, _ = memstore.load_turtle(
			&dictionary,
			&dataset,
			transmute([]byte)string(VALIDATION_DATA),
			"",
			nil,
			allocator,
		)

		b: shacl.Bindings
		shacl_memstore.bind(&b, &s, &dictionary, allocator)
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
			_ = shacl_memstore.validate(
				&s,
				&b,
				&dictionary,
				&dataset,
				visit,
				&count,
				store.DEFAULT_GRAPH,
				allocator,
			)
		}
	})
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
			_, _ = shacl_memstore.compile_turtle(&s, transmute([]byte)source, "", allocator)

			dictionary: memstore.Dictionary
			memstore.dictionary_init(&dictionary, allocator)
			defer memstore.dictionary_destroy(&dictionary)
			dataset: memstore.Dataset
			memstore.dataset_init(&dataset, allocator)
			defer memstore.dataset_destroy(&dataset)
			_, _ = memstore.load_turtle(
				&dictionary,
				&dataset,
				transmute([]byte)string(VALIDATION_DATA),
				"",
				nil,
				allocator,
			)

			b: shacl.Bindings
			shacl_memstore.bind(&b, &s, &dictionary, allocator)
			defer shacl.bindings_destroy(&b)

			stop :: proc(data: rawptr, result: shacl.Result) -> bool {
				return false
			}
			for _ in 0 ..< 4 {
				_ = shacl_memstore.validate(
					&s,
					&b,
					&dictionary,
					&dataset,
					stop,
					nil,
					store.DEFAULT_GRAPH,
					allocator,
				)
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
		_, _ = shacl_memstore.compile_turtle(&s, transmute([]byte)string(VALIDATION_SHAPES), "", allocator)

		dictionary: memstore.Dictionary
		memstore.dictionary_init(&dictionary, allocator)
		defer memstore.dictionary_destroy(&dictionary)
		dataset: memstore.Dataset
		memstore.dataset_init(&dataset, allocator)
		defer memstore.dataset_destroy(&dataset)
		_, _ = memstore.load_turtle(
			&dictionary,
			&dataset,
			transmute([]byte)string(VALIDATION_DATA),
			"",
			nil,
			allocator,
		)

		b: shacl.Bindings
		shacl_memstore.bind(&b, &s, &dictionary, allocator)
		defer shacl.bindings_destroy(&b)

		for _ in 0 ..< 4 {
			_, _ = shacl_memstore.conforms(&s, &b, &dictionary, &dataset, store.DEFAULT_GRAPH, allocator)
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
			_, _ = shacl_memstore.compile_turtle(&s, transmute([]byte)string(SHAPES), "", allocator)
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
// It is also the machinery with no suite entry behind it until SHACL-T-0017, so
// this guard and `shacl/suppress_test.odin` are the whole of its cover.
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
		_, _ = shacl_memstore.compile_turtle(&s, transmute([]byte)string(SUPPRESS), "", allocator)

		dictionary: memstore.Dictionary
		memstore.dictionary_init(&dictionary, allocator)
		defer memstore.dictionary_destroy(&dictionary)
		dataset: memstore.Dataset
		memstore.dataset_init(&dataset, allocator)
		defer memstore.dataset_destroy(&dataset)
		_, _ = memstore.load_turtle(
			&dictionary,
			&dataset,
			transmute([]byte)string(VALIDATION_DATA),
			"",
			nil,
			allocator,
		)

		b: shacl.Bindings
		shacl_memstore.bind(&b, &s, &dictionary, allocator)
		defer shacl.bindings_destroy(&b)

		node := rdf.Term(rdf.IRI("http://example.org/a"))
		for shape_index in 0 ..< len(s.shapes) {
			for _ in 0 ..< 4 {
				_, _ = shacl_memstore.conforms_node(
					&s,
					&b,
					&dictionary,
					&dataset,
					node,
					shape_index,
					store.DEFAULT_GRAPH,
					allocator,
				)
			}
		}
	})
}
