package shacl

import "core:strings"
import "core:text/regex"
import regex_common "core:text/regex/common"
import "core:unicode/utf8"

import rdf "rdf:rdf"
import store "store:store"

// Constraint dispatch: the seam the catalogue initiative fills.
//
// Adding a constraint component is four edits: a `Constraint_Kind`, its
// parameter in `compile_constraints`, its scope below — which says *how often*
// it is asked — and a case in `check_value` or `check_node_set`.
//
// **There is a fifth, for components that compare their parameter by ID**, and
// SHACL-T-0015 found it the hard way: `bindings_init` in `validate.odin` resolves
// a constraint's term to a data-store `Term_ID`, and it does so from a
// kind-switch. A component left out of that switch does not fail — it reads its
// parameter as unbound, concludes the data store has never seen it, and reports
// nothing at all. The four property-pair components compiled, dispatched, ran,
// and produced an empty second set on every focus node until their kinds were
// added there. So the earlier claim that no edit is in the evaluator held for
// the spine's seven and does not hold in general.
//
// **Read the corpus entries before writing the component.** Every component
// family SHACL-I-0002 added turned out to have exactly one detail that
// contradicted the obvious implementation — and in each case the obvious version
// passed every test that had been written for it:
//
//   - `sh:uniqueLang` is switched on by the *term* `"true"^^xsd:boolean` rather
//     than by its value. `property/uniqueLang-002` declares `"1"^^xsd:boolean`
//     over two `@en` literals and expects a conforming report.
//   - `sh:lessThan` emits a result per failing **pair**, not per failing value
//     node. `property/lessThan-002` expects four results from two value nodes.
//   - `sh:equals` reports members of the *other* predicate's set, which are not
//     value nodes at all. `node/equals-001` expects one.
//   - `sh:datatype` needs §4.1.2's lexical check, which the spine deferred for a
//     whole initiative because its enabled directories only ever used
//     `xsd:string`, whose lexical space is every string.
//   - `sh:closed` reports `sh:resultPath <the offending predicate>` — a term of
//     the *data* graph, on a node shape that has no path at all — and does not
//     ignore `rdf:type` unless the shapes graph says so. `node/closed-001` and
//     `closed-002` are the pair that show both.
//
// Five families, five traps. The entries are a few minutes to read and the
// alternative is a component that looks right.
//
// **A sixth edit, for a component that asks a new question of the data.**
// `sh:closed` needed the predicate and object of one triple together, which none
// of `Access`'s three read verbs could express, so it added a fourth
// (`Outgoing`, below) and an adapter per backend. That is not a seam edit at all
// — it is the seam admitting the engine had only ever asked for one quad
// position at a time.
//
// **Scope is the thing worth naming**, and it answers exactly one question:
// how often is the component asked? A value-scoped one is asked once per value
// node; a set-scoped one is asked once about the whole value-node set. Getting
// it wrong produces plausible results that are wrong in a way the suite catches
// immediately.
//
// **What a result blames is a separate question, and the two are not the same
// question.** The spine's seven made them look identical — every value-scoped
// component named its node in `sh:value` and every set-scoped one named none,
// which is why `path-complex-001` expects an `sh:hasValue` violation with no
// `sh:value` while `targetClassImplicit-001` expects an `sh:in` violation that
// names one. That correlation was a property of those seven, not a rule, and
// SHACL-T-0015 is where it breaks: `sh:equals` is asked once about the set and
// reports **one result per member of the symmetric difference**, each naming
// that member — including members that are not value nodes at all, because they
// came from the other predicate. `node/equals-001` expects exactly that.
//
// So scope decides the call, and `emit_result`'s `has_value` decides the blame.
// A component reaching for a third scope is probably reaching for this
// distinction instead.
//
// Dispatch is a switch rather than a table of procedure pointers. That is
// SPARQL-T-0011's finding applied unchanged: the family's no-dynamic-dispatch
// default is free here, and its counterweight — that procedure pointers
// measured as noise once a call does real work — is the escape hatch if the
// catalogue ever wants one.

