package shacl

import "base:runtime"

import "rdf:rdf"
import "record:record"

// Validation: the join point where the compiled model, the targets, the paths,
// the constraints, and the result stream become one engine (SHACL §3.4).
//
// The whole of it is this: for every shape carrying a target, resolve the
// target to focus nodes; for every focus node, compute the shape's value nodes;
// check every constraint against them; and then do the same for each
// `sh:property` child with those value nodes as *its* focus nodes. Everything
// else here is the machinery that keeps that honest.
//
// **The walk is an explicit stack over the flat model** (SHACL-A-0001 decision
// 4). Recursion would work — but the stack is what makes recursion *detection*
// free: the set of shapes currently being validated is literally the stack,
// and `on_stack` is a bit per shape rather than a search. §3.4 leaves
// recursive shapes undefined and permits a processor to signal a failure
// instead, which is what this does, at the first re-entry, before any
// traversal can hang on cyclic data.
//
// **The dispatch seam is a switch, not a table** (`check.odin`), consistent
// with SPARQL-T-0011's finding that the family's no-dynamic-dispatch default
// costs nothing here. Adding a constraint component means adding a
// `Constraint_Kind`, a scope, and a case — nothing in this file.
//
// **The store is reached through the session verbs in session.odin** and
// nothing else — odin-rdf-record, directly, the one and only store
// (SHACL-I-0004).

// Bindings is the term-binding bridge for a whole validation: every `rdf.Term`
// the compiled model holds, resolved to the *data* store's ids once, before
// anything is validated.
//
// This is the SHACL half of what odin-rdf-sparql does for algebra constants,
// and it carries the asymmetry SHACL-I-0001 warned about rather than
// discovering it: an absent term means **emptiness** on a path or a target and
// **failure** in a constraint. A `sh:class ex:Missing` whose class the data
// store has never seen makes every value node violate; a step through a
// predicate it has never seen simply reaches nothing. Both are correct, and
// they are opposite, so `bound` is carried per use rather than collapsed into
// one rule.
Bindings :: struct {
	targets:          Target_Bindings,
	paths:            Path_Bindings,

	// Indexed by Shapes.constraints: the single-term parameter of
	// Class/Datatype/Has_Value. Meaningless for the other kinds.
	constraint:       []record.Term_ID,
	constraint_bound: []bool,

	// Indexed by Shapes.values: the members of every list-valued parameter —
	// `sh:in`, `sh:languageIn`, and `sh:closed`'s allowed predicates.
	value:            []record.Term_ID,
	value_bound:      []bool,
	allocator:        runtime.Allocator,
}

// bindings_init resolves the model against the data session's snapshot.
// Resolving is the non-interning lookup by construction — record's read side
// cannot write — so preparing a validation never touches the graph it is
// about to read.
bindings_init :: proc(b: ^Bindings, s: ^Shapes, se: Session, allocator := context.allocator) {
	b.allocator = allocator
	target_bindings_init(&b.targets, s, se, allocator)
	path_bindings_init(&b.paths, s, se, allocator)

	b.constraint = make([]record.Term_ID, len(s.constraints), allocator)
	b.constraint_bound = make([]bool, len(s.constraints), allocator)
	// Only the components that compare their parameter **by ID** need it bound.
	// The value-range components hold a term too and never look here: they
	// compare by value, so an ID would tell them nothing.
	//
	// **This switch is a fifth edit the seam's own documentation does not
	// mention**, and it fails quietly — a component left out of it reads
	// `constraint_bound` as false, treats its parameter as a term the data store
	// has never seen, and reports *nothing at all* rather than erroring.
	// SHACL-T-0015 lost a diagnostic round to exactly that: the property-pair
	// components compiled, dispatched, ran, and produced an empty second set on
	// every focus node. If a component's check reads `v.b.constraint`, its kind
	// belongs here.
	for c, i in s.constraints {
		#partial switch c.kind {
		//
		// `sh:closed` is deliberately absent: its parameter is a *list*, so it
		// resolves through `b.value` below exactly as `sh:in`'s members do, and it
		// never reads `b.constraint` at all.
		case .Class,
		     .Datatype,
		     .Has_Value,
		     .Equals,
		     .Disjoint,
		     .Less_Than,
		     .Less_Than_Or_Equals:
			id, found := session_resolve(se, c.term)
			b.constraint[i] = id
			b.constraint_bound[i] = found
		}
	}

	b.value = make([]record.Term_ID, len(s.values), allocator)
	b.value_bound = make([]bool, len(s.values), allocator)
	for term, i in s.values {
		id, found := session_resolve(se, term)
		b.value[i] = id
		b.value_bound[i] = found
	}
}

