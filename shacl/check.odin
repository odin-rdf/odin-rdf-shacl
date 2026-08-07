package shacl

import "core:strings"
import "core:text/regex"
import regex_common "core:text/regex/common"
import "core:unicode/utf8"

import rdf "rdf:rdf"
import store "store:store"

// Constraint dispatch: the seam the catalogue initiative fills.
//
// Adding a constraint component is three edits and none of them is in the
// evaluator: a `Constraint_Kind`, its parameter in `compile_constraints`, and a
// case here — plus its scope, below, which says *how often* it is asked.
//
// **Scope is the thing worth naming.** SHACL's components divide into two
// shapes, and getting one wrong produces plausible results that are wrong in a
// way the suite catches immediately. A value-scoped component is asked once per
// value node and blames that node, so its result carries `sh:value`. A
// set-scoped component is asked once about the whole value-node set and has no
// single node to blame, so its result carries none — which is exactly why
// `path-complex-001` expects an `sh:hasValue` violation with a `sh:resultPath`
// and no `sh:value`, while `targetClassImplicit-001` expects an `sh:in`
// violation that names one.
//
// Dispatch is a switch rather than a table of procedure pointers. That is
// SPARQL-T-0011's finding applied unchanged: the family's no-dynamic-dispatch
// default is free here, and its counterweight — that procedure pointers
// measured as noise once a call does real work — is the escape hatch if the
// catalogue ever wants one.

// Constraint_Scope says whether a component is checked once per value node or
// once over the whole value-node set.
Constraint_Scope :: enum u8 {
	Value,
	Node_Set,
}

// constraint_scope is a component's scope. Exported because it is part of the
// seam: a catalogue component adds a case here as well as in `check_value` or
// `check_node_set`, and getting it wrong is the failure mode described above.
constraint_scope :: proc(kind: Constraint_Kind) -> Constraint_Scope {
	switch kind {
	// `sh:uniqueLang` is the third set-scoped component and the one that reads
	// least like it: it looks per-value — "is this literal's tag unique?" — and
	// is not, because uniqueness is a property of the set. §4.5.5 asks for one
	// result per language used twice, which no per-value check could produce.
	case .Min_Count, .Max_Count, .Has_Value, .Unique_Lang:
		return .Node_Set
	case .Class,
	     .Datatype,
	     .Node_Kind,
	     .In,
	     .Min_Inclusive,
	     .Max_Inclusive,
	     .Min_Exclusive,
	     .Max_Exclusive,
	     .Min_Length,
	     .Max_Length,
	     .Pattern,
	     .Language_In:
		return .Value
	}
	return .Value
}

// check_shape runs every constraint a shape declares against one focus node's
// value nodes.
@(private)
check_shape :: proc(v: ^Validation, shape_index: int, values: Value_Set) {
	shape := v.s.shapes[shape_index]
	start := shape.constraints.start
	for c, i in shape_constraints(v.s, shape) {
		switch constraint_scope(c.kind) {
		case .Node_Set:
			check_node_set(v, shape_index, c, start + i, values)
		case .Value:
			for n in 0 ..< value_set_count(values) {
				check_value(v, shape_index, c, start + i, values.focus, value_set_at(values, n))
				if v.stopped {
					return
				}
			}
		}
		if v.stopped {
			return
		}
	}
}

// check_node_set runs the components that are asked once about the whole
// value-node set. Their results name the focus node and carry no `sh:value`.
@(private = "file")
check_node_set :: proc(
	v: ^Validation,
	shape_index: int,
	c: Constraint,
	constraint_index: int,
	values: Value_Set,
) {
	count := value_set_count(values)

	#partial switch c.kind {
	case .Min_Count:
		// §4.2: the cardinality components apply to property shapes only. A
		// node shape has exactly one value node by definition, so asking would
		// answer a question nobody posed.
		if v.s.shapes[shape_index].path < 0 {
			return
		}
		if count < c.count {
			emit_result(v, shape_index, values.focus, {}, false, .Min_Count)
		}

	case .Max_Count:
		if v.s.shapes[shape_index].path < 0 {
			return
		}
		if count > c.count {
			emit_result(v, shape_index, values.focus, {}, false, .Max_Count)
		}

	case .Has_Value:
		// §4.5.1: the term must be *among* the value nodes. One violation for
		// the shape, not one per node that is not it.
		for n in 0 ..< count {
			if node_is_term(v, value_set_at(values, n), constraint_index, c.term) {
				return
			}
		}
		emit_result(v, shape_index, values.focus, {}, false, .Has_Value)

	case .Unique_Lang:
		check_unique_lang(v, shape_index, values)
	}
}