// Outgoing streams the predicate and object of every triple with `subject` as
// its subject — the properties a node actually uses, and their values.
//
// The fourth way this engine reads the data graph, and the first added since the
// spine. `Scan` and `Step` both yield one position of a matched quad, which
// answers every question the engine had until `sh:closed`: that component needs
// the predicate and the object of the *same* triple, and no sequence of
// single-position reads gives a pair without matching twice.
//
// **The gap is in `Access`, not in odin-rdf-store.** The published match
// interface returns whole `Encoded_Quad`s, so every backend already had the
// answer; what was too narrow was this package's own adapter. Recorded in
// `docs/store-evidence.md`, because a narrowing that has to be widened is worth
// as much to the log as a capability that was missing.
//
// `visit` returning false stops the read, and Outgoing then returns false, so
// early exit reaches the store rather than being simulated above it — the same
// contract `Scan` has. The graph is the adapter's, for the same reason.
Outgoing :: #type proc(
	data: rawptr,
	subject: store.Term_ID,
	visit: proc(data: rawptr, predicate, object: store.Term_ID) -> bool,
	visit_data: rawptr,
) -> bool

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
	// is not, because uniqueness is a property of the set. §4.4.5 asks for one
	// result per language used twice, which no per-value check could produce.
	// The property-pair components are set-scoped for two reasons. `sh:equals`
	// and `sh:disjoint` compare set against set and could not be answered from
	// one node; the ordering pair could be, but the second read of the data
	// graph is per *focus* node, so asking per value node would repeat it once
	// for every value.
	//
	// The qualified pair joins them, and reads as though it should not: it looks
	// like `sh:node` with a count bolted on. It is not — the count is over the
	// value-node *set*, so `qualifiedValueShape-001` expects one result naming the
	// focus node and the path and **no `sh:value`**, because no single value node
	// is to blame for there being two of them where three were wanted.
	case .Min_Count,
	     .Max_Count,
	     .Has_Value,
	     .Unique_Lang,
	     .Equals,
	     .Disjoint,
	     .Less_Than,
	     .Less_Than_Or_Equals,
	     .Qualified_Min_Count,
	     .Qualified_Max_Count:
		return .Node_Set
	//
	// `sh:closed` is value-scoped and reads as though it were not, which is the
	// mirror image of `sh:uniqueLang` above. It looks like a statement about the
	// shape — "this shape is closed" — and §4.8.1 asks it of each **value node**,
	// whose outgoing triples are what it inspects. On a node shape the two are
	// indistinguishable, since the single value node is the focus node, and that
	// is every entry the corpus has; on a property shape they differ, and the
	// spec's wording is what decides it rather than the corpus.
	//
	// The four logical combinators are value-scoped, and the corpus is
	// unambiguous about it in both directions: `node/*`'s entries put them on
	// node shapes and name the focus node in `sh:value`, while
	// `property/or-datatypes-001` puts one on a property shape with four value
	// nodes and expects **three** results, one per value node that fails.
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
	     .Language_In,
	     .Closed,
	     .And,
	     .Or,
	     .Not,
	     .Xone,
	     .Node:
		return .Value
	}
	return .Value
}

// check_shape runs every constraint a shape declares against one focus node's
// value nodes.
//
// A failure abandons the remaining constraints as a stop does. That mattered
// from SHACL-T-0017 rather than from the spine: until the logical combinators,
// the only failure was shape recursion, which `push_frame` raises *after* this
// procedure has run, so nothing here could ever see one. A suppressed run raises
// it from inside a constraint check, and the constraints after it would
// otherwise keep reporting into a report the caller must already discard.
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
				if v.stopped || v.failure != .None {
					return
				}
			}
		}
		if v.stopped || v.failure != .None {
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
		// §4.8.2: the term must be *among* the value nodes. One violation for
		// the shape, not one per node that is not it.
		for n in 0 ..< count {
			if node_is_term(v, value_set_at(values, n), constraint_index, c.term) {
				return
			}
		}
		emit_result(v, shape_index, values.focus, {}, false, .Has_Value)

	case .Unique_Lang:
		check_unique_lang(v, shape_index, values)

	case .Equals, .Disjoint, .Less_Than, .Less_Than_Or_Equals:
		check_property_pair(v, shape_index, c, constraint_index, values)

	case .Qualified_Min_Count, .Qualified_Max_Count:
		check_qualified(v, shape_index, c, values)
	}
}

