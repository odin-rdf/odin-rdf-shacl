package shacl

import "core:strings"

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

	// The components whose parameter is a single term. The four value-range
	// bounds join them unchanged: what differs is how the term is *compared*,
	// which is the evaluator's business and not this table's — SHACL-T-0013
	// added four lines here and nothing else in this file.
	terms := [7]struct {
		iri:  string,
		kind: Constraint_Kind,
	} {
		{CLASS, .Class},
		{DATATYPE, .Datatype},
		{HAS_VALUE, .Has_Value},
		{MIN_INCLUSIVE, .Min_Inclusive},
		{MAX_INCLUSIVE, .Max_Inclusive},
		{MIN_EXCLUSIVE, .Min_Exclusive},
		{MAX_EXCLUSIVE, .Max_Exclusive},
	}
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

// The `sh:`-namespace predicates this engine acts on. Everything the compiler
// reads off a shape node belongs here — the shape's own structure, its targets,
// and the constraint components implemented above — and a component's entry
// goes in **when the component starts validating**, not when the compiler first
// learns to read it.
//
// That distinction is the whole point of the list, and `sh:node` is the case
// that shows it: SHACL-T-0010 makes its value a shape, so discovery recognises
// it, but nothing validates against it until SHACL-T-0018. It is therefore
// *not* implemented, and a shapes graph using it says so through
// `shapes_ignored`. The six shape-expecting parameters move here as the tasks
// that enforce them land.
@(private)
IMPLEMENTED_PARAMETERS := []string {
	// The shape itself (§2.1).
	PROPERTY,
	PATH,
	DEACTIVATED,
	MESSAGE,
	SEVERITY,
	// Target declarations (§2.1.3).
	TARGET_NODE,
	TARGET_CLASS,
	TARGET_SUBJECTS_OF,
	TARGET_OBJECTS_OF,
	// The constraint components of SHACL-T-0007's minimal set (§4).
	MIN_COUNT,
	MAX_COUNT,
	CLASS,
	DATATYPE,
	NODE_KIND,
	HAS_VALUE,
	IN,
	// The value-range components (SHACL-T-0013).
	MIN_INCLUSIVE,
	MAX_INCLUSIVE,
	MIN_EXCLUSIVE,
	MAX_EXCLUSIVE,
}

// The spec's non-validating annotation properties: recognised, deliberately
// inert, and never reported as ignored. See the constants in vocab.odin for why
// this list exists separately rather than being folded into the one above.
@(private)
INERT_PARAMETERS := []string{NAME, DESCRIPTION, ORDER, GROUP, DEFAULT_VALUE}

// record_ignored_parameters adds every `sh:`-namespace predicate on this shape
// node that the engine neither implements nor recognises as inert to the
// model's ignored list, deduplicated.
//
// It reads the shape node's predicates once, which is one extra store query per
// shape at compile time — compilation runs once over a small graph, and the
// alternative (threading a "did anything go unread" flag through every read
// above) would put the bookkeeping in the seam every future component has to
// edit.
//
// Non-`sh:` predicates are not recorded: RDF is open, a shape node routinely
// carries `rdf:type`, `rdfs:label`, and whatever else the document says about
// it, and none of that is evidence of a missing component.
@(private)
record_ignored_parameters :: proc(
	s: ^Shapes,
	r: Reader($D, $It),
	shape_id: store.Term_ID,
	load: Term_Loader,
	load_data: rawptr,
	$MATCH: proc(dataset: ^D, pattern: store.Match_Pattern) -> It,
	$NEXT: proc(it: ^It) -> (store.Encoded_Quad, bool),
	$DESTROY: proc(it: ^It),
) {
	preds := predicates_of(r, shape_id, MATCH, NEXT, DESTROY)
	defer delete(preds)

	for id in preds {
		term, owned := load(load_data, id, s.allocator)
		if parameter_is_ignored(term) {
			recorded := intern(&s.terms, term)
			seen := false
			for existing in s.ignored {
				if existing == recorded {
					seen = true
					break
				}
			}
			if !seen {
				append(&s.ignored, recorded)
			}
		}
		if owned {
			rdf.destroy_term(term, s.allocator)
		}
	}
}

// parameter_is_ignored decides whether one predicate belongs in the record: a
// `sh:`-namespace IRI that is neither implemented nor inert. Ordinary and
// non-generic, like every other decision the compiler makes without touching
// the store — and, incidentally, the only place the namespace test lives.
@(private = "file")
parameter_is_ignored :: proc(term: rdf.Term) -> bool {
	iri, is_iri := term.(rdf.IRI)
	if !is_iri || !strings.has_prefix(string(iri), NS) {
		return false
	}
	for known in IMPLEMENTED_PARAMETERS {
		if known == string(iri) {
			return false
		}
	}
	for known in INERT_PARAMETERS {
		if known == string(iri) {
			return false
		}
	}
	return true
}