// check_unique_lang is `sh:uniqueLang` (§4.5.5): no two value nodes may carry
// the same non-empty language tag.
//
// **One result per language used twice, not one per shape and not one per
// node.** `property/uniqueLang-001` is what pins it: its second focus node has
// three `@en` values and two `@de` values and expects exactly *two* results,
// both naming the focus node and neither carrying an `sh:value` — there is no
// single node to blame when the fault is that two of them agree.
//
// Like the cardinality components, it applies to property shapes only. A node
// shape has exactly one value node, so no two of them could share anything.
//
// The tags are cloned because they are read from materialised terms, and on the
// persistent backend a materialised term's strings die with it — a `map` keyed
// on the borrowed tag would be reading freed database bytes by the second
// iteration. The comparison is `equal_fold` because RDF language tags are
// case-insensitive; see `language_matches` for the same rule stated where it
// matters more.
@(private = "file")
check_unique_lang :: proc(v: ^Validation, shape_index: int, values: Value_Set) {
	if v.s.shapes[shape_index].path < 0 {
		return
	}
	tags := make([dynamic]string, v.allocator)
	defer {
		for tag in tags {
			delete(tag, v.allocator)
		}
		delete(tags)
	}

	for n in 0 ..< value_set_count(values) {
		term, owned := materialize(v, value_set_at(values, n))
		if literal, is_literal := term.(rdf.Literal); is_literal && literal.language != "" {
			append(&tags, strings.clone(literal.language, v.allocator))
		}
		if owned {
			rdf.destroy_term(term, v.allocator)
		}
	}

	// A quadratic scan over one focus node's value nodes, which is a handful.
	// Reporting on the *first* occurrence of each tag is what keeps three `@en`
	// values to one result rather than two.
	for i in 0 ..< len(tags) {
		seen_earlier := false
		repeats := 0
		for j in 0 ..< len(tags) {
			if !strings.equal_fold(tags[i], tags[j]) {
				continue
			}
			if j < i {
				seen_earlier = true
				break
			}
			repeats += 1
		}
		if !seen_earlier && repeats > 1 {
			emit_result(v, shape_index, values.focus, {}, false, .Unique_Lang)
		}
		if v.stopped {
			return
		}
	}
}

// check_value runs the components that are asked once per value node. Their
// results name the node they blame in `sh:value`.
@(private = "file")
check_value :: proc(
	v: ^Validation,
	shape_index: int,
	c: Constraint,
	constraint_index: int,
	focus: Focus_Node,
	value: Node_Ref,
) {
	ok: bool
	switch c.kind {
	case .Class:
		ok = check_class(v, c, constraint_index, value)
	case .Datatype:
		ok = check_datatype(v, c, value)
	case .Node_Kind:
		ok = node_kind_of(v, value) & c.node_kind != {}
	case .In:
		ok = check_in(v, c, value)
	case .Min_Inclusive, .Max_Inclusive, .Min_Exclusive, .Max_Exclusive:
		ok = check_range(v, c, value)
	case .Min_Length, .Max_Length, .Pattern:
		ok = check_string(v, c, value)
	case .Language_In:
		ok = check_language_in(v, c, value)
	case .Min_Count, .Max_Count, .Has_Value, .Unique_Lang:
		return
	}
	if !ok {
		emit_result(v, shape_index, focus, value, true, c.kind)
	}
}

