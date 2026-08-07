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
	MIN_INCLUSIVE,
	MAX_INCLUSIVE,
	MIN_EXCLUSIVE,
	MAX_EXCLUSIVE,
	MIN_LENGTH,
	MAX_LENGTH,
	PATTERN,
	FLAGS,
	LANGUAGE_IN,
	UNIQUE_LANG,
	EQUALS,
	DISJOINT,
	LESS_THAN,
	LESS_THAN_OR_EQUALS,
	CLOSED,
	IGNORED_PROPERTIES,
	NODE,
	NOT,
	AND,
	OR,
	XONE,
	QUALIFIED_VALUE_SHAPE,
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

// The shape-expecting parameters of §2.1.1, with how the shapes are reached:
// `sh:and`, `sh:or`, and `sh:xone` name an RDF list whose *members* are shapes,
// the other three name one directly.
//
// This table is discovery's, not the evaluator's. None of these six validates
// anything yet — that is SHACL-T-0017 and SHACL-T-0018 — and until then a
// shapes graph using one is reported through `shapes_ignored`. What lands here
// in SHACL-T-0010 is only the §2.1.1 rule that their values *are shapes*, which
// every one of those later components depends on and none of them should have
// to introduce.
@(private)
SHAPE_EXPECTING_PARAMETERS := [6]struct {
	iri:     string,
	is_list: bool,
} {
	{NODE, false},
	{NOT, false},
	{QUALIFIED_VALUE_SHAPE, false},
	{AND, true},
	{OR, true},
	{XONE, true},
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
	// §2.1.1 defines a shape broadly. Four of its cases are implemented: a node
	// typed sh:NodeShape or sh:PropertyShape, a node carrying a target
	// declaration, a value of sh:property, and — since SHACL-T-0010 — a value of
	// a shape-expecting parameter (sh:node, sh:not, sh:and, sh:or, sh:xone,
	// sh:qualifiedValueShape).
	//
	// **Discovery is reachability, not a global scan**, and the last two cases
	// are why that has to be said. §2.1.1 reads globally — a node is a shape if
	// it is the object of *any* sh:node triple — while this enqueues the values
	// of a shape's parameters as it compiles that shape, so a shape nobody
	// references is never found. The spine already made this choice for
	// sh:property and the suite has been green on it, and the reason to keep it
	// is sharper here: in the W3C corpus the shapes graph, the data graph, the
	// manifest, and the *expected validation report* are usually one document,
	// so a global scan would compile parts of a test fixture as shapes. A shapes
	// graph whose shapes are unreachable from any target has nothing to validate
	// anyway.
	//
	// §2.1.1's remaining case — a node is a shape by being the subject of a
	// triple whose predicate is a parameter — is deliberately not implemented:
	// it would make every node carrying sh:minCount a root-less shape, and
	// nothing needs it.

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
		sh.severity = intern(&s.terms, rdf.IRI(VIOLATION))

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

		// Any IRI is a severity. The three built-ins get no special treatment
		// here, and a shapes graph declaring its own — which `misc/severity-002`
		// does — compiles and reports under it.
		if v.found[SEVERITY] {
			vals := objects_of(r, shape_id, v.ids[SEVERITY], MATCH, NEXT, DESTROY)
			defer delete(vals)
			for id in vals {
				term := materialize_term(s, load, load_data, id)
				if _, is_iri := term.(rdf.IRI); !is_iri {
					return Error{.Severity_Not_IRI, sh.node, intern(&s.terms, rdf.IRI(SEVERITY))}
				}
				sh.severity = term
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

		record_ignored_parameters(s, r, shape_id, load, load_data, MATCH, NEXT, DESTROY)

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

		// The shape-expecting parameters. Their values are shapes too, and they
		// are queued as node shapes: the guess costs nothing, because a value
		// carrying sh:path is reclassified as a property shape when it is
		// compiled, exactly as sh:property's values are.
		//
		// Termination is `enqueue`'s dedupe by ID, which is what makes a
		// self-referencing `ex:S sh:node ex:S` — and any longer cycle — compile
		// once rather than forever.
		for entry in SHAPE_EXPECTING_PARAMETERS {
			if !v.found[entry.iri] {
				continue
			}
			vals := objects_of(r, shape_id, v.ids[entry.iri], MATCH, NEXT, DESTROY)
			defer delete(vals)
			for id in vals {
				if !entry.is_list {
					if store.id_kind(id) == .Literal {
						return Error{.Shape_Expected, sh.node, intern(&s.terms, rdf.IRI(entry.iri))}
					}
					enqueue(&pending, &pending_kind, &queued, id, .Node)
					continue
				}
				// A malformed list is not rejected here. Whether `sh:and ( )`
				// with a broken list is an ill-formed shapes graph is the
				// logical combinators' question (SHACL-T-0017), and answering it
				// from discovery would reject graphs whose sh:and this engine
				// does not yet enforce at all.
				items, list_ok := list_items(r, id, MATCH, NEXT, DESTROY)
				defer delete(items)
				if !list_ok {
					continue
				}
				for member in items {
					if store.id_kind(member) == .Literal {
						return Error{.Shape_Expected, sh.node, intern(&s.terms, rdf.IRI(entry.iri))}
					}
					enqueue(&pending, &pending_kind, &queued, member, .Node)
				}
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

	// ---- The one constraint that had to wait for the fixup -----------------
	//
	// `sh:closed`'s allowed-predicate set is a statement about a shape's
	// *children*, so it cannot be compiled until they are linked. Everything else
	// about the component was decided in `compile_constraints`; this only fills in
	// `Constraint.values`.
	if err := compile_closed_sets(
		s,
		r,
		pending[:len(s.shapes)],
		load,
		load_data,
		&v,
		MATCH,
		NEXT,
		DESTROY,
	); err.kind != .None {
		return err
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
	s.ignored = make([dynamic]rdf.Term, allocator)
	term_table_init(&s.terms, allocator)
}
