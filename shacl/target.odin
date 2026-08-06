package shacl

import "base:runtime"

import rdf "rdf:rdf"
import store "store:store"

// Target resolution: a shape's target declarations turned into the focus
// nodes it applies to (SHACL §2.1.3).
//
// Every read is a `match` with the graph position bound. That is not a
// stylistic note — it is the property that retired the vision's prediction
// that this project would need STORE-T-0017, the named-graph wildcard. The
// wildcard was only ever wanted for validating a union of graphs, and
// SHACL-A-0001 decision 5 chose one caller-named graph instead.
//
// Resolution **streams**: focus nodes are handed to a visitor as they are
// found, never collected into a list. What it does keep is a set of the nodes
// already yielded, and that is unavoidable rather than an oversight — §2.1.3
// makes the focus nodes of a shape the *union* of its targets, so a node
// reached by two declarations must be validated once. `multipleTargets-001`
// in the suite is exactly that case.

// Scan streams one match. `subject`, `predicate` and `object` are bound IDs or
// `store.WILDCARD`; `position` says which of QUAD_S / QUAD_O to yield.
//
// The graph is deliberately **not** a parameter: the adapter owns it and binds
// it in every pattern, so the core cannot accidentally leave it wildcard and
// widen a validation to the whole dataset.
//
// `visit` returning false stops the scan, and Scan then returns false, which
// is how early exit reaches the store layer rather than being simulated above
// it.
Scan :: #type proc(
	data: rawptr,
	subject, predicate, object: store.Term_ID,
	position: int,
	visit: proc(data: rawptr, id: store.Term_ID) -> bool,
	visit_data: rawptr,
) -> bool

// Node_Ref names a node of the data graph: its ID when the store holds one,
// and otherwise the term itself.
//
// `bound` is false when the node is not in the data store's dictionary, which
// happens for `sh:targetNode` naming a term the data graph never mentions.
// **That is a focus node all the same** — the spec targets the node, not the
// node's appearances — and validating it is meaningful: a property shape with
// `sh:minCount 1` must report a violation, because the node has no values.
//
// So `term` carries it. For a bound node `term` is nil and the caller
// materialises through the dictionary if it needs one; for an unbound node
// `term` borrows the compiled model's storage, which outlives the validation.
Node_Ref :: struct {
	id:    store.Term_ID,
	bound: bool,
	term:  rdf.Term,
}

// Focus_Node is a node a shape applies to — the same shape as any other node
// reference, named for where it is used.
Focus_Node :: Node_Ref

// Focus_Visitor receives each focus node. Returning false stops resolution.
Focus_Visitor :: #type proc(data: rawptr, focus: Focus_Node) -> bool

// Target_Bindings is the term-binding bridge for targets: the compiled
// model's target terms, and the two RDF/RDFS predicates class targeting
// needs, resolved to the *data* store's IDs once before resolution.
Target_Bindings :: struct {
	term:         []store.Term_ID, // indexed by s.targets
	bound:        []bool,
	rdf_type:     store.Term_ID,
	has_type:     bool,
	subclass_of:  store.Term_ID,
	has_subclass: bool,
	allocator:    runtime.Allocator,
}

// RDFS_SUBCLASS_OF is the one RDFS term class targeting needs beyond rdf:type.
// It lives here rather than in vocab.odin because it is not SHACL vocabulary.
RDFS_SUBCLASS_OF :: "http://www.w3.org/2000/01/rdf-schema#subClassOf"

// target_bindings_init resolves every target term in the model, plus rdf:type
// and rdfs:subClassOf, against a data store. `find` must be the non-interning
// lookup. Freed by `target_bindings_destroy`.
target_bindings_init :: proc(
	b: ^Target_Bindings,
	s: ^Shapes,
	find: Term_Finder,
	find_data: rawptr,
	allocator := context.allocator,
) {
	b.allocator = allocator
	b.term = make([]store.Term_ID, len(s.targets), allocator)
	b.bound = make([]bool, len(s.targets), allocator)
	for target, i in s.targets {
		id, found := find(find_data, target.term)
		b.term[i] = id
		b.bound[i] = found
	}
	b.rdf_type, b.has_type = find(find_data, rdf.RDF_TYPE)
	b.subclass_of, b.has_subclass = find(find_data, rdf.IRI(RDFS_SUBCLASS_OF))
}

// target_bindings_destroy frees the bindings, leaving the model and the store
// untouched.
target_bindings_destroy :: proc(b: ^Target_Bindings) {
	delete(b.term, b.allocator)
	delete(b.bound, b.allocator)
	b^ = {}
}

