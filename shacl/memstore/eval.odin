package shacl_memstore

import store "store:store"
import memstore "store:store/memstore"

import shacl ".."

// The evaluation half of the memstore instantiation: the one concrete
// procedure the path evaluator reaches the store through.
//
// The evaluator itself is ordinary recursive code in the core package,
// because a generic procedure over `$`-procedure constants cannot call
// itself. This adapter is where that ends: it is concrete, so the match call
// inside it is direct and inlinable, and the only indirection is the single
// call through the procedure value per predicate step.

// Data is what step_adapter needs: the dataset to read and the graph to read
// it in. The graph is bound in every pattern rather than left wildcard, which
// is SHACL-A-0001 decision 5 made mechanical — validation reads one
// caller-named graph, never a union.
Data :: struct {
	dataset: ^memstore.Dataset,
	graph:   store.Term_ID,
}

// step_adapter expands one predicate step. Forward it matches
// (from, predicate, *); inverted, (*, predicate, from).
@(private)
step_adapter :: proc(
	data: rawptr,
	from: store.Term_ID,
	predicate: store.Term_ID,
	inverted: bool,
	out: ^[dynamic]store.Term_ID,
) {
	d := cast(^Data)data
	pattern :=
		inverted \
		? store.Match_Pattern{store.WILDCARD, predicate, from, d.graph} \
		: store.Match_Pattern{from, predicate, store.WILDCARD, d.graph}
	position := inverted ? store.QUAD_S : store.QUAD_O

	it := memstore.match(d.dataset, pattern)
	defer memstore.match_destroy(&it)
	for {
		q, ok := memstore.match_next(&it)
		if !ok {
			break
		}
		append(out, q[position])
	}
}

// value_nodes returns the value nodes of a compiled path from a focus node,
// against a memstore data graph. The caller owns and deletes the result.
//
// `bindings` must have been produced by `bind_paths` against the *same*
// dictionary: the model's terms are resolved to this store's IDs, and IDs
// from another store mean nothing here.
value_nodes :: proc(
	s: ^shacl.Shapes,
	bindings: ^shacl.Path_Bindings,
	dictionary: ^memstore.Dictionary,
	dataset: ^memstore.Dataset,
	path: int,
	focus: store.Term_ID,
	graph: store.Term_ID = store.DEFAULT_GRAPH,
	allocator := context.allocator,
) -> [dynamic]store.Term_ID {
	data := Data {
		dataset = dataset,
		graph   = graph,
	}
	return shacl.value_nodes(s, bindings, path, focus, step_adapter, &data, allocator)
}

// bind_paths resolves the compiled model's predicate terms to this store's
// IDs — the term-binding bridge, once per validation rather than per step.
bind_paths :: proc(
	b: ^shacl.Path_Bindings,
	s: ^shacl.Shapes,
	dictionary: ^memstore.Dictionary,
	allocator := context.allocator,
) {
	shacl.path_bindings_init(b, s, find_adapter, dictionary, allocator)
}

// scan_adapter streams one match. The graph comes from the adapter's own Data
// rather than from the caller, which is what makes it structurally impossible
// for target resolution to leave the graph position wildcard and widen a
// validation to the whole dataset (SHACL-A-0001 decision 5).
@(private)
scan_adapter :: proc(
	data: rawptr,
	subject, predicate, object: store.Term_ID,
	position: int,
	visit: proc(data: rawptr, id: store.Term_ID) -> bool,
	visit_data: rawptr,
) -> bool {
	d := cast(^Data)data
	it := memstore.match(d.dataset, store.Match_Pattern{subject, predicate, object, d.graph})
	defer memstore.match_destroy(&it)
	for {
		q, ok := memstore.match_next(&it)
		if !ok {
			return true
		}
		if !visit(visit_data, q[position]) {
			return false
		}
	}
}

// outgoing_adapter streams the predicate and object of every triple with
// `subject` as its subject — one match with the subject and the graph bound and
// the other two positions wildcard.
//
// It exists because `scan_adapter` yields one position of a matched quad and
// `sh:closed` needs two of the same quad. The store's own `match` has always
// returned whole quads, so this widens the adapter rather than the interface.
@(private)
outgoing_adapter :: proc(
	data: rawptr,
	subject: store.Term_ID,
	visit: proc(data: rawptr, predicate, object: store.Term_ID) -> bool,
	visit_data: rawptr,
) -> bool {
	d := cast(^Data)data
	it := memstore.match(
		d.dataset,
		store.Match_Pattern{subject, store.WILDCARD, store.WILDCARD, d.graph},
	)
	defer memstore.match_destroy(&it)
	for {
		q, ok := memstore.match_next(&it)
		if !ok {
			return true
		}
		if !visit(visit_data, q[store.QUAD_P], q[store.QUAD_O]) {
			return false
		}
	}
}

// resolve_targets streams a shape's focus nodes against a memstore data
// graph. Returns false if the visitor asked to stop.
resolve_targets :: proc(
	s: ^shacl.Shapes,
	bindings: ^shacl.Target_Bindings,
	shape_index: int,
	dataset: ^memstore.Dataset,
	visit: shacl.Focus_Visitor,
	visit_data: rawptr,
	graph: store.Term_ID = store.DEFAULT_GRAPH,
	allocator := context.allocator,
) -> bool {
	data := Data {
		dataset = dataset,
		graph   = graph,
	}
	return shacl.resolve_targets(s, bindings, shape_index, scan_adapter, &data, visit, visit_data, allocator)
}

// bind_targets resolves the compiled model's target terms to this store's IDs.
bind_targets :: proc(
	b: ^shacl.Target_Bindings,
	s: ^shacl.Shapes,
	dictionary: ^memstore.Dictionary,
	allocator := context.allocator,
) {
	shacl.target_bindings_init(b, s, find_adapter, dictionary, allocator)
}
