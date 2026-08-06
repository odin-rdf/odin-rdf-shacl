package shacl_memstore

import "core:testing"

import memstore "store:store/memstore"

// The memstore counterpart of `shacl/kvstore`'s linkage test: it asserts that
// this package's half of the backend binding compiles and runs against the
// in-memory backend at whatever Term_ID width the build selected.
//
// It is far less load-bearing than the kvstore one — there is no foreign
// archive to resolve here — but it keeps the two packages parallel, and it
// makes the pinned package list in the Makefile real rather than aspirational
// from the first commit (SHACL-T-0001).
@(test)
test_memstore_binding_compiles_and_runs :: proc(t: ^testing.T) {
	ds: memstore.Dataset
	memstore.dataset_init(&ds)
	defer memstore.dataset_destroy(&ds)

	d: memstore.Dictionary
	memstore.dictionary_init(&d)
	defer memstore.dictionary_destroy(&d)

	testing.expect_value(t, memstore.count(&ds), 0)
}
