package shacl

import "base:runtime"

import rdf "rdf:rdf"
import store "store:store"

// Shapes-graph compilation.
//
// The shapes graph is read **through the match interface** (SHACL-A-0001
// decision 1), and the access pattern is random rather than sequential:
// reading a property shape means following `sh:property` to a node and then
// reading `sh:path`, `sh:minCount`, `sh:class` off *that* node. Compiling from
// the parser's stream instead would mean buffering the whole document and
// building a private index over it — a store, reimplemented worse — and it
// would read the entire graph where this reads only what the shapes reach.
// That matters more here than it looks: in the W3C suite the shapes graph and
// the data graph are usually the same document.
//
// **Why this is one long procedure.** SPARQL-T-0011 established that a generic
// procedure taking `$`-procedure constants and calling itself hangs the Odin
// compiler (dev-2026-07) rather than failing. Shape and path structures are
// recursive, so the recursion is carried in explicit worklists inside a single
// generic procedure, and every helper that issues a query is generic-but-flat.
// Pure logic — classifying a node kind, reading an integer — lives in ordinary
// non-generic procedures in query.odin.
//
// The two cold operations reach the compiler as ordinary procedure pointers
// rather than compile-time constants, the same split odin-rdf-sparql uses:
// compilation runs once over a small graph, and SPARQL-T-0011 measured
// procedure-pointer dispatch as noise even on a hot path.

// Term_Loader materializes an ID into a term. `owned` reports whether the
// caller must destroy it: memstore borrows its dictionary's storage, kvstore
// builds the term from the database's bytes.
Term_Loader :: #type proc(
	data: rawptr,
	id: store.Term_ID,
	allocator: runtime.Allocator,
) -> (
	term: rdf.Term,
	owned: bool,
)

// Term_Finder is the non-interning direction: it never assigns an ID, so
// compiling a shapes graph never writes to the store it reads.
Term_Finder :: #type proc(data: rawptr, term: rdf.Term) -> (id: store.Term_ID, found: bool)

// Vocab holds the shapes graph's IDs for the vocabulary the compiler asks
// about. A term the store has never seen has no ID, and no triple can mention
// it — `found` false means every query using it would be empty, so it is
// skipped rather than run.
@(private)
Vocab :: struct {
	ids:   map[string]store.Term_ID,
	found: map[string]bool,
}

@(private)
VOCAB_TERMS := []string {
	NODE_SHAPE,
	PROPERTY_SHAPE,
	PROPERTY,
	PATH,
	DEACTIVATED,
	MESSAGE,
	SEVERITY,
	VIOLATION,
	WARNING,
	INFO,
	TARGET_NODE,
	TARGET_CLASS,
	TARGET_SUBJECTS_OF,
	TARGET_OBJECTS_OF,
	INVERSE_PATH,
	ALTERNATIVE_PATH,
	ZERO_OR_MORE_PATH,
	ONE_OR_MORE_PATH,
	ZERO_OR_ONE_PATH,
	MIN_COUNT,
	MAX_COUNT,
	CLASS,
	DATATYPE,
	NODE_KIND,
	HAS_VALUE,
	IN,
	IRI_KIND,
	BLANK_NODE_KIND,
	LITERAL_KIND,
	BLANK_NODE_OR_IRI,
	BLANK_NODE_OR_LITERAL,
	IRI_OR_LITERAL,
}

// RDFS_CLASS is needed for implicit class targets (§2.1.3.3) and is the only
// non-SHACL vocabulary term the compiler asks about beyond the RDF list
// terms.
RDFS_CLASS :: "http://www.w3.org/2000/01/rdf-schema#Class"

// The target declarations, paired with the kind they compile to. Shared by
// discovery (a node carrying one is a shape) and compilation.
@(private)
TARGET_PREDICATES := [4]struct {
	iri:  string,
	kind: Target_Kind,
} {
	{TARGET_NODE, .Node},
	{TARGET_CLASS, .Class},
	{TARGET_SUBJECTS_OF, .Subjects_Of},
	{TARGET_OBJECTS_OF, .Objects_Of},
}

