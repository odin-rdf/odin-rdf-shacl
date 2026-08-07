package shacl

import "base:runtime"
import "core:fmt"

import rdf "rdf:rdf"

// The validation report graph (SHACL §3).
//
// A Report is an ordinary consumer of the result stream that happens to build
// a graph. That layering is deliberate: the stream is the primitive, and
// report building sits on top, so a caller that only wants a conformance
// answer never pays for a graph, and a caller that wants both gets them from
// one traversal.
//
// It also solves `sh:conforms`, which is the one genuinely blocking part of a
// report: it is only knowable when the last result has been seen. Emitting the
// report *head* at `report_finish`, after the stream has drained, handles that
// without buffering a single result.
//
// The graph is `[]rdf.Triple` — the family's data model, not a serialisation.
// Writing it out is odin-rdf-parser's job through any of its four emitters,
// which is the "primitives over frameworks" line: this produces the graph and
// leaves the format to the caller.

// Report accumulates a validation report graph.
//
// It owns every term in the graph, including the blank-node labels it
// generates, and frees them at `report_destroy`. The triples it hands out
// borrow from it.
//
// **A report names nodes in three graphs, and their blank nodes are
// standardised apart** — the merge rule RDF has always had, and the source of
// the only two bugs SHACL-T-0019 found. A blank node in a report is one of:
//
//	_:b…   the data graph's, exactly as the store labelled it — `sh:focusNode`
//	       and `sh:value`, which is how a result says *which* unnamed node
//	       failed, so these are the labels a consumer can act on
//	_:s…   the shapes graph's, its store label prefixed with `s` —
//	       `sh:sourceShape` when the shape is a blank node
//	_:r…   the report's own: the report node, each result node, and the
//	       structure of a non-predicate `sh:resultPath`. Meaningless outside
//	       the report
//
// See `fresh_blank` and `shape_term` for why, and for what a caller supplying
// its own `Term_Loader` owes.
Report :: struct {
	triples:   [dynamic]rdf.Triple,
	node:      rdf.Term, // the sh:ValidationReport node
	conforms:  bool,
	finished:  bool,
	counter:   int,
	terms:     Term_Table,
	allocator: runtime.Allocator,
}

// report_init prepares an empty report and writes its head node. Every
// allocation the report makes comes from `allocator`, and `report_destroy`
// returns all of it.
report_init :: proc(r: ^Report, allocator := context.allocator) {
	r.allocator = allocator
	r.triples = make([dynamic]rdf.Triple, allocator)
	r.conforms = true
	r.finished = false
	r.counter = 0
	term_table_init(&r.terms, allocator)
	r.node = fresh_blank(r)
	append(&r.triples, triple(r, r.node, rdf.IRI(rdf.RDF_TYPE), rdf.IRI(VALIDATION_REPORT)))
}

// report_destroy frees the graph and every term in it. The triples
// `report_triples` handed out are invalid afterwards.
report_destroy :: proc(r: ^Report) {
	delete(r.triples)
	term_table_destroy(&r.terms)
	r^ = {}
}

// report_triples is the graph. Valid until `report_destroy`, and complete only
// after `report_finish` — before that it is missing `sh:conforms`.
report_triples :: proc(r: ^Report) -> []rdf.Triple {
	return r.triples[:]
}

// report_conforms reports whether any result broke conformance. Meaningful at
// any time, final after the stream has drained.
report_conforms :: proc(r: ^Report) -> bool {
	return r.conforms
}

// report_finish writes the report head. Call it once, after the last result.
//
// `sh:conforms` is emitted here rather than at init because its value is not
// known until then — which is exactly why results stream and the head trails,
// instead of the whole result set being buffered so the head can come first.
report_finish :: proc(r: ^Report) {
	if r.finished {
		return
	}
	r.finished = true
	lexical := r.conforms ? "true" : "false"
	append(
		&r.triples,
		triple(
			r,
			r.node,
			rdf.IRI(CONFORMS),
			rdf.Literal{lexical = lexical, datatype = rdf.XSD_BOOLEAN},
		),
	)
}

