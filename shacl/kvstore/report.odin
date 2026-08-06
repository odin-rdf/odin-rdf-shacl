package shacl_kvstore

import shacl ".."

// report_add folds one validation result into a report graph, materialising
// its node IDs through the session's store.
//
// kvstore's lookup_term allocates, and the report interns what it is given, so
// the loader's copy is freed inside `shacl.report_add` — the report ends up
// owning every term in the graph either way, which is what lets it outlive
// the store.
report_add :: proc(r: ^shacl.Report, s: ^shacl.Shapes, result: shacl.Result, session: ^Session) {
	shacl.report_add(r, s, result, load_adapter, session)
}
