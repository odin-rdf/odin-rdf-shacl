package shacl

import "core:strconv"

import rdf "rdf:rdf"
import store "store:store"

// The compiler's reads of the shapes graph, and the pure value decoders that
// go with them.
//
// **Why a Reader struct rather than loose parameters.** A generic procedure
// can infer `$It` from a `$MATCH` constant it is passed directly, but it
// cannot then *forward* that constant to another generic procedure: the
// callee would be introducing `$It` in the return type of a procedure-typed
// parameter, and the compiler reports it cannot determine the complete type.
// Binding both `$D` and `$It` on an earlier value parameter fixes it, which is
// exactly why odin-rdf-sparql's helpers take `e: ^Exec($D, $It)` first. Reader
// is this repo's equivalent, and it carries the dataset, the graph, and the
// RDF-list vocabulary that nearly every read needs anyway.
//
// Every procedure here is **flat**: none calls another generic procedure and
// none calls itself, which is the discipline SPARQL-T-0011's compiler hang
// imposes. All the recursion lives in explicit worklists in `compile` and
// `compile_path`.
//
// Each read returns a fresh dynamic array the caller deletes. Materializing
// IDs into terms is the caller's job, because only the caller knows whether a
// result is being kept in the model or inspected and dropped.
@(private)
Reader :: struct($D: typeid, $It: typeid) {
	dataset:   ^D,
	graph:     store.Term_ID,
	first_id:  store.Term_ID,
	has_first: bool,
	rest_id:   store.Term_ID,
	has_rest:  bool,
	nil_id:    store.Term_ID,
	has_nil:   bool,
}

// objects_of returns the objects of (subject, predicate, *) in the graph.
@(private)
objects_of :: proc(
	r: Reader($D, $It),
	subject, predicate: store.Term_ID,
	$MATCH: proc(dataset: ^D, pattern: store.Match_Pattern) -> It,
	$NEXT: proc(it: ^It) -> (store.Encoded_Quad, bool),
	$DESTROY: proc(it: ^It),
) -> [dynamic]store.Term_ID {
	out: [dynamic]store.Term_ID
	it := MATCH(r.dataset, store.Match_Pattern{subject, predicate, store.WILDCARD, r.graph})
	defer DESTROY(&it)
	for {
		q, ok := NEXT(&it)
		if !ok {
			break
		}
		append(&out, q[store.QUAD_O])
	}
	return out
}

// first_object returns the single object of (subject, predicate, *), which is
// what every read of a functional parameter wants.
@(private)
first_object :: proc(
	r: Reader($D, $It),
	subject, predicate: store.Term_ID,
	$MATCH: proc(dataset: ^D, pattern: store.Match_Pattern) -> It,
	$NEXT: proc(it: ^It) -> (store.Encoded_Quad, bool),
	$DESTROY: proc(it: ^It),
) -> (
	object: store.Term_ID,
	found: bool,
) {
	it := MATCH(r.dataset, store.Match_Pattern{subject, predicate, store.WILDCARD, r.graph})
	defer DESTROY(&it)
	q, ok := NEXT(&it)
	if !ok {
		return store.WILDCARD, false
	}
	return q[store.QUAD_O], true
}

// subjects_matching returns the subjects of (*, predicate, object).
@(private)
subjects_matching :: proc(
	r: Reader($D, $It),
	predicate, object: store.Term_ID,
	$MATCH: proc(dataset: ^D, pattern: store.Match_Pattern) -> It,
	$NEXT: proc(it: ^It) -> (store.Encoded_Quad, bool),
	$DESTROY: proc(it: ^It),
) -> [dynamic]store.Term_ID {
	out: [dynamic]store.Term_ID
	it := MATCH(r.dataset, store.Match_Pattern{store.WILDCARD, predicate, object, r.graph})
	defer DESTROY(&it)
	for {
		q, ok := NEXT(&it)
		if !ok {
			break
		}
		append(&out, q[store.QUAD_S])
	}
	return out
}