// check_qualified is `sh:qualifiedValueShape` with `sh:qualifiedMinCount`,
// `sh:qualifiedMaxCount` and `sh:qualifiedValueShapesDisjoint` (§4.7.3): how
// many of a shape's value nodes conform to a given shape, against a bound.
//
// **The count is the constraint, so the result blames nobody in particular.** It
// names the focus node and the shape's path and carries no `sh:value` — there is
// no single value node at fault when the fault is that there were two of them
// and three were wanted. `qualifiedValueShape-001` is the entry that says so.
//
// **Disjointness is an exclusion, not a second test.** A value node that
// conforms to the qualified shape is *not* counted if it also conforms to any
// sibling property shape's qualified shape, where the siblings were resolved at
// compile time (`compile_qualified_siblings`). The exclusion is symmetric, and
// `qualifiedValueShapesDisjoint-001` is what proves it has to be: one node that
// is both a finger and a thumb drops out of the finger count *and* the thumb
// count, and the entry expects both to violate.
//
// Both counts share one `sh:qualifiedValueShape`, so a shape carrying a minimum
// and a maximum walks its value nodes twice. That is one suppressed validation
// per value node per bound, which is the cost SHACL-A-0002 declined to memoise
// until a consumer measured it; a shapes graph wanting one walk can write one
// bound.
@(private = "file")
check_qualified :: proc(v: ^Validation, shape_index: int, c: Constraint, values: Value_Set) {
	operands := constraint_shapes(v.s, c)
	if len(operands) == 0 {
		// `sh:qualifiedValueShape` naming a node the compile did not turn into a
		// shape. Nothing to count against, so nothing is counted — the same
		// silence §4.7.3 asks for when the parameter is absent entirely.
		return
	}
	siblings := constraint_siblings(v.s, c)

	conformed := 0
	for n in 0 ..< value_set_count(values) {
		value := value_set_at(values, n)
		if !node_conforms(v, operands[0], value) {
			continue
		}
		if v.failure != .None {
			return
		}
		excluded := false
		for sibling in siblings {
			if node_conforms(v, sibling, value) {
				excluded = true
			}
			if v.failure != .None {
				return
			}
			if excluded {
				break
			}
		}
		if !excluded {
			conformed += 1
		}
	}
	if v.failure != .None {
		return
	}

	violates := c.kind == .Qualified_Min_Count ? conformed < c.count : conformed > c.count
	if violates {
		emit_result(v, shape_index, values.focus, {}, false, c.kind)
	}
}