// bindings_destroy frees every binding, including the target and path bindings
// it contains. The model and the store are untouched.
bindings_destroy :: proc(b: ^Bindings) {
	target_bindings_destroy(&b.targets)
	path_bindings_destroy(&b.paths)
	delete(b.constraint, b.allocator)
	delete(b.constraint_bound, b.allocator)
	delete(b.value, b.allocator)
	delete(b.value_bound, b.allocator)
	b^ = {}
}

// Failure is the spec's *failure* (§3.3), which is not a validation result and
// must never be confused with one: a result says the data is wrong, a failure
// says the processor could not answer.
//
// `Recursive_Shape` is the one this engine raises. SHACL leaves recursive
// shapes undefined and explicitly permits signalling a failure, and that is the
// decision SHACL-I-0001 recorded — cycle-breaking ("assume valid on re-entry")
// stays addable later without redesign. Reporting it beats the alternatives in
// both directions: hanging on cyclic data is unusable, and silently accepting
// is a conformance answer the spec does not license.
Failure :: enum u8 {
	None,
	Recursive_Shape,
}

// failure_message returns a static description of a failure. Allocation-free,
// like `error_message`, and ending with the spec section that licenses it.
failure_message :: proc(f: Failure) -> string {
	switch f {
	case .None:
		return "no failure"
	case .Recursive_Shape:
		return "shape recursion: a shape was re-entered while already being validated (§3.4)"
	}
	return "unknown failure"
}

// validate runs the whole shapes model against the data graph the session
// reads and streams every result to `visit`.
//
// Returns a Failure rather than results: results went to the visitor as they
// were found. `.None` means the traversal completed *or* the visitor stopped it
// — both are ordinary — and anything else means the report is incomplete and
// must not be read as a conformance answer.
//
// The visitor returning false stops validation where it stands: no further
// focus nodes are resolved and no further paths are walked. That reaches the
// store rather than being simulated above it, which is what makes
// `Conformance` cost one triple on badly broken data instead of a full
// traversal.
validate :: proc(
	s: ^Shapes,
	b: ^Bindings,
	se: Session,
	visit: Result_Visitor,
	visit_data: rawptr,
	allocator := context.allocator,
) -> Failure {
	v := Validation {
		s          = s,
		b          = b,
		se         = se,
		visit      = visit,
		visit_data = visit_data,
		allocator  = allocator,
	}
	validation_init(&v, allocator)
	defer validation_destroy(&v)

	for root in s.roots {
		if v.stopped || v.failure != .None {
			break
		}
		state := Root_State {
			v     = &v,
			shape = root,
		}
		resolve_targets(s, &b.targets, root, se, visit_focus, &state, allocator)
	}
	return v.failure
}

// validate_report runs a validation and builds the `sh:ValidationReport`
// graph, finished and ready to serialise. The report owns every term in it,
// so it outlives the snapshot it was produced from.
validate_report :: proc(
	r: ^Report,
	s: ^Shapes,
	b: ^Bindings,
	se: Session,
	allocator := context.allocator,
) -> Failure {
	sink := Report_Sink {
		report = r,
		shapes = s,
		se     = se,
	}
	failure := validate(s, b, se, report_sink_visitor, &sink, allocator)
	report_finish(r)
	return failure
}

// conforms answers "does this graph conform?" and stops at the first result of
// **any severity**, which is what early exit is for. Severity does not enter
// into it (§3.1): a warning breaks conformance exactly as a violation does, and
// `misc/severity-001` is the entry that settles it.
//
// The boolean is meaningless when the Failure is not `.None`.
conforms :: proc(
	s: ^Shapes,
	b: ^Bindings,
	se: Session,
	allocator := context.allocator,
) -> (
	bool,
	Failure,
) {
	c: Conformance
	conformance_init(&c)
	failure := validate(s, b, se, conformance_visitor, &c, allocator)
	return c.conforms, failure
}

