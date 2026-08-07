package main

import "core:fmt"
import "core:os"
import "core:time"

import store "store:store"
import kvstore "store:store/kvstore"

import shacl "../shacl"
import shacl_kvstore "../shacl/kvstore"

// The instrumented mode: reads and allocation, never timings.
//
// Both instruments go on together because both are deterministic for a fixed
// seed and neither belongs in a timed run. The counting `Access` adds an
// indirection per read; the tracking allocator adds bookkeeping per allocation.
// Either would be lost in the noise of a single measurement and neither is
// worth defending in a number someone quotes.
//
// **Allocation is tracked around `validate` and nothing else.** The promise
// under test is about validation — memory flat as the violation count rises —
// and folding compile and bind into the same tally would bury it under a
// one-off cost that scales with the shapes graph instead.

instrument_kvstore :: proc(c: Config, w: Workload) -> (out: Instrumented, ok: bool) {
	model: shacl.Shapes
	defer shacl.shapes_destroy(&model)

	shapes_db, shapes_path, shapes_open := open_temp_store(c.name, "shapes-i")
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
	if e := shacl_kvstore.compile(&model, &session); e.kind != .None {
		fail("%s: shapes graph did not compile on kvstore", c.name)
		return
	}

	db, path, opened := open_temp_store(c.name, "data-i")
	if !opened {
		return
	}
	defer close_temp_store(db, path)
	if _, parse_err, load_err := kvstore.load_turtle(db, transmute([]byte)w.data_ttl);
	   load_err != nil || parse_err.message != "" {
		fail("%s: data graph failed to load into kvstore", c.name)
		return
	}

	// Binding needs a Session; the counting Access needs a Kv_Probe. They are
	// two views of the same store, which is fine — `bind` is not part of what is
	// being counted, because it resolves terms rather than reading the graph.
	bind_session: shacl_kvstore.Session
	shacl_kvstore.session_init(&bind_session, db)
	bindings: shacl.Bindings
	defer shacl.bindings_destroy(&bindings)
	shacl_kvstore.bind(&bindings, &model, &bind_session)

	probe := Kv_Probe {
		db    = db,
		graph = store.DEFAULT_GRAPH,
	}
	failure := shacl.validate(
		&model,
		&bindings,
		kv_access(&probe),
		count_visitor,
		&out.results,
	)
	if failure != .None {
		fail("%s: instrumented kvstore validation failed — %s", c.name, shacl.failure_message(failure))
		return
	}
	if probe.err != nil {
		fail("%s: a store read failed during instrumented kvstore validation", c.name)
		return
	}

	out.reads = probe.reads
	return out, true
}

report_timing :: proc(backend: string, c: Config, t: Timing) {
	per_focus := c.focus_nodes > 0 ? time.duration_nanoseconds(t.validate) / i64(c.focus_nodes) : 0
	fmt.printfln(
		"   %s  compile %8v   bind %8v   validate %8v  (%d ns/focus node, %d results)",
		backend,
		t.compile,
		t.bind,
		t.validate,
		per_focus,
		t.results,
	)
}

report_instrumented :: proc(backend: string, c: Config, i: Instrumented) {
	total := reads_total(i.reads)
	per_focus := c.focus_nodes > 0 ? total / c.focus_nodes : 0
	fmt.printfln(
		"   %s  reads %6d (scan %d step %d outgoing %d load %d, %d/focus node)",
		backend,
		total,
		i.reads.scan,
		i.reads.step,
		i.reads.outgoing,
		i.reads.load,
		per_focus,
	)
	// Allocation is memstore-only in practice: the kvstore run shares this
	// report shape but takes no tracker, so its zeros are absence rather than a
	// measurement and are not printed.
	if i.allocations > 0 {
		fmt.printfln(
			"   %s  peak %d bytes, %d bytes total over %d allocations",
			backend,
			i.peak,
			i.total_bytes,
			i.allocations,
		)
	}
}

// open_temp_store opens a fresh LMDB store under the OS temp directory.
//
// The separator and the fallback order are the ones `tests/w3c/harness` and
// `shacl/kvstore`'s tests already carry, for the reason recorded there: macOS
// exports TMPDIR with a trailing slash, Linux usually exports nothing, and
// Windows names it TEMP or TMP and has no /tmp to fall back on.
open_temp_store :: proc(name, role: string) -> (db: ^kvstore.Store, path: string, ok: bool) {
	tmp := os.get_env("TMPDIR", context.temp_allocator)
	if tmp == "" {
		tmp = os.get_env("TEMP", context.temp_allocator)
	}
	if tmp == "" {
		tmp = os.get_env("TMP", context.temp_allocator)
	}
	if tmp == "" {
		tmp = "/tmp"
	}
	if tmp[len(tmp) - 1] == '/' || tmp[len(tmp) - 1] == '\\' {
		tmp = tmp[:len(tmp) - 1]
	}
	path = fmt.aprintf("%s/odin-rdf-shacl-bench-%s-%s", tmp, name, role)

	// A store left behind by an interrupted run would make the next one measure
	// a graph twice its size, so the path is cleared before it is opened.
	remove_store_files(path)
	opened, err := kvstore.open(path)
	if err != nil {
		fail("%s: could not open a temporary store at %s — %v", name, path, err)
		delete(path)
		return nil, "", false
	}
	return opened, path, true
}

close_temp_store :: proc(db: ^kvstore.Store, path: string) {
	kvstore.close(db)
	remove_store_files(path)
	delete(path)
}

@(private = "file")
remove_store_files :: proc(path: string) {
	os.remove(fmt.tprintf("%s/data.mdb", path))
	os.remove(fmt.tprintf("%s/lock.mdb", path))
	os.remove(path)
}