// check_property_pair is the four components of §4.5, which compare a shape's
// value nodes against the values of another predicate **at the same focus
// node**.
//
// This is the first place the engine reads the data graph a second time from
// the focus node, and it does so through `Access.step` — the same procedure a
// predicate path uses, with the graph bound by the instantiation package. No new
// store capability was wanted and none is used, so `docs/store-evidence.md` gains
// nothing from this task.
//
// **Absence is emptiness here, not failure.** A predicate the data store has
// never seen, or an unbound focus node, can appear in no triple, so the second
// set is empty — and an empty second set is a real answer: `sh:equals` on it
// reports every value node, `sh:lessThan` on it reports nothing, and
// `property/equals-001` and `lessThan-001` expect exactly those two.
@(private = "file")
check_property_pair :: proc(
	v: ^Validation,
	shape_index: int,
	c: Constraint,
	constraint_index: int,
	values: Value_Set,
) {
	// §4.5.3–4.5.4: the ordering pair may be used at property shapes only.
	// `sh:equals` and `sh:disjoint` carry no such restriction — `node/equals-001`
	// puts one on a node shape.
	if c.kind == .Less_Than || c.kind == .Less_Than_Or_Equals {
		if v.s.shapes[shape_index].path < 0 {
			return
		}
	}

	others := make([dynamic]store.Term_ID, v.allocator)
	defer delete(others)
	if values.focus.bound && v.b.constraint_bound[constraint_index] {
		v.access.step(v.access.data, values.focus.id, v.b.constraint[constraint_index], false, &others)
	}

	count := value_set_count(values)
	#partial switch c.kind {
	case .Equals:
		// §4.5.1: the two sets must be equal, so every member of the symmetric
		// difference is a result naming itself — in both directions. The second
		// loop is the one that surprises: it reports a node that is *not* a value
		// node, which is why `property/equals-001` expects a result for a focus
		// node whose value-node set is empty.
		for n in 0 ..< count {
			value := value_set_at(values, n)
			if !node_among(value, others[:]) {
				emit_result(v, shape_index, values.focus, value, true, .Equals)
				if v.stopped {
					return
				}
			}
		}
		for id in others {
			if !id_among(values, id) {
				emit_result(v, shape_index, values.focus, Node_Ref{id = id, bound = true}, true, .Equals)
				if v.stopped {
					return
				}
			}
		}

	case .Disjoint:
		// §4.5.2: the sets must share nothing, so every member of the
		// intersection is a result. One direction is enough — a shared node is a
		// value node by definition.
		for n in 0 ..< count {
			value := value_set_at(values, n)
			if node_among(value, others[:]) {
				emit_result(v, shape_index, values.focus, value, true, .Disjoint)
				if v.stopped {
					return
				}
			}
		}

	case .Less_Than, .Less_Than_Or_Equals:
		// §4.5.3–4.5.4: every value node must compare against **every** member of
		// the other set, and a result is emitted **per failing pair** rather than
		// per failing value node.
		//
		// That is not the natural reading and `property/lessThan-002` is what
		// forces it: two values against two incomparable others produce *four*
		// results, with `sh:value` repeated twice for each value node. A
		// per-node loop with a break would produce two and look right.
		for n in 0 ..< count {
			value := value_set_at(values, n)
			for id in others {
				if !pair_ordered(v, c.kind, value, id) {
					emit_result(v, shape_index, values.focus, value, true, c.kind)
					if v.stopped {
						return
					}
				}
			}
		}
	}
}

// pair_ordered compares one value node against one member of the other set,
// by **value** — which is what makes `sh:lessThan` a consumer of SHACL-T-0012
// rather than of term comparison.
//
// `.Incomparable` fails, and it fails for the same reason the value-range
// components treat it that way: the spec's condition is that the comparison
// holds. `property/lessThan-002` is the entry that measures it — integers
// against strings, where every pair is incomparable and every pair is a result.
@(private = "file")
pair_ordered :: proc(v: ^Validation, kind: Constraint_Kind, value: Node_Ref, other: store.Term_ID) -> bool {
	left, left_owned := materialize(v, value)
	defer if left_owned {
		rdf.destroy_term(left, v.allocator)
	}
	right, right_owned := v.access.load(v.access.load_data, other, v.allocator)
	defer if right_owned {
		rdf.destroy_term(right, v.allocator)
	}

	order := compare_values(value_of(left), value_of(right))
	#partial switch kind {
	case .Less_Than:
		return order == .Less
	case .Less_Than_Or_Equals:
		return order == .Less || order == .Equal
	}
	return false
}

// node_among and id_among are the set membership the equality pair needs, both
// by `Term_ID` — which is the whole point of STORE-A-0001 on a comparison that
// runs once per value node per focus node.
//
// An unbound value node is in no set of IDs: a term the data store has never
// seen cannot be the object of any triple, so it cannot be among the values of
// the other predicate.
@(private = "file")
node_among :: proc(value: Node_Ref, ids: []store.Term_ID) -> bool {
	if !value.bound {
		return false
	}
	for id in ids {
		if id == value.id {
			return true
		}
	}
	return false
}

@(private = "file")
id_among :: proc(values: Value_Set, id: store.Term_ID) -> bool {
	for n in 0 ..< value_set_count(values) {
		ref := value_set_at(values, n)
		if ref.bound && ref.id == id {
			return true
		}
	}
	return false
}

