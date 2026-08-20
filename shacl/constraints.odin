package shacl

import "core:strings"
import "core:text/regex"

import "rdf:rdf"

// Constraint-parameter compilation.
//
// The full SHACL Core catalogue. A new component is a new case here and a new
// Constraint_Kind, with — usually — nothing in the evaluator to touch; see
// check.odin's package note for the exceptions that discipline has met.
@(private)
compile_constraints :: proc(
	s: ^Shapes,
	r: Reader,
	shape_id: u32,
	shape_node: rdf.Term,
	v: ^Vocab,
) -> Error {
	// The components whose parameter is a non-negative integer: the two
	// cardinalities (§4.2) and the two string lengths (§4.4.1–4.4.2). They read
	// identically and cite different sections, so the error kinds travel in the
	// table rather than being decided by the reader.
	counts := [4]struct {
		iri:         string,
		kind:        Constraint_Kind,
		not_integer: Error_Kind,
		negative:    Error_Kind,
	} {
		{MIN_COUNT, .Min_Count, .Count_Not_Integer, .Count_Negative},
		{MAX_COUNT, .Max_Count, .Count_Not_Integer, .Count_Negative},
		{MIN_LENGTH, .Min_Length, .Length_Not_Integer, .Length_Negative},
		{MAX_LENGTH, .Max_Length, .Length_Not_Integer, .Length_Negative},
	}
	for entry in counts {
		if !v.found[entry.iri] {
			continue
		}
		vals := objects_of(r, shape_id, v.ids[entry.iri])
		defer delete(vals)
		for id in vals {
			term := materialize_term(s, r.se, id)
			n, ok := integer_value(term)
			if !ok {
				return Error{entry.not_integer, shape_node, intern(&s.terms, rdf.IRI(entry.iri))}
			}
			if n < 0 {
				return Error{entry.negative, shape_node, intern(&s.terms, rdf.IRI(entry.iri))}
			}
			append(&s.constraints, Constraint{kind = entry.kind, count = n})
		}
	}

	// The components whose parameter is a single term. The four value-range
	// bounds join them unchanged: what differs is how the term is *compared*,
	// which is the evaluator's business and not this table's — SHACL-T-0013
	// added four lines here and nothing else in this file.
	terms := [11]struct {
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
		// The property-pair parameters are predicates rather than values, and
		// they compile the same way regardless: a term the model interns and the
		// bindings resolve to a data-store ID.
		{EQUALS, .Equals},
		{DISJOINT, .Disjoint},
		{LESS_THAN, .Less_Than},
		{LESS_THAN_OR_EQUALS, .Less_Than_Or_Equals},
	}
	for entry in terms {
		if !v.found[entry.iri] {
			continue
		}
		vals := objects_of(r, shape_id, v.ids[entry.iri])
		defer delete(vals)
		for id in vals {
			append(&s.constraints, Constraint{kind = entry.kind, term = materialize_term(s, r.se, id)})
		}
	}

	// sh:nodeKind.
	if v.found[NODE_KIND] {
		vals := objects_of(r, shape_id, v.ids[NODE_KIND])
		defer delete(vals)
		for id in vals {
			term := materialize_term(s, r.se, id)
			nk, ok := node_kind_value(term)
			if !ok {
				return Error{.Node_Kind_Unknown, shape_node, intern(&s.terms, rdf.IRI(NODE_KIND))}
			}
			append(&s.constraints, Constraint{kind = .Node_Kind, node_kind = nk})
		}
	}

	// The components taking an RDF list of terms: `sh:in` (§4.8.3) and
	// `sh:languageIn` (§4.4.4). The members go into the model's flat value array
	// and are named by span, like every other child relation.
	lists := [2]struct {
		iri:      string,
		kind:     Constraint_Kind,
		not_list: Error_Kind,
	}{{IN, .In, .In_Not_A_List}, {LANGUAGE_IN, .Language_In, .Language_In_Not_A_List}}
	for entry in lists {
		if !v.found[entry.iri] {
			continue
		}
		vals := objects_of(r, shape_id, v.ids[entry.iri])
		defer delete(vals)
		for head in vals {
			items, ok := list_items(r, head)
			defer delete(items)
			if !ok {
				return Error{entry.not_list, shape_node, intern(&s.terms, rdf.IRI(entry.iri))}
			}
			start := len(s.values)
			for id in items {
				append(&s.values, materialize_term(s, r.se, id))
			}
			append(&s.constraints, Constraint{kind = entry.kind, values = Span{start, len(s.values) - start}})
		}
	}

	// sh:pattern with sh:flags (§4.4.3). The regular expression is compiled
	// here, once, so that matching a value node is a run of an already-built
	// program — and so that a pattern this engine cannot compile, or a flag it
	// does not have, is an ill-formed shapes graph rather than a surprise
	// halfway through a validation.
	//
	// `sh:flags` is read before the loop because it is one parameter for the
	// shape: two `sh:pattern` values on one shape share it.
	if v.found[PATTERN] {
		flags: regex.Flags
		if v.found[FLAGS] {
			ids := objects_of(r, shape_id, v.ids[FLAGS])
			defer delete(ids)
			for id in ids {
				parsed, ok := regex_flags(materialize_term(s, r.se, id))
				if !ok {
					return Error{.Flags_Unsupported, shape_node, intern(&s.terms, rdf.IRI(FLAGS))}
				}
				flags |= parsed
			}
		}
		vals := objects_of(r, shape_id, v.ids[PATTERN])
		defer delete(vals)
		for id in vals {
			literal, is_literal := materialize_term(s, r.se, id).(rdf.Literal)
			if !is_literal {
				return Error{.Pattern_Ill_Formed, shape_node, intern(&s.terms, rdf.IRI(PATTERN))}
			}
			compiled, err := regex.create(literal.lexical, flags, s.allocator)
			if err != nil {
				return Error{.Pattern_Ill_Formed, shape_node, intern(&s.terms, rdf.IRI(PATTERN))}
			}
			append(&s.constraints, Constraint{kind = .Pattern, pattern = compiled})
		}
	}

	// sh:uniqueLang (§4.4.5), whose parameter switches the component on rather
	// than configuring it — so a `false` compiles to no constraint at all and
	// the Constraint carries nothing.
	//
	// **`true` means the term `"true"^^xsd:boolean` and nothing else**, which is
	// a term comparison in a file that has spent two tasks learning to compare
	// values. `property/uniqueLang-002` is why: it declares
	// `sh:uniqueLang "1"^^xsd:boolean` over two `@en` literals — which would
	// violate if the component were active — and expects `sh:conforms true`.
	//
	// **This follows the suite's reading, and the reading is arguable.** The
	// entry carries a comment explaining itself: "Only true is mentioned in the
	// spec, meaning that `1` will not activate the constraint." That is a
	// judgement about §4.4.5's prose, and it cuts against the spec's own
	// normative validator, which tests the parameter with SPARQL `=` — and
	// `"1"^^xsd:boolean = true` is *true* by value. The entry is `sht:approved`,
	// and this family's rule is that the suite defines done, so the suite wins.
	// Recorded rather than smoothed over: if a later revision of the corpus
	// reverses it, one comparison here changes and this note is the reason why.
	if v.found[UNIQUE_LANG] {
		vals := objects_of(r, shape_id, v.ids[UNIQUE_LANG])
		defer delete(vals)
		for id in vals {
			literal, is_literal := materialize_term(s, r.se, id).(rdf.Literal)
			if !is_literal || literal.datatype != rdf.XSD_BOOLEAN {
				return Error{.Unique_Lang_Not_Boolean, shape_node, intern(&s.terms, rdf.IRI(UNIQUE_LANG))}
			}
			if literal.lexical == "true" {
				append(&s.constraints, Constraint{kind = .Unique_Lang})
			}
		}
	}

	// sh:closed (§4.8.1). Switched on by its parameter exactly as `sh:uniqueLang`
	// is, and read exactly as strictly — **the term `"true"^^xsd:boolean` and
	// nothing else** — which is a choice rather than a measurement, because no
	// corpus entry writes it any other way.
	//
	// The two readings are the same two `sh:uniqueLang` faced. §4.8.1's prose says
	// "if sh:closed is true", which is the wording `property/uniqueLang-002`
	// settled strictly; the spec's normative SPARQL says `FILTER ($closed)`, whose
	// effective boolean value makes `"1"^^xsd:boolean` activate it. Nothing in the
	// corpus distinguishes them here, so this follows the engine's own precedent:
	// two parameters the specification words identically should not answer
	// differently in one engine, and the reading that already has a suite entry
	// behind it wins. If a later corpus revision adds the entry, it is this
	// comparison that changes.
	//
	// **The allowed-predicate set is not read here**, and cannot be: it includes
	// the predicate paths of this shape's `sh:property` children, which are not
	// linked to it until the fixup pass. `compile` fills `values` afterwards; see
	// `compile_closed_sets`.
	if v.found[CLOSED] {
		vals := objects_of(r, shape_id, v.ids[CLOSED])
		defer delete(vals)
		for id in vals {
			literal, is_literal := materialize_term(s, r.se, id).(rdf.Literal)
			if !is_literal || literal.datatype != rdf.XSD_BOOLEAN {
				return Error{.Closed_Not_Boolean, shape_node, intern(&s.terms, rdf.IRI(CLOSED))}
			}
			if literal.lexical == "true" {
				append(&s.constraints, Constraint{kind = .Closed})
			}
		}
	}

	// The logical combinators (§4.6). One constraint per value of the parameter —
	// `sh:and (A B) , (C D)` is two conjunctions, not one of four — and the
	// operands are resolved later, for the same reason `sh:closed`'s allowed set
	// is: a shape's index does not exist until every shape is compiled. See
	// `compile_shape_operands`.
	//
	// Nothing is read here at all beyond "how many", which is why this loop looks
	// unlike every other in this procedure. It is still the place the constraint
	// is created, because `Shape.constraints` is a contiguous span and a later
	// pass cannot append into the middle of one.
	for entry in SHAPE_VALUED_PARAMETERS {
		if !v.found[entry.iri] {
			continue
		}
		vals := objects_of(r, shape_id, v.ids[entry.iri])
		defer delete(vals)
		for _ in vals {
			append(&s.constraints, Constraint{kind = entry.kind})
		}
	}

	// The qualified family (§4.7.3). Two components — the counts — sharing one
	// `sh:qualifiedValueShape`, which is read here only to decide whether they
	// exist at all.
	//
	// **They compile to one constraint carrying both bounds, not to one each**
	// (SHACL-T-0026). The sharing is structural rather than incidental: §4.7.3
	// gives a shape at most one `sh:qualifiedValueShape`, so both counts are
	// counting the same conforming value nodes, and two constraints made the
	// evaluator walk them twice for an answer that cannot differ. `count` is the
	// minimum and `count_max` the maximum, each -1 where the shapes graph wrote
	// nothing; a violation of either still names its own component, because the
	// merge is in the model and not in the report.
	//
	// **Nothing compiles without `sh:qualifiedValueShape`**, and that is a
	// requirement rather than an optimisation: `node/qualified-001` declares
	// `sh:qualifiedMinCount 5` and `sh:qualifiedMaxCount 2` with no qualified
	// shape and expects *neither* to fire. Five values, a maximum of two, and a
	// conforming answer — the counts are meaningless without something to count,
	// so §4.7.3 makes them inert. The engine got this right by not implementing
	// them; this is the line that keeps it right.
	//
	// A consequence worth naming: an ill-formed `sh:qualifiedMinCount` on a shape
	// with no qualified value shape is never read and so never reported. That is
	// the same silence the spec asks for about the parameter itself.
	//
	// `sh:qualifiedValueShape` is treated as functional, like `sh:path`. The
	// shape is resolved in `compile_shape_operands`; only its presence matters
	// here.
	if v.found[QUALIFIED_VALUE_SHAPE] {
		if _, has_shape := first_object(r, shape_id, v.ids[QUALIFIED_VALUE_SHAPE]); has_shape {
			// Where this shape's qualified constraints begin. The two passes below
			// fill the *same* constraints from opposite sides — the k-th minimum
			// and the k-th maximum are one constraint — so the second pass has to
			// be able to find what the first appended. Nothing else appends
			// between, this block being the last in the procedure.
			//
			// **Pairing by ordinal is for a shape that should not exist.** §4.7.3
			// gives a property shape at most one of each count, which is the case
			// that matters and the case this collapses to: one minimum and one
			// maximum become one constraint, and either alone becomes one
			// constraint with the other bound absent. A shapes graph writing a
			// count twice is ill-formed and gets what it got before the merge —
			// every value checked — rather than a silently dropped bound.
			start := len(s.constraints)
			qualified := [2]struct {
				iri:    string,
				is_max: bool,
			}{{QUALIFIED_MIN_COUNT, false}, {QUALIFIED_MAX_COUNT, true}}
			for entry in qualified {
				if !v.found[entry.iri] {
					continue
				}
				vals := objects_of(r, shape_id, v.ids[entry.iri])
				defer delete(vals)
				for id, i in vals {
					n, ok := integer_value(materialize_term(s, r.se, id))
					if !ok {
						return Error {
							.Qualified_Count_Not_Integer,
							shape_node,
							intern(&s.terms, rdf.IRI(entry.iri)),
						}
					}
					if n < 0 {
						return Error{.Qualified_Count_Negative, shape_node, intern(&s.terms, rdf.IRI(entry.iri))}
					}
					index := start + i
					if index == len(s.constraints) {
						append(
							&s.constraints,
							Constraint{kind = .Qualified_Value_Shape, count = -1, count_max = -1},
						)
					}
					if entry.is_max {
						s.constraints[index].count_max = n
					} else {
						s.constraints[index].count = n
					}
				}
			}
		}
	}

	return Error{}
}

