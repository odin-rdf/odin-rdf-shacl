package shacl

import "base:runtime"

import store "store:store"

// Value-node evaluation: given a focus node and a compiled path, the set of
// nodes a property shape's constraints apply to (SHACL §2.3).
//
// This is *the* property-shape primitive. Every property constraint in this
// initiative and in the catalogue one consumes it, and every read it makes is
// a `match` call with the graph position bound to the caller-named data graph.
//
// **Why the store is reached through a procedure pointer here, when
// compilation used compile-time constants.** Path evaluation is recursive over
// the path structure — a sequence of alternatives of inverses — and a generic
// procedure over `$`-procedure constants that calls itself hangs the Odin
// compiler (SPARQL-T-0011). odin-rdf-sparql hit exactly this, for exactly
// property paths, and answered it exactly this way: its `expand_adapter` is
// "the same door for a property path's step: the traversal is running inside
// the executor and has to run an operator tree to expand a frontier node,
// which only a concrete procedure can ask for."
//
// So the structure recursion is ordinary non-generic code, and the one place
// it touches the store is a `Step` the instantiation package supplies. Inside
// that adapter the match call is direct, because the adapter is concrete — the
// indirection is one call per predicate step, and SPARQL-T-0011 measured
// procedure-pointer dispatch on the store hot path as noise (−2%).
//
// Everything below works in `Term_ID`s. Value nodes are compared, deduplicated
// and closed over as integers; nothing is materialised into an `rdf.Term`
// until a constraint or a result needs one.

// Step expands one predicate step from a node: append to `out` every node
// reachable from `from` by `predicate`, or reaching `from` by it when
// `inverted`. The implementation is a single `match` call.
//
// It appends rather than returning, so the caller's buffer is reused across a
// frontier instead of allocated per node.
Step :: #type proc(
	data: rawptr,
	from: store.Term_ID,
	predicate: store.Term_ID,
	inverted: bool,
	out: ^[dynamic]store.Term_ID,
)

// Path_Bindings is the term-binding bridge for paths: the compiled model's
// predicate terms resolved to the *data* store's IDs, once, before evaluation.
//
// The model holds `rdf.Term` because the shapes graph and the data graph may
// be different stores (SHACL-A-0001 decision 2). This is where that is paid
// off — one `find_term` per predicate path node, at setup.
//
// A predicate the data store has never seen is `bound = false`, and a step
// through it yields nothing. That is correct rather than a shortcut: no triple
// in the graph can mention a term the dictionary does not hold, so the match
// would be empty anyway. Note this is the *opposite* of what an absent term
// means to a constraint — `sh:class ex:Missing` makes every value node
// violate. Absence is emptiness on a path and failure in a constraint.
Path_Bindings :: struct {
	predicate: []store.Term_ID,
	bound:     []bool,
	allocator: runtime.Allocator,
}

path_bindings_init :: proc(
	b: ^Path_Bindings,
	s: ^Shapes,
	find: Term_Finder,
	find_data: rawptr,
	allocator := context.allocator,
) {
	b.allocator = allocator
	b.predicate = make([]store.Term_ID, len(s.paths), allocator)
	b.bound = make([]bool, len(s.paths), allocator)
	for node, i in s.paths {
		if node.kind != .Predicate {
			continue
		}
		id, found := find(find_data, node.predicate)
		b.predicate[i] = id
		b.bound[i] = found
	}
}

path_bindings_destroy :: proc(b: ^Path_Bindings) {
	delete(b.predicate, b.allocator)
	delete(b.bound, b.allocator)
	b^ = {}
}

// value_nodes returns the value nodes of `path` from `focus`, as a set — no
// duplicates, in no guaranteed order. The caller owns and deletes the result.
//
// `path` is a shape's `Shape.path`; calling this with -1 (a node shape, which
// has no path) returns an empty set rather than failing, because a node
// shape's value node is its focus node and the caller handles that case.
value_nodes :: proc(
	s: ^Shapes,
	b: ^Path_Bindings,
	path: int,
	focus: store.Term_ID,
	step: Step,
	step_data: rawptr,
	allocator := context.allocator,
) -> [dynamic]store.Term_ID {
	if path < 0 || path >= len(s.paths) {
		return make([dynamic]store.Term_ID, allocator)
	}
	inputs := [1]store.Term_ID{focus}
	return eval_path(s, b, path, inputs[:], false, step, step_data, allocator)
}