// resolve_targets streams the focus nodes of one shape to `visit`, and
// returns false if the visitor asked to stop.
//
// A shape with no targets yields nothing: it is reached through `sh:property`
// from a shape that does have them, and its focus nodes are its parent's value
// nodes rather than anything resolved here.
resolve_targets :: proc(
	s: ^Shapes,
	b: ^Target_Bindings,
	shape_index: int,
	scan: Scan,
	scan_data: rawptr,
	visit: Focus_Visitor,
	visit_data: rawptr,
	allocator := context.allocator,
) -> bool {
	shape := s.shapes[shape_index]

	// The union-of-targets set. Bound nodes dedupe by ID; the handful that are
	// unbound dedupe by term, linearly, because a shape has few targets and a
	// map keyed on a serialized term would cost more than it saved.
	state := Resolve_State {
		visit      = visit,
		visit_data = visit_data,
		seen       = make(map[store.Term_ID]bool, allocator),
		unbound    = make([dynamic]rdf.Term, allocator),
	}
	defer delete(state.seen)
	defer delete(state.unbound)

	start := shape.targets.start
	for target, i in shape_targets(s, shape) {
		index := start + i

		switch target.kind {
		case .Node:
			// An absent target node is still a focus node; see Focus_Node.
			if b.bound[index] {
				if !emit(&state, Focus_Node{id = b.term[index], bound = true}) {
					return false
				}
			} else {
				if !emit_unbound(&state, target.term) {
					return false
				}
			}

		case .Class, .Implicit_Class:
			if !b.has_type || !b.bound[index] {
				// A class the data store has never seen has no instances, so
				// the shape applies to nothing. This is the case the task
				// singled out, and it is emptiness rather than failure — the
				// opposite of what an absent `sh:class` will mean.
				continue
			}
			classes := subclass_closure(b, scan, scan_data, b.term[index], allocator)
			defer delete(classes)
			for class in classes {
				if !scan(scan_data, store.WILDCARD, b.rdf_type, class, store.QUAD_S, visit_id, &state) {
					return false
				}
			}

		case .Subjects_Of:
			if !b.bound[index] {
				continue
			}
			if !scan(scan_data, store.WILDCARD, b.term[index], store.WILDCARD, store.QUAD_S, visit_id, &state) {
				return false
			}

		case .Objects_Of:
			if !b.bound[index] {
				continue
			}
			if !scan(scan_data, store.WILDCARD, b.term[index], store.WILDCARD, store.QUAD_O, visit_id, &state) {
				return false
			}
		}
	}
	return true
}

@(private = "file")
Resolve_State :: struct {
	visit:      Focus_Visitor,
	visit_data: rawptr,
	seen:       map[store.Term_ID]bool,
	unbound:    [dynamic]rdf.Term,
}

@(private = "file")
emit :: proc(state: ^Resolve_State, focus: Focus_Node) -> bool {
	if state.seen[focus.id] {
		return true
	}
	state.seen[focus.id] = true
	return state.visit(state.visit_data, focus)
}

@(private = "file")
emit_unbound :: proc(state: ^Resolve_State, term: rdf.Term) -> bool {
	for seen in state.unbound {
		if rdf.equal_term(seen, term) {
			return true
		}
	}
	append(&state.unbound, term)
	return state.visit(state.visit_data, Focus_Node{bound = false, term = term})
}

@(private = "file")
visit_id :: proc(data: rawptr, id: store.Term_ID) -> bool {
	state := cast(^Resolve_State)data
	return emit(state, Focus_Node{id = id, bound = true})
}

// subclass_closure returns `class` together with every class that reaches it
// through `rdfs:subClassOf*` — the set whose instances `sh:targetClass class`
// targets (§2.1.3.2).
//
// The direction is worth being explicit about, because it is easy to invert:
// this walks *down* the hierarchy. A node typed `ex:Sub` is a focus node of
// `sh:targetClass ex:Super` when `ex:Sub rdfs:subClassOf ex:Super`, so the
// scan looks for subjects of `subClassOf` whose object is a class already in
// the set.
//
// Breadth-first with a visited set, for the same reason path reachability
// needs one: `rdfs:subClassOf` cycles are ill-advised but not prevented, and a
// class hierarchy that loops would otherwise not terminate.
@(private)
subclass_closure :: proc(
	b: ^Target_Bindings,
	scan: Scan,
	scan_data: rawptr,
	class: store.Term_ID,
	allocator: runtime.Allocator,
) -> [dynamic]store.Term_ID {
	out := make([dynamic]store.Term_ID, allocator)
	append(&out, class)
	if !b.has_subclass {
		return out
	}

	seen := make(map[store.Term_ID]bool, allocator)
	defer delete(seen)
	seen[class] = true

	collector := Closure_State {
		seen  = &seen,
		fresh = make([dynamic]store.Term_ID, allocator),
	}
	defer delete(collector.fresh)

	frontier := make([dynamic]store.Term_ID, allocator)
	defer delete(frontier)
	append(&frontier, class)

	for len(frontier) > 0 {
		clear(&collector.fresh)
		for super in frontier {
			scan(scan_data, store.WILDCARD, b.subclass_of, super, store.QUAD_S, collect_id, &collector)
		}
		clear(&frontier)
		for id in collector.fresh {
			append(&out, id)
			append(&frontier, id)
		}
	}
	return out
}

@(private = "file")
Closure_State :: struct {
	seen:  ^map[store.Term_ID]bool,
	fresh: [dynamic]store.Term_ID,
}

@(private = "file")
collect_id :: proc(data: rawptr, id: store.Term_ID) -> bool {
	state := cast(^Closure_State)data
	if state.seen[id] {
		return true
	}
	state.seen[id] = true
	append(&state.fresh, id)
	return true
}
