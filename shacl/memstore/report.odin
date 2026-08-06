package shacl_memstore

import memstore "store:store/memstore"

import shacl ".."

// report_add folds one validation result into a report graph, materialising
// its node IDs through this store's dictionary.
//
// The wrapper exists so a caller never has to name the loader: it is the same
// adapter compilation uses, and which one is right depends on the backend
// rather than on the caller.
report_add :: proc(
	r: ^shacl.Report,
	s: ^shacl.Shapes,
	result: shacl.Result,
	dictionary: ^memstore.Dictionary,
) {
	shacl.report_add(r, s, result, load_adapter, dictionary)
}
