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
	] .
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