// check_class is `sh:class` (§4.4.1): the value node must be a SHACL instance
// of the class — it must carry an `rdf:type` that is the class or a subclass of
// it, transitively, **in the data graph**.
//
// The two absences below are the initiative's asymmetry made concrete. A data
// store that has never seen the class term, or has never seen `rdf:type` at
// all, cannot hold such a triple, so every value node violates. That is the
// opposite of what the same absence means on a path, where it is emptiness.
@(private = "file")
check_class :: proc(v: ^Validation, c: Constraint, constraint_index: int, value: Node_Ref) -> bool {
	if !v.b.constraint_bound[constraint_index] || !v.b.targets.has_type || !value.bound {
		return false
	}
	state := Class_Check {
		members = class_closure(v, v.b.constraint[constraint_index]),
	}
	v.access.scan(
		v.access.data,
		value.id,
		v.b.targets.rdf_type,
		store.WILDCARD,
		store.QUAD_O,
		class_check_visit,
		&state,
	)
	return state.found
}

@(private = "file")
Class_Check :: struct {
	members: ^map[store.Term_ID]bool,
	found:   bool,
}

// class_check_visit returns false once it has an answer, which stops the scan
// inside the store rather than reading the rest of the node's types.
@(private = "file")
class_check_visit :: proc(data: rawptr, id: store.Term_ID) -> bool {
	state := cast(^Class_Check)data
	if state.members[id] {
		state.found = true
		return false
	}
	return true
}

// check_datatype is `sh:datatype` (§4.3.1): the value node must be a literal
// whose datatype IRI is exactly the parameter **and whose lexical form lies in
// that datatype's lexical space**.
//
// Exactly, and by code point: RDF 1.1 Concepts §3.2 forbids further
// normalization of IRIs, so the first half is string equality and not a
// judgement call. A language-tagged literal carries `rdf:langString` and
// therefore never satisfies `sh:datatype xsd:string`, which falls out of the
// comparison rather than needing a case.
//
// **The second half was the spine's recorded debt**, discharged in
// SHACL-T-0012 along with the lexical-to-value machinery it shares. It is not a
// refinement: `"300"^^xsd:byte` and `"c"^^xsd:byte` both name xsd:byte exactly
// and neither is one, and `core/property`'s `datatype-ill-formed` is the entry
// that says so. The spine's enabled directories used `sh:datatype` only with
// `xsd:string`, whose lexical space is every string, which is why they could go
// green without it.
//
// **An unmodelled datatype satisfies.** `lexical_status` answers `.Unchecked`
// for a datatype this engine does not model — rdf:HTML is the one in the corpus
// — and only `.Ill_Formed` violates. Violating on `.Unchecked` would fail
// `sh:datatype rdf:HTML` on a perfectly good HTML literal: an engine may say a
// lexical form is outside a lexical space only when it knows the space.
@(private = "file")
check_datatype :: proc(v: ^Validation, c: Constraint, value: Node_Ref) -> bool {
	want, is_iri := c.term.(rdf.IRI)
	if !is_iri {
		return false
	}
	term, owned := materialize(v, value)
	defer if owned {
		rdf.destroy_term(term, v.allocator)
	}
	literal, is_literal := term.(rdf.Literal)
	if !is_literal || literal.datatype != want {
		return false
	}
	return lexical_status(literal) != .Ill_Formed
}

// check_in is `sh:in` (§4.6.1): the value node must be a member of the list.
@(private = "file")
check_in :: proc(v: ^Validation, c: Constraint, value: Node_Ref) -> bool {
	for i in 0 ..< c.values.count {
		index := c.values.start + i
		if value.bound {
			if v.b.value_bound[index] && value.id == v.b.value[index] {
				return true
			}
		} else if rdf.equal_term(value.term, v.s.values[index]) {
			return true
		}
	}
	return false
}

