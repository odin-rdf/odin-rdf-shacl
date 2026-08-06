package shacl

import rdf "rdf:rdf"
import store "store:store"

// Property-path compilation (SHACL §2.3.1).
//
// Paths are recursive structures — a sequence of alternatives of inverses —
// and the compiler may not recurse, so the descent is an explicit stack of
// frames. Each frame holds the operands still to visit and the child indices
// gathered so far; a frame is emitted as a Path_Node when its operands run
// out, and its index is appended to its parent's children.
//
// The same constraint the model's flat representation answers to
// (SHACL-A-0001 decision 4), applied to the compiler rather than the
// evaluator. Evaluation to value nodes is SHACL-T-0004; this produces only the
// structure.

@(private = "file")
Path_Frame :: struct {
	kind:     Path_Kind,
	operands: [dynamic]store.Term_ID,
	next:     int,
	children: [dynamic]int,
}

// compile_path compiles the path rooted at `root_id` and returns its index in
// s.paths.
@(private)
compile_path :: proc(
	s: ^Shapes,
	r: Reader($D, $It),
	root_id: store.Term_ID,
	shape_node: rdf.Term,
	load: Term_Loader,
	load_data: rawptr,
	v: ^Vocab,
	$MATCH: proc(dataset: ^D, pattern: store.Match_Pattern) -> It,
	$NEXT: proc(it: ^It) -> (store.Encoded_Quad, bool),
	$DESTROY: proc(it: ^It),
) -> (
	root: int,
	err: Error,
) {
	stack: [dynamic]Path_Frame
	defer {
		for &f in stack {
			delete(f.operands)
			delete(f.children)
		}
		delete(stack)
	}

	ill_formed := Error{.Path_Ill_Formed, shape_node, intern(&s.terms, rdf.IRI(PATH))}

	// A bare IRI is a predicate path and needs no frame.
	if store.id_kind(root_id) == .IRI {
		return emit_path(s, .Predicate, materialize_term(s, load, load_data, root_id), nil), Error{}
	}
	if store.id_kind(root_id) == .Literal {
		return -1, ill_formed
	}

	kind, operands, ok := classify_path(r, root_id, v, MATCH, NEXT, DESTROY)
	if !ok {
		delete(operands)
		return -1, ill_formed
	}
	if bad := path_arity_error(kind, len(operands)); bad != .None {
		delete(operands)
		return -1, Error{bad, shape_node, intern(&s.terms, rdf.IRI(PATH))}
	}
	append(&stack, Path_Frame{kind = kind, operands = operands})

	result := -1
	for len(stack) > 0 {
		top := &stack[len(stack) - 1]

		if top.next < len(top.operands) {
			child_id := top.operands[top.next]
			top.next += 1

			if store.id_kind(child_id) == .IRI {
				index := emit_path(s, .Predicate, materialize_term(s, load, load_data, child_id), nil)
				append(&top.children, index)
				continue
			}
			if store.id_kind(child_id) == .Literal {
				return -1, ill_formed
			}

			child_kind, child_operands, child_ok := classify_path(r, child_id, v, MATCH, NEXT, DESTROY)
			if !child_ok {
				delete(child_operands)
				return -1, ill_formed
			}
			if bad := path_arity_error(child_kind, len(child_operands)); bad != .None {
				delete(child_operands)
				return -1, Error{bad, shape_node, intern(&s.terms, rdf.IRI(PATH))}
			}
			append(&stack, Path_Frame{kind = child_kind, operands = child_operands})
			continue
		}

		// Operands exhausted: emit this frame and hand its index up.
		index := emit_path(s, top.kind, nil, top.children[:])
		delete(top.operands)
		delete(top.children)
		pop(&stack)
		if len(stack) > 0 {
			parent := &stack[len(stack) - 1]
			append(&parent.children, index)
		} else {
			result = index
		}
	}
	return result, Error{}
}

// classify_path decides what a non-IRI path node is and returns its operands.
// Flat: it issues queries and calls list_items, but nothing calls it back, so
// it cannot participate in an instantiation cycle.
@(private = "file")
classify_path :: proc(
	r: Reader($D, $It),
	node: store.Term_ID,
	v: ^Vocab,
	$MATCH: proc(dataset: ^D, pattern: store.Match_Pattern) -> It,
	$NEXT: proc(it: ^It) -> (store.Encoded_Quad, bool),
	$DESTROY: proc(it: ^It),
) -> (
	kind: Path_Kind,
	operands: [dynamic]store.Term_ID,
	ok: bool,
) {
	// The single-operand forms.
	single := [4]struct {
		iri:  string,
		kind: Path_Kind,
	} {
		{INVERSE_PATH, .Inverse},
		{ZERO_OR_MORE_PATH, .Zero_Or_More},
		{ONE_OR_MORE_PATH, .One_Or_More},
		{ZERO_OR_ONE_PATH, .Zero_Or_One},
	}
	for entry in single {
		if !v.found[entry.iri] {
			continue
		}
		if object, found := first_object(r, node, v.ids[entry.iri], MATCH, NEXT, DESTROY); found {
			append(&operands, object)
			return entry.kind, operands, true
		}
	}

	// sh:alternativePath takes an RDF list.
	if v.found[ALTERNATIVE_PATH] {
		if head, found := first_object(r, node, v.ids[ALTERNATIVE_PATH], MATCH, NEXT, DESTROY); found {
			items, list_ok := list_items(r, head, MATCH, NEXT, DESTROY)
			if !list_ok {
				delete(items)
				return .Alternative, operands, false
			}
			delete(operands)
			return .Alternative, items, true
		}
	}

	// Anything else must be a sequence path, which is a bare RDF list.
	items, list_ok := list_items(r, node, MATCH, NEXT, DESTROY)
	if !list_ok {
		delete(items)
		return .Sequence, operands, false
	}
	delete(operands)
	return .Sequence, items, true
}

// emit_path appends a node and returns its index. Children are copied into
// the model's flat child array here, which is the only place a span is made.
@(private)
emit_path :: proc(s: ^Shapes, kind: Path_Kind, predicate: rdf.Term, children: []int) -> int {
	start := len(s.path_children)
	for c in children {
		append(&s.path_children, c)
	}
	append(&s.paths, Path_Node{kind = kind, predicate = predicate, children = Span{start, len(children)}})
	return len(s.paths) - 1
}

// path_arity_error enforces the operand counts the spec fixes. Sequence and
// alternative paths need at least two members; the rest take exactly one.
@(private = "file")
path_arity_error :: proc(kind: Path_Kind, operands: int) -> Error_Kind {
	switch kind {
	case .Predicate:
		return .None
	case .Sequence, .Alternative:
		if operands < 2 {
			return .Path_List_Too_Short
		}
	case .Inverse, .Zero_Or_More, .One_Or_More, .Zero_Or_One:
		if operands != 1 {
			return .Path_Ill_Formed
		}
	}
	return .None
}
