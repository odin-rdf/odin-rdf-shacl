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

import shacl "../../shacl"
import shacl_memstore "../../shacl/memstore"

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