// The parameters whose value **is a shape**, paired with the kind they compile
// to and how the shape is reached: `sh:and`, `sh:or` and `sh:xone` name an RDF
// list whose members are the shapes; `sh:not` and `sh:node` name one directly
// (§2.1.1).
//
// `sh:qualifiedValueShape` is deliberately absent even though its value is a
// shape too. It compiles to no constraint of its own — the two counts are the
// components — so it has nothing to pair with by ordinal, and
// `compile_shape_operands` resolves it separately.
//
// Shared by `compile_constraints`, which counts them, and
// `compile_shape_operands`, which resolves them — and shared deliberately, so
// the two passes cannot disagree about which parameters exist or in what order.
@(private = "file")
SHAPE_VALUED_PARAMETERS := [5]struct {
	iri:     string,
	kind:    Constraint_Kind,
	is_list: bool,
}{{AND, .And, true}, {OR, .Or, true}, {XONE, .Xone, true}, {NOT, .Not, false}, {NODE, .Node, false}}

// compile_shape_operands resolves the operand shapes of every logical
// combinator in the model, from shapes-graph node IDs to indices into
// `Shapes.shapes`.
//
// **Why this is a separate pass, again.** The same reason `compile_closed_sets`
// is: the model names shapes by index, and a branch's index is unknown while the
// shape carrying the combinator is being compiled — `sh:and ( ex:A ex:B )` may
// name shapes that come later in the worklist, or the shape itself. `compiled`
// is the worklist's ID-to-index map, complete only once the loop has drained.
//
// **How a constraint finds its own parameter value.** By ordinal: the k-th
// `.And` constraint on a shape belongs to the k-th value of `sh:and` on that
// shape's node. That holds because both passes read the same parameter of the
// same shape from the same store with the same pattern, and a match is
// deterministic per store — `compile_constraints` appended in exactly this
// order. It is stated rather than assumed because it is the one coupling between
// the two halves, and a `sh:and` with two values is what would expose it.
//
// A malformed list is an error here (`Shape_List_Not_A_List`). Discovery skips
// one silently, which SHACL-T-0010 recorded as this task's question to answer;
// the answer is that it is ill-formed like every other broken list parameter, and
// it is decided in one place rather than two.
@(private)
compile_shape_operands :: proc(
	s: ^Shapes,
	r: Reader,
	shape_ids: []u32,
	compiled: ^map[u32]int,
	v: ^Vocab,
) -> Error {
	for shape_index in 0 ..< len(s.shapes) {
		shape := s.shapes[shape_index]

		// `sh:qualifiedValueShape` first, and outside the ordinal table: it names
		// no constraint of its own, and the constraint that carries it holds both
		// counts (SHACL-T-0026), so there is nothing to pair by position. A
		// well-formed shape has exactly one qualified constraint here; an
		// ill-formed one repeating a count has several, and they all get the same
		// one-entry span, because there is only ever one qualified shape to give.
		if v.found[QUALIFIED_VALUE_SHAPE] {
			carries_qualified := false
			for offset in 0 ..< shape.constraints.count {
				if s.constraints[shape.constraints.start + offset].kind == .Qualified_Value_Shape {
					carries_qualified = true
					break
				}
			}
			if carries_qualified {
				start := len(s.shape_children)
				if value, has := first_object(r, shape_ids[shape_index], v.ids[QUALIFIED_VALUE_SHAPE]); has {
					if operand, found := compiled[value]; found {
						append(&s.shape_children, operand)
					}
				}
				span := Span{start, len(s.shape_children) - start}
				for offset in 0 ..< shape.constraints.count {
					index := shape.constraints.start + offset
					if s.constraints[index].kind == .Qualified_Value_Shape {
						s.constraints[index].shapes = span
					}
				}
			}
		}

		for entry in SHAPE_VALUED_PARAMETERS {
			if !v.found[entry.iri] {
				continue
			}
			// Nothing to resolve unless this shape actually carries one, which
			// keeps compilation to the reads it had before for every shapes graph
			// that uses no combinator.
			wanted := 0
			for offset in 0 ..< shape.constraints.count {
				if s.constraints[shape.constraints.start + offset].kind == entry.kind {
					wanted += 1
				}
			}
			if wanted == 0 {
				continue
			}

			vals := objects_of(r, shape_ids[shape_index], v.ids[entry.iri])
			defer delete(vals)

			cursor := 0
			for offset in 0 ..< shape.constraints.count {
				index := shape.constraints.start + offset
				if s.constraints[index].kind != entry.kind {
					continue
				}
				if cursor >= len(vals) {
					break
				}
				value := vals[cursor]
				cursor += 1

				start := len(s.shape_children)
				if entry.is_list {
					items, ok := list_items(r, value)
					defer delete(items)
					if !ok {
						return Error {
							.Shape_List_Not_A_List,
							shape.node,
							intern(&s.terms, rdf.IRI(entry.iri)),
						}
					}
					for member in items {
						if operand, found := compiled[member]; found {
							append(&s.shape_children, operand)
						}
					}
				} else if operand, found := compiled[value]; found {
					append(&s.shape_children, operand)
				}
				s.constraints[index].shapes = Span{start, len(s.shape_children) - start}
			}
		}
	}
	return Error{}
}

