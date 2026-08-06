package shacl_memstore

import "base:runtime"

import rdf "rdf:rdf"
import store "store:store"
import memstore "store:store/memstore"

import shacl ".."

// The three hot-path adapters. Ordinary procedures, passed to the core as
// compile-time constants, so the compiler monomorphizes against them and
// every store call is direct.
@(private)
match_adapter :: proc(dataset: ^memstore.Dataset, pattern: store.Match_Pattern) -> memstore.Match_Iterator {
	return memstore.match(dataset, pattern)
}

@(private)
next_adapter :: proc(it: ^memstore.Match_Iterator) -> (store.Encoded_Quad, bool) {
	return memstore.match_next(it)
}

@(private)
destroy_adapter :: proc(it: ^memstore.Match_Iterator) {
	memstore.match_destroy(it)
}

// load_adapter materializes an ID. memstore's lookup_term borrows the
// dictionary's storage, so nothing is owned and nothing needs freeing — and
// that is precisely why the shapes model interns rather than borrows: kvstore
// answers `owned = true` here, and a model that borrowed would have two
// lifetime rules instead of one.
@(private)
load_adapter :: proc(
	data: rawptr,
	id: store.Term_ID,
	allocator: runtime.Allocator,
) -> (
	term: rdf.Term,
	owned: bool,
) {
	dictionary := cast(^memstore.Dictionary)data
	return memstore.lookup_term(dictionary, id), false
}

// find_adapter is the non-interning lookup, so compiling a shapes graph never
// assigns an ID and never turns a read into a write.
@(private)
find_adapter :: proc(data: rawptr, term: rdf.Term) -> (id: store.Term_ID, found: bool) {
	dictionary := cast(^memstore.Dictionary)data
	return memstore.find_term(dictionary, term)
}

// compile builds a shapes model from a shapes graph already in a memstore.
//
// `graph` names the graph to read — `store.DEFAULT_GRAPH` for the default
// graph. The returned model owns everything it holds: `dictionary` and
// `dataset` may be destroyed immediately afterwards.
compile :: proc(
	s: ^shacl.Shapes,
	dictionary: ^memstore.Dictionary,
	dataset: ^memstore.Dataset,
	graph: store.Term_ID = store.DEFAULT_GRAPH,
	allocator := context.allocator,
) -> shacl.Error {
	return shacl.compile(
		s,
		dataset,
		graph,
		load_adapter,
		dictionary,
		find_adapter,
		dictionary,
		match_adapter,
		next_adapter,
		destroy_adapter,
		allocator,
	)
}

// compile_turtle is the convenience path most callers want: a shapes graph in
// a Turtle document, compiled to a model.
//
// It lives here rather than in the core package on purpose. The core names no
// backend and imports none, which is what keeps LMDB out of the link of every
// consumer that only wants an in-memory store (SHACL-A-0001) — so the "parse a
// file and compile it" helper, which necessarily names a backend, belongs to
// an instantiation package.
//
// The store it builds is private and destroyed before returning. That the
// model survives it is the ownership property, exercised on every call rather
// than only in the test that asserts it.
compile_turtle :: proc(
	s: ^shacl.Shapes,
	source: []byte,
	base := "",
	allocator := context.allocator,
) -> (
	err: shacl.Error,
	load_err: store.Load_Error,
) {
	dictionary: memstore.Dictionary
	memstore.dictionary_init(&dictionary, allocator)
	defer memstore.dictionary_destroy(&dictionary)

	dataset: memstore.Dataset
	memstore.dataset_init(&dataset, allocator)
	defer memstore.dataset_destroy(&dataset)

	_, load_err = memstore.load_turtle(&dictionary, &dataset, source, base, nil, allocator)
	if load_err.message != "" {
		return shacl.Error{}, load_err
	}
	err = compile(s, &dictionary, &dataset, store.DEFAULT_GRAPH, allocator)
	return err, load_err
}