// validate_node validates **one node against one shape** and streams the
// results, which is the question `conforms_node` answers with a boolean.
//
// The two are the same walk and differ only in what receives the results:
// `conforms_node` swaps in a probe that records the first one and stops,
// because its six internal consumers — `sh:not`, `sh:or`, `sh:xone`, and the
// three qualified parameters — want conformance *without* a report. This is the
// third caller, the one that supplies its own visitor. An application checking a
// resource it is about to accept asks exactly the narrow question and needs
// exactly the opposite answer shape: not "no", but *which constraint*.
//
// **Use this rather than filtering `validate`'s results by focus node.** That
// works and is correct, and it validates every targeted node in the dataset to
// answer about one — so the cost of asking about a single resource scales with
// the data around it, which for a consumer doing this per write is a latency
// problem before it is anything worse.
//
// `focus` names the node — build one from a term with `node_focus`, which
// resolves it against the session's snapshot: a term the data graph never
// mentions is still a perfectly good focus node, validated as unbound.
//
// The `Failure` means what it means everywhere else: `.None` says the walk
// completed or the visitor stopped it, and anything else says the stream is
// incomplete and must not be read as conformance. Recursion detection, the
// subclass-closure cache, and the stop-on-false visitor contract are the shared
// ones, because this is the shared walk.
//
// An out-of-range `shape_index` produces no results and no failure, mirroring
// `conforms_node`, which answers "does not conform" rather than reading memory
// it has no business reading.
//
// **The shape need not target the node.** §3.4 defines conformance for any node
// and any shape, and that is deliberate — naming a shape is the point of this
// entry point. It does mean a caller can validate a resource against one shape
// while several others also target it and believe the resource checked out; what
// this answers is the question asked, not every question that applies.
validate_node :: proc(
	s: ^Shapes,
	b: ^Bindings,
	se: Session,
	shape_index: int,
	focus: Focus_Node,
	visit: Result_Visitor,
	visit_data: rawptr,
	allocator := context.allocator,
) -> Failure {
	if shape_index < 0 || shape_index >= len(s.shapes) {
		return .None
	}
	v := Validation {
		s          = s,
		b          = b,
		se         = se,
		visit      = visit,
		visit_data = visit_data,
		allocator  = allocator,
	}
	validation_init(&v, allocator)
	defer validation_destroy(&v)

	validate_focus(&v, shape_index, focus)
	return v.failure
}

// validate_node_report validates one node against one shape and builds the
// `sh:ValidationReport` graph for it — standing to `validate_node` as
// `validate_report` stands to `validate`.
//
// The report is about that one node, so `sh:conforms` in it answers the narrow
// question and not the graph's. It owns every term in it and outlives the
// snapshot.
validate_node_report :: proc(
	r: ^Report,
	s: ^Shapes,
	b: ^Bindings,
	se: Session,
	node: rdf.Term,
	shape_index: int,
	allocator := context.allocator,
) -> Failure {
	sink := Report_Sink {
		report = r,
		shapes = s,
		se     = se,
	}
	failure := validate_node(
		s,
		b,
		se,
		shape_index,
		node_focus(se, node),
		report_sink_visitor,
		&sink,
		allocator,
	)
	report_finish(r)
	return failure
}

// validation_init prepares the two pieces of per-validation state that outlive
// a single frame: the recursion set and the subclass-closure cache. Split out
// of `validate` because a suppressed sub-run needs them too — and needs to
// *share* them rather than build its own; see `node_conforms`.
@(private)
validation_init :: proc(v: ^Validation, allocator := context.allocator) {
	v.allocator = allocator
	v.on_stack = make([]bool, len(v.s.shapes), allocator)
	v.classes.allocator = allocator
	v.classes.class = make([dynamic]record.Term_ID, allocator)
	v.classes.member = make([dynamic]map[record.Term_ID]bool, allocator)
}

@(private)
validation_destroy :: proc(v: ^Validation) {
	delete(v.on_stack, v.allocator)
	for &m in v.classes.member {
		delete(m)
	}
	delete(v.classes.member)
	delete(v.classes.class)
	v.on_stack = nil
	v.classes = {}
}