// compile_qualified_siblings fills in the sibling shapes that a disjoint
// `sh:qualifiedValueShape` excludes against, and is the only place this engine
// reads the shapes model **upward**.
//
// §4.7.3 defines the sibling shapes of a shape S as the values of `sh:property`
// at the shapes that have S as a value of `sh:property`, minus S itself; a value
// node counts toward the qualified cardinality only if it conforms to S's
// `sh:qualifiedValueShape` and to **none** of the siblings'. The model names
// children and not parents, so the relation is inverted here, once, rather than
// searched for per value node during validation.
//
// **The exclusion is symmetric and that is the whole point.**
// `qualifiedValueShapesDisjoint-001` puts two property shapes on the same path,
// one qualifying on `ex:Thumb` and one on `ex:Finger`, over a hand holding three
// fingers and one `ex:FingerAndThumb`. That node conforms to both qualified
// shapes, so it is excluded from **both** counts — the thumb shape counts zero
// against a minimum of one and the finger shape counts three against a minimum
// of four, and the entry expects both violations. An implementation that
// excluded it from one side only produces one result and looks half right.
//
// **`sh:qualifiedValueShapesDisjoint false` leaves the span empty**, which is
// also what a shape with no siblings gets, because the two are the same thing to
// the evaluator. Runs after the qualified shapes are resolved, since that is what
// a sibling contributes.
@(private)
compile_qualified_siblings :: proc(s: ^Shapes, r: Reader, shape_ids: []u32, v: ^Vocab) -> Error {
	if !v.found[QUALIFIED_VALUE_SHAPES_DISJOINT] {
		return Error{}
	}

	// The parent's children are copied out before anything is appended:
	// `shape_properties` slices `Shapes.shape_children`, and this loop grows it.
	children := make([dynamic]int, s.allocator)
	defer delete(children)

	for parent in 0 ..< len(s.shapes) {
		clear(&children)
		append(&children, ..shape_properties(s, s.shapes[parent]))
		if len(children) < 2 {
			// A shape with one child has no siblings, and one with none has no
			// qualified constraints to give them to.
			continue
		}

		for child in children {
			disjoint, err := qualified_is_disjoint(s, r, shape_ids[child], s.shapes[child].node, v)
			if err.kind != .None {
				return err
			}
			if !disjoint {
				continue
			}

			shape := s.shapes[child]
			start := len(s.shape_children)
			for other in children {
				if other == child {
					continue
				}
				for offset in 0 ..< s.shapes[other].constraints.count {
					c := s.constraints[s.shapes[other].constraints.start + offset]
					if c.kind != .Qualified_Value_Shape {
						continue
					}
					// One qualified constraint per well-formed sibling, and where
					// there are several they share the one shape, so take the first
					// and stop.
					for operand in constraint_shapes(s, c) {
						append(&s.shape_children, operand)
					}
					break
				}
			}
			span := Span{start, len(s.shape_children) - start}

			for offset in 0 ..< shape.constraints.count {
				index := shape.constraints.start + offset
				if s.constraints[index].kind == .Qualified_Value_Shape {
					s.constraints[index].siblings = span
				}
			}
		}
	}
	return Error{}
}