// compile builds a shapes model from the shapes graph in `dataset` at
// `graph`, a bound graph ID — `store.DEFAULT_GRAPH` for the default graph.
// The model owns everything it holds and outlives the dataset.
//
// On a malformed shapes graph the returned Error names the shape node and the
// parameter at fault. The model is still returned and must still be
// destroyed: its term table is what the error's terms borrow from.
compile :: proc(
	s: ^Shapes,
	dataset: ^$D,
	graph: store.Term_ID,
	load: Term_Loader,
	load_data: rawptr,
	find: Term_Finder,
	find_data: rawptr,
	$MATCH: proc(dataset: ^D, pattern: store.Match_Pattern) -> $It,
	$NEXT: proc(it: ^It) -> (store.Encoded_Quad, bool),
	$DESTROY: proc(it: ^It),
	allocator := context.allocator,
) -> Error {
	shapes_init(s, allocator)
	context.allocator = allocator

	v: Vocab
	v.ids = make(map[string]store.Term_ID, allocator)
	v.found = make(map[string]bool, allocator)
	defer delete(v.ids)
	defer delete(v.found)
	for iri in VOCAB_TERMS {
		id, ok := find(find_data, rdf.IRI(iri))
		v.ids[iri] = id
		v.found[iri] = ok
	}
	rdf_type_id, has_type := find(find_data, rdf.RDF_TYPE)
	rdfs_class_id, has_class := find(find_data, rdf.IRI(RDFS_CLASS))
	first_id, has_first := find(find_data, rdf.RDF_FIRST)
	rest_id, has_rest := find(find_data, rdf.RDF_REST)
	nil_id, has_nil := find(find_data, rdf.RDF_NIL)

	r := Reader(D, It) {
		dataset   = dataset,
		graph     = graph,
		first_id  = first_id,
		has_first = has_first,
		rest_id   = rest_id,
		has_rest  = has_rest,
		nil_id    = nil_id,
		has_nil   = has_nil,
	}

	// ---- Discovery: which nodes are shapes, and of which kind. -----------
	//
	// §2.1.1 defines a shape broadly. The spine implements the three cases the
	// exit-criteria directories need: a node typed sh:NodeShape or
	// sh:PropertyShape, a node carrying a target declaration, and a value of
	// sh:property. The catalogue initiative widens this when sh:node and the
	// logical combinators arrive, which is the other way a node becomes a
	// shape.

	pending: [dynamic]store.Term_ID
	pending_kind: [dynamic]Shape_Kind
	queued: map[store.Term_ID]bool
	compiled: map[store.Term_ID]int
	defer delete(pending)
	defer delete(pending_kind)
	defer delete(queued)
	defer delete(compiled)

	enqueue :: proc(
		pending: ^[dynamic]store.Term_ID,
		pending_kind: ^[dynamic]Shape_Kind,
		queued: ^map[store.Term_ID]bool,
		id: store.Term_ID,
		kind: Shape_Kind,
	) {
		if queued[id] {
			return
		}
		queued[id] = true
		append(pending, id)
		append(pending_kind, kind)
	}

	if has_type && v.found[NODE_SHAPE] {
		subs := subjects_matching(r, rdf_type_id, v.ids[NODE_SHAPE], MATCH, NEXT, DESTROY)
		defer delete(subs)
		for id in subs {
			enqueue(&pending, &pending_kind, &queued, id, .Node)
		}
	}
	if has_type && v.found[PROPERTY_SHAPE] {
		subs := subjects_matching(r, rdf_type_id, v.ids[PROPERTY_SHAPE], MATCH, NEXT, DESTROY)
		defer delete(subs)
		for id in subs {
			enqueue(&pending, &pending_kind, &queued, id, .Property)
		}
	}
	for entry in TARGET_PREDICATES {
		if !v.found[entry.iri] {
			continue
		}
		subs := subjects_with_predicate(r, v.ids[entry.iri], MATCH, NEXT, DESTROY)
		defer delete(subs)
		for id in subs {
			enqueue(&pending, &pending_kind, &queued, id, .Node)
		}
	}

	// ---- Compilation: one shape per iteration, growing the worklist. -----

	at := 0
	for at < len(pending) {
		shape_id := pending[at]
		kind := pending_kind[at]
		at += 1

		sh: Shape
		sh.node = materialize_term(s, load, load_data, shape_id)
		sh.kind = kind
		sh.path = -1
		sh.severity = .Violation

		// sh:path decides the kind regardless of what discovery guessed: a
		// shape with a path is a property shape (§2.1.2).
		if v.found[PATH] {
			paths := objects_of(r, shape_id, v.ids[PATH], MATCH, NEXT, DESTROY)
			defer delete(paths)
			if len(paths) > 1 {
				return Error{.Path_Multiple, sh.node, intern(&s.terms, rdf.IRI(PATH))}
			}
			if len(paths) == 1 {
				sh.kind = .Property
				root, err := compile_path(s, r, paths[0], sh.node, load, load_data, &v, MATCH, NEXT, DESTROY)
				if err.kind != .None {
					return err
				}
				sh.path = root
			}
		}
		if sh.kind == .Property && sh.path < 0 {
			return Error{.Path_Missing, sh.node, intern(&s.terms, rdf.IRI(PATH))}
		}

		if v.found[DEACTIVATED] {
			vals := objects_of(r, shape_id, v.ids[DEACTIVATED], MATCH, NEXT, DESTROY)
			defer delete(vals)
			for id in vals {
				term := materialize_term(s, load, load_data, id)
				b, ok := boolean_value(term)
				if !ok {
					return Error{.Deactivated_Not_Boolean, sh.node, intern(&s.terms, rdf.IRI(DEACTIVATED))}
				}
				sh.deactivated = b
			}
		}

		if v.found[SEVERITY] {
			vals := objects_of(r, shape_id, v.ids[SEVERITY], MATCH, NEXT, DESTROY)
			defer delete(vals)
			for id in vals {
				term := materialize_term(s, load, load_data, id)
				sev, ok := severity_value(term)
				if !ok {
					return Error{.Severity_Unknown, sh.node, intern(&s.terms, rdf.IRI(SEVERITY))}
				}
				sh.severity = sev
			}
		}

		sh.messages.start = len(s.messages)
		if v.found[MESSAGE] {
			vals := objects_of(r, shape_id, v.ids[MESSAGE], MATCH, NEXT, DESTROY)
			defer delete(vals)
			for id in vals {
				term, owned := load(load_data, id, s.allocator)
				if lit, is_lit := term.(rdf.Literal); is_lit {
					append(
						&s.messages,
						Message {
							text = intern_string(&s.terms, lit.lexical),
							language = intern_string(&s.terms, lit.language),
						},
					)
				}
				if owned {
					rdf.destroy_term(term, s.allocator)
				}
			}
		}
		sh.messages.count = len(s.messages) - sh.messages.start

		sh.targets.start = len(s.targets)
		for entry in TARGET_PREDICATES {
			if !v.found[entry.iri] {
				continue
			}
			vals := objects_of(r, shape_id, v.ids[entry.iri], MATCH, NEXT, DESTROY)
			defer delete(vals)
			for id in vals {
				append(&s.targets, Target{kind = entry.kind, term = materialize_term(s, load, load_data, id)})
			}
		}
		// Implicit class target: a shape that is also an rdfs:Class targets
		// its own instances (§2.1.3.3). The shape node itself is stored as the
		// class, so target resolution has no special case.
		if has_type && has_class {
			types := objects_of(r, shape_id, rdf_type_id, MATCH, NEXT, DESTROY)
			defer delete(types)
			for id in types {
				if id == rdfs_class_id {
					append(&s.targets, Target{kind = .Implicit_Class, term = sh.node})
					break
				}
			}
		}
		sh.targets.count = len(s.targets) - sh.targets.start

		sh.constraints.start = len(s.constraints)
		if err := compile_constraints(
			s,
			r,
			shape_id,
			sh.node,
			load,
			load_data,
			&v,
			MATCH,
			NEXT,
			DESTROY,
		); err.kind != .None {
			return err
		}
		sh.constraints.count = len(s.constraints) - sh.constraints.start

		compiled[shape_id] = len(s.shapes)
		append(&s.shapes, sh)

		// sh:property values are shapes. Queue them; the link is recorded in
		// the fixup pass, because their indices are not known yet.
		if v.found[PROPERTY] {
			props := objects_of(r, shape_id, v.ids[PROPERTY], MATCH, NEXT, DESTROY)
			defer delete(props)
			for id in props {
				if store.id_kind(id) == .Literal {
					return Error{.Shape_Expected, sh.node, intern(&s.terms, rdf.IRI(PROPERTY))}
				}
				enqueue(&pending, &pending_kind, &queued, id, .Property)
			}
		}
	}

	// ---- Fixup: resolve sh:property links now that every shape has an index.
	//
	// A second pass rather than inline, because a shape's properties may not
	// have been compiled when the shape itself was, and the model names
	// children by index. `pending` still holds every shape's ID in the order
	// they were compiled, so the shapes graph is not re-queried for them.
	if v.found[PROPERTY] {
		for shape_index in 0 ..< len(s.shapes) {
			props := objects_of(r, pending[shape_index], v.ids[PROPERTY], MATCH, NEXT, DESTROY)
			defer delete(props)
			start := len(s.shape_children)
			for pid in props {
				if child, ok := compiled[pid]; ok {
					append(&s.shape_children, child)
				}
			}
			s.shapes[shape_index].properties = Span{start, len(s.shape_children) - start}
		}
	}

	// Roots are where validation starts: the shapes carrying targets.
	for sh, i in s.shapes {
		if sh.targets.count > 0 {
			append(&s.roots, i)
		}
	}
	return Error{}
}

@(private = "file")
shapes_init :: proc(s: ^Shapes, allocator: runtime.Allocator) {
	s.allocator = allocator
	s.shapes = make([dynamic]Shape, allocator)
	s.targets = make([dynamic]Target, allocator)
	s.constraints = make([dynamic]Constraint, allocator)
	s.paths = make([dynamic]Path_Node, allocator)
	s.messages = make([dynamic]Message, allocator)
	s.shape_children = make([dynamic]int, allocator)
	s.path_children = make([dynamic]int, allocator)
	s.values = make([dynamic]rdf.Term, allocator)
	s.roots = make([dynamic]int, allocator)
	term_table_init(&s.terms, allocator)
}