@(private)
Validation :: struct {
	s:          ^Shapes,
	b:          ^Bindings,
	se:         Session,
	visit:      Result_Visitor,
	visit_data: rawptr,
	on_stack:   []bool, // indexed by Shapes.shapes: the recursion set
	stopped:    bool, // the visitor asked to stop
	failure:    Failure,
	classes:    Class_Closures,
	allocator:  runtime.Allocator,
}

@(private = "file")
Root_State :: struct {
	v:     ^Validation,
	shape: int,
}

// visit_focus is the Focus_Visitor target resolution streams into: each focus
// node starts one walk. Returning false is how a stop or a failure reaches the
// store's iterator rather than being checked after the fact.
@(private = "file")
visit_focus :: proc(data: rawptr, focus: Focus_Node) -> bool {
	state := cast(^Root_State)data
	validate_focus(state.v, state.shape, focus)
	return !state.v.stopped && state.v.failure == .None
}

// Frame is one (shape, focus node) pair being validated.
//
// `values` holds the shape's value nodes: the path's result for a property
// shape, and the focus node itself for a node shape (§2.3). `unbound` covers
// the one case an ID cannot express — a node shape whose focus node is a
// `sh:targetNode` the data graph never mentions — where the single value node
// is the focus node's term.
//
// `cursor` walks the cross product of the shape's `sh:property` children and
// its value nodes, because a child's focus nodes are exactly its parent's value
// nodes.
@(private = "file")
Frame :: struct {
	shape:   int,
	focus:   Focus_Node,
	values:  [dynamic]record.Term_ID,
	unbound: bool,
	cursor:  int,
}

// Value_Set is a shape's value nodes at one focus node, in the form every
// constraint check consumes. It borrows the frame's storage and is valid only
// while that frame is on the stack.
@(private)
Value_Set :: struct {
	focus:   Focus_Node,
	ids:     []record.Term_ID,
	unbound: bool,
}

@(private)
value_set_count :: proc(vs: Value_Set) -> int {
	return vs.unbound ? 1 : len(vs.ids)
}

@(private)
value_set_at :: proc(vs: Value_Set, i: int) -> Node_Ref {
	if vs.unbound {
		return vs.focus
	}
	return Node_Ref{id = vs.ids[i], bound = true}
}

@(private = "file")
frame_values :: proc(f: Frame) -> Value_Set {
	return Value_Set{focus = f.focus, ids = f.values[:], unbound = f.unbound}
}

// validate_focus is the stack-driven walk: one focus node of one shape, and
// everything that hangs off it.
//
// Package-visible rather than file-private because it is also the whole of a
// suppressed run (`suppress.odin`): asking whether a node conforms to a shape
// is this walk with the visitor swapped, which is what stops suppression from
// being a second evaluator.
@(private)
validate_focus :: proc(v: ^Validation, shape_index: int, focus: Focus_Node) {
	stack := make([dynamic]Frame, v.allocator)
	defer delete(stack)

	push_frame(v, &stack, shape_index, focus)

	for len(stack) > 0 {
		// A stop or a failure abandons the walk. Unwinding by hand rather than
		// returning is what keeps every frame's value set freed and every
		// on-stack bit cleared on the abnormal path too.
		if v.stopped || v.failure != .None {
			for &f in stack {
				delete(f.values)
				v.on_stack[f.shape] = false
			}
			clear(&stack)
			break
		}

		top := &stack[len(stack) - 1]
		properties := shape_properties(v.s, v.s.shapes[top.shape])
		count := value_set_count(frame_values(top^))

		if count > 0 && top.cursor < len(properties) * count {
			child := properties[top.cursor / count]
			next := value_set_at(frame_values(top^), top.cursor % count)
			top.cursor += 1
			// `top` is invalidated by the append inside push_frame, so nothing
			// may touch it after this point.
			push_frame(v, &stack, child, next)
			continue
		}

		v.on_stack[top.shape] = false
		delete(top.values)
		pop(&stack)
	}
}