// qualified_is_disjoint reads one shape's `sh:qualifiedValueShapesDisjoint`.
//
// `true` means the term `"true"^^xsd:boolean` and nothing else, which is the
// reading `sh:uniqueLang` took on a suite entry's authority and `sh:closed`
// inherited. Nothing in the corpus distinguishes it here —
// `qualifiedMinCountDisjoint-001` and `qualifiedValueShapesDisjoint-001` both
// write `"true"^^xsd:boolean` — so this is consistency rather than measurement,
// recorded in the same terms as the other two.
@(private = "file")
qualified_is_disjoint :: proc(
	s: ^Shapes,
	r: Reader,
	shape_id: u32,
	shape_node: rdf.Term,
	v: ^Vocab,
) -> (
	disjoint: bool,
	err: Error,
) {
	ids := objects_of(r, shape_id, v.ids[QUALIFIED_VALUE_SHAPES_DISJOINT])
	defer delete(ids)
	for id in ids {
		literal, is_literal := materialize_term(s, r.se, id).(rdf.Literal)
		if !is_literal || literal.datatype != rdf.XSD_BOOLEAN {
			return false, Error {
				.Qualified_Disjoint_Not_Boolean,
				shape_node,
				intern(&s.terms, rdf.IRI(QUALIFIED_VALUE_SHAPES_DISJOINT)),
			}
		}
		if literal.lexical == "true" {
			disjoint = true
		}
	}
	return disjoint, Error{}
}

