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
// It imports `store:store/memstore` directly rather than `shacl/memstore`
// because that package has no exported symbols yet. Switch the import when
// SHACL-T-0003 fills it — the property under test is the same either way, and
// going through the instantiation package tests slightly more of it.
package main

import "core:fmt"

import shacl "../../shacl"
import memstore "store:store/memstore"

main :: proc() {
	ds: memstore.Dataset
	memstore.dataset_init(&ds)
	defer memstore.dataset_destroy(&ds)

	fmt.printf("shacl namespace: %s\n", shacl.NS)
	fmt.printf("quads in empty dataset: %d\n", memstore.count(&ds))
}