// check_range is the four value-range components (§4.6.2–4.6.5):
// `sh:minInclusive`, `sh:maxInclusive`, `sh:minExclusive`, and `sh:maxExclusive`.
// One procedure rather than four, because they differ only in which of the four
// answers they accept.
//
// **These compare values, not terms**, and that is the whole reason
// SHACL-T-0012 exists: `sh:minInclusive 4` is satisfied by `"4.0"^^xsd:decimal`,
// which is a different term and the same number. Everything else in this file
// answers from a `Term_ID` and never materialises a bound.
//
// **Incomparable violates, and it does so structurally.** The spec's condition
// is that the comparison *holds*, and a comparison that could not be made does
// not hold — so `sh:minInclusive 4` violates on `ex:John`, on `"Hello"`, on
// `"abc"^^xsd:integer`, and on a dateTime whose timezone window overlaps the
// bound's. None of those needs a case here: `.Incomparable` matches no arm below
// and falls through to false. That is deliberate. Writing it as an early
// `if order == .Incomparable { return false }` would be the same behaviour with
// a place for a later component to get the polarity backwards.
@(private = "file")
check_range :: proc(v: ^Validation, c: Constraint, value: Node_Ref) -> bool {
	term, owned := materialize(v, value)
	defer if owned {
		rdf.destroy_term(term, v.allocator)
	}
	// Ordered value-against-bound, so the component names read as they do in the
	// shapes graph: `.Greater` is the value node above the minimum.
	order := compare_values(value_of(term), value_of(c.term))
	#partial switch c.kind {
	case .Min_Inclusive:
		return order == .Greater || order == .Equal
	case .Max_Inclusive:
		return order == .Less || order == .Equal
	case .Min_Exclusive:
		return order == .Greater
	case .Max_Exclusive:
		return order == .Less
	}
	return false
}

// check_string is the three components that work on a value node's **string**:
// `sh:minLength`, `sh:maxLength` (§4.5.1–4.5.2), and `sh:pattern` (§4.5.3).
//
// They share a procedure because they share the hard part, which is deciding
// what a node's string *is*. §4.5 answers it the same way for all three, and it
// is not the answer a reader expects: a literal contributes its lexical form,
// **an IRI contributes the IRI itself**, and a blank node contributes nothing
// and therefore always violates.
//
// `node/minLength-001` pins all three in one entry. `<a:b>` is an IRI of length
// three and violates `sh:minLength 4`; `"2017-03-29"^^xsd:date` is ten
// characters of lexical form and passes; a blank node found by `sh:targetClass`
// violates. `node/pattern-001` does the same for the regular expression, down to
// matching `"777777"@mi` on its lexical form and ignoring the tag.
//
// **Length is in code points, not bytes.** §4.5.1 counts the string length as
// XPath's `fn:string-length` does, which counts characters; a byte count would
// make any non-ASCII lexical form longer than it is. No corpus entry is
// non-ASCII, so this is the spec being followed rather than a test passing.
@(private = "file")
check_string :: proc(v: ^Validation, c: Constraint, value: Node_Ref) -> bool {
	term, owned := materialize(v, value)
	defer if owned {
		rdf.destroy_term(term, v.allocator)
	}
	text, has_text := node_string(term)
	if !has_text {
		return false
	}
	#partial switch c.kind {
	case .Min_Length:
		return utf8.rune_count_in_string(text) >= c.count
	case .Max_Length:
		return utf8.rune_count_in_string(text) <= c.count
	case .Pattern:
		// A capture is required by the API and unwanted here — the question is
		// whether the pattern matched at all — so it is a fixed-size stack
		// buffer rather than an allocation on the engine's inner loop.
		positions: [regex_common.MAX_CAPTURE_GROUPS][2]int
		groups: [regex_common.MAX_CAPTURE_GROUPS]string
		capture := regex.Capture {
			pos    = positions[:],
			groups = groups[:],
		}
		_, matched := regex.match_with_preallocated_capture(c.pattern, text, &capture)
		return matched
	}
	return false
}

// node_string is what §4.5 means by a value node's string: a literal's lexical
// form, an IRI's own text, and nothing at all for a blank node — which is how
// the spec makes a blank node violate every string component without any of
// them naming it.
@(private = "file")
node_string :: proc(term: rdf.Term) -> (text: string, ok: bool) {
	#partial switch t in term {
	case rdf.Literal:
		return t.lexical, true
	case rdf.IRI:
		return string(t), true
	}
	return "", false
}

