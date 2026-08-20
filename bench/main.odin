// Package main is odin-rdf-shacl's benchmark: what validation costs, measured
// rather than argued (SHACL-I-0003; rebuilt against odin-rdf-record at
// SHACL-T-0036). Run with:
//
//	make bench
//
// which builds with `-o:speed -no-bounds-check` **twice** and runs each: once
// plain, for timings; once with `-define:SHACL_COUNT_READS=true`, for reads,
// allocation and the assertions. See "Two modes" below for why.
//
//
// # What it reports, and in what units
//
// **Three phases, separately**, because they scale differently and are paid at
// different rates. `compile` (shapes graph to model) and `bind` (model to
// snapshot ids) are once-per-process; `validate` is the repeated one. Rolling
// them into a single number would hide the interesting one — and the
// once-per-process pair is not a footnote here, because the deployment this
// family is designed around is ~200 processes per machine each compiling a
// shapes graph at start-up.
//
// **`validate` is normalised per focus node.** Not per value node and not per
// triple: how many nodes will be validated is the one quantity a reader knows
// about their own graph. It is meaningless without the shapes configuration
// beside it, which is why the configuration travels with the number everywhere
// it is quoted.
//
// **Two modes over one workload, because every instrument here perturbs what it
// measures** — and since the port they are two *builds* rather than two code
// paths in one binary:
//
//   - *Timing* — the plain build. The real path through the engine over a
//     record snapshot, the real allocator, nothing wrapped. Wall clock only.
//   - *Instrumented* — built with `SHACL_COUNT_READS`, which compiles a tally
//     into the engine's four session verbs (`shacl/counting.odin`), plus a
//     `mem.Tracking_Allocator` around each consumer. Reports store reads and
//     allocation. **No timing is taken here and none should ever be quoted
//     from it.**
//
// The old store's benchmark counted reads by supplying its own procedure set
// to a seam the engine read through, so no shipped code changed. That seam
// went with the backend abstraction (SHACL-I-0004 — record is the one and only
// store and the engine calls it directly), and a `when`-gated counter at the
// read sites is what replaced it: compiled out of every build but this one's
// instrumented half, so the plain build is still the one a consumer gets.
//
// Allocation joins reads in the instrumented mode rather than taking a third:
// both are deterministic for a fixed seed, neither belongs in a timed run, and
// they answer adjacent questions. `peak` is what tests the flat-memory promise;
// `total` and the allocation count are where a per-result leak would show.
//
// **`validate` is a warm-up plus the best of REPS; `compile` and `bind` are
// measured once, cold.** That asymmetry is deliberate rather than sloppy. The
// question about validation is what it costs in steady state, and the first
// pass pays for cold pages and an unwarmed allocator. The question about
// compile and bind is the opposite: they happen once per process, so a cold
// number is not noise in the measurement, it is the measurement. Reporting a
// warmed figure for a cost nobody pays twice would flatter it.
//
//
// # What it asserts
//
// A benchmark that only prints is a benchmark nobody reads. Two things fail
// the run rather than appearing in the output, and a third set of promises is
// checked across configurations (`assert_promises`):
//
//  1. **The generator is deterministic.** One seed, byte-identical graphs.
//     Everything below rests on it. Note what this does and does not catch: it
//     catches a generator that varies *within a process* — a global RNG, a
//     clock, a map iteration order — because both calls would disagree. It
//     cannot catch a generator whose stream merely *changed*, since both calls
//     would agree on the new one. That case is caught by (2), which was
//     confirmed by perturbing the PRNG and watching the pins fail rather than
//     this assertion.
//  2. **The read count matches its pin.** See `config.odin` — a constant per
//     configuration, changed only by deliberate edit.
//
// There used to be a third — the read count was identical on two backends and
// at two id widths — and both halves went with what they compared: one store,
// fixed widths. What replaced it is a fact rather than an assertion: the pins
// measured over the old store came through the port to the integer, so the
// count has now held across three stores. Nothing checks that on each run any
// more; the pin is what keeps the number from moving unnoticed from here.
//
//
// # What these numbers are not
//
// A workload this project chose. They are a regression instrument and a
// comparative one — the engine against itself over time, and with a change
// against without — not a claim about what SHACL costs in the world. See
// `generate.odin` for the shape of the workload and why it is synthetic.
//
// **And the timings and allocations are not comparable with the numbers the
// old store produced** — a read there was an LMDB cursor, here a range over a
// memory-resident permutation, and the materialised-term accounting differs.
// **The read counts are**: they came out identical to the last integer, which
// says the engine asks exactly the questions it asked before (`config.odin`).
// The old baselines stand in Metis as the record of what that store cost.
package main

