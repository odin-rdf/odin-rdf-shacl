package shacl

import rdf "rdf:rdf"

// Errors for ill-formed shapes.
//
// The family's error style comes from its parsers, where an error carries a
// byte offset, a line, and a column. **That does not transfer here, and the
// difference is not cosmetic.** A shapes graph reaches this package as triples
// in a store: the source text is long gone, and for a graph built
// programmatically it never existed. There is no position to carry.
//
// The equivalent precision for graph-sourced input is graph-shaped — name the
// shape node, name the parameter at fault, and say which rule was violated.
// Everything else about the family's convention is kept: a flat `Error_Kind`
// enum, no message string in the struct, and a static allocation-free
// `error_message` whose text ends with the spec section in parentheses.
//
// A caller that wants text positions wants them from the *parse* that produced
// the graph, which is odin-rdf-parser's job and already does it.

// Error_Kind is what is wrong with a shapes graph. Flat rather than nested,
// per the family's convention, so a caller can switch on it exhaustively.
Error_Kind :: enum {
	None,
	Path_Missing, // a property shape with no sh:path
	Path_Multiple, // more than one sh:path on one shape
	Path_Ill_Formed, // an sh:path value that is not a well-formed path
	Path_List_Ill_Formed, // a sequence or alternative whose RDF list is broken
	Path_List_Too_Short, // sh:alternativePath with fewer than two members
	Node_Kind_Unknown, // an sh:nodeKind that is not one of the six
	Count_Not_Integer, // sh:minCount / sh:maxCount whose value is not an integer
	Count_Negative, // a negative cardinality
	Severity_Not_IRI, // an sh:severity whose value is not an IRI
	Deactivated_Not_Boolean, // sh:deactivated whose value is not a boolean
	In_Not_A_List, // sh:in whose value is not an RDF list
	Shape_Expected, // a value where a shape was required
}

// error_message returns a static description of kind. Allocation-free, and
// the text ends with the SHACL section that fixes the rule — section numbers
// are quoted because the SHACL Recommendation is stable, unlike a working
// draft's numbering.
error_message :: proc(kind: Error_Kind) -> string {
	switch kind {
	case .None:
		return "no error"
	case .Path_Missing:
		return "property shape has no sh:path (§2.1.2)"
	case .Path_Multiple:
		return "shape has more than one sh:path (§2.1.2)"
	case .Path_Ill_Formed:
		return "sh:path value is not a well-formed property path (§2.3.1)"
	case .Path_List_Ill_Formed:
		return "path list is not a well-formed RDF list (§2.3.1)"
	case .Path_List_Too_Short:
		return "sh:alternativePath needs at least two members (§2.3.1.4)"
	case .Node_Kind_Unknown:
		return "sh:nodeKind is not one of the six node kinds (§4.4.2)"
	case .Count_Not_Integer:
		return "cardinality parameter is not an xsd:integer (§4.2)"
	case .Count_Negative:
		return "cardinality parameter is negative (§4.2)"
	case .Severity_Not_IRI:
		return "sh:severity value is not an IRI (§2.1.4)"
	case .Deactivated_Not_Boolean:
		return "sh:deactivated is not an xsd:boolean (§2.1.1.4)"
	case .In_Not_A_List:
		return "sh:in value is not an RDF list (§4.6.1)"
	case .Shape_Expected:
		return "value must be a shape, an IRI or a blank node (§2.1.1)"
	}
	return "unknown error"
}

// Error locates a fault in the shapes graph.
//
// `shape` is the offending shape node and `parameter` the predicate at fault;
// either may be nil where the fault is not attributable to one. Both borrow
// from the compiling model's term table and stay valid as long as it does —
// on a failed compile the model is still returned, precisely so the error
// remains readable.
Error :: struct {
	kind:      Error_Kind,
	shape:     rdf.Term,
	parameter: rdf.Term,
}
