package shacl_memstore

import rdf "rdf:rdf"
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
		outgoing  = outgoing_adapter,
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
// It stops at the **first result of any severity** — no further focus nodes
// resolved, no further paths walked — which on badly broken data is the
// difference between reading one triple and reading the graph. Severity does
// not enter into it: §3.1 makes `sh:conforms` a question about whether there
// are results at all, and `misc/severity-001` settles it by producing exactly
// one `sh:Warning` and expecting `sh:conforms false`.
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

// conforms_node answers the conformance question for one node against one
// shape: does `node` conform to `s.shapes[shape_index]` and every property
// shape below it (§3.4)?
//
// This is the narrower sibling of `conforms`, which asks it of the whole graph
// through the shapes that carry targets. Here the caller names both the node
// and the shape, and **no results are produced** — the question is the boolean.
// `shape_index` indexes the compiled model, which is how every other part of
// the API names a shape (`Result.shape` is the same index); `shape_index_of`
// finds it for a shape the author gave an IRI.
//
// The node need not be in the data graph. A term the store has never seen is
// resolved through the non-interning lookup and validated as an unbound focus
// node, exactly as an absent `sh:targetNode` is: a path from it reaches
// nothing, which is emptiness and is meaningful.
//
// The boolean is meaningless when the Failure is not `.None`.
conforms_node :: proc(
	s: ^shacl.Shapes,
	b: ^shacl.Bindings,
	dictionary: ^memstore.Dictionary,
	dataset: ^memstore.Dataset,
	node: rdf.Term,
	shape_index: int,
	graph: store.Term_ID = store.DEFAULT_GRAPH,
	allocator := context.allocator,
) -> (
	bool,
	shacl.Failure,
) {
	data := Data {
		dataset = dataset,
		graph   = graph,
	}
	access := shacl.Access {
		scan      = scan_adapter,
		step      = step_adapter,
		outgoing  = outgoing_adapter,
		load      = load_adapter,
		data      = &data,
		load_data = dictionary,
	}
	focus := shacl.Focus_Node {
		term = node,
	}
	if id, found := memstore.find_term(dictionary, node); found {
		focus.id = id
		focus.bound = true
	}
	return shacl.conforms_node(s, b, access, shape_index, focus, allocator)
}
