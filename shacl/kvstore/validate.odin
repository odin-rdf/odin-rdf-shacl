package shacl_kvstore

import shacl ".."

// The kvstore instantiation of validation — the persistent twin of
// `shacl/memstore/validate.odin`. Read the two together: the engine is shared
// and unchanged, and everything different here follows from the backend.
//
// The one difference that matters: a read can fail. The core's `Access` has
// nowhere to put an error, so the adapters record the first failure into the
// Session and every entry point below is documented as needing a
// `session_error` check. Swallowing it would be the worst outcome — a failed
// read yields no value nodes, which is indistinguishable from a shape that
// genuinely reaches nothing, and from there a broken store reads as a
// conforming graph.

// bind resolves the compiled model's terms to this store's IDs — the
// term-binding bridge, once per validation rather than once per check.
//
// The session must be the *data* graph's. Check `session_error` afterwards: a
// failed lookup binds as "absent", and absence is not neutral — it makes
// `sh:class` violate.
bind :: proc(b: ^shacl.Bindings, s: ^shacl.Shapes, session: ^Session, allocator := context.allocator) {
	shacl.bindings_init(b, s, find_adapter, session, allocator)
}

// validate runs the shapes model against a persistent data graph, streaming
// every result to `visit`.
//
// The graph read is the session's, bound into every pattern rather than left
// wildcard (SHACL-A-0001 decision 5). Returning false from the visitor stops
// validation. Check `session_error(session)` as well as the returned Failure.
validate :: proc(
	s: ^shacl.Shapes,
	b: ^shacl.Bindings,
	session: ^Session,
	visit: shacl.Result_Visitor,
	visit_data: rawptr,
	allocator := context.allocator,
) -> shacl.Failure {
	access := shacl.Access {
		scan      = scan_adapter,
		step      = step_adapter,
		load      = load_adapter,
		data      = session,
		load_data = session,
	}
	return shacl.validate(s, b, access, visit, visit_data, allocator)
}

// validate_report runs a validation and builds the `sh:ValidationReport` graph,
// finished and ready to serialise.
//
// The report owns every term in it, so it outlives the store it was produced
// from — which on kvstore is not a nicety: every term the loader hands over is
// built from database bytes that closing the store invalidates.
validate_report :: proc(
	r: ^shacl.Report,
	s: ^shacl.Shapes,
	b: ^shacl.Bindings,
	session: ^Session,
	allocator := context.allocator,
) -> shacl.Failure {
	sink := Report_Sink {
		report  = r,
		shapes  = s,
		session = session,
	}
	failure := validate(s, b, session, report_sink_visitor, &sink, allocator)
	shacl.report_finish(r)
	return failure
}

// conforms answers "does this graph conform?" and stops at the first result of
// **any severity**, which is what early exit is for. Severity does not enter
// into it (§3.1): a warning breaks conformance exactly as a violation does, and
// `misc/severity-001` is the entry that settles it.
//
// The boolean is meaningless when the Failure is not `.None`, or when
// `session_error` is set.
conforms :: proc(
	s: ^shacl.Shapes,
	b: ^shacl.Bindings,
	session: ^Session,
	allocator := context.allocator,
) -> (
	bool,
	shacl.Failure,
) {
	c: shacl.Conformance
	shacl.conformance_init(&c)
	failure := validate(s, b, session, shacl.conformance_visitor, &c, allocator)
	return c.conforms, failure
}