// compile_closed_sets fills in the allowed-predicate set of every `sh:closed`
// constraint in the model, and is the one piece of constraint compilation that
// cannot run while its shape is being compiled.
//
// **Why it is a separate pass.** §4.8.1's allowed set is `sh:ignoredProperties`
// together with the predicates the shape's *property shapes* declare, and a
// shape's `sh:property` children are linked by index in `compile`'s fixup pass,
// after every shape exists. `compile_constraints` runs before that and would
// have to re-query the shapes graph for children it cannot yet name. So the
// boolean is compiled there and the set here, and the two halves meet through
// `Constraint.values` — appended contiguously, like `sh:in`'s members, so
// `bindings_init` resolves them to data-store IDs with no case of its own.
//
// **A property shape declares a predicate only when its path is a bare
// predicate.** A sequence, an inverse, or any other compound path is a blank
// node in the shapes graph, and a triple's predicate is always an IRI, so such a
// path can never name one — the spec says so by defining the allowed set through
// `sh:property/sh:path`, and it falls out here rather than needing a rule. The
// case is real and in the corpus: `core/complex`'s `personexample.ttl` closes a
// shape one of whose property shapes has `sh:path [ sh:inversePath ex:worksFor ]`.
//
// `shape_ids` is every compiled shape's node in the *shapes* store, indexed by
// shape index — `compile`'s worklist, which already holds them in that order, so
// the graph is not re-queried to find them.
@(private)
compile_closed_sets :: proc(s: ^Shapes, r: Reader, shape_ids: []u32, v: ^Vocab) -> Error {
	for shape_index in 0 ..< len(s.shapes) {
		shape := s.shapes[shape_index]
		for offset in 0 ..< shape.constraints.count {
			index := shape.constraints.start + offset
			if s.constraints[index].kind != .Closed {
				continue
			}
			start := len(s.values)

			if v.found[IGNORED_PROPERTIES] {
				heads := objects_of(r, shape_ids[shape_index], v.ids[IGNORED_PROPERTIES])
				defer delete(heads)
				for head in heads {
					items, ok := list_items(r, head)
					defer delete(items)
					if !ok {
						return Error {
							.Ignored_Properties_Not_A_List,
							shape.node,
							intern(&s.terms, rdf.IRI(IGNORED_PROPERTIES)),
						}
					}
					for id in items {
						append(&s.values, materialize_term(s, r.se, id))
					}
				}
			}

			// The predicates the shape's own property shapes declare. Already
			// interned by path compilation, so this borrows the model's table
			// rather than materializing anything a second time.
			for child in shape_properties(s, shape) {
				path := s.shapes[child].path
				if path < 0 || s.paths[path].kind != .Predicate {
					continue
				}
				append(&s.values, s.paths[path].predicate)
			}

			s.constraints[index].values = Span{start, len(s.values) - start}
		}
	}
	return Error{}
}

