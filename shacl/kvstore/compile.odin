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
//
// **A session reads either through a store or through a transaction, never
// both.** `session_init` sets `db` and leaves `txn` nil, and every read is an
// autocommit operation — today's behaviour, and the default.
// `session_init_txn` sets `txn` and leaves `db` nil, and every read goes
// through that transaction, which is what makes validate-before-commit
// expressible (odin-rdf-store STORE-A-0007). Code reaching for `db` on a
// session it did not construct should go through the reads below instead.
Session :: struct {
	db:    ^kvstore.Store,
	txn:   ^kvstore.Txn,
	graph: store.Term_ID,
	err:   kvstore.Error,
}

// session_init binds a session to a store and a graph, with no error recorded
// yet. It allocates nothing and needs no destroy; the session borrows the store
// and is valid as long as it is open.
//
// Every read through it is an autocommit operation — a transaction of the
// appropriate mode, one operation, closed. A validation is many reads, so it is
// many transactions and therefore many datasets; that is correct for a store
// nobody is writing to, and `session_init_txn` is the answer when somebody is.
session_init :: proc(s: ^Session, st: ^kvstore.Store, graph: store.Term_ID = store.DEFAULT_GRAPH) {
	s.db = st
	s.txn = nil
	s.graph = graph
	s.err = nil
}

// session_init_txn binds a session to an open transaction and a graph, so that
// every read below it sees that transaction's dataset. The transaction is the
// caller's throughout: this neither commits nor aborts it, and the session must
// not outlive it.
//
// **This is what makes validate-before-commit reachable.** Build a candidate
// inside a write transaction, validate through that same transaction, and keep
// or discard the write on the answer. The alternative the API used to steer a
// caller toward — build the candidate in a second store and validate *that* —
// is wrong rather than slow: every constraint that must consult existing data
// reads an empty world and passes vacuously, so a `sh:maxCount` over a property
// the dataset already carries values for, or a `sh:class` against a hierarchy
// that lives only in the committed graph, cannot fail.
//
// **Both modes are legal and they buy different things.** A `.Read`
// transaction makes a validation one answer about one dataset rather than a
// sequence of independent reads. A `.Write` transaction adds read-your-own-
// writes, which is the whole point of the pattern above.
//
// **Two costs, and they are contract rather than backend detail** (STORE-A-0007):
//
//   - A **write** transaction holds the environment's writer lock for its whole
//     life, serializing every other writer against that environment. The
//     validate-before-commit pattern holds one across an *entire* validation by
//     construction, and a validation is not fast. For the deployment shape this
//     family targets — ~200 processes per machine, each embedding its own store
//     — that serializes within an environment and not between them, which is why
//     it is acceptable. A consumer putting one store behind many concurrent
//     writers should know what it is buying before adopting the pattern, not
//     after.
//   - A **read** transaction pins pages, so a concurrent writer grows the file
//     for as long as the snapshot is held. A validation is a fine lifetime for
//     that; a request handler holding one across unrelated work is making a
//     storage-sizing decision.
//
// The compiled shapes model is unaffected either way: it owns every term it
// holds (SHACL-A-0001), so compile once at startup and validate many, each
// validation optionally inside a transaction of its own.
session_init_txn :: proc(s: ^Session, tx: ^kvstore.Txn, graph: store.Term_ID = store.DEFAULT_GRAPH) {
	s.db = nil
	s.txn = tx
	s.graph = graph
	s.err = nil
}

// The three reads this package performs, each in one place so that the
// transactional and autocommit forms cannot drift apart across the seven call
// sites that use them. They report failure rather than recording it: the error
// slot belongs to the adapters, which are the ones that have to keep the walk
// well-formed afterwards.

@(private)
session_match :: proc(
	s: ^Session,
	pattern: store.Match_Pattern,
) -> (
	kvstore.Match_Iterator,
	kvstore.Error,
) {
	if s.txn != nil {
		// The iterator borrows the transaction: match_destroy closes the
		// cursor and leaves the transaction alone, so nothing about this
		// package's iterator handling changes.
		return kvstore.match_txn(s.txn, pattern)
	}
	return kvstore.match(s.db, pattern)
}

@(private)
session_lookup :: proc(
	s: ^Session,
	id: store.Term_ID,
	allocator: runtime.Allocator,
) -> (
	rdf.Term,
	kvstore.Error,
) {
	if s.txn != nil {
		return kvstore.lookup_term_txn(s.txn, id, allocator)
	}
	return kvstore.lookup_term(s.db, id, allocator)
}

@(private)
session_find_term :: proc(s: ^Session, term: rdf.Term) -> (store.Term_ID, bool, kvstore.Error) {
	if s.txn != nil {
		// Through a write transaction this sees that transaction's own
		// interning, which is what binds a candidate's fresh terms.
		return kvstore.find_term_txn(s.txn, term)
	}
	return kvstore.find_term(s.db, term)
}

// session_error reports the first store failure seen during compilation, or
// nil. A compile that returns no shacl.Error and a non-nil session error read
// less of the shapes graph than it should have.
session_error :: proc(s: ^Session) -> kvstore.Error {
	return s.err
}

@(private)
match_adapter :: proc(session: ^Session, pattern: store.Match_Pattern) -> kvstore.Match_Iterator {
	it, err := session_match(session, pattern)
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
	loaded, err := session_lookup(session, id, allocator)
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
	got, ok, err := session_find_term(session, term)
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

// compile_turtle_txn is compile_turtle through the caller's write transaction:
// the document is loaded and the shapes compiled from it without either being
// visible outside the transaction, and neither is durable until the caller
// commits.
//
// **The transaction must be a .Write one**, because this loads. It is the
// caller's throughout — this neither commits nor aborts it, and an abort
// discards the loaded shapes graph while leaving the returned `shacl.Shapes`
// perfectly valid, since the model owns every term it holds (SHACL-A-0001) and
// outlives both the transaction and the store.
//
// The compile-once rule that compile_turtle documents holds here unchanged, and
// has one sharper edge worth naming: two loads of the same document into *one*
// transaction still mint distinct blank nodes, so a transaction does not make
// loading idempotent either.
//
// Check `db_err` as well as the other two: a store failure means the shapes
// were compiled from an incomplete read.
compile_turtle_txn :: proc(
	s: ^shacl.Shapes,
	tx: ^kvstore.Txn,
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
	added, load_err, db_err = kvstore.load_turtle_txn(tx, source, base, graph, allocator)
	_ = added
	if db_err != nil || load_err.message != "" {
		return shacl.Error{}, load_err, db_err
	}

	graph_id, found, find_err := kvstore.find_graph_label_txn(tx, graph)
	if find_err != nil {
		return shacl.Error{}, load_err, find_err
	}
	if !found {
		// The load just put statements there, so the label must exist.
		return shacl.Error{}, load_err, nil
	}

	session: Session
	session_init_txn(&session, tx, graph_id)
	err = compile(s, &session, allocator)
	return err, load_err, session_error(&session)
}
