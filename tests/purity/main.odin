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
// It goes through `shacl/memstore` rather than naming the store directly
// (SHACL-T-0003 filled that package, discharging the note this file used to
// carry), which tests slightly more of the property: the instantiation
// package is where a stray `store:store/kvstore` import would be most tempting
// and least visible.
package main

import "core:fmt"

import shacl "../../shacl"
import shacl_memstore "../../shacl/memstore"

SHAPES :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix ex: <http://example.org/> .
ex:S a sh:NodeShape ; sh:targetClass ex:C ; sh:property [ sh:path ex:p ; sh:minCount 1 ] .
`

main :: proc() {
	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)

	err, load_err := shacl_memstore.compile_turtle(&s, transmute([]byte)string(SHAPES))
	fmt.printf("shacl namespace:  %s\n", shacl.NS)
	fmt.printf("load error:       %q\n", load_err.message)
	fmt.printf("compile error:    %s\n", shacl.error_message(err.kind))
	fmt.printf("shapes compiled:  %d\n", len(s.shapes))
	fmt.printf("root shapes:      %d\n", len(s.roots))
}
