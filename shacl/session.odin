package shacl

import "rdf:rdf"
import "record:record"

// The store binding: how the engine reads a data or shapes graph.
//
// odin-rdf-record is the one and only store (SHACL-I-0004), and this file is
// where the engine touches it. Every read anywhere in the package goes through
// the session verbs below, so the graph discipline of SHACL-A-0001 decision 5
// — validation reads one caller-named graph, never a union — is enforced in
// one place: the graph is bound into every pattern and nothing above this file
// ever writes one.
//
// A record read cannot fail. The projection is memory-resident, so the error
// plumbing the old kvstore instantiation carried — an error slot on the
// session, a `session_error` check after every entry point — is gone rather
// than ported: an empty answer *is* the answer.

// Session is a read handle on one graph of one snapshot: everything a
// compile or a validation reads through.
//
// It is a value, and it borrows the snapshot: the caller acquires one with
// `record.store_latest` or `record.store_at`, builds sessions over it, and
// releases it when done — a session must not outlive its snapshot, and this
// package never retains either beyond the call it received them in. (That
// discipline is record's contract for `Validator` candidates too, which is
// what makes the same engine usable inside one.)
Session :: struct {
	snap:  record.Snapshot,
	graph: record.Term_ID, // the graph's resident id, resolved once from the caller's
	//                        rdf.Graph_Label at session_init: MATCH_DEFAULT_GRAPH for
	//                        nil, GRAPH_ABSENT for a label the store has never seen.
	//                        Never 0 — that is "every graph" in a record Pattern.
}

// GRAPH_ABSENT is the graph binding of a session whose graph label the store
// has never seen. It is drawn from record's consumer id range
// (`CONSUMER_ID_FIRST ..= CONSUMER_ID_LAST` — values that can never name a
// term, api.md §3), so a pattern bound to it matches nothing: a graph the
// dictionary does not hold contains no quads, and every read through such a
// session is empty without a special case anywhere.
//
// It must never be 0 — in a record `Pattern` an unbound position means
// "match everything", and an unknown graph widening a validation to the whole
// dataset is exactly the failure the bound-graph discipline exists to prevent.
GRAPH_ABSENT :: record.CONSUMER_ID_FIRST

// session_init binds a session to a graph of a snapshot: nil for the default
// graph, or a graph label the data carries. A label the store has never seen
// yields a session that reads nothing, which is correct — such a graph holds
// no quads — and is reported by `found` for the caller that wants to
// distinguish an empty graph from an absent one.
session_init :: proc(se: ^Session, snap: record.Snapshot, graph: rdf.Graph_Label = nil) -> (found: bool) {
	se.snap = snap
	se.graph = record.MATCH_DEFAULT_GRAPH
	found = true
	if graph != nil {
		term: rdf.Term
		switch g in graph {
		case rdf.IRI:
			term = g
		case rdf.Blank_Node:
			term = g
		}
		id, ok := record.snapshot_resolve(se.snap, term)
		if ok {
			se.graph = id
		} else {
			se.graph = GRAPH_ABSENT
			found = false
		}
	}
	return found
}

// Term_Buf is the stack buffer `session_term` materialises inlined ids into.
// Sized by record's contract: at least INLINE_LEXICAL_MAX bytes.
Term_Buf :: [record.INLINE_LEXICAL_MAX]u8

// session_term decodes an id into a term. **The term is borrowed** — from the
// store's dictionary arena, or from `buf` for an inlined id — and is valid
// only while both are: use it or intern it before the buffer goes away, and
// never destroy it.
//
// One caveat inherited from record: an IRI stored in the split encoding joins
// in one allocation, which this contract would leak. No store written through
// `record.apply` contains one (its encoder emits full IRIs only), and this
// engine reads apply-written stores.
session_term :: proc(se: Session, id: record.Term_ID, buf: []byte) -> (term: rdf.Term, ok: bool) {
	when SHACL_COUNT_READS {
		read_counts.term += 1
	}
	return record.snapshot_term(se.snap, id, buf)
}