// subjects_with_predicate returns the subjects of (*, predicate, *).
@(private)
subjects_with_predicate :: proc(
	r: Reader($D, $It),
	predicate: store.Term_ID,
	$MATCH: proc(dataset: ^D, pattern: store.Match_Pattern) -> It,
	$NEXT: proc(it: ^It) -> (store.Encoded_Quad, bool),
	$DESTROY: proc(it: ^It),
) -> [dynamic]store.Term_ID {
	out: [dynamic]store.Term_ID
	it := MATCH(r.dataset, store.Match_Pattern{store.WILDCARD, predicate, store.WILDCARD, r.graph})
	defer DESTROY(&it)
	for {
		q, ok := NEXT(&it)
		if !ok {
			break
		}
		append(&out, q[store.QUAD_S])
	}
	return out
}

// list_items walks an RDF list from head and returns its members in order.
// ok is false if the list is malformed — a cell with no rdf:first, or a chain
// that neither terminates at rdf:nil nor continues.
//
// The visited set is not defensive programming: an RDF list is a chain of
// blank nodes, and nothing stops a shapes graph from asserting a cycle, which
// would otherwise be an infinite loop inside compilation.
@(private)
list_items :: proc(
	r: Reader($D, $It),
	head: store.Term_ID,
	$MATCH: proc(dataset: ^D, pattern: store.Match_Pattern) -> It,
	$NEXT: proc(it: ^It) -> (store.Encoded_Quad, bool),
	$DESTROY: proc(it: ^It),
) -> (
	items: [dynamic]store.Term_ID,
	ok: bool,
) {
	if !r.has_first || !r.has_rest {
		return items, false
	}
	visited: map[store.Term_ID]bool
	defer delete(visited)

	cell := head
	for {
		if r.has_nil && cell == r.nil_id {
			return items, true
		}
		if visited[cell] {
			return items, false
		}
		visited[cell] = true

		member: store.Term_ID
		found_first := false
		{
			it := MATCH(r.dataset, store.Match_Pattern{cell, r.first_id, store.WILDCARD, r.graph})
			defer DESTROY(&it)
			if q, more := NEXT(&it); more {
				member = q[store.QUAD_O]
				found_first = true
			}
		}
		if !found_first {
			return items, false
		}
		append(&items, member)

		next_cell: store.Term_ID
		found_rest := false
		{
			it := MATCH(r.dataset, store.Match_Pattern{cell, r.rest_id, store.WILDCARD, r.graph})
			defer DESTROY(&it)
			if q, more := NEXT(&it); more {
				next_cell = q[store.QUAD_O]
				found_rest = true
			}
		}
		if !found_rest {
			return items, false
		}
		cell = next_cell
	}
}

// ---- Pure value decoders. No store, no allocation, no generics. ----------

// boolean_value reads an xsd:boolean literal. `sh:deactivated` takes
// "true"/"false"; "1"/"0" are accepted too, since xsd:boolean's lexical space
// admits them.
@(private)
boolean_value :: proc(term: rdf.Term) -> (value: bool, ok: bool) {
	lit, is_lit := term.(rdf.Literal)
	if !is_lit {
		return false, false
	}
	switch lit.lexical {
	case "true", "1":
		return true, true
	case "false", "0":
		return false, true
	}
	return false, false
}

// integer_value reads an xsd:integer literal. The lexical form is parsed
// rather than the datatype trusted: a cardinality written as a plain string
// is ill-formed and must be reported, not silently read as zero.
@(private)
integer_value :: proc(term: rdf.Term) -> (value: int, ok: bool) {
	lit, is_lit := term.(rdf.Literal)
	if !is_lit {
		return 0, false
	}
	n, parsed := strconv.parse_int(lit.lexical, 10)
	if !parsed {
		return 0, false
	}
	return n, true
}

@(private)
node_kind_value :: proc(term: rdf.Term) -> (value: Node_Kind, ok: bool) {
	iri, is_iri := term.(rdf.IRI)
	if !is_iri {
		return {}, false
	}
	switch string(iri) {
	case IRI_KIND:
		return NODE_KIND_IRI, true
	case BLANK_NODE_KIND:
		return NODE_KIND_BLANK_NODE, true
	case LITERAL_KIND:
		return NODE_KIND_LITERAL, true
	case BLANK_NODE_OR_IRI:
		return NODE_KIND_BLANK_NODE_OR_IRI, true
	case BLANK_NODE_OR_LITERAL:
		return NODE_KIND_BLANK_NODE_OR_LITERAL, true
	case IRI_OR_LITERAL:
		return NODE_KIND_IRI_OR_LITERAL, true
	}
	return {}, false
}
