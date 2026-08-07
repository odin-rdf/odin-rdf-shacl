// Package main is odin-rdf-shacl's benchmark: what validation costs, measured
// rather than argued (SHACL-I-0003). Run with:
//
//	make bench
//
// which builds with `-o:speed -no-bounds-check` and runs the binary at each
// `Term_ID` width, exactly as `make test` runs the suite at each.
//
//
// # What it reports, and in what units
//
// **Three phases, separately**, because they scale differently and are paid at
// different rates. `compile` (shapes graph to model) and `bind` (model to
// data-store IDs) are once-per-process; `validate` is the repeated one. Rolling
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
// measures.**
//
//   - *Timing* — the real path through `shacl/memstore` and `shacl/kvstore`,
//     the real allocator, nothing wrapped. Wall clock only.
//   - *Instrumented* — this package's counting `Access` (see `access.odin`) and
//     a `mem.Tracking_Allocator`. Reports store reads and allocation. **No
//     timing is taken here and none should ever be quoted from it.**
//
// Allocation joins reads in the instrumented mode rather than taking a third:
// both are deterministic for a fixed seed, neither belongs in a timed run, and
// they answer adjacent questions. `peak` is what tests the flat-memory promise;
// `total` and the allocation count are where a per-result leak would show.
//
// **`validate` is a warm-up plus the best of REPS; `compile` and `bind` are
// measured once, cold.** That asymmetry is deliberate rather than sloppy. The
// question about validation is what it costs in steady state, and the first
// pass pays for cold pages and an unwarmed allocator — the very first run of
// this benchmark reported memstore as *slower* than LMDB on the reference
// configuration, purely because memstore went first. The question about compile
// and bind is the opposite: they happen once per process, so a cold number is
// not noise in the measurement, it is the measurement. Reporting a warmed
// figure for a cost nobody pays twice would flatter it.
//
//
// # What it asserts
//
// A benchmark that only prints is a benchmark nobody reads. Three things fail
// the run rather than appearing in the output:
//
//  1. **The generator is deterministic.** One seed, byte-identical graphs.
//     Everything below rests on it. Note what this does and does not catch: it
//     catches a generator that varies *within a process* — a global RNG, a
//     clock, a map iteration order — because both calls would disagree. It
//     cannot catch a generator whose stream merely *changed*, since both calls
//     would agree on the new one. That case is caught by (3), which was
//     confirmed by perturbing the PRNG and watching the pins fail rather than
//     this assertion.
//  2. **The read count is identical on memstore and kvstore.** The
//     backend-independent core decides *what* to ask and the adapter decides
//     only *how*, so a divergence is a bug rather than a property of a backend.
//  3. **The read count matches its pin.** See `config.odin` — a constant per
//     configuration, changed only by deliberate edit.
//
// The width half of (2) is asserted across runs rather than within one: ID
// width is a build-time choice, so `make bench` runs the binary at each width
// and the same pins have to hold. One integer, four ways.
//
//
// # What these numbers are not
//
// A workload this project chose. They are a regression instrument and a
// comparative one — the engine against itself over time, and with a change
// against without — not a claim about what SHACL costs in the world. See
// `generate.odin` for the shape of the workload and why it is synthetic.
package main

import "core:fmt"
import "core:os"
import "core:time"

import store "store:store"
import kvstore "store:store/kvstore"
import memstore "store:store/memstore"

import shacl "../shacl"
import shacl_kvstore "../shacl/kvstore"
import shacl_memstore "../shacl/memstore"

// REPS is how many timed validations a configuration runs after its warm-up.
// The reported figure is the fastest of them: a minimum is the statistic that
// resists the scheduler, which only ever makes a run slower.
REPS :: 5

// Timing is one configuration's wall clock on one backend.
Timing :: struct {
	compile:  time.Duration,
	bind:     time.Duration,
	validate: time.Duration,
	results:  int,
}

// Instrumented is one configuration's reads and allocation on one backend.
Instrumented :: struct {
	reads:       Reads,
	results:     int,
	peak:        int,
	total_bytes: int,
	allocations: int,
}

failures := 0

fail :: proc(format: string, args: ..any) {
	fmt.eprintf("FAIL: ")
	fmt.eprintfln(format, ..args)
	failures += 1
}

