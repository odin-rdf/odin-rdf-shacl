// The core-purity check, in executable form.
//
// SHACL-A-0001 splits the engine into a backend-independent core (`shacl`)
// and thin instantiation packages, and the decisive reason is linkage:
// `store:store/kvstore` foreign-imports a static LMDB archive, so a core that
// imported it — even transitively, even by one convenience import — would put
// LMDB into the link of every consumer, including the ones that only ever
// want an in-memory store.
//
// That property is easy to state, easy to believe, and easy to break
// silently. This program is what makes it checkable: a consumer that uses the
// SHACL core and the in-memory backend and nothing else. `make purity` builds
// it and asserts the resulting binary carries no LMDB symbols.
//
// **Retargeted 2026-08-07 (SHACL-T-0028), and honestly weaker than it was.**
// This program used to go through `shacl/memstore`, which tested more of the
// property: an instantiation package is where a stray `store:store/kvstore`
// import is most tempting and least visible. odin-rdf-store has retired its
// in-memory backend (STORE-A-0006), so there is no longer a backend a
// consumer can use without LMDB — and the property this file guards no longer
// has a beneficiary in the original sense. Every consumer of this library
// links LMDB now.
//
// What survives is worth keeping anyway: package `shacl` itself must not
// acquire a backend import, because the core/instantiation split is what a
// second backend would bind to and what keeps the core's dependencies
// legible. So the check is narrower — a consumer of the core alone — and it
// is internal hygiene rather than a promise to users. SHACL-A-0001 decision 1
// is amended to say so.
package main

import "core:fmt"

import shacl "../../shacl"

SHAPES :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix ex: <http://example.org/> .
ex:S a sh:NodeShape ; sh:targetClass ex:C ; sh:property [ sh:path ex:p ; sh:minCount 1 ] .
`

main :: proc() {
	// A core-only consumer cannot compile a shapes graph -- compiling needs a
	// backend, and naming one is exactly what this program must not do. So it
	// exercises what the core offers on its own: the vocabulary, the error
	// vocabulary, and the model's lifecycle.
	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)

	fmt.printf("shacl namespace:  %s\n", shacl.NS)
	fmt.printf("compile error:    %s\n", shacl.error_message(shacl.Error_Kind.None))
	fmt.printf("shapes compiled:  %d\n", len(s.shapes))
	fmt.printf("root shapes:      %d\n", len(s.roots))
	fmt.printf("ignored:          %d\n", len(shacl.shapes_ignored(&s)))
	fmt.printf("shapes graph len: %d\n", len(SHAPES))
}