// check_unique_lang is `sh:uniqueLang` (§4.4.5): no two value nodes may carry
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
	// `sh:closed` returns before the shared tail below, because it is the one
	// value-scoped component that emits **several** results for one value node —
	// one per triple it objects to — and each names a different `sh:resultPath`
	// and `sh:value`. There is nothing for a single `ok` to carry.
	if c.kind == .Closed {
		check_closed(v, shape_index, c, focus, value)
		return
	}

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
	case .And, .Or, .Not, .Xone, .Node:
		ok = check_logical(v, c, value)
	case .Min_Count,
	     .Max_Count,
	     .Has_Value,
	     .Unique_Lang,
	     .Equals,
	     .Disjoint,
	     .Less_Than,
	     .Less_Than_Or_Equals,
	     .Closed,
	     .Qualified_Min_Count,
	     .Qualified_Max_Count:
		return
	}
	if !ok {
		emit_result(v, shape_index, focus, value, true, c.kind)
	}
}

// check_logical is the four logical combinators of §4.6 — `sh:not`, `sh:and`,
// `sh:or`, `sh:xone` — and `sh:node` (§4.7.1), which belongs here rather than in
// a procedure of its own because it *is* one of them: `sh:not` without the
// inversion, and the degenerate `sh:and` of a single shape.
//
// **The value node becomes the inner shape's focus node.** That is the sentence
// the whole family turns on, and it is what makes these components a consumer of
// suppressed validation rather than of anything new: each operand is asked
// "does *this node* conform to you?" through `node_conforms` (SHACL-A-0002),
// which is the ordinary walk with the visitor swapped for a probe. None of the
// operands' own results reaches the caller — `property/not-001`'s inner shape
// produces a `sh:datatype` violation for every value node that is not an
// integer, and the report contains exactly one result, a `sh:not`.
//
// **The result names the shape that carries the combinator, not the branch that
// failed.** `node/and-001` expects `sh:sourceShape ex:Rectangle` even though the
// branch that failed is an anonymous shape inside its list, which falls out of
// `emit_result` taking the enclosing shape — but it is worth saying, because a
// reader looking for `sh:detail`-style nesting will not find it and it is not an
// omission (SHACL-I-0002 measured `sh:detail` as absent from the corpus).
//
// **A failure answers nothing.** If a suppressed run hit shape recursion it
// could not establish conformance, so this returns "satisfied" and emits no
// result; the failure is already on the `Validation` and the walk abandons at
// the next check. Reporting a violation instead would put a result in the
// caller's report that the engine never established.
//
// Short-circuiting is not an optimisation here so much as the natural reading:
// `sh:and` stops at the first branch that fails, `sh:or` at the first that
// holds, and `sh:xone` at the second — after two, "exactly one" is settled
// whatever the rest do. Each branch skipped is a whole suppressed walk not run.
@(private = "file")
check_logical :: proc(v: ^Validation, c: Constraint, value: Node_Ref) -> bool {
	operands := constraint_shapes(v.s, c)

	// An empty list is not an error and the three answers differ: the conjunction
	// of nothing holds, the disjunction of nothing does not, and exactly-one of
	// nothing does not. No corpus entry writes one; these fall out of the loops
	// below rather than being special-cased, and are recorded here because a
	// reader will wonder.
	#partial switch c.kind {
	case .Not:
		// One operand, and the polarity inverted: this violates when the value
		// node *did* conform. A `sh:not` with several values compiles to several
		// constraints, so the loop still runs exactly once.
		for index in operands {
			conforms := node_conforms(v, index, value)
			if v.failure != .None {
				return true
			}
			if conforms {
				return false
			}
		}
		return true

	// `sh:node` and `sh:and` are the same loop, and saying so is more honest than
	// giving `sh:node` a case that reads identically: every named shape must be
	// conformed to. They differ only in how many shapes the compile put in the
	// span — one, or an RDF list's worth — and in which component a result names.
	case .Node, .And:
		for index in operands {
			conforms := node_conforms(v, index, value)
			if v.failure != .None {
				return true
			}
			if !conforms {
				return false
			}
		}
		return true

	case .Or:
		for index in operands {
			conforms := node_conforms(v, index, value)
			if v.failure != .None {
				return true
			}
			if conforms {
				return true
			}
		}
		return false

	case .Xone:
		// **Exactly one, counted rather than found**, and `node/xone-duplicate`
		// is the entry that makes the difference visible: `sh:xone ( ex:s2 ex:s2 )`
		// over a node that conforms to `ex:s2` conforms to *both* copies, and is
		// expected to violate. An at-least-one reading passes it, and so does a
		// reading that deduplicates the list before counting.
		conformed := 0
		for index in operands {
			conforms := node_conforms(v, index, value)
			if v.failure != .None {
				return true
			}
			if conforms {
				conformed += 1
				if conformed > 1 {
					return false
				}
			}
		}
		return conformed == 1
	}
	return true
}

