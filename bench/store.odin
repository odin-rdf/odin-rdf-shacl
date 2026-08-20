package main

import "core:time"

import "record:record"
import "record:record/ingest"

import "../shacl"

// The store under the benchmark: odin-rdf-record over its memory seam
// (SHACL-T-0036). One `Graph_Store` holds one loaded graph — open, ingest,
// apply as one epoch, pin the head snapshot — the shape every suite in this
// repository uses, written once more here because a benchmark is not a test
// and reaches the engine through its own module path.
//
// **Never copied or moved after `graph_open`**: the writer holds a pointer to
// the `Mem_FS` inside. Declare one where it lives and pass it by pointer.
//
// The memory seam rather than a directory on disk, deliberately: what is
// measured is validation, and the store's own write path — the fsync, the
// segment rotation — is record's benchmark, not this one's. Nothing here is
// timed until the graph is loaded and the snapshot pinned.
Graph_Store :: struct {
	fs:     record.Mem_FS,
	st:     record.Store,
	snap:   record.Snapshot,
	ok:     bool,
	pinned: bool,
}

// graph_open opens a store, loads one Turtle document into its default graph
// as one epoch under `blank_prefix`, and pins the head snapshot. Failures are
// reported through `fail` with the configuration's name.
graph_open :: proc(g: ^Graph_Store, config_name, ttl, blank_prefix: string) -> bool {
	_, err, _, _ := record.store_open(&g.st, config_name, record.mem_file_ops(&g.fs))
	if err != .None {
		fail("%s: store_open failed — %v", config_name, err)
		return false
	}
	g.ok = true

	ops, ierr := ingest.turtle(transmute([]byte)ttl, nil, context.allocator, blank_prefix = blank_prefix)
	if ierr.kind != .None {
		fail("%s: generated graph failed to ingest — %v", config_name, ierr.kind)
		return false
	}
	defer ingest.ops_destroy(ops, context.allocator)
	if _, _, aerr := record.apply(&g.st, {ops = ops}); aerr != (record.Apply_Error{}) {
		fail("%s: generated graph failed to apply — %v at op %d", config_name, aerr.kind, aerr.op)
		return false
	}

	snap, serr := record.store_latest(&g.st)
	if serr != .None {
		fail("%s: store_latest failed — %v", config_name, serr)
		return false
	}
	g.snap = snap
	g.pinned = true
	return true
}

// graph_session is a session over the pinned snapshot's default graph.
graph_session :: proc(g: ^Graph_Store) -> shacl.Session {
	se: shacl.Session
	shacl.session_init(&se, g.snap)
	return se
}

// graph_close releases the snapshot before the store, the order record
// asserts, and is safe on a store that never opened.
graph_close :: proc(g: ^Graph_Store) {
	if g.pinned {
		record.snapshot_release(&g.snap)
		g.pinned = false
	}
	if g.ok {
		record.store_close(&g.st)
		g.ok = false
	}
	record.mem_fs_destroy(&g.fs)
}

// compile_model compiles the workload's shapes graph from a store of its own
// and closes that store before returning — the model owns its terms
// (SHACL-A-0001), and every run below validates with a model whose store is
// gone, exactly as a long-lived process would. The elapsed time is the
// compile alone: the load is done before the clock starts.
compile_model :: proc(c: Config, w: Workload, model: ^shacl.Shapes) -> (elapsed: time.Duration, ok: bool) {
	g: Graph_Store
	defer graph_close(&g)
	if !graph_open(&g, c.name, w.shapes_ttl, "s_") {
		return
	}
	se := graph_session(&g)
	start := time.tick_now()
	err := shacl.compile(model, se)
	elapsed = time.tick_since(start)
	if err.kind != .None {
		fail("%s: shapes graph did not compile — %s", c.name, shacl.error_message(err.kind))
		return
	}
	return elapsed, true
}
