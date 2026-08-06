package shacl

// Suppressed validation: asking whether a node conforms to a shape without
// reporting why it does not (SHACL-A-0002).
//
// The engine streams every result to the caller's visitor as it is found, and
// that is what makes early exit and flat memory work. But six of SHACL Core's
// components need the *opposite* of a report. `sh:not` validates a node against
// a shape and violates precisely when the inner shape was satisfied, emitting
// none of the inner shape's results. `sh:or` and `sh:xone` need the same per
// branch; the three qualified parameters need it and a count besides.
//
// This is that capability, built once and before any of its consumers, because
// a mechanism retrofitted from whichever component happens to land first gets
// that component's assumptions baked into it — the reason SHACL-I-0002 put this
// task third rather than eighth.
//
//
// # What a suppressed run is
//
// The same walk, with the visitor swapped for a probe that records the first
// result and stops. It is not a second evaluator and it is not a copy of the
// `Validation`: it **reuses the in-flight one**, saving the three fields that
// belong to the caller's stream and restoring them afterwards.
//
// Reusing rather than copying is the whole of the design, and it is what the
// alternatives got wrong:
//
//   - **Copying the `Validation`** would copy `classes`, whose dynamic arrays
//     the inner run appends to. The outer's copy would then hold stale headers
//     and, after a reallocation, dangling ones — a bug that would surface as
//     corrupted class closures under nesting, far from its cause.
//   - **A suppression flag on the frame** was the cheap option: mark a subtree
//     and have `emit_result` check the mark. It leaks in both directions — the
//     mark has to be cleared on every abnormal exit, and there is no natural
//     place to *collect the answer*, which is what `sh:or` needs per branch.
//   - **A separate `Validation` sharing state through pointers** works, but it
//     splits the struct in two to express something the save/restore already
//     says in five lines.
//
// What is shared is therefore everything except the result stream: the model,
// the bindings, the access, the allocator, the subclass-closure cache, the
// recursion set, and `failure`. What is saved and restored is `visit`,
// `visit_data`, and `stopped`.
//
//
// # Two properties that must hold, and why each is a test
//
// **Nothing leaks into the caller's report.** A suppressed run that produced
// results must leave the caller's visitor uncalled and the caller's
// `sh:conforms` untouched. This is the failure mode the whole task is written
// around: it is invisible in the engine and shows up as a stranger's report
// containing results for a shape they never targeted.
//
// **The inner stop does not stop the outer.** The probe returns false at its
// first result, which sets `stopped` — the same mechanism the caller uses to
// abandon a traversal. If that value survived the sub-run, a single inner
// violation would silently truncate the outer validation, and the report would
// look complete. Restoring `stopped` is the whole fix, and it is asserted
// rather than assumed.
//
//
// # Recursion: a suppressed run shares the outer walk's stack
//
// Decided in SHACL-A-0002. `on_stack` is shared, so a shape re-entered *through*
// a suppressed check is recursion exactly as one re-entered through
// `sh:property` is, and `ex:S sh:not [ sh:node ex:S ]` reports
// `Failure.Recursive_Shape` rather than validating.
//
// The alternative — a fresh recursion set per sub-run — does not merely give a
// different answer, it gives no answer: that same shapes graph would enter
// `ex:S`, reach `sh:not`, start a sub-run with an empty set, enter `ex:S`
// again, and never terminate. A snapshot copy per sub-run would behave
// identically to sharing while adding an allocation and a way to get the
// write-back wrong.
//
// Sharing also means the depth of nesting is bounded by the number of shapes in
// the model, not by anything about the data: a shape cannot appear twice on the
// stack, so the walk cannot nest deeper than `len(s.shapes)` before the failure
// is raised. That is the memory bound this mechanism promises.

// Suppressed_Probe records whether a suppressed run produced any result. One
// bit, and no storage for the results themselves: what the six consumers ask is
// whether the node conformed, never why not.
@(private)
Suppressed_Probe :: struct {
	found: bool,
}

// suppressed_visitor stops at the first result of any severity, which is
// §3.4's conformance question exactly: a node conforms to a shape when
// validating it against that shape produces no results at all. Severity does
// not enter into it, for the same reason it does not enter into `Conformance`.
@(private)
suppressed_visitor :: proc(data: rawptr, result: Result) -> bool {
	probe := cast(^Suppressed_Probe)data
	probe.found = true
	return false
}

// node_conforms reports whether `focus` conforms to the shape at `shape_index`,
// producing no results and leaving the caller's stream untouched.
//
// This is the procedure `sh:not`, `sh:or`, `sh:xone`, `sh:node`, and the
// qualified parameters will call from their constraint checks. It is safe to
// nest: each level saves its own three fields and restores them, so a
// suppressed run that itself runs one unwinds in the order it entered.
//
// **The answer is meaningful only when `v.failure` is still `.None`.** A
// suppressed run that hit shape recursion could not answer, and it propagates
// the failure to the whole validation rather than reporting a conformance it
// did not establish — the caller's outer loop sees the failure and abandons the
// traversal. A consumer must check it before believing a `true`.
@(private)
node_conforms :: proc(v: ^Validation, shape_index: int, focus: Focus_Node) -> bool {
	saved_visit := v.visit
	saved_visit_data := v.visit_data
	saved_stopped := v.stopped

	probe: Suppressed_Probe
	v.visit = suppressed_visitor
	v.visit_data = &probe
	v.stopped = false

	validate_focus(v, shape_index, focus)

	v.visit = saved_visit
	v.visit_data = saved_visit_data
	v.stopped = saved_stopped

	return !probe.found
}

// conforms_node answers §3.4's conformance question for one node against one
// shape: does `focus` conform to `s.shapes[shape_index]`, counting that shape's
// constraints and every `sh:property` shape below it?
//
// This is the standalone form of what the logical and shape-based components
// use internally, and it is public for two reasons. It is the primitive a
// caller wants when validating a node against a shape it names itself, rather
// than against everything the shapes graph targets — the family's "primitives
// over frameworks" line. And it is what makes the mechanism testable against a
// real backend today: the six components that consume it internally arrive two
// tasks later, and a capability with no reachable surface would go that long
// with no backend-level test at all.
//
// `focus` names the node. A caller with an `rdf.Term` should use the
// instantiation package's wrapper, which resolves it through the store's
// non-interning lookup — a term the data graph never mentions is still a
// perfectly good focus node, and still conforms or does not.
//
// **The boolean is meaningless when the Failure is not `.None`**, exactly as it
// is for `conforms`: a failure means the processor could not answer, which is
// not the same as "no".
conforms_node :: proc(
	s: ^Shapes,
	b: ^Bindings,
	access: Access,
	shape_index: int,
	focus: Focus_Node,
	allocator := context.allocator,
) -> (
	conforms: bool,
	failure: Failure,
) {
	if shape_index < 0 || shape_index >= len(s.shapes) {
		return false, .None
	}
	v := Validation {
		s      = s,
		b      = b,
		access = access,
	}
	validation_init(&v, allocator)
	defer validation_destroy(&v)

	conforms = node_conforms(&v, shape_index, focus)
	return conforms, v.failure
}