// check_closed is `sh:closed` with `sh:ignoredProperties` (§4.8.1): the value
// node may use no predicate beyond those the shape's property shapes declare and
// those the shapes graph explicitly ignores.
//
// **This is the component that asks the store a question the spine never
// asked** — which predicates a node actually uses — and it is why SHACL-I-0002
// singled it out as the likeliest source of store evidence. The answer is one
// match with the subject and the graph bound and the other two positions
// wildcard, which the published interface has always served; what was too narrow
// was `Access`, whose three existing verbs each yield a single quad position. See
// `Outgoing` above and `docs/store-evidence.md`.
//
// **A result per offending triple, not per offending predicate**, and each names
// that triple: `sh:resultPath` is the predicate and `sh:value` is the object.
// `node/closed-001` measures it — `ex:InvalidInstance1` carries `rdf:type` and
// `ex:otherProperty` outside the shape and expects two results, one naming
// `ex:SomeClass` and one naming `4`. The same entry settles something easy to
// assume away: **`rdf:type` is not ignored by default.** It is an ordinary
// predicate here, and `closed-002` is the same data with
// `sh:ignoredProperties ( rdf:type )` and one result instead of two.
//
// An unbound value node is the subject of no triple — nothing in the graph can
// mention a term the dictionary does not hold — so it uses no predicates and
// conforms. That is the emptiness reading, and it is the right one here: this
// component objects to what a node *has*, not to what it lacks.
@(private = "file")
check_closed :: proc(
	v: ^Validation,
	shape_index: int,
	c: Constraint,
	focus: Focus_Node,
	value: Node_Ref,
) {
	if !value.bound {
		return
	}
	state := Closed_Check {
		v           = v,
		shape_index = shape_index,
		constraint  = c,
		focus       = focus,
	}
	v.access.outgoing(v.access.data, value.id, closed_visit, &state)
}

@(private = "file")
Closed_Check :: struct {
	v:           ^Validation,
	shape_index: int,
	constraint:  Constraint,
	focus:       Focus_Node,
}

// closed_visit judges one of the value node's triples.
//
// The allowed set is compared by `Term_ID`, which is what the compile-time work
// in `compile_closed_sets` bought: the predicates are resolved to data-store IDs
// once per validation, so this is an integer scan over a handful of entries per
// triple rather than a term comparison. An allowed predicate the data store has
// never seen is unbound and matches nothing, which is correct — a predicate that
// appears in a triple is in the dictionary by definition, so an unbound entry
// cannot be the one being judged.
@(private = "file")
closed_visit :: proc(data: rawptr, predicate, object: store.Term_ID) -> bool {
	state := cast(^Closed_Check)data
	v := state.v
	c := state.constraint

	for i in 0 ..< c.values.count {
		index := c.values.start + i
		if v.b.value_bound[index] && v.b.value[index] == predicate {
			return true
		}
	}

	emit_result(
		v,
		state.shape_index,
		state.focus,
		Node_Ref{id = object, bound = true},
		true,
		.Closed,
		Node_Ref{id = predicate, bound = true},
		true,
	)
	return !v.stopped
}

// check_class is `sh:class` (§4.1.1): the value node must be a SHACL instance
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

// check_datatype is `sh:datatype` (§4.1.2): the value node must be a literal
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

// check_in is `sh:in` (§4.8.3): the value node must be a member of the list.
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

// check_range is the four value-range components (§4.3.1–4.3.4):
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
// `sh:minLength`, `sh:maxLength` (§4.4.1–4.4.2), and `sh:pattern` (§4.4.3).
//
// They share a procedure because they share the hard part, which is deciding
// what a node's string *is*. §4.4 answers it the same way for all three, and it
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
// **Length is in code points, not bytes.** §4.4.1 counts the string length as
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

// node_string is what §4.4 means by a value node's string: a literal's lexical
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

// check_language_in is `sh:languageIn` (§4.4.4): the value node must be a
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
