package shacl

import "core:strconv"

import rdf "rdf:rdf"
import "record:record"

// The compiler's reads of the shapes graph, and the pure value decoders that
// go with them.
//
// Reader carries the session and the RDF-list vocabulary that nearly every
// read needs. It was a parametric struct threading compile-time `$MATCH`
// procedure constants when the backend was a seam; with odin-rdf-record bound
// directly (SHACL-I-0004) every helper is an ordinary procedure and the
// generic plumbing — and the compiler-hang discipline it required
// (SPARQL-T-0011) — is gone with it.
//
// Each read returns a fresh dynamic array the caller deletes. Materializing
// IDs into terms is the caller's job, because only the caller knows whether a
// result is being kept in the model or inspected and dropped.
@(private)
Reader :: struct {
	se:        Session,
	first_id:  u32,
	has_first: bool,
	rest_id:   u32,
	has_rest:  bool,
	nil_id:    u32,
	has_nil:   bool,
}

@(private)
reader_match :: proc(r: Reader, subject, predicate, object: u32) -> record.Scan {
	rng := record.snapshot_match(
		r.se.snap,
		record.Pattern{s = subject, p = predicate, o = object, g = r.se.graph},
	)
	return record.range_iter(rng, record.Filter{origin = .Any})
}

// objects_of returns the objects of (subject, predicate, *) in the graph.
@(private)
objects_of :: proc(r: Reader, subject, predicate: u32) -> [dynamic]u32 {
	out: [dynamic]u32
	sc := reader_match(r, subject, predicate, 0)
	for {
		id, ok := record.scan_next(&sc)
		if !ok {
			break
		}
		append(&out, record.snapshot_fact(r.se.snap, id).o)
	}
	return out
}

// first_object returns the single object of (subject, predicate, *), which is
// what every read of a functional parameter wants.
@(private)
first_object :: proc(r: Reader, subject, predicate: u32) -> (object: u32, found: bool) {
	sc := reader_match(r, subject, predicate, 0)
	id, ok := record.scan_next(&sc)
	if !ok {
		return 0, false
	}
	return record.snapshot_fact(r.se.snap, id).o, true
}

// predicates_of returns the predicates of (subject, *, *) in the graph, with
// duplicates: a predicate with three objects appears three times. The one
// caller — the ignored-parameter record — deduplicates as it interns, and
// filtering here would cost a set to save a handful of comparisons on a graph
// this small.
@(private)
predicates_of :: proc(r: Reader, subject: u32) -> [dynamic]u32 {
	out: [dynamic]u32
	sc := reader_match(r, subject, 0, 0)
	for {
		id, ok := record.scan_next(&sc)
		if !ok {
			break
		}
		append(&out, record.snapshot_fact(r.se.snap, id).p)
	}
	return out
}

// subjects_matching returns the subjects of (*, predicate, object).
@(private)
subjects_matching :: proc(r: Reader, predicate, object: u32) -> [dynamic]u32 {
	out: [dynamic]u32
	sc := reader_match(r, 0, predicate, object)
	for {
		id, ok := record.scan_next(&sc)
		if !ok {
			break
		}
		append(&out, record.snapshot_fact(r.se.snap, id).s)
	}
	return out
}

// subjects_with_predicate returns the subjects of (*, predicate, *).
@(private)
subjects_with_predicate :: proc(r: Reader, predicate: u32) -> [dynamic]u32 {
	out: [dynamic]u32
	sc := reader_match(r, 0, predicate, 0)
	for {
		id, ok := record.scan_next(&sc)
		if !ok {
			break
		}
		append(&out, record.snapshot_fact(r.se.snap, id).s)
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
list_items :: proc(r: Reader, head: u32) -> (items: [dynamic]u32, ok: bool) {
	if !r.has_first || !r.has_rest {
		return items, false
	}
	visited: map[u32]bool
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

		member, found_first := first_object(r, cell, r.first_id)
		if !found_first {
			return items, false
		}
		append(&items, member)

		next_cell, found_rest := first_object(r, cell, r.rest_id)
		if !found_rest {
			return items, false
		}
		cell = next_cell
	}
}

// ---- Pure value decoders. No store, no allocation. -----------------------

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
