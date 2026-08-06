package shacl

import "base:runtime"

import rdf "rdf:rdf"

// The compiled shapes model (SHACL-A-0001).
//
// Everything is a flat array with children named by index, and every walk is
// an explicit stack. That is forced rather than stylistic: SPARQL-T-0011
// established that a self-referencing parametric struct, or a generic
// procedure over `$`-procedure constants that calls itself, sends the Odin
// compiler (dev-2026-07) into unbounded instantiation — it hangs rather than
// failing. SHACL's evaluator is naturally recursive where SPARQL's operator
// tree was not, so the shape that avoids the hang is adopted from the first
// line here rather than discovered at `sh:node`.
//
// The model holds `rdf.Term` values, never `Term_ID`s: the shapes graph and
// the data graph may be different stores with different dictionaries, so an
// ID from the shapes store means nothing against the data store. Binding to
// the data store's IDs happens once at validation setup.
//
// **The model owns every term it holds.** It interns them at compile time and
// frees them at `shapes_destroy`, so the store a shapes graph was compiled
// from may be destroyed immediately afterwards. This is a deliberate
// exception to the family's borrow-by-default discipline (RDF-A-0001), and
// the reason is that the two backends disagree: memstore's `lookup_term`
// borrows the dictionary's storage while kvstore's allocates from the
// database's bytes. Owning removes a lifetime rule that would otherwise be
// backend-dependent and part of the public contract. Shapes graphs are small
// and bounded, so the cost is a copy of a handful of terms, once.

// Span names a contiguous range in one of the model's flat arrays. Children
// are ranges rather than pointers for the reason above.
Span :: struct {
	start: int,
	count: int,
}

Shape_Kind :: enum u8 {
	Node,
	Property,
}

// Severity is `sh:severity`, defaulting to `sh:Violation` (SHACL §2.1.4).
Severity :: enum u8 {
	Violation,
	Warning,
	Info,
}

Target_Kind :: enum u8 {
	Node, // sh:targetNode
	Class, // sh:targetClass
	Subjects_Of, // sh:targetSubjectsOf
	Objects_Of, // sh:targetObjectsOf
	Implicit_Class, // a shape that is also an rdfs:Class (§2.1.3.3)
}

Target :: struct {
	kind: Target_Kind,
	// The class or predicate the target names; for Implicit_Class this is
	// the shape node itself, so target resolution does not have to special-
	// case it.
	term: rdf.Term,
}

Path_Kind :: enum u8 {
	Predicate, // a bare IRI
	Inverse, // sh:inversePath
	Sequence, // an RDF list of paths
	Alternative, // sh:alternativePath, an RDF list of paths
	Zero_Or_More, // sh:zeroOrMorePath
	One_Or_More, // sh:oneOrMorePath
	Zero_Or_One, // sh:zeroOrOnePath
}

// Path_Node is one node of a compiled property path. `predicate` is set for
// Predicate; every other kind names its operands through `children`, a range
// into Shapes.path_children whose entries are indices back into Shapes.paths.
//
// Compiled here (SHACL-T-0003); evaluated to value nodes in SHACL-T-0004.
Path_Node :: struct {
	kind:      Path_Kind,
	predicate: rdf.Term,
	children:  Span,
}

// The constraint components the spine implements. The catalogue initiative
// extends this enum; the dispatch seam is built so that adding a component
// means adding a case and its parameters, not touching the evaluator.
//
// Seven rather than the five SHACL-I-0001 first named: SHACL-T-0002 measured
// what the exit-criteria suite directories actually exercise and found
// `sh:in` and `sh:hasValue` among them.
Constraint_Kind :: enum u8 {
	Min_Count,
	Max_Count,
	Class,
	Datatype,
	Node_Kind,
	Has_Value,
	In,
}

// Node_Kind is `sh:nodeKind` (§4.4.2), as a set of the three primitive kinds
// so the six spec values are one representation.
Node_Kind :: distinct bit_set[Node_Kind_Bit;u8]

Node_Kind_Bit :: enum u8 {
	IRI,
	Blank_Node,
	Literal,
}

