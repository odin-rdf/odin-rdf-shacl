package shacl

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
	case .Min_Count, .Max_Count, .Has_Value:
		return .Node_Set
	case .Class, .Datatype, .Node_Kind, .In:
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
	case .Min_Count, .Max_Count, .Has_Value:
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
// whose datatype IRI is exactly the parameter.
//
// Exactly, and by code point: RDF 1.1 Concepts §3.2 forbids further
// normalization of IRIs, so this is string equality and not a judgement call. A
// language-tagged literal carries `rdf:langString` and therefore never
// satisfies `sh:datatype xsd:string`, which falls out of the comparison rather
// than needing a case.
//
// **What is deliberately not here.** §4.3.1 also requires the lexical form to
// be well-formed for the datatype, so `"abc"^^xsd:integer` should violate even
// though the datatype matches. That check belongs with the catalogue
// initiative's value-range components, which need the same lexical-to-value
// machinery; the spine's enabled directories exercise `sh:datatype` only with
// `xsd:string`, whose lexical space is every string. Recorded rather than
// forgotten: `core/property`'s `datatype-ill-formed` is the entry that demands
// it — `"300"^^xsd:byte` is out of range and `"c"^^xsd:byte` is not a number,
// and both must violate against `sh:datatype xsd:byte` even though the datatype
// IRI matches exactly. That directory stays disabled until they do.
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
	return is_literal && literal.datatype == want
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