main :: proc() {
	fmt.printfln("odin-rdf-shacl bench — Term_ID width %d bits", store.TERM_ID_BITS)
	fmt.println(
		"Synthetic workload; a regression instrument, not a claim about real-world cost.",
	)

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
	// binary did.
	warm_up()

	for c in CONFIGS {
		fmt.printfln("\n== %s ==", c.name)
		run_config(c)
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
		_, _ = time_memstore(c, w)
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

	mem_t, mem_ok := time_memstore(c, w)
	kv_t, kv_ok := time_kvstore(c, w)
	if mem_ok {
		report_timing("memstore", c, mem_t)
	}
	if kv_ok {
		report_timing("kvstore ", c, kv_t)
	}

	mem_i, mem_i_ok := instrument_memstore(c, w)
	kv_i, kv_i_ok := instrument_kvstore(c, w)
	if mem_i_ok {
		report_instrumented("memstore", c, mem_i)
	}
	if kv_i_ok {
		report_instrumented("kvstore ", c, kv_i)
	}
	if !mem_i_ok || !kv_i_ok {
		return
	}

	// (2) The cross-backend invariant. Per verb rather than only in total: two
	// errors that cancel in the sum are exactly what a total would hide.
	if mem_i.reads != kv_i.reads {
		fail(
			"%s: backends disagree on reads — memstore %v, kvstore %v. The core decides what to ask and the adapter only how, so this is a defect rather than a measurement",
			c.name,
			mem_i.reads,
			kv_i.reads,
		)
	}
	if mem_i.results != kv_i.results {
		fail(
			"%s: backends disagree on results — memstore %d, kvstore %d",
			c.name,
			mem_i.results,
			kv_i.results,
		)
	}

	// (3) The pin.
	total := reads_total(mem_i.reads)
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
}

// count_visitor is the result sink for every run here: it counts and keeps
// nothing, which is what makes the flat-memory promise testable. A visitor that
// retained results would make `peak` a measurement of the visitor.
count_visitor :: proc(data: rawptr, result: shacl.Result) -> bool {
	n := cast(^int)data
	n^ += 1
	return true
}

@(private = "file")
time_memstore :: proc(c: Config, w: Workload) -> (t: Timing, ok: bool) {
	model: shacl.Shapes
	defer shacl.shapes_destroy(&model)

	shapes_dict: memstore.Dictionary
	memstore.dictionary_init(&shapes_dict)
	defer memstore.dictionary_destroy(&shapes_dict)
	shapes_data: memstore.Dataset
	memstore.dataset_init(&shapes_data)
	defer memstore.dataset_destroy(&shapes_data)

	// Loading is untimed on purpose: parsing and interning are odin-rdf-parser's
	// and odin-rdf-store's measured business, and this is a non-goal of
	// SHACL-I-0003. What is timed is what this repository wrote.
	if _, err := memstore.load_turtle(
		&shapes_dict,
		&shapes_data,
		transmute([]byte)w.shapes_ttl,
	); err.message != "" {
		fail("%s: shapes graph failed to load — %s", c.name, err.message)
		return
	}

	start := time.tick_now()
	compile_err := shacl_memstore.compile(&model, &shapes_dict, &shapes_data)
	t.compile = time.tick_since(start)
	if compile_err.kind != .None {
		fail("%s: shapes graph did not compile — %s", c.name, shacl.error_message(compile_err.kind))
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
		fail("%s: data graph failed to load — %s", c.name, err.message)
		return
	}

	bindings: shacl.Bindings
	defer shacl.bindings_destroy(&bindings)
	start = time.tick_now()
	shacl_memstore.bind(&bindings, &model, &dict)
	t.bind = time.tick_since(start)

	t.validate = max(time.Duration)
	for rep in 0 ..< REPS + 1 {
		t.results = 0
		start = time.tick_now()
		failure := shacl_memstore.validate(
			&model,
			&bindings,
			&dict,
			&data,
			count_visitor,
			&t.results,
		)
		elapsed := time.tick_since(start)
		if failure != .None {
			fail("%s: memstore validation failed — %s", c.name, shacl.failure_message(failure))
			return
		}
		// Rep 0 is the warm-up and is discarded.
		if rep > 0 && elapsed < t.validate {
			t.validate = elapsed
		}
	}
	return t, true
}

@(private = "file")
time_kvstore :: proc(c: Config, w: Workload) -> (t: Timing, ok: bool) {
	model: shacl.Shapes
	defer shacl.shapes_destroy(&model)

	shapes_db, shapes_path, shapes_open := open_temp_store(c.name, "shapes-t")
	if !shapes_open {
		return
	}
	defer close_temp_store(shapes_db, shapes_path)

	if _, parse_err, load_err := kvstore.load_turtle(
		shapes_db,
		transmute([]byte)w.shapes_ttl,
	); load_err != nil || parse_err.message != "" {
		fail("%s: shapes graph failed to load into kvstore", c.name)
		return
	}

	session: shacl_kvstore.Session
	shacl_kvstore.session_init(&session, shapes_db)
	start := time.tick_now()
	compile_err := shacl_kvstore.compile(&model, &session)
	t.compile = time.tick_since(start)
	if compile_err.kind != .None || shacl_kvstore.session_error(&session) != nil {
		fail("%s: shapes graph did not compile on kvstore", c.name)
		return
	}

	db, path, opened := open_temp_store(c.name, "data-t")
	if !opened {
		return
	}
	defer close_temp_store(db, path)
	if _, parse_err, load_err := kvstore.load_turtle(db, transmute([]byte)w.data_ttl);
	   load_err != nil || parse_err.message != "" {
		fail("%s: data graph failed to load into kvstore", c.name)
		return
	}

	data_session: shacl_kvstore.Session
	shacl_kvstore.session_init(&data_session, db)

	bindings: shacl.Bindings
	defer shacl.bindings_destroy(&bindings)
	start = time.tick_now()
	shacl_kvstore.bind(&bindings, &model, &data_session)
	t.bind = time.tick_since(start)

	t.validate = max(time.Duration)
	for rep in 0 ..< REPS + 1 {
		t.results = 0
		start = time.tick_now()
		failure := shacl_kvstore.validate(
			&model,
			&bindings,
			&data_session,
			count_visitor,
			&t.results,
		)
		elapsed := time.tick_since(start)
		if failure != .None {
			fail("%s: kvstore validation failed — %s", c.name, shacl.failure_message(failure))
			return
		}
		if rep > 0 && elapsed < t.validate {
			t.validate = elapsed
		}
	}
	// A failed LMDB read yields no value nodes, which looks exactly like a
	// conforming graph — so a fast, silent, empty validation would be a broken
	// store reported as good news.
	if err := shacl_kvstore.session_error(&data_session); err != nil {
		fail("%s: a store read failed during kvstore validation — %v", c.name, err)
		return
	}
	return t, true
}