import "core:fmt"
import "core:os"
import "core:time"

import "../shacl"

// REPS is how many timed validations a configuration runs after its warm-up.
// The reported figure is the fastest of them: a minimum is the statistic that
// resists the scheduler, which only ever makes a run slower.
REPS :: 5

// Timing is one configuration's wall clock.
Timing :: struct {
	compile:  time.Duration,
	bind:     time.Duration,
	validate: time.Duration,
	results:  int,
}

// Instrumented is one configuration's store reads.
Instrumented :: struct {
	reads:   shacl.Read_Counts,
	results: int,
}

reads_total :: proc(r: shacl.Read_Counts) -> int {
	return r.scan + r.step + r.outgoing + r.term
}

// Observation is what one configuration contributed to the cross-configuration
// assertions below. Collected rather than asserted in place, because the
// interesting promises are *comparisons between* configurations — flat peak as
// density rises is not a statement any single run can make.
Observation :: struct {
	config:             Config,
	raw_peak:           int,
	raw_total_bytes:    int,
	raw_allocs:         int,
	conformance_allocs: int,
	conforms:           bool,
	report_bytes:       int,
	report_triples:     int,
}

observations: [dynamic]Observation

failures := 0

fail :: proc(format: string, args: ..any) {
	fmt.eprintf("FAIL: ")
	fmt.eprintfln(format, ..args)
	failures += 1
}

main :: proc() {
	when shacl.SHACL_COUNT_READS {
		fmt.println("odin-rdf-shacl bench — instrumented: store reads, allocation, assertions. No timings.")
	} else {
		fmt.println("odin-rdf-shacl bench — timing: nothing wrapped.")
	}
	fmt.println("Synthetic workload over odin-rdf-record (memory seam); a regression instrument, not a claim about real-world cost.")

	// A process-level warm-up, discarded entirely, before any configuration is
	// timed.
	//
	// Per-configuration warm-up is not enough on its own, and the run that
	// proved it is worth recording: with only the inner warm-up, `dense`
	// (1200 results) timed *faster* than `clean` (0 results) on the same walk,
	// and the figures drifted downward across the whole configuration list. The
	// first configurations were paying for the process — a growing allocator
	// arena, cold pages, first touches of code that every later configuration
	// then found warm — and whichever ran first wore the cost.
	//
	// That is the kind of artifact that reads as a finding. A benchmark whose
	// answer depends on the order of its own list is worse than none, so the
	// process is warmed once here and no number below is the first thing this
	// binary did. The instrumented build takes no timings and skips it.
	when !shacl.SHACL_COUNT_READS {
		warm_up()
	}

	for c in CONFIGS {
		fmt.printfln("\n== %s ==", c.name)
		run_config(c)
	}

	when shacl.SHACL_COUNT_READS {
		assert_promises()
	}

	fmt.println()
	if failures > 0 {
		fmt.eprintfln("%d assertion(s) failed", failures)
		os.exit(1)
	}
	fmt.println("all assertions passed")
}

// warm_up validates a small workload repeatedly and throws it all away. It
// deliberately uses the first standing configuration rather than a special one:
// warming the paths that are about to be measured is the point.
@(private = "file")
warm_up :: proc() {
	if len(CONFIGS) == 0 {
		return
	}
	c := CONFIGS[0]
	w := generate(c)
	defer workload_destroy(&w)
	for _ in 0 ..< 3 {
		_, _ = time_config(c, w)
	}
}