// regex_flags reads an `sh:flags` string into the flags this engine's regex
// package understands, and fails on anything else.
//
// **This is where the dialect divergence is enforced rather than hidden.** SHACL
// defines `sh:pattern` by XPath's `fn:matches`, whose flags are `i s m x q`;
// `core:text/regex` offers `m i x u`. Three of those five map across; `s` (dot
// matches newline) and `q` (treat the pattern as a literal) have no equivalent
// and are rejected. Silently ignoring one would mean validating against a
// different pattern than the shapes graph asked for and reporting conformance —
// which is the failure mode this whole engine's ignored-parameter record exists
// to prevent, applied one level down.
//
// `u` is not accepted either, and for the opposite reason: it is Odin's, not
// SHACL's, and this package should not invent flags the specification does not
// define.
@(private = "file")
regex_flags :: proc(term: rdf.Term) -> (flags: regex.Flags, ok: bool) {
	literal, is_literal := term.(rdf.Literal)
	if !is_literal {
		return {}, false
	}
	for i in 0 ..< len(literal.lexical) {
		switch literal.lexical[i] {
		case 'i':
			flags |= {.Case_Insensitive}
		case 'm':
			flags |= {.Multiline}
		case 'x':
			flags |= {.Ignore_Whitespace}
		case:
			return {}, false
		}
	}
	return flags, true
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
	// The string-based components (SHACL-T-0014). `sh:flags` is here because it
	// is read and acted on, even though it is a modifier rather than a component
	// of its own — a shapes graph using it is not using anything unimplemented.
	MIN_LENGTH,
	MAX_LENGTH,
	PATTERN,
	FLAGS,
	LANGUAGE_IN,
	UNIQUE_LANG,
	// The property-pair components (SHACL-T-0015).
	EQUALS,
	DISJOINT,
	LESS_THAN,
	LESS_THAN_OR_EQUALS,
	// `sh:closed` (SHACL-T-0016). `sh:ignoredProperties` is here for `sh:flags`'
	// reason: it is read and acted on, so a shapes graph carrying one is not using
	// anything unimplemented, even though it names no component of its own.
	CLOSED,
	IGNORED_PROPERTIES,
	// The logical combinators (SHACL-T-0017) — the first four of the six
	// shape-expecting parameters to move here from "discovered but not enforced".
	// `sh:node` and `sh:qualifiedValueShape` stay out until SHACL-T-0018.
	AND,
	OR,
	NOT,
	XONE,
	// The shape-based constraints (SHACL-T-0018), which complete SHACL Core's §4
	// except for what needs SPARQL. With these five the list holds every
	// parameter the specification defines that this engine acts on, so a
	// non-empty `shapes_ignored` now means a vendor extension or SHACL-SPARQL.
	NODE,
	QUALIFIED_VALUE_SHAPE,
	QUALIFIED_MIN_COUNT,
	QUALIFIED_MAX_COUNT,
	QUALIFIED_VALUE_SHAPES_DISJOINT,
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
record_ignored_parameters :: proc(s: ^Shapes, r: Reader, shape_id: u32) {
	preds := predicates_of(r, shape_id)
	defer delete(preds)

	for id in preds {
		buf: Term_Buf
		term, ok := session_term(r.se, id, buf[:])
		if !ok {
			continue
		}
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
	}
}

// parameter_is_ignored decides whether one predicate belongs in the record: a
// `sh:`-namespace IRI that is neither implemented nor inert. The only place
// the namespace test lives.
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
