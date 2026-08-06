package shacl

import rdf "rdf:rdf"
import store "store:store"

// Constraint-parameter compilation.
//
// Seven components: the five SHACL-I-0001 named, plus `sh:in` and
// `sh:hasValue`, which SHACL-T-0002 found the exit-criteria suite directories
// exercise. The catalogue initiative adds the rest, and this procedure is the
// seam it extends — a new component is a new case here and a new
// Constraint_Kind, with nothing in the evaluator to touch.
//
// Flat and generic, like the query helpers: it issues store reads but calls
// no generic procedure that could call it back, and never itself.
@(private)
compile_constraints :: proc(
	s: ^Shapes,
	r: Reader($D, $It),
	shape_id: store.Term_ID,
	shape_node: rdf.Term,
	load: Term_Loader,
	load_data: rawptr,
	v: ^Vocab,
	$MATCH: proc(dataset: ^D, pattern: store.Match_Pattern) -> It,
	$NEXT: proc(it: ^It) -> (store.Encoded_Quad, bool),
	$DESTROY: proc(it: ^It),
) -> Error {
	// The cardinality components.
	counts := [2]struct {
		iri:  string,
		kind: Constraint_Kind,
	}{{MIN_COUNT, .Min_Count}, {MAX_COUNT, .Max_Count}}
	for entry in counts {
		if !v.found[entry.iri] {
			continue
		}
		vals := objects_of(r, shape_id, v.ids[entry.iri], MATCH, NEXT, DESTROY)
		defer delete(vals)
		for id in vals {
			term := materialize_term(s, load, load_data, id)
			n, ok := integer_value(term)
			if !ok {
				return Error{.Count_Not_Integer, shape_node, intern(&s.terms, rdf.IRI(entry.iri))}
			}
			if n < 0 {
				return Error{.Count_Negative, shape_node, intern(&s.terms, rdf.IRI(entry.iri))}
			}
			append(&s.constraints, Constraint{kind = entry.kind, count = n})
		}
	}

	// The components whose parameter is a single term.
	terms := [3]struct {
		iri:  string,
		kind: Constraint_Kind,
	}{{CLASS, .Class}, {DATATYPE, .Datatype}, {HAS_VALUE, .Has_Value}}
	for entry in terms {
		if !v.found[entry.iri] {
			continue
		}
		vals := objects_of(r, shape_id, v.ids[entry.iri], MATCH, NEXT, DESTROY)
		defer delete(vals)
		for id in vals {
			append(
				&s.constraints,
				Constraint{kind = entry.kind, term = materialize_term(s, load, load_data, id)},
			)
		}
	}

	// sh:nodeKind.
	if v.found[NODE_KIND] {
		vals := objects_of(r, shape_id, v.ids[NODE_KIND], MATCH, NEXT, DESTROY)
		defer delete(vals)
		for id in vals {
			term := materialize_term(s, load, load_data, id)
			nk, ok := node_kind_value(term)
			if !ok {
				return Error{.Node_Kind_Unknown, shape_node, intern(&s.terms, rdf.IRI(NODE_KIND))}
			}
			append(&s.constraints, Constraint{kind = .Node_Kind, node_kind = nk})
		}
	}

	// sh:in takes an RDF list of terms. The members go into the model's flat
	// value array and are named by span, like every other child relation.
	if v.found[IN] {
		vals := objects_of(r, shape_id, v.ids[IN], MATCH, NEXT, DESTROY)
		defer delete(vals)
		for head in vals {
			items, ok := list_items(r, head, MATCH, NEXT, DESTROY)
			defer delete(items)
			if !ok {
				return Error{.In_Not_A_List, shape_node, intern(&s.terms, rdf.IRI(IN))}
			}
			start := len(s.values)
			for id in items {
				append(&s.values, materialize_term(s, load, load_data, id))
			}
			append(&s.constraints, Constraint{kind = .In, values = Span{start, len(s.values) - start}})
		}
	}

	return Error{}
}