run_config :: proc(c: Config) {
	w := generate(c)
	defer workload_destroy(&w)

	// (1) Determinism. Asserted first because every other assertion in this
	// package is a statement about a fixed workload, and a generator that
	// wandered would make all of them meaningless in a way that looked like an
	// engine regression.
	{
		again := generate(c)
		defer workload_destroy(&again)
		if again.shapes_ttl != w.shapes_ttl || again.data_ttl != w.data_ttl {
			fail("%s: the generator is not deterministic for seed %d", c.name, c.seed)
			return
		}
	}

	fmt.printfln(
		"   %d focus nodes, %d value nodes (%d violating), %d shapes, nesting %d, %v path, qualified=%v",
		c.focus_nodes,
		w.value_nodes,
		w.violating,
		c.shapes,
		c.nesting,
		c.path_form,
		c.qualified,
	)

	when shacl.SHACL_COUNT_READS {
		i, i_ok := instrument_config(c, w)
		if !i_ok {
			return
		}
		report_instrumented(c, i)

		if k, k_ok := measure_consumers(c, w); k_ok {
			report_consumers(c, k)
			append(
				&observations,
				Observation {
					config = c,
					raw_peak = k.raw.peak,
					raw_total_bytes = k.raw.total_bytes,
					raw_allocs = k.raw.allocations,
					conformance_allocs = k.conformance.allocations,
					conforms = k.conforms,
					report_bytes = k.report.total_bytes,
					report_triples = triple_count(k.report),
				},
			)
		}

		// (2) The pin.
		total := reads_total(i.reads)
		pinned, has_pin := pinned_reads(c.name)
		switch {
		case !has_pin:
			fail("%s: no entry in PINNED_READS — measured %d reads", c.name, total)
		case pinned == UNPINNED:
			fmt.printfln("   pin: UNPINNED — measured %d reads; write this into config.odin", total)
		case pinned != total:
			fail(
				"%s: %d reads, pinned at %d. If the engine legitimately asks the store a different number of questions, re-pin and say why",
				c.name,
				total,
				pinned,
			)
		case:
			fmt.printfln("   pin: %d reads, as pinned", total)
		}
	} else {
		if t, ok := time_config(c, w); ok {
			report_timing(c, t)
		}
	}
}

// count_visitor is the result sink for every run here: it counts and keeps
// nothing, which is what makes the flat-memory promise testable. A visitor that
// retained results would make `peak` a measurement of the visitor.
count_visitor :: proc(data: rawptr, result: shacl.Result) -> bool {
	n := cast(^int)data
	n^ += 1
	return true
}

