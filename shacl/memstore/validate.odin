package shacl_memstore

import store "store:store"
import memstore "store:store/memstore"

import shacl ".."

// The memstore instantiation of validation: the core's `Access` filled in with
// this backend's three adapters, and the two consumers most callers actually
// want.
//
// Nothing here decides anything. `shacl/kvstore/validate.odin` is the same file
// against the persistent backend, and the two are meant to stay recognizably
// parallel — a change to one is a question about the other.

// bind resolves the compiled model's terms to this store's IDs: the
// term-binding bridge, once per validation rather than once per check.
//
// `dictionary` must be the *data* graph's. A model compiled from a different
// store holds terms, not IDs, precisely so this can happen against whichever
// store is about to be validated (SHACL-A-0001 decision 3).
bind :: proc(
	b: ^shacl.Bindings,
	s: ^shacl.Shapes,
	dictionary: ^memstore.Dictionary,
	allocator := context.allocator,
) {
	shacl.bindings_init(b, s, find_adapter, dictionary, allocator)
}

// validate runs the shapes model against a memstore data graph, streaming every
// result to `visit`.
//
// `graph` names the one graph read — `store.DEFAULT_GRAPH` for the default
// graph. It is bound into every pattern the adapters issue, never left wildcard
// (SHACL-A-0001 decision 5).
//
// Returning false from the visitor stops validation. The returned Failure is
// the spec's failure, not a result: `.None` means the traversal completed or
// was stopped, and anything else means the stream is incomplete.
validate :: proc(
	s: ^shacl.Shapes,
	b: ^shacl.Bindings,
	dictionary: ^memstore.Dictionary,
	dataset: ^memstore.Dataset,
	visit: shacl.Result_Visitor,
	visit_data: rawptr,
	graph: store.Term_ID = store.DEFAULT_GRAPH,
	allocator := context.allocator,
) -> shacl.Failure {
	data := Data {
		dataset = dataset,
		graph   = graph,
	}
	access := shacl.Access {
		scan      = scan_adapter,
		step      = step_adapter,
		load      = load_adapter,
		data      = &data,
		load_data = dictionary,
	}
	return shacl.validate(s, b, access, visit, visit_data, allocator)
}

// validate_report runs a validation and builds the `sh:ValidationReport` graph,
// finished and ready to serialise.
//
// This is the ordinary consumer of the result stream, not a second engine:
// results are folded into the graph as they arrive and none is buffered. The
// report head — `sh:conforms` — is written last, because its value is only
// known when the stream has drained.
//
// `r` must be freshly `report_init`ed; the caller owns and destroys it.
validate_report :: proc(
	r: ^shacl.Report,
	s: ^shacl.Shapes,
	b: ^shacl.Bindings,
	dictionary: ^memstore.Dictionary,
	dataset: ^memstore.Dataset,
	graph: store.Term_ID = store.DEFAULT_GRAPH,
	allocator := context.allocator,
) -> shacl.Failure {
	sink := Report_Sink {
		report     = r,
		shapes     = s,
		dictionary = dictionary,
	}
	failure := validate(s, b, dictionary, dataset, report_sink_visitor, &sink, graph, allocator)
	shacl.report_finish(r)
	return failure
}

// conforms answers the one question that admits early exit: does this graph
// conform?
//
// It stops at the first `sh:Violation` — no further focus nodes resolved, no
// further paths walked — which on badly broken data is the difference between
// reading one triple and reading the graph. A warning does not break
// conformance (§3.1.2) and does not stop it.
//
// The boolean is meaningless when the Failure is not `.None`: a failure means
// the processor could not answer, which is not the same as "no".
conforms :: proc(
	s: ^shacl.Shapes,
	b: ^shacl.Bindings,
	dictionary: ^memstore.Dictionary,
	dataset: ^memstore.Dataset,
	graph: store.Term_ID = store.DEFAULT_GRAPH,
	allocator := context.allocator,
) -> (
	bool,
	shacl.Failure,
) {
	c: shacl.Conformance
	shacl.conformance_init(&c)
	failure := validate(s, b, dictionary, dataset, shacl.conformance_visitor, &c, graph, allocator)
	return c.conforms, failure
}
