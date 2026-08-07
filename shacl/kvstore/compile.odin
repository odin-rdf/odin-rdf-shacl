package shacl_kvstore

import "base:runtime"

import rdf "rdf:rdf"
import store "store:store"
import kvstore "store:store/kvstore"

import shacl ".."

// Session is the dataset handle the compiler reads through: the store, plus
// the place a failed store operation is recorded.
//
// The error slot is the whole reason this package differs from
// `shacl/memstore`. An LMDB read can fail, and the compiler's hot-path
// signatures have nowhere to put an error — but swallowing one would be the
// worst possible outcome here, because a failed read is indistinguishable
// from a shapes graph that simply does not assert the triple. A shape would
// silently lose a constraint. So the adapters record the first failure and
// `session_error` reports it; a caller that ignores it gets a model compiled
// from whatever was readable, which is why `compile` below checks it before
// returning success.
//
// The same shape odin-rdf-sparql arrived at in SPARQL-T-0011, for the same
// reason.
//
// `graph` is the graph every read binds in its pattern — the shapes graph
// when compiling, the data graph when evaluating (SHACL-A-0001 decision 5).
// A caller whose shapes and data live in different graphs of one store uses
// two Sessions over the same store, which is a struct rather than a handle
// and costs nothing.
Session :: struct {
	db:    ^kvstore.Store,
	graph: store.Term_ID,
	err:   kvstore.Error,
}

// session_init binds a session to a store and a graph, with no error recorded
// yet. It allocates nothing and needs no destroy; the session borrows the store
// and is valid as long as it is open.
session_init :: proc(s: ^Session, st: ^kvstore.Store, graph: store.Term_ID = store.DEFAULT_GRAPH) {
	s.db = st
	s.graph = graph
	s.err = nil
}

// session_error reports the first store failure seen during compilation, or
// nil. A compile that returns no shacl.Error and a non-nil session error read
// less of the shapes graph than it should have.
session_error :: proc(s: ^Session) -> kvstore.Error {
	return s.err
}

@(private)
match_adapter :: proc(session: ^Session, pattern: store.Match_Pattern) -> kvstore.Match_Iterator {
	it, err := kvstore.match(session.db, pattern)
	if err != nil {
		if session.err == nil {
			session.err = err
		}
		// A failed match must not look like an exhausted one, but it must
		// still be safe to step and destroy. The error is what the caller
		// acts on; this only keeps the walk well-formed.
		return kvstore.Match_Iterator{state = .Done}
	}
	return it
}

@(private)
next_adapter :: proc(it: ^kvstore.Match_Iterator) -> (store.Encoded_Quad, bool) {
	return kvstore.match_next(it)
}

@(private)
destroy_adapter :: proc(it: ^kvstore.Match_Iterator) {
	kvstore.match_destroy(it)
}

// load_adapter materializes an ID. kvstore builds the term from the
// database's bytes, so it allocates and `owned` is true — the opposite of
// memstore, and exactly the divergence that made the shapes model own its
// terms rather than borrow them (SHACL-A-0001 decision 3).
@(private)
load_adapter :: proc(
	data: rawptr,
	id: store.Term_ID,
	allocator: runtime.Allocator,
) -> (
	term: rdf.Term,
	owned: bool,
) {
	session := cast(^Session)data
	loaded, err := kvstore.lookup_term(session.db, id, allocator)
	if err != nil {
		if session.err == nil {
			session.err = err
		}
		return nil, false
	}
	return loaded, true
}

@(private)
find_adapter :: proc(data: rawptr, term: rdf.Term) -> (id: store.Term_ID, found: bool) {
	session := cast(^Session)data
	got, ok, err := kvstore.find_term(session.db, term)
	if err != nil {
		if session.err == nil {
			session.err = err
		}
		return store.WILDCARD, false
	}
	return got, ok
}

// compile builds a shapes model from a shapes graph in a persistent store.
//
// The graph read is the session's. The returned model owns everything it
// holds, so the store may be
// closed immediately afterwards; on kvstore that is not a nicety but the only
// workable rule, since every term it hands out is built from database bytes
// that the close invalidates.
//
// Check `session_error(session)` as well as the returned Error: a store
// failure means the model was compiled from an incomplete read.
compile :: proc(s: ^shacl.Shapes, session: ^Session, allocator := context.allocator) -> shacl.Error {
	return shacl.compile(
		s,
		session,
		session.graph,
		load_adapter,
		session,
		find_adapter,
		session,
		match_adapter,
		next_adapter,
		destroy_adapter,
		allocator,
	)
}

// compile_turtle loads a shapes graph from a Turtle document into a graph of
// the caller's store and compiles it.
//
// `graph` names the graph the document lands in — nil for the default graph.
// The returned model owns every term it holds (SHACL-A-0001), so the store may
// be closed immediately afterwards and the model bound to a different one.
//
// **The store is the caller's, deliberately.** The memstore version of this
// procedure built a private store, compiled from it, and destroyed it, so a
// caller needed nothing but a document. That was reasonable when a store was a
// hash map; it is not when a store is an LMDB environment, and a validation
// library should not silently own a database. Every consumer of this package
// already has a store open for the data graph, so the parameter costs nothing
// it did not already have — and `Session`'s own documentation already describes
// the arrangement this produces: shapes and data in two graphs of one store,
// read through two Sessions.
//
// **Compile once, validate many.** There is no `remove` in the store yet
// (odin-rdf-store STORE-T-0023), and loading is *not* idempotent: `load_turtle`
// gives every load its own blank-node scope, and shapes graphs are dense with
// blank nodes (`sh:property [ sh:path ex:p ; sh:minCount 1 ]`). Loading the
// same document into the same graph twice therefore does not dedupe — it
// deposits a second copy of every blank-node-rooted shape, and a later compile
// over that graph sees duplicated shapes. Load shapes once at startup and keep
// the `shacl.Shapes` value, which outlives the store by design. This restriction
// relaxes when `remove` lands.
//
// Check `db_err` as well as the other two: a store failure means the shapes
// were compiled from an incomplete read.
compile_turtle :: proc(
	s: ^shacl.Shapes,
	st: ^kvstore.Store,
	source: []byte,
	graph: rdf.Graph_Label = nil,
	base := "",
	allocator := context.allocator,
) -> (
	err: shacl.Error,
	load_err: store.Load_Error,
	db_err: kvstore.Error,
) {
	added: int
	added, load_err, db_err = kvstore.load_turtle(st, source, base, graph, allocator)
	_ = added
	if db_err != nil || load_err.message != "" {
		return shacl.Error{}, load_err, db_err
	}

	graph_id, found, find_err := kvstore.find_graph_label(st, graph)
	if find_err != nil {
		return shacl.Error{}, load_err, find_err
	}
	if !found {
		// The load just put statements there, so the label must exist.
		return shacl.Error{}, load_err, nil
	}

	session: Session
	session_init(&session, st, graph_id)
	err = compile(s, &session, allocator)
	return err, load_err, session_error(&session)
}