// report_add folds one result into the graph.
//
// `load` materialises the bound node IDs; an unbound node — a `sh:targetNode`
// the data graph never mentions — carries its term already and needs no
// lookup, which is the whole reason Node_Ref has that shape.
report_add :: proc(r: ^Report, s: ^Shapes, result: Result, load: Term_Loader, load_data: rawptr) {
	// Any result at all makes the graph non-conforming (§3.1); severity is
	// carried into the report but has no say in `sh:conforms`.
	r.conforms = false

	node := fresh_blank(r)
	append(&r.triples, triple(r, r.node, rdf.IRI(RESULT), node))
	append(&r.triples, triple(r, node, rdf.IRI(rdf.RDF_TYPE), rdf.IRI(VALIDATION_RESULT)))
	append(&r.triples, triple(r, node, rdf.IRI(FOCUS_NODE), node_term(r, result.focus, load, load_data)))

	if result.has_value {
		append(&r.triples, triple(r, node, rdf.IRI(VALUE), node_term(r, result.value, load, load_data)))
	}

	// `sh:resultPath` comes from the shape's compiled path, except for the one
	// component whose path is a term of the data graph: `sh:closed` names the
	// predicate it objected to (§4.8.1), which no compiled path can express and
	// which a node shape — where `path` is -1 — carries all the same.
	if result.has_path_predicate {
		append(
			&r.triples,
			triple(r, node, rdf.IRI(RESULT_PATH), node_term(r, result.path_predicate, load, load_data)),
		)
	} else if result.path >= 0 {
		append(&r.triples, triple(r, node, rdf.IRI(RESULT_PATH), write_path(r, s, result.path)))
	}

	append(&r.triples, triple(r, node, rdf.IRI(RESULT_SEVERITY), result.severity))
	append(
		&r.triples,
		triple(r, node, rdf.IRI(SOURCE_CONSTRAINT_COMPONENT), rdf.IRI(component_iri(result.component))),
	)
	append(&r.triples, triple(r, node, rdf.IRI(SOURCE_SHAPE), shape_term(r, result_source_shape(s, result))))

	// Only what the shape declared: no processor-generated messages, ever.
	//
	// The predicate changes on the way in: a shape declares `sh:message`, a
	// result carries `sh:resultMessage` (§3.1). They are different properties
	// and the report vocabulary means the second one.
	for message in result_messages(s, result) {
		append(
			&r.triples,
			triple(
				r,
				node,
				rdf.IRI(RESULT_MESSAGE),
				rdf.Literal {
					lexical = message.text,
					language = message.language,
					datatype = message.language != "" ? rdf.RDF_LANG_STRING : rdf.XSD_STRING,
				},
			),
		)
	}
}

// write_path serialises a compiled path back into RDF and returns the term to
// use as the `sh:resultPath` object — the inverse of what the compiler did.
//
// A predicate path is its IRI and adds no triples. Every other form is a
// blank-node structure, and sequences and alternatives are RDF lists, so a
// single result can contribute a dozen triples of path. The suite really does
// expect this: `path-inverse-001`'s expected report carries
// `sh:resultPath [ sh:inversePath ex:child ]`, which is also why report
// comparison has to be blank-node isomorphism rather than a label match.
//
// Ordinary recursion, over the path structure and never over data — the same
// reasoning as the evaluator, and no store access at all here.
@(private = "file")
write_path :: proc(r: ^Report, s: ^Shapes, path: int) -> rdf.Term {
	node := s.paths[path]
	switch node.kind {
	case .Predicate:
		return intern(&r.terms, node.predicate)

	case .Inverse, .Zero_Or_More, .One_Or_More, .Zero_Or_One:
		operands := path_operands(s, node)
		subject := fresh_blank(r)
		predicate: string
		switch node.kind {
		case .Inverse:
			predicate = INVERSE_PATH
		case .Zero_Or_More:
			predicate = ZERO_OR_MORE_PATH
		case .One_Or_More:
			predicate = ONE_OR_MORE_PATH
		case .Zero_Or_One:
			predicate = ZERO_OR_ONE_PATH
		case .Predicate, .Sequence, .Alternative:
		}
		append(&r.triples, triple(r, subject, rdf.IRI(predicate), write_path(r, s, operands[0])))
		return subject

	case .Sequence:
		return write_list(r, s, path_operands(s, node))

	case .Alternative:
		subject := fresh_blank(r)
		list := write_list(r, s, path_operands(s, node))
		append(&r.triples, triple(r, subject, rdf.IRI(ALTERNATIVE_PATH), list))
		return subject
	}
	return nil
}

// write_list writes an RDF list of paths and returns its head.
@(private = "file")
write_list :: proc(r: ^Report, s: ^Shapes, operands: []int) -> rdf.Term {
	if len(operands) == 0 {
		return rdf.IRI(rdf.RDF_NIL)
	}
	head := fresh_blank(r)
	cell := head
	for op, i in operands {
		append(&r.triples, triple(r, cell, rdf.IRI(rdf.RDF_FIRST), write_path(r, s, op)))
		if i == len(operands) - 1 {
			append(&r.triples, triple(r, cell, rdf.IRI(rdf.RDF_REST), rdf.IRI(rdf.RDF_NIL)))
		} else {
			next := fresh_blank(r)
			append(&r.triples, triple(r, cell, rdf.IRI(rdf.RDF_REST), next))
			cell = next
		}
	}
	return head
}