NODE_KIND_IRI :: Node_Kind{.IRI}
NODE_KIND_BLANK_NODE :: Node_Kind{.Blank_Node}
NODE_KIND_LITERAL :: Node_Kind{.Literal}
NODE_KIND_BLANK_NODE_OR_IRI :: Node_Kind{.Blank_Node, .IRI}
NODE_KIND_BLANK_NODE_OR_LITERAL :: Node_Kind{.Blank_Node, .Literal}
NODE_KIND_IRI_OR_LITERAL :: Node_Kind{.IRI, .Literal}

// Constraint is one constraint component with its parameter. Which field
// carries the parameter depends on kind: `count` for the cardinality
// components, `term` for Class/Datatype/Has_Value, `node_kind` for Node_Kind,
// and `values` — a range into Shapes.values — for In.
Constraint :: struct {
	kind:      Constraint_Kind,
	count:     int,
	term:      rdf.Term,
	node_kind: Node_Kind,
	values:    Span,
}

// Message is one `sh:message`. A shape may carry several, typically one per
// language, so they are a range rather than a single term.
Message :: struct {
	text:     string,
	language: string,
}

// Shape is one compiled node shape or property shape.
//
// `path` indexes Shapes.paths and is -1 for a node shape — a property shape
// always has exactly one path, and a node shape never has one.
Shape :: struct {
	node:        rdf.Term, // the shape node itself: an IRI or a blank node
	kind:        Shape_Kind,
	path:        int,
	deactivated: bool,
	severity:    Severity,
	targets:     Span, // into Shapes.targets
	constraints: Span, // into Shapes.constraints
	properties:  Span, // into Shapes.shape_children: indices into Shapes.shapes
	messages:    Span, // into Shapes.messages
}

// Shapes is a compiled shapes graph: the model, and the storage every part of
// it points into.
Shapes :: struct {
	shapes:         [dynamic]Shape,
	targets:        [dynamic]Target,
	constraints:    [dynamic]Constraint,
	paths:          [dynamic]Path_Node,
	messages:       [dynamic]Message,

	// Child index arrays. `shape_children` holds indices into `shapes`
	// (a shape's sh:property values); `path_children` holds indices into
	// `paths` (a path node's operands); `values` holds terms (sh:in).
	shape_children: [dynamic]int,
	path_children:  [dynamic]int,
	values:         [dynamic]rdf.Term,

	// `roots` holds indices into `shapes` for the shapes that carry at least
	// one target, which is where validation starts.
	roots:          [dynamic]int,

	// Everything the model owns. Terms and message strings live here, and
	// every rdf.Term above borrows from it.
	terms:          Term_Table,
	allocator:      runtime.Allocator,
}

shapes_destroy :: proc(s: ^Shapes) {
	delete(s.shapes)
	delete(s.targets)
	delete(s.constraints)
	delete(s.paths)
	delete(s.messages)
	delete(s.shape_children)
	delete(s.path_children)
	delete(s.values)
	delete(s.roots)
	term_table_destroy(&s.terms)
	s^ = {}
}

// shape_properties returns the indices of a shape's property shapes.
shape_properties :: proc(s: ^Shapes, sh: Shape) -> []int {
	return s.shape_children[sh.properties.start:][:sh.properties.count]
}

// shape_targets returns a shape's target declarations.
shape_targets :: proc(s: ^Shapes, sh: Shape) -> []Target {
	return s.targets[sh.targets.start:][:sh.targets.count]
}

// shape_constraints returns a shape's constraint components.
shape_constraints :: proc(s: ^Shapes, sh: Shape) -> []Constraint {
	return s.constraints[sh.constraints.start:][:sh.constraints.count]
}

// shape_messages returns a shape's declared sh:message values.
shape_messages :: proc(s: ^Shapes, sh: Shape) -> []Message {
	return s.messages[sh.messages.start:][:sh.messages.count]
}

// path_operands returns the operand path indices of a compound path node.
path_operands :: proc(s: ^Shapes, p: Path_Node) -> []int {
	return s.path_children[p.children.start:][:p.children.count]
}

// constraint_values returns the member terms of an sh:in constraint.
constraint_values :: proc(s: ^Shapes, c: Constraint) -> []rdf.Term {
	return s.values[c.values.start:][:c.values.count]
}
