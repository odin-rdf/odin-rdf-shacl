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
Session :: struct {
	store: ^kvstore.Store,
	err:   kvstore.Error,
}

session_init :: proc(s: ^Session, st: ^kvstore.Store) {
	s.store = st
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
	it, err := kvstore.match(session.store, pattern)
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
	loaded, err := kvstore.lookup_term(session.store, id, allocator)
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
	got, ok, err := kvstore.find_term(session.store, term)
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
// `graph` names the graph to read — `store.DEFAULT_GRAPH` for the default
// graph. The returned model owns everything it holds, so the store may be
// closed immediately afterwards; on kvstore that is not a nicety but the only
// workable rule, since every term it hands out is built from database bytes
// that the close invalidates.
//
// Check `session_error(session)` as well as the returned Error: a store
// failure means the model was compiled from an incomplete read.
compile :: proc(
	s: ^shacl.Shapes,
	session: ^Session,
	graph: store.Term_ID = store.DEFAULT_GRAPH,
	allocator := context.allocator,
) -> shacl.Error {
	return shacl.compile(
		s,
		session,
		graph,
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
