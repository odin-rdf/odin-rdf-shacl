package shacl

import "base:runtime"

import "core:text/regex"

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

// Shape_Kind distinguishes the two kinds of shape (§2.1). The difference that
// matters downstream is the value nodes: a node shape's are its focus node, a
// property shape's are its path's result.
Shape_Kind :: enum u8 {
	Node,
	Property,
}

// Target_Kind is which target declaration produced a Target (§2.1.3).
Target_Kind :: enum u8 {
	Node, // sh:targetNode
	Class, // sh:targetClass
	Subjects_Of, // sh:targetSubjectsOf
	Objects_Of, // sh:targetObjectsOf
	Implicit_Class, // a shape that is also an rdfs:Class (§2.1.3.3)
}

// Target is one target declaration: how to find focus nodes, and the term it
// finds them by.
Target :: struct {
	kind: Target_Kind,
	// The class or predicate the target names; for Implicit_Class this is
	// the shape node itself, so target resolution does not have to special-
	// case it.
	term: rdf.Term,
}

// Path_Kind is the property-path grammar of §2.3.1, one case per form.
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
	// The value-range components (SHACL-T-0013). They carry `term` like
	// Class/Datatype/Has_Value do, and are the first components that compare it
	// by value rather than by term.
	Min_Inclusive,
	Max_Inclusive,
	Min_Exclusive,
	Max_Exclusive,
	// The string-based components (SHACL-T-0014). Pattern is the only one that
	// owns anything: its regular expression is compiled once here rather than
	// per value node.
	Min_Length,
	Max_Length,
	Pattern,
	Language_In,
	Unique_Lang,
	// The property-pair components (SHACL-T-0015). `term` is a predicate rather
	// than a value: these compare the shape's value nodes against the values of
	// that predicate at the same focus node.
	Equals,
	Disjoint,
	Less_Than,
	Less_Than_Or_Equals,
	// `sh:closed` (SHACL-T-0016). `values` holds the **allowed** predicates, and
	// it is the only constraint whose parameter is not read off its own shape
	// node alone: the set is `sh:ignoredProperties` together with the predicate
	// paths of the shape's `sh:property` children, so it cannot be filled until
	// those children are linked. See the closing pass in `compile`.
	Closed,
}

// Node_Kind is `sh:nodeKind` (§4.4.2), as a set of the three primitive kinds
// so the six spec values are one representation.
Node_Kind :: distinct bit_set[Node_Kind_Bit;u8]

// Node_Kind_Bit is one primitive node kind — the members of the Node_Kind set.
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
// carries the parameter depends on kind: `count` for the cardinality components
// and the two lengths, `term` for Class/Datatype/Has_Value and the four
// value-range bounds, `node_kind` for Node_Kind, `values` — a range into
// Shapes.values — for In, Language_In and Closed, and `pattern` for Pattern.
// The four property-pair components also use `term`, but it holds a *predicate*
// rather than something to compare against.
//
// `Unique_Lang` carries nothing at all. Its parameter is the boolean that
// switches it on, and a constraint that is switched off is simply not compiled,
// so by the time one exists there is nothing left to record. `Closed`'s boolean
// works the same way; what its `values` holds is the set the boolean makes
// meaningful, not the boolean.
//
// **`pattern` is the first thing a Constraint owns.** Every other field either
// borrows the model's term table or is a plain value; a compiled regular
// expression is an allocation, made once at compile time so that matching a
// value node costs no compilation, and freed by `shapes_destroy` with the
// model's own allocator.
Constraint :: struct {
	kind:      Constraint_Kind,
	count:     int,
	term:      rdf.Term,
	node_kind: Node_Kind,
	values:    Span,
	pattern:   regex.Regular_Expression,
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

	// `sh:severity` (§2.1.4). **Any IRI**, not one of three: the spec names
	// `sh:Violation`, `sh:Warning`, and `sh:Info` as the built-ins but does not
	// close the set, and the suite depends on it — `misc/severity-002` declares
	// `sh:severity ex:MySeverity` and expects it echoed into the report
	// unchanged. Defaults to `sh:Violation`, interned like every other term the
	// model holds.
	severity:    rdf.Term,
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
	// `paths` (a path node's operands); `values` holds terms (sh:in,
	// sh:languageIn, sh:closed's allowed predicates).
	shape_children: [dynamic]int,
	path_children:  [dynamic]int,
	values:         [dynamic]rdf.Term,

	// `roots` holds indices into `shapes` for the shapes that carry at least
	// one target, which is where validation starts.
	roots:          [dynamic]int,

	// `ignored` is every `sh:`-namespace predicate this compile saw on a shape
	// and does not implement, deduplicated and interned like every other term.
	// See `shapes_ignored` for what it is for.
	ignored:        [dynamic]rdf.Term,

	// Everything the model owns. Terms and message strings live here, and
	// every rdf.Term above borrows from it.
	terms:          Term_Table,
	allocator:      runtime.Allocator,
}

