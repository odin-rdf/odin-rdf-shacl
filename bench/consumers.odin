package main

import "core:fmt"
import "core:mem"

import memstore "store:store/memstore"

import shacl "../shacl"
import shacl_memstore "../shacl/memstore"

// The three result consumers, measured against the same walk (SHACL-T-0024).
//
// The result stream is the primitive and the other two are ordinary consumers
// of it, so the interesting number is not any one of them but the *shape* of
// the three together. Two of the `shacl` package's promises are only checkable
// this way, and both are checked here at a size `tests/guards` cannot build:
//
//   - **`Conformance` allocates nothing at all, whatever the violation count.**
//     An absolute claim, so it is an exact assertion — `total_allocation_count`
//     must be zero, on the configuration with the most violations in the set,
//     not merely small or steady.
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

// measure_consumers runs the same validation three ways on memstore, each under
// its own tracking allocator.
//
// memstore only, deliberately. The question is what *this engine* allocates, and
// on kvstore every figure would carry LMDB's page handling and term
// materialisation as well — a different question, and one the store already
// answers for itself.
measure_consumers :: proc(c: Config, w: Workload) -> (out: Consumers, ok: bool) {
	model: shacl.Shapes
	defer shacl.shapes_destroy(&model)

	shapes_dict: memstore.Dictionary
	memstore.dictionary_init(&shapes_dict)
	defer memstore.dictionary_destroy(&shapes_dict)
	shapes_data: memstore.Dataset
	memstore.dataset_init(&shapes_data)
	defer memstore.dataset_destroy(&shapes_data)
	if _, err := memstore.load_turtle(
		&shapes_dict,
		&shapes_data,
		transmute([]byte)w.shapes_ttl,
	); err.message != "" {
		fail("%s: shapes graph failed to load", c.name)
		return
	}
	if e := shacl_memstore.compile(&model, &shapes_dict, &shapes_data); e.kind != .None {
		fail("%s: shapes graph did not compile", c.name)
		return
	}

	dict: memstore.Dictionary
	memstore.dictionary_init(&dict)
	defer memstore.dictionary_destroy(&dict)
	data: memstore.Dataset
	memstore.dataset_init(&data)
	defer memstore.dataset_destroy(&data)
	if _, err := memstore.load_turtle(&dict, &data, transmute([]byte)w.data_ttl);
	   err.message != "" {
		fail("%s: data graph failed to load", c.name)
		return
	}

	bindings: shacl.Bindings
	defer shacl.bindings_destroy(&bindings)
	shacl_memstore.bind(&bindings, &model, &dict)

	// (1) The raw stream, counting and keeping nothing.
	{
		tracker: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracker, context.allocator)
		defer mem.tracking_allocator_destroy(&tracker)
		failure := shacl_memstore.validate(
			&model,
			&bindings,
			&dict,
			&data,
			count_visitor,
			&out.raw.results,
			allocator = mem.tracking_allocator(&tracker),
		)
		if failure != .None {
			fail("%s: raw validation failed — %s", c.name, shacl.failure_message(failure))
			return
		}
		record(&out.raw, &tracker)
	}

	// (2) Conformance. It stops at the first result of any severity, so its
	// result count is not comparable with the others' — what is measured is the
	// allocation, and the promise is that there is none.
	{
		tracker: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracker, context.allocator)
		defer mem.tracking_allocator_destroy(&tracker)
		conforms, failure := shacl_memstore.conforms(
			&model,
			&bindings,
			&dict,
			&data,
			allocator = mem.tracking_allocator(&tracker),
		)
		if failure != .None {
			fail("%s: conformance check failed — %s", c.name, shacl.failure_message(failure))
			return
		}
		out.conforms = conforms
		record(&out.conformance, &tracker)
	}

	// (3) The report graph. The one that is supposed to grow.
	{
		tracker: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracker, context.allocator)
		defer mem.tracking_allocator_destroy(&tracker)
		r: shacl.Report
		shacl.report_init(&r, mem.tracking_allocator(&tracker))
		failure := shacl_memstore.validate_report(
			&r,
			&model,
			&bindings,
			&dict,
			&data,
			allocator = mem.tracking_allocator(&tracker),
		)
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
			fail(
				"%s: report building leaked %d allocation(s)",
				c.name,
				len(tracker.allocation_map),
			)
		}
	}

	return out, true
}

@(private = "file")
record :: proc(s: ^Consumer_Stats, t: ^mem.Tracking_Allocator) {
	s.peak = int(t.peak_memory_allocated)
	s.total_bytes = int(t.total_memory_allocated)
	s.allocations = int(t.total_allocation_count)
}

report_consumers :: proc(c: Config, k: Consumers) {
	fmt.printfln(
		"   consumers  raw: peak %d B, %d allocs, %d results",
		k.raw.peak,
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
