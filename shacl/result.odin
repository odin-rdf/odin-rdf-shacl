package shacl

import rdf "rdf:rdf"

// Validation results.
//
// **Results stream.** The validator hands each one to a visitor as it is
// found and keeps no violation set, so memory stays flat exactly when the
// data is worst. That is not only frugality: it is what admits early exit —
// a caller asking "does this graph conform?" returns false from the visitor
// at the first violation, and validation stops rather than finishing a
// traversal whose answer is already known.
//
// **A Result borrows.** It names nodes by `Term_ID` and shapes and paths by
// index into the compiled model; it owns nothing and allocates nothing. It is
// valid for the duration of the visitor call, and a caller that wants to keep
// one must copy what it needs — materialise the terms, or fold it into a
// report. This is stated rather than discovered, because the alternative
// (results owning materialised terms) would allocate on the hottest path in
// the engine to serve the case that already has `Report`.

// Result is one `sh:ValidationResult` (SHACL §3.1), before it is a graph.
//
// `path` and `value` are the two that are frequently absent: a node shape's
// result has no path, and a constraint that failed against the focus node
// itself — `sh:minCount`, say — has no single value to blame.
Result :: struct {
	focus:              Focus_Node,
	value:              Node_Ref,
	has_value:          bool,
	path:               int, // index into Shapes.paths, or -1

	// The result path when it is **not** the shape's, which happens for exactly
	// one component. `sh:closed` reports the predicate of the triple it objects
	// to (§4.8.1), and that predicate is a term of the *data* graph — not a
	// compiled path, so `path` cannot name it, and `node/closed-001` puts it on a
	// node shape whose `path` is -1 and still expects an `sh:resultPath`.
	//
	// When `has_path_predicate` is true this is the `sh:resultPath` and `path` is
	// -1; the two are never both set.
	path_predicate:     Node_Ref,
	has_path_predicate: bool,
	shape:              int, // index into Shapes.shapes
	component:          Constraint_Kind,

	// The shape's `sh:severity`, borrowed from the compiled model's term table
	// and valid as long as the model is. Any IRI, not one of three — see
	// `Shape.severity`.
	severity:           rdf.Term,
}

// Result_Visitor receives each result. Returning false stops validation.
Result_Visitor :: #type proc(data: rawptr, result: Result) -> bool

// component_iri is the `sh:sourceConstraintComponent` a result names.
component_iri :: proc(kind: Constraint_Kind) -> string {
	switch kind {
	case .Min_Count:
		return MIN_COUNT_COMPONENT
	case .Max_Count:
		return MAX_COUNT_COMPONENT
	case .Class:
		return CLASS_COMPONENT
	case .Datatype:
		return DATATYPE_COMPONENT
	case .Node_Kind:
		return NODE_KIND_COMPONENT
	case .Has_Value:
		return HAS_VALUE_COMPONENT
	case .In:
		return IN_COMPONENT
	case .Min_Inclusive:
		return MIN_INCLUSIVE_COMPONENT
	case .Max_Inclusive:
		return MAX_INCLUSIVE_COMPONENT
	case .Min_Exclusive:
		return MIN_EXCLUSIVE_COMPONENT
	case .Max_Exclusive:
		return MAX_EXCLUSIVE_COMPONENT
	case .Min_Length:
		return MIN_LENGTH_COMPONENT
	case .Max_Length:
		return MAX_LENGTH_COMPONENT
	// `sh:flags` has no component of its own: it modifies the pattern, and a
	// result from the pair names the pattern's.
	case .Pattern:
		return PATTERN_COMPONENT
	case .Language_In:
		return LANGUAGE_IN_COMPONENT
	case .Unique_Lang:
		return UNIQUE_LANG_COMPONENT
	case .Equals:
		return EQUALS_COMPONENT
	case .Disjoint:
		return DISJOINT_COMPONENT
	case .Less_Than:
		return LESS_THAN_COMPONENT
	case .Less_Than_Or_Equals:
		return LESS_THAN_OR_EQUALS_COMPONENT
	// `sh:ignoredProperties` has no component of its own, like `sh:flags`: it
	// widens what `sh:closed` allows, and a result from the pair names this.
	case .Closed:
		return CLOSED_COMPONENT
	case .And:
		return AND_COMPONENT
	case .Or:
		return OR_COMPONENT
	case .Not:
		return NOT_COMPONENT
	case .Xone:
		return XONE_COMPONENT
	case .Node:
		return NODE_COMPONENT
	// `sh:qualifiedValueShape` and `sh:qualifiedValueShapesDisjoint` name no
	// component of their own: the two counts are the components, and a result
	// from the family names whichever count it broke.
	case .Qualified_Min_Count:
		return QUALIFIED_MIN_COUNT_COMPONENT
	case .Qualified_Max_Count:
		return QUALIFIED_MAX_COUNT_COMPONENT
	}
	return ""
}

// severity_is reports whether a result's severity is a given vocabulary IRI —
// `severity_is(result.severity, shacl.WARNING)`. A convenience for callers
// triaging results, and the reason `Severity` is not an enum: the set is open.
severity_is :: proc(severity: rdf.Term, iri: string) -> bool {
	got, is_iri := severity.(rdf.IRI)
	return is_iri && string(got) == iri
}

// result_message_terms is what a result's messages are, per the shape that
// produced it — **only what the shape declared**.
//
// No processor-generated message is ever emitted into a report graph
// (SHACL-I-0001). That keeps suite comparison exact blank-node isomorphism
// with no fuzzy-match policy anywhere in the harness, and it costs nothing,
// because a caller wanting human-readable explanation has the whole Result
// and the model to describe it from.
result_messages :: proc(s: ^Shapes, result: Result) -> []Message {
	return shape_messages(s, s.shapes[result.shape])
}

// result_source_shape is the shape node a result blames.
result_source_shape :: proc(s: ^Shapes, result: Result) -> rdf.Term {
	return s.shapes[result.shape].node
}

// Conformance is the smallest useful result consumer: it answers "does this
// graph conform?" and nothing else.
//
// It exists here rather than in a caller because it is what early exit is
// *for*. Its visitor returns false at the **first result of any severity**,
// which stops validation where it stands — no further focus nodes resolved, no
// further paths walked. On data with many violations that is the difference
// between reading one triple and reading the graph, and at ~200 processes per
// machine it is the difference worth having.
//
// **Severity does not enter into it** (§3.1): `sh:conforms` is true if and only
// if there are no results, whatever severity they carry. This is worth stating
// because the opposite reading is tempting — a warning sounds like it should
// not break conformance — and the suite settles it: `misc/severity-001`
// produces exactly one `sh:Warning` result and expects `sh:conforms false`.
Conformance :: struct {
	conforms: bool,
}

// conformance_init starts a Conformance at "conforms", which is what an empty
// result stream means. It allocates nothing and needs no destroy.
conformance_init :: proc(c: ^Conformance) {
	c.conforms = true
}

// conformance_visitor is a Result_Visitor. Pass it with a ^Conformance as its
// data.
conformance_visitor :: proc(data: rawptr, result: Result) -> bool {
	c := cast(^Conformance)data
	c.conforms = false
	return false
}
