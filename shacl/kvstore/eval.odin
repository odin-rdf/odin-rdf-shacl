package shacl_kvstore

import store "store:store"
import kvstore "store:store/kvstore"

import shacl ".."

// The evaluation half of the kvstore instantiation — the persistent twin of
// `shacl/memstore`'s. Read the two together: the path evaluator is shared and
// unchanged, and the only difference here is that a step can fail.
//
// That difference is not cosmetic. A failed LMDB read yields no nodes, which
// is indistinguishable from a path that genuinely reaches nothing — and on a
// path, reaching nothing is a perfectly ordinary answer. Left unrecorded, a
// transient store failure would quietly turn into "this focus node has no
// value nodes", and from there into a shape that appears to conform. So the
// step records the first failure into the Session, and a caller checks
// `session_error` before believing a result.

// step_adapter expands one predicate step. Forward it matches
// (from, predicate, *); inverted, (*, predicate, from). The graph is bound in
// both, never wildcard: validation reads one caller-named graph
// (SHACL-A-0001 decision 5).
@(private)
step_adapter :: proc(
	data: rawptr,
	from: store.Term_ID,
	predicate: store.Term_ID,
	inverted: bool,
	out: ^[dynamic]store.Term_ID,
) {
	session := cast(^Session)data
	pattern :=
		inverted \
		? store.Match_Pattern{store.WILDCARD, predicate, from, session.graph} \
		: store.Match_Pattern{from, predicate, store.WILDCARD, session.graph}
	position := inverted ? store.QUAD_S : store.QUAD_O

	it, err := kvstore.match(session.db, pattern)
	if err != nil {
		if session.err == nil {
			session.err = err
		}
		return
	}
	defer kvstore.match_destroy(&it)
	for {
		q, ok := kvstore.match_next(&it)
		if !ok {
			break
		}
		append(out, q[position])
	}
}

// value_nodes returns the value nodes of a compiled path from a focus node,
// against a persistent data graph. The caller owns and deletes the result,
// and should check `session_error` — an empty result and a failed read look
// the same from here.
value_nodes :: proc(
	s: ^shacl.Shapes,
	bindings: ^shacl.Path_Bindings,
	session: ^Session,
	path: int,
	focus: store.Term_ID,
	allocator := context.allocator,
) -> [dynamic]store.Term_ID {
	return shacl.value_nodes(s, bindings, path, focus, step_adapter, session, allocator)
}

// bind_paths resolves the compiled model's predicate terms to this store's
// IDs — the term-binding bridge, once per validation rather than per step.
bind_paths :: proc(
	b: ^shacl.Path_Bindings,
	s: ^shacl.Shapes,
	session: ^Session,
	allocator := context.allocator,
) {
	shacl.path_bindings_init(b, s, find_adapter, session, allocator)
}
