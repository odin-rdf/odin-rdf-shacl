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

// Report_Sink is `report_add` as a Result_Visitor — the persistent twin of
// `shacl/memstore`'s, and one field shorter because kvstore keeps its
// dictionary and its quads in one handle.
//
// It never stops the stream: a report wants every result, and a short report is
// a wrong one. `Conformance` is the consumer that stops.
Report_Sink :: struct {
	report:  ^shacl.Report,
	shapes:  ^shacl.Shapes,
	session: ^Session,
}

report_sink_visitor :: proc(data: rawptr, result: shacl.Result) -> bool {
	sink := cast(^Report_Sink)data
	shacl.report_add(sink.report, sink.shapes, result, load_adapter, sink.session)
	return true
}