// node_term resolves a Node_Ref into a term the report owns.
@(private = "file")
node_term :: proc(r: ^Report, ref: Node_Ref, load: Term_Loader, load_data: rawptr) -> rdf.Term {
	if !ref.bound {
		return intern(&r.terms, ref.term)
	}
	term, owned := load(load_data, ref.id, r.allocator)
	result := intern(&r.terms, term)
	if owned {
		rdf.destroy_term(term, r.allocator)
	}
	return result
}

// shape_term resolves a **shapes-graph** term into the report's own storage.
// Only `sh:sourceShape` uses it, because it is the only place a shapes-graph
// term reaches a report as a node rather than as a vocabulary IRI.
//
// An IRI or a literal passes through. A blank node is **relabelled**, and that
// is this procedure's entire reason to exist (SHACL-T-0019): a report names
// nodes in two different graphs, and merging two graphs without standardising
// their blank nodes apart is the oldest mistake in RDF. Both backends label
// loaded blank nodes `b0`, `b1`, … from zero, per store — so a shapes graph's
// first blank node and a data graph's first blank node arrive here carrying the
// same label while denoting nothing like each other, and a report that took
// both at face value would assert `sh:sourceShape _:b0 ; sh:value _:b0` and mean
// that the shape and the value it blamed were the same node.
//
// The data graph's labels are the ones kept, because they are the ones a
// consumer can act on: `sh:value _:b0` is how a result says *which* unnamed node
// failed, and that is only useful if it is the store's own name for it. So the
// shapes graph is the side that moves, to `s` + its label. A consumer resolving
// a blank-node source shape back to the shapes graph strips the `s`.
//
// The suite cannot see any of this and could not have found it. Every `core/`
// entry names one file as both its data graph and its shapes graph, so the two
// loads assign identical labels and conflating them is accidentally correct;
// and the comparison is by isomorphism, so relabelling is invisible either way.
// It is a defect a consumer would have hit on the first shapes graph kept in a
// separate file from its data.
@(private = "file")
shape_term :: proc(r: ^Report, term: rdf.Term) -> rdf.Term {
	blank, is_blank := term.(rdf.Blank_Node)
	if !is_blank {
		return intern(&r.terms, term)
	}
	label := fmt.aprintf("s%s", string(blank), allocator = r.allocator)
	defer delete(label, r.allocator)
	return intern(&r.terms, rdf.Blank_Node(label))
}

// fresh_blank mints a blank node the report owns: the report node, each
// result node, and the blank-node structure of a non-predicate
// `sh:resultPath`.
//
// **The `r` is the whole point of the label** (SHACL-T-0019). A report graph
// mixes blank nodes from three graphs, and this is one of the two places they
// are standardised apart — see `shape_term` for the other, and for the general
// argument. The three namespaces:
//
//	b…   the data graph's, untouched — the label the store gave it
//	s…   the shapes graph's, prefixed by shape_term
//	r…   the report's own, minted here
//
// This one minted `b0`, `b1`, … until SHACL-T-0019, which put it in direct
// collision with the first namespace and produced a wrong graph rather than an
// ugly one: in `core/property/nodeKind-001` — six blank-node property shapes
// over data with three blank nodes — a result node and the source shape it
// blamed came out as the same term, and the report asserted
// `_:b3 sh:sourceShape _:b3`. That one the suite did catch, as an isomorphism
// failure, which is what an isomorphism check is for: conflating two nodes is
// invisible to any comparison that only counts triples.
//
// The residual contract, since a prefix is a convention and not a proof:
// borrowed blank-node labels must not begin with `r` or `s`. Both shipped
// backends generate `b` followed by decimal digits and nothing else, so it holds
// by construction there; a caller writing its own `Term_Loader` is the one case
// that has to know.
//
// Beyond that the labels carry no meaning — report comparison is by
// isomorphism — and they are sequential only because a counter is the cheapest
// way to be distinct.
@(private = "file")
fresh_blank :: proc(r: ^Report) -> rdf.Term {
	label := fmt.aprintf("r%d", r.counter, allocator = r.allocator)
	defer delete(label, r.allocator)
	r.counter += 1
	return intern(&r.terms, rdf.Blank_Node(label))
}

// triple interns each term into the report's own storage, so the graph
// outlives whatever produced it — the shapes model, the store, both.
@(private = "file")
triple :: proc(r: ^Report, subject, predicate, object: rdf.Term) -> rdf.Triple {
	return rdf.Triple {
		subject = intern(&r.terms, subject),
		predicate = intern(&r.terms, predicate),
		object = intern(&r.terms, object),
	}
}
