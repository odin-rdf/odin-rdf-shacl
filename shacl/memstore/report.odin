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

// Report_Sink is `report_add` as a Result_Visitor: the three things folding a
// result into a graph needs, in the one `rawptr` the streaming API carries.
//
// It never stops the stream, which is the point — a report is the case where
// every result matters, so early exit would produce a graph that quietly said
// less than the truth. `Conformance` is the consumer that stops.
Report_Sink :: struct {
	report:     ^shacl.Report,
	shapes:     ^shacl.Shapes,
	dictionary: ^memstore.Dictionary,
}

// report_sink_visitor is the Result_Visitor to pass with a `^Report_Sink` as
// its data. `validate_report` wires it up for you; use it directly only to fold
// results into a report while doing something else with them too.
report_sink_visitor :: proc(data: rawptr, result: shacl.Result) -> bool {
	sink := cast(^Report_Sink)data
	shacl.report_add(sink.report, sink.shapes, result, load_adapter, sink.dictionary)
	return true
}