// eval_path evaluates one path node against a set of input nodes.
//
// `inverted` carries direction down the tree rather than rewriting the path:
// the inverse of a sequence is the reversed sequence of inverses, which is one
// `#reverse` below rather than a compile-time transformation.
//
// Ordinary recursion, deliberately: see the package note above. Depth is
// bounded by the nesting of the shapes graph's path expression, which is
// small — this recurses over the *path*, never over the data.
@(private)
eval_path :: proc(
	s: ^Shapes,
	b: ^Path_Bindings,
	node_index: int,
	inputs: []store.Term_ID,
	inverted: bool,
	step: Step,
	step_data: rawptr,
	allocator: runtime.Allocator,
) -> [dynamic]store.Term_ID {
	node := s.paths[node_index]

	switch node.kind {
	case .Predicate:
		out := make([dynamic]store.Term_ID, allocator)
		if !b.bound[node_index] {
			return out
		}
		seen := make(map[store.Term_ID]bool, allocator)
		defer delete(seen)
		// One buffer for the whole frontier rather than one per node: a step
		// is the innermost thing this evaluator does.
		buf := make([dynamic]store.Term_ID, allocator)
		defer delete(buf)
		for from in inputs {
			clear(&buf)
			step(step_data, from, b.predicate[node_index], inverted, &buf)
			for id in buf {
				if !seen[id] {
					seen[id] = true
					append(&out, id)
				}
			}
		}
		return out

	case .Inverse:
		operands := path_operands(s, node)
		return eval_path(s, b, operands[0], inputs, !inverted, step, step_data, allocator)

	case .Sequence:
		operands := path_operands(s, node)
		current := dedupe_ids(inputs, allocator)
		if inverted {
			#reverse for op in operands {
				next := eval_path(s, b, op, current[:], true, step, step_data, allocator)
				delete(current)
				current = next
			}
		} else {
			for op in operands {
				next := eval_path(s, b, op, current[:], false, step, step_data, allocator)
				delete(current)
				current = next
			}
		}
		return current

	case .Alternative:
		out := make([dynamic]store.Term_ID, allocator)
		seen := make(map[store.Term_ID]bool, allocator)
		defer delete(seen)
		for op in path_operands(s, node) {
			branch := eval_path(s, b, op, inputs, inverted, step, step_data, allocator)
			defer delete(branch)
			for id in branch {
				if !seen[id] {
					seen[id] = true
					append(&out, id)
				}
			}
		}
		return out

	case .Zero_Or_One:
		// The focus node itself is a value node of a zero-or-one path.
		out := dedupe_ids(inputs, allocator)
		seen := make(map[store.Term_ID]bool, allocator)
		defer delete(seen)
		for id in out {
			seen[id] = true
		}
		operands := path_operands(s, node)
		once := eval_path(s, b, operands[0], inputs, inverted, step, step_data, allocator)
		defer delete(once)
		for id in once {
			if !seen[id] {
				seen[id] = true
				append(&out, id)
			}
		}
		return out

	case .One_Or_More:
		return closure(s, b, node, inputs, inverted, false, step, step_data, allocator)

	case .Zero_Or_More:
		return closure(s, b, node, inputs, inverted, true, step, step_data, allocator)
	}

	return make([dynamic]store.Term_ID, allocator)
}

// closure is the shared reachability walk behind zeroOrMorePath and
// oneOrMorePath: breadth-first over `Term_ID`s with a visited set.
//
// The visited set is what makes this safe on cyclic data, and cyclic data is
// not exotic — an asset that is `ex:partOf` another asset which is
// `ex:partOf` the first is an ordinary modelling mistake, and a
// `sh:zeroOrMorePath` over it would otherwise not terminate.
//
// `reflexive` distinguishes the two forms: zero-or-more includes the input
// nodes themselves, one-or-more does not unless they are genuinely reachable.
@(private)
closure :: proc(
	s: ^Shapes,
	b: ^Path_Bindings,
	node: Path_Node,
	inputs: []store.Term_ID,
	inverted: bool,
	reflexive: bool,
	step: Step,
	step_data: rawptr,
	allocator: runtime.Allocator,
) -> [dynamic]store.Term_ID {
	operands := path_operands(s, node)
	out := make([dynamic]store.Term_ID, allocator)
	seen := make(map[store.Term_ID]bool, allocator)
	defer delete(seen)

	if reflexive {
		for id in inputs {
			if !seen[id] {
				seen[id] = true
				append(&out, id)
			}
		}
	}

	current := eval_path(s, b, operands[0], inputs, inverted, step, step_data, allocator)
	for {
		fresh := make([dynamic]store.Term_ID, allocator)
		for id in current {
			if !seen[id] {
				seen[id] = true
				append(&out, id)
				append(&fresh, id)
			}
		}
		delete(current)
		if len(fresh) == 0 {
			delete(fresh)
			break
		}
		current = eval_path(s, b, operands[0], fresh[:], inverted, step, step_data, allocator)
		delete(fresh)
	}
	return out
}

// dedupe_ids copies ids into a fresh set-valued array.
@(private)
dedupe_ids :: proc(ids: []store.Term_ID, allocator: runtime.Allocator) -> [dynamic]store.Term_ID {
	out := make([dynamic]store.Term_ID, allocator)
	seen := make(map[store.Term_ID]bool, allocator)
	defer delete(seen)
	for id in ids {
		if !seen[id] {
			seen[id] = true
			append(&out, id)
		}
	}
	return out
}