// shapes_destroy frees everything a compiled model owns, including every term
// it interned. Safe on a zero-valued or partly-compiled model, which matters:
// a failed compile still returns one, because the Error's terms borrow from
// its table.
shapes_destroy :: proc(s: ^Shapes) {
	// The compiled regular expressions, which are the one thing in the model
	// that is not a term or an index. A partly-compiled model may hold some, so
	// this runs on the failure path too.
	for c in s.constraints {
		if c.kind == .Pattern {
			regex.destroy(c.pattern, s.allocator)
		}
	}
	delete(s.shapes)
	delete(s.targets)
	delete(s.constraints)
	delete(s.paths)
	delete(s.messages)
	delete(s.shape_children)
	delete(s.path_children)
	delete(s.values)
	delete(s.roots)
	delete(s.ignored)
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

// shape_index_of finds a shape by its node, which is how a caller names one to
// `conforms_node` and how a `Result` reports one.
//
// **Shapes are named by index, not by term**, and this is the bridge rather
// than an admission that the index was the wrong choice. Most shapes in a real
// shapes graph have no name to be found by: every `sh:property [ ... ]` is a
// blank node, and its label is the parser's business, not the author's. The
// index names all of them, and a `Result` already carries it. What this
// procedure serves is the other case — a shape the author gave an IRI, which
// the author can therefore ask about.
//
// A linear scan, deliberately: a shapes graph holds a handful of shapes, and an
// index keyed by term would cost more to build than every lookup it saves.
shape_index_of :: proc(s: ^Shapes, node: rdf.Term) -> (index: int, found: bool) {
	for sh, i in s.shapes {
		if rdf.equal_term(sh.node, node) {
			return i, true
		}
	}
	return -1, false
}

// shapes_ignored returns the `sh:`-namespace predicates this compile found on a
// shape and does not implement — deduplicated, in first-seen order, owned by
// the model like every other term.
//
// **This is how an incomplete engine says so.** Validation ignores a parameter
// it does not recognise, which is the only workable policy: erroring would
// reject the spec's own non-validating annotations (`sh:name`,
// `sh:description`, `sh:order`, `sh:group`, `sh:defaultValue` — all in this
// package's inert list and never reported here) and every vendor extension a
// real shapes graph carries. But ignoring *silently* is what lets an engine
// implementing a third of SHACL Core produce a conforming report and look
// complete. So the compile records what it passed over, and a caller that wants
// to know whether a `sh:conforms true` means anything can ask.
//
// It is a property of the **compile**, not of a shape: the question it answers
// is "did this shapes graph use anything this engine does not enforce". The
// suite harness asserts it is empty for every enabled directory, which is what
// keeps "enabled means fully green" from quietly meaning "green because we did
// nothing".
//
// A parameter listed here was *seen and skipped*. A parameter absent from a
// shapes graph entirely is not listed, and neither is one this engine
// implements.
shapes_ignored :: proc(s: ^Shapes) -> []rdf.Term {
	return s.ignored[:]
}

// constraint_values returns the member terms of a list-valued constraint:
// `sh:in`'s and `sh:languageIn`'s members, and `sh:closed`'s allowed predicates.
constraint_values :: proc(s: ^Shapes, c: Constraint) -> []rdf.Term {
	return s.values[c.values.start:][:c.values.count]
}
