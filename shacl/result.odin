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
	focus:       Focus_Node,
	value:       Node_Ref,
	has_value:   bool,
	path:        int, // index into Shapes.paths, or -1
	shape:       int, // index into Shapes.shapes
	component:   Constraint_Kind,
	severity:    Severity,
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
	}
	return ""
}

// severity_iri is the `sh:resultSeverity` a result names.
severity_iri :: proc(severity: Severity) -> string {
	switch severity {
	case .Violation:
		return VIOLATION
	case .Warning:
		return WARNING
	case .Info:
		return INFO
	}
	return VIOLATION
}

// conforms reports whether a severity counts against conformance.
//
// Only `sh:Violation` does (§3.1.2): a report can carry warnings and
// informational results and still say `sh:conforms true`. That asymmetry is
// easy to miss and changes what an early-exit caller may stop on.
severity_breaks_conformance :: proc(severity: Severity) -> bool {
	return severity == .Violation
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
// *for*. Its visitor returns false at the first violation, which stops
// validation where it stands — no further focus nodes resolved, no further
// paths walked. On data with many violations that is the difference between
// reading one triple and reading the graph, and at ~200 processes per machine
// it is the difference worth having.
//
// Note it stops on `sh:Violation` only. A warning does not break conformance
// (§3.1.2), so stopping on one would both answer the wrong question and cut
// the traversal short.
Conformance :: struct {
	conforms: bool,
}

conformance_init :: proc(c: ^Conformance) {
	c.conforms = true
}

// conformance_visitor is a Result_Visitor. Pass it with a ^Conformance as its
// data.
conformance_visitor :: proc(data: rawptr, result: Result) -> bool {
	c := cast(^Conformance)data
	if severity_breaks_conformance(result.severity) {
		c.conforms = false
		return false
	}
	return true
}