// push_frame enters a shape at a focus node: compute its value nodes, check its
// constraints, and leave it on the stack for its children.
//
// Three things can stop it before it pushes. A deactivated shape produces no
// results and no children (§2.1.1.4) — it is skipped rather than pushed, so its
// property shapes are never reached. A shape already on the stack is recursion,
// and the failure is raised here, at the re-entry, before a single further
// triple is read. And a shape with no path over an unbound focus node has one
// value node that is not in the dictionary at all, which `unbound` carries.
@(private = "file")
push_frame :: proc(v: ^Validation, stack: ^[dynamic]Frame, shape_index: int, focus: Focus_Node) {
	shape := v.s.shapes[shape_index]
	if shape.deactivated {
		return
	}
	if v.on_stack[shape_index] {
		v.failure = .Recursive_Shape
		return
	}

	f := Frame {
		shape = shape_index,
		focus = focus,
	}
	if shape.path < 0 {
		// A node shape's value node is its focus node.
		f.values = make([dynamic]record.Term_ID, v.allocator)
		if focus.bound {
			append(&f.values, focus.id)
		} else {
			f.unbound = true
		}
	} else if focus.bound {
		f.values = value_nodes(v.s, &v.b.paths, shape.path, focus.id, v.se, v.allocator)
	} else {
		// No triple can mention a term the dictionary does not hold, so a path
		// from an unbound focus node reaches nothing. That is emptiness, and it
		// is meaningful: `sh:minCount 1` on such a node is a violation.
		f.values = make([dynamic]record.Term_ID, v.allocator)
	}

	v.on_stack[shape_index] = true
	check_shape(v, shape_index, frame_values(f))
	append(stack, f)
}

// emit_result hands one result to the visitor and records a stop.
//
// The result borrows and owns nothing (see result.odin): it names nodes by
// id and the shape and path by index, and is valid only for the duration
// of the call.
//
// The two trailing parameters serve `sh:closed` alone and default to off. A
// component that supplies a `path_predicate` is saying its `sh:resultPath` is a
// term of the data graph rather than the shape's path, so the shape's path is
// dropped rather than carried alongside — the report would otherwise have to
// choose between two, and §4.8.1 already chose.
@(private)
emit_result :: proc(
	v: ^Validation,
	shape_index: int,
	focus: Focus_Node,
	value: Node_Ref,
	has_value: bool,
	component: Constraint_Kind,
	path_predicate: Node_Ref = {},
	has_path_predicate: bool = false,
) {
	shape := v.s.shapes[shape_index]
	result := Result {
		focus              = focus,
		value              = value,
		has_value          = has_value,
		path               = has_path_predicate ? -1 : shape.path,
		path_predicate     = path_predicate,
		has_path_predicate = has_path_predicate,
		shape              = shape_index,
		component          = component,
		severity           = shape.severity,
	}
	if !v.visit(v.visit_data, result) {
		v.stopped = true
	}
}

// ---- The subclass closures a sh:class check needs ------------------------
//
// `sh:class C` holds of a value node when the node has an `rdf:type` in the
// downward closure of C under `rdfs:subClassOf` — the same set `sh:targetClass`
// resolves over, and computed by the same procedure.
//
// It is cached per class rather than per check because the closure is a walk
// over the data graph and the same class is asked about once per value node.
// The cache is a linear scan: a shapes graph names a handful of classes, and a
// map keyed on an id would cost more bookkeeping than the scan saves.

@(private)
Class_Closures :: struct {
	class:     [dynamic]record.Term_ID,
	member:    [dynamic]map[record.Term_ID]bool,
	allocator: runtime.Allocator,
}

// class_closure returns the members of `class`'s closure, computing it on first
// ask. The map borrows the cache and is valid until the validation ends.
@(private)
class_closure :: proc(v: ^Validation, class: record.Term_ID) -> ^map[record.Term_ID]bool {
	for known, i in v.classes.class {
		if known == class {
			return &v.classes.member[i]
		}
	}
	ids := subclass_closure(&v.b.targets, v.se, class, v.allocator)
	defer delete(ids)

	set := make(map[record.Term_ID]bool, v.classes.allocator)
	for id in ids {
		set[id] = true
	}
	append(&v.classes.class, class)
	append(&v.classes.member, set)
	return &v.classes.member[len(v.classes.member) - 1]
}
