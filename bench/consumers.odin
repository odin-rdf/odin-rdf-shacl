package main

import "core:fmt"
import "core:mem"

import "../shacl"

// The three result consumers, measured against the same walk (SHACL-T-0024).
//
// The result stream is the primitive and the other two are ordinary consumers
// of it, so the interesting number is not any one of them but the *shape* of
// the three together. Two of the `shacl` package's promises are only checkable
// this way, and both are checked here at a size `tests/guards` cannot build:
//
//   - **`Conformance` allocates nothing over the walk it rides on.** On a
//     conforming graph its allocation count equals the raw stream's exactly;
//     on a violating one it is strictly less (`assert_promises`).
//   - **Memory stays flat exactly when the data is worst.** Peak must not move
//     as violation density goes 0 → 20 → 100 percent over an otherwise
//     identical workload.
//
// **And a third that is the counterweight to those two.** A `Report` is the one
// consumer that is *meant* to grow with the violation count — it is a graph,
// and that is what it is for. Asserting only that things stay flat would pass
// just as well on an engine that had stopped reporting anything, so the report
// is measured too and its growth is the evidence that the other two are flat
// for the right reason.
//
// **What the figures include changed with each store.** On memstore they were
// the engine alone — its `lookup_term` borrowed. On kvstore every materialised
// term was copied into the caller's allocator and counted. On record,
// `session_term` borrows again (the dictionary arena, or a stack buffer for an
// inlined id) and the engine interns what it keeps — so these are once more
// the engine's own allocation, with one systematic shift against the memstore
// numbers: ids are 32-bit natively, so every id-holding structure is smaller
// (the 64-bit peak of 27076 B became 20868 B, the 32-bit build's old figure).
// Allocation *counts* came through the port unchanged.
//
// *(Amended 2026-08-25, SHACL-T-0038: "borrows again" describes every term kind
// that existed when this was written and every term in this corpus. Since
// odin-rdf-record v0.4.0 a triple term and a split IRI are **owned**, paired
// with `session_term_destroy`; neither occurs here, so the figures below are
// unmoved — and a corpus that grew one would show the decode and the free, not
// a leak.)*

// Consumer_Stats is one consumer's allocation profile over one validation.
Consumer_Stats :: struct {
	peak:        int,
	total_bytes: int,
	allocations: int,
	results:     int,
}

// Consumers is all three over the same model, bindings, and data.
Consumers :: struct {
	raw:         Consumer_Stats,
	conformance: Consumer_Stats,
	report:      Consumer_Stats,
	conforms:    bool,
}

// measure_consumers runs the same validation three ways, each under its own
// tracking allocator. Allocation is tracked around validation and nothing
// else: the promise under test is about validation — memory flat as the
// violation count rises — and folding compile and bind into the same tally
// would bury it under a one-off cost that scales with the shapes graph.
measure_consumers :: proc(c: Config, w: Workload) -> (out: Consumers, ok: bool) {
	model: shacl.Shapes
	defer shacl.shapes_destroy(&model)
	if _, compile_ok := compile_model(c, w, &model); !compile_ok {
		return
	}

	data: Graph_Store
	defer graph_close(&data)
	if !graph_open(&data, c.name, w.data_ttl, "d_") {
		return
	}
	se := graph_session(&data)

	bindings: shacl.Bindings
	defer shacl.bindings_destroy(&bindings)
	shacl.bindings_init(&bindings, &model, se)

	// (1) The raw stream, counting and keeping nothing.
	{
		tracker: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracker, context.allocator)
		defer mem.tracking_allocator_destroy(&tracker)
		failure := shacl.validate(
			&model,
			&bindings,
			se,
			count_visitor,
			&out.raw.results,
			allocator = mem.tracking_allocator(&tracker),
		)
		if failure != .None {
			fail("%s: raw validation failed — %s", c.name, shacl.failure_message(failure))
			return
		}
		record_stats(&out.raw, &tracker)
	}

	// (2) Conformance. It stops at the first result of any severity, so its
	// result count is not comparable with the others' — what is measured is the
	// allocation, and the promise is that the consumer adds none.
	{
		tracker: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracker, context.allocator)
		defer mem.tracking_allocator_destroy(&tracker)
		conforms, failure := shacl.conforms(&model, &bindings, se, allocator = mem.tracking_allocator(&tracker))
		if failure != .None {
			fail("%s: conformance check failed — %s", c.name, shacl.failure_message(failure))
			return
		}
		out.conforms = conforms
		record_stats(&out.conformance, &tracker)
	}

	// (3) The report graph. The one that is supposed to grow.
	{
		tracker: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracker, context.allocator)
		defer mem.tracking_allocator_destroy(&tracker)
		r: shacl.Report
		shacl.report_init(&r, mem.tracking_allocator(&tracker))
		failure := shacl.validate_report(&r, &model, &bindings, se, allocator = mem.tracking_allocator(&tracker))
		if failure != .None {
			fail("%s: report validation failed — %s", c.name, shacl.failure_message(failure))
			shacl.report_destroy(&r)
			return
		}
		// Peak is read before the report is destroyed: the whole point is how
		// large the graph got, and destroying it first would report the trough.
		out.report.peak = int(tracker.peak_memory_allocated)
		out.report.total_bytes = int(tracker.total_memory_allocated)
		out.report.allocations = int(tracker.total_allocation_count)
		out.report.results = len(shacl.report_triples(&r))
		shacl.report_destroy(&r)
		if len(tracker.allocation_map) != 0 {
			fail("%s: report building leaked %d allocation(s)", c.name, len(tracker.allocation_map))
		}
	}

	return out, true
}

@(private = "file")
record_stats :: proc(s: ^Consumer_Stats, t: ^mem.Tracking_Allocator) {
	s.peak = int(t.peak_memory_allocated)
	s.total_bytes = int(t.total_memory_allocated)
	s.allocations = int(t.total_allocation_count)
}

report_consumers :: proc(c: Config, k: Consumers) {
	fmt.printfln(
		"   consumers  raw: peak %d B, %d B total, %d allocs, %d results",
		k.raw.peak,
		k.raw.total_bytes,
		k.raw.allocations,
		k.raw.results,
	)
	fmt.printfln(
		"              conformance: peak %d B, %d allocs, conforms=%v",
		k.conformance.peak,
		k.conformance.allocations,
		k.conforms,
	)
	fmt.printfln(
		"              report: peak %d B, %d allocs, %d triples",
		k.report.peak,
		k.report.allocations,
		triple_count(k.report),
	)
}

// triple_count reads better at the call site than `results` does for a report,
// where the number really is triples rather than results.
triple_count :: proc(s: Consumer_Stats) -> int {
	return s.results
}