// check_language_in is `sh:languageIn` (§4.5.4): the value node must be a
// language-tagged literal whose tag matches one of the listed language ranges.
//
// **Matching is RFC 4647 basic filtering**, not equality, which is why
// `property/languageIn-001` expects `"Hill"@en-NZ` to satisfy the range `en`.
// A range matches a tag that equals it or extends it at a subtag boundary, so
// `en` matches `en-NZ` and not `english`.
//
// It is also why this component **cannot fire the family's language-tag
// trigger**, which is worth saying because this is the one task that could have.
// Basic filtering is case-insensitive by definition, so a comparison here can
// never depend on whether the parser folded a tag's case — the question the
// trigger exists to force is not asked.
@(private = "file")
check_language_in :: proc(v: ^Validation, c: Constraint, value: Node_Ref) -> bool {
	term, owned := materialize(v, value)
	defer if owned {
		rdf.destroy_term(term, v.allocator)
	}
	literal, is_literal := term.(rdf.Literal)
	if !is_literal || literal.language == "" {
		return false
	}
	for i in 0 ..< c.values.count {
		allowed, is_allowed_literal := v.s.values[c.values.start + i].(rdf.Literal)
		if is_allowed_literal && language_matches(literal.language, allowed.lexical) {
			return true
		}
	}
	return false
}

// language_matches is RFC 4647 §3.3.1 basic filtering: a range matches a tag
// that equals it, or that extends it at a subtag boundary. Case-insensitive,
// per RFC 4647 and RFC 5646 both.
@(private = "file")
language_matches :: proc(tag, range: string) -> bool {
	if range == "" {
		return false
	}
	if range == "*" {
		return tag != ""
	}
	if len(tag) < len(range) {
		return false
	}
	if !strings.equal_fold(tag[:len(range)], range) {
		return false
	}
	return len(tag) == len(range) || tag[len(range)] == '-'
}

// node_kind_of is the value node's node kind, as the one-element set the
// `sh:nodeKind` bit set compares against.
//
// A bound node answers from its `Term_ID` alone, with no dictionary lookup:
// STORE-A-0001 puts the kind tag in the ID's high bits precisely so this kind
// of question is free. An RDF-star triple term is a fourth kind SHACL 1.0's six
// node kinds do not name, so it satisfies none of them — an empty set, which
// the caller's intersection turns into a violation.
@(private = "file")
node_kind_of :: proc(v: ^Validation, value: Node_Ref) -> Node_Kind {
	if value.bound {
		#partial switch store.id_kind(value.id) {
		case .IRI:
			return NODE_KIND_IRI
		case .Blank_Node:
			return NODE_KIND_BLANK_NODE
		case .Literal:
			return NODE_KIND_LITERAL
		}
		return {}
	}
	#partial switch _ in value.term {
	case rdf.IRI:
		return NODE_KIND_IRI
	case rdf.Blank_Node:
		return NODE_KIND_BLANK_NODE
	case rdf.Literal:
		return NODE_KIND_LITERAL
	}
	return {}
}

// node_is_term reports whether a value node *is* a given model term.
//
// A bound node compares by ID, which is why the binding exists: an integer
// comparison instead of a term comparison, on the engine's inner loop. It also
// makes the absent case correct for free — a term the data store has never seen
// has no ID, so nothing in the graph can equal it.
//
// An unbound node has no ID on either side and compares by term.
@(private = "file")
node_is_term :: proc(v: ^Validation, value: Node_Ref, constraint_index: int, term: rdf.Term) -> bool {
	if value.bound {
		return v.b.constraint_bound[constraint_index] && value.id == v.b.constraint[constraint_index]
	}
	return rdf.equal_term(value.term, term)
}

// materialize turns a value node into a term. `owned` says whether the caller
// must destroy it: kvstore builds terms from the database's bytes, memstore
// borrows its dictionary's, and an unbound node already carries its own.
@(private = "file")
materialize :: proc(v: ^Validation, value: Node_Ref) -> (term: rdf.Term, owned: bool) {
	if !value.bound {
		return value.term, false
	}
	return v.access.load(v.access.load_data, value.id, v.allocator)
}