// time_config is the timing mode: compile cold, bind cold, validate warm-up
// plus best-of-REPS, over the plain engine.
@(private = "file")
time_config :: proc(c: Config, w: Workload) -> (t: Timing, ok: bool) {
	model: shacl.Shapes
	defer shacl.shapes_destroy(&model)
	compile_ok: bool
	if t.compile, compile_ok = compile_model(c, w, &model); !compile_ok {
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
	start := time.tick_now()
	shacl.bindings_init(&bindings, &model, se)
	t.bind = time.tick_since(start)

	t.validate = max(time.Duration)
	for rep in 0 ..< REPS + 1 {
		t.results = 0
		start = time.tick_now()
		failure := shacl.validate(&model, &bindings, se, count_visitor, &t.results)
		elapsed := time.tick_since(start)
		if failure != .None {
			fail("%s: validation failed — %s", c.name, shacl.failure_message(failure))
			return
		}
		if rep > 0 && elapsed < t.validate {
			t.validate = elapsed
		}
	}
	return t, true
}

report_timing :: proc(c: Config, t: Timing) {
	per_focus := c.focus_nodes > 0 ? time.duration_nanoseconds(t.validate) / i64(c.focus_nodes) : 0
	fmt.printfln(
		"   compile %8v   bind %8v   validate %8v  (%d ns/focus node, %d results)",
		t.compile,
		t.bind,
		t.validate,
		per_focus,
		t.results,
	)
}

when shacl.SHACL_COUNT_READS {
	// instrument_config is the read count: one validation with the tally reset
	// immediately before it. `bindings_init` resolves terms and is not part of
	// what is counted; `compile` reads the shapes graph through the same verbs,
	// which is why the reset comes after it.
	instrument_config :: proc(c: Config, w: Workload) -> (out: Instrumented, ok: bool) {
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

		shacl.read_counts_reset()
		failure := shacl.validate(&model, &bindings, se, count_visitor, &out.results)
		if failure != .None {
			fail("%s: instrumented validation failed — %s", c.name, shacl.failure_message(failure))
			return
		}
		out.reads = shacl.read_counts_get()
		return out, true
	}

	report_instrumented :: proc(c: Config, i: Instrumented) {
		total := reads_total(i.reads)
		per_focus := c.focus_nodes > 0 ? total / c.focus_nodes : 0
		fmt.printfln(
			"   reads %d (scan %d step %d outgoing %d term %d, %d/focus node, %d results)",
			total,
			i.reads.scan,
			i.reads.step,
			i.reads.outgoing,
			i.reads.term,
			per_focus,
			i.results,
		)
	}
}

// same_workload_but_density reports whether two configurations differ only in
// how much of their data violates. Compared structurally rather than by name:
// the density family is a property of the knobs, and a name-based grouping
// would silently stop meaning anything the moment someone renamed a
// configuration or changed one of its other knobs.
@(private = "file")
same_workload_but_density :: proc(a, b: Config) -> bool {
	x, y := a, b
	x.name, y.name = "", ""
	x.violation_percent, y.violation_percent = 0, 0
	return x == y
}

// assert_promises checks the two claims the `shacl` package doc makes that only
// a comparison across configurations can test, plus the counterweight that
// stops them passing vacuously.
@(private = "file")
assert_promises :: proc() {
	if len(observations) == 0 {
		return
	}

	// **`Conformance` costs nothing over the walk it rides on.**
	//
	// The package doc says `Conformance` allocates "nothing at all, whatever the
	// violation count", and SHACL-T-0024 first read that as
	// `total_allocation_count == 0` over a whole validation. That is not what it
	// claims, and the sentence before it says so: *validation* allocates per
	// focus node, per reachability round, and per shape entered. The tighter
	// promise is about the **consumer** — `tests/guards` asserts it in isolation,
	// feeding a synthetic result stream — and a conformance run still pays for
	// the walk underneath.
	//
	// So the checkable form at scale is a comparison rather than a zero, and it
	// is sharper than it looks. On a graph that **conforms**, nothing exits
	// early, so the walk is exactly the raw stream's walk: any difference in
	// allocations is the consumer, and the promise is that there is none —
	// an equality, not a bound. On a graph that does not conform, `Conformance`
	// stops at the first result, so it must allocate strictly less; more would
	// mean early exit was costing rather than saving.
	for o in observations {
		if o.conforms {
			if o.conformance_allocs != o.raw_allocs {
				fail(
					"%s conforms, so Conformance and the raw stream walk identically — but Conformance made %d allocation(s) against the stream's %d, so the consumer is costing something",
					o.config.name,
					o.conformance_allocs,
					o.raw_allocs,
				)
			}
			continue
		}
		if o.conformance_allocs > o.raw_allocs {
			fail(
				"%s: Conformance made %d allocation(s) against the raw stream's %d. It stops at the first result, so early exit is costing rather than saving",
				o.config.name,
				o.conformance_allocs,
				o.raw_allocs,
			)
		}
	}

	// **Memory stays flat exactly when the data is worst.** Within a density
	// family — same workload, different violation percentage — peak must not
	// move. It is an equality rather than a bound: the result stream buffers
	// nothing, so there is no reason for a single byte of difference, and a
	// tolerance would be a place for a slow leak to hide.
	for a, i in observations {
		for b in observations[i + 1:] {
			if !same_workload_but_density(a.config, b.config) {
				continue
			}
			if a.raw_peak != b.raw_peak {
				fail(
					"%s (%d%% violating) peaks at %d bytes and %s (%d%%) at %d — the same walk over the same data, so memory did not stay flat as density rose",
					a.config.name,
					a.config.violation_percent,
					a.raw_peak,
					b.config.name,
					b.config.violation_percent,
					b.raw_peak,
				)
			}

			// **And flat in total bytes, not only in peak** — because peak is a
			// high-water mark of *live* bytes, which is a statement about an
			// allocator that frees. Under an arena, `free` is a no-op and the
			// figure a caller sees is the total. The `shacl` package doc invites
			// a caller to supply any allocator, so a flat-memory promise that
			// held only for the heap would be a promise with a footnote nobody
			// reads. Both are asserted, so it holds either way.
			if a.raw_total_bytes != b.raw_total_bytes {
				fail(
					"%s (%d%% violating) allocated %d bytes in total and %s (%d%%) allocated %d — flat in peak but not in total, so the promise would not survive an arena allocator",
					a.config.name,
					a.config.violation_percent,
					a.raw_total_bytes,
					b.config.name,
					b.config.violation_percent,
					b.raw_total_bytes,
				)
			}

			// **And the counterweight.** Everything above would pass just as
			// well on an engine that had quietly stopped reporting anything, so
			// the one consumer that is *meant* to grow with the violation count
			// must be seen to. More violations, a larger report graph — strictly,
			// because a report is a graph and that is what it is for.
			denser, sparser := a, b
			if denser.config.violation_percent < sparser.config.violation_percent {
				denser, sparser = sparser, denser
			}
			if denser.config.violation_percent == sparser.config.violation_percent {
				continue
			}
			if denser.report_triples <= sparser.report_triples {
				fail(
					"%s (%d%% violating) reports %d triples and %s (%d%%) reports %d — a Report is supposed to grow with the violation count",
					denser.config.name,
					denser.config.violation_percent,
					denser.report_triples,
					sparser.config.name,
					sparser.config.violation_percent,
					sparser.report_triples,
				)
			}
		}
	}
}