// session_resolve is the non-interning term lookup: the id a term has in this
// snapshot's dictionary, or found = false for a term the store has never
// seen. Resolving never writes — record's read side has no way to.
session_resolve :: proc(se: Session, term: rdf.Term) -> (id: record.Term_ID, found: bool) {
	return record.snapshot_resolve(se.snap, term)
}

// session_kind is a bound node's kind — IRI, blank node, or literal — read
// without decoding the term.
session_kind :: proc(se: Session, id: record.Term_ID) -> record.Term_Kind {
	return record.snapshot_kind(se.snap, id)
}

// Pos names the quad position a scan yields.
@(private)
Pos :: enum u8 {
	Subject,
	Object,
}

// session_scan streams one position of every quad matching (s, p, o) in the
// session's graph — 0 for an unbound position, exactly record's pattern
// convention. `visit` returning false stops the scan and session_scan then
// returns false, so early exit reaches the store's iterator rather than being
// simulated above it.
@(private)
session_scan :: proc(
	se: Session,
	subject, predicate, object: record.Term_ID,
	position: Pos,
	visit: proc(data: rawptr, id: record.Term_ID) -> bool,
	visit_data: rawptr,
) -> bool {
	when SHACL_COUNT_READS {
		read_counts.scan += 1
	}
	rng := record.snapshot_match(se.snap, record.Pattern{s = subject, p = predicate, o = object, g = se.graph})
	sc := record.range_iter(rng, record.Filter{origin = .Any})
	for {
		id, ok := record.scan_next(&sc)
		if !ok {
			return true
		}
		f := record.snapshot_fact(se.snap, id)
		if !visit(visit_data, position == .Subject ? f.s : f.o) {
			return false
		}
	}
}

// session_step expands one predicate step: append to `out` every node
// reachable from `from` by `predicate` — or reaching `from` by it, when
// `inverted`. The path evaluator's one read.
@(private)
session_step :: proc(se: Session, from, predicate: record.Term_ID, inverted: bool, out: ^[dynamic]record.Term_ID) {
	when SHACL_COUNT_READS {
		read_counts.step += 1
	}
	p :=
		inverted \
		? record.Pattern{p = predicate, o = from, g = se.graph} \
		: record.Pattern{s = from, p = predicate, g = se.graph}
	rng := record.snapshot_match(se.snap, p)
	sc := record.range_iter(rng, record.Filter{origin = .Any})
	for {
		id, ok := record.scan_next(&sc)
		if !ok {
			return
		}
		f := record.snapshot_fact(se.snap, id)
		append(out, inverted ? f.s : f.o)
	}
}

// session_outgoing streams the predicate and the object of every quad with
// `subject` as its subject — the two positions of one quad together, which is
// the read `sh:closed` needs and single-position scans cannot express.
@(private)
session_outgoing :: proc(
	se: Session,
	subject: record.Term_ID,
	visit: proc(data: rawptr, predicate, object: record.Term_ID) -> bool,
	visit_data: rawptr,
) -> bool {
	when SHACL_COUNT_READS {
		read_counts.outgoing += 1
	}
	rng := record.snapshot_match(se.snap, record.Pattern{s = subject, g = se.graph})
	sc := record.range_iter(rng, record.Filter{origin = .Any})
	for {
		id, ok := record.scan_next(&sc)
		if !ok {
			return true
		}
		f := record.snapshot_fact(se.snap, id)
		if !visit(visit_data, f.p, f.o) {
			return false
		}
	}
}

// node_focus resolves a caller's term to a focus node: bound when the
// snapshot's dictionary holds it, unbound when it does not. **A term the data
// graph never mentions is still a perfectly good focus node**, validated as
// unbound — every path from it reaches nothing, and that emptiness is
// meaningful rather than an error: `sh:minCount 1` on such a node violates.
node_focus :: proc(se: Session, node: rdf.Term) -> Focus_Node {
	focus := Focus_Node {
		term = node,
	}
	if id, found := session_resolve(se, node); found {
		focus.id = id
		focus.bound = true
	}
	return focus
}
