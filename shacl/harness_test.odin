package shacl

// The test harness: one throwaway record store over the memory seam, the
// shape every suite here shares — open, ingest + apply, snapshot, session,
// close (SHACL-T-0032; the record handoff's call-site mapping).
//
// A Test_DB owns the whole stack. `tdb_load` may be called any number of
// times (each load is one epoch); the first `tdb_session` pins the head
// snapshot, so load everything before asking for a session. `tdb_close`
// releases the snapshot before the store, in the order record asserts.

import "core:testing"

import "rdf:rdf"
import "record:record"
import "record:record/ingest"

@(private)
Test_DB :: struct {
	fs:       record.Mem_FS,
	st:       record.Store,
	snap:     record.Snapshot,
	has_snap: bool,
	ok:       bool,
}

// tdb_open opens the store in place. A Test_DB must not be copied or moved
// after this: the writer holds a pointer to the Mem_FS inside the struct.
@(private)
tdb_open :: proc(t: ^testing.T, db: ^Test_DB) -> bool {
	_, err, _, _ := record.store_open(&db.st, "test", record.mem_file_ops(&db.fs))
	db.ok = testing.expectf(t, err == .None, "store_open failed: %v", err)
	return db.ok
}

// tdb_load ingests a Turtle document and applies it as one epoch. The
// blank prefix is the load scope: two loads with different prefixes keep
// their blank nodes apart, the discipline `load_turtle`'s Load_Scope used to
// supply.
@(private)
tdb_load :: proc(
	t: ^testing.T,
	db: ^Test_DB,
	source: string,
	graph: rdf.Graph_Label = nil,
	blank_prefix := "t_",
	base := "",
) -> bool {
	if !db.ok {
		return false
	}
	ops, ierr := ingest.turtle(
		transmute([]byte)source,
		graph,
		context.allocator,
		blank_prefix = blank_prefix,
		base = base,
	)
	if !testing.expectf(t, ierr.kind == .None, "turtle ingest failed: %v", ierr) {
		return false
	}
	defer ingest.ops_destroy(ops, context.allocator)
	_, _, aerr := record.apply(&db.st, {ops = ops})
	return testing.expectf(t, aerr == record.Apply_Error{}, "apply failed: %v", aerr)
}

// tdb_session binds a session over the head snapshot, pinning it on first
// use. Load before you session: an epoch applied after the pin is invisible
// to every session already handed out.
@(private)
tdb_session :: proc(db: ^Test_DB, graph: rdf.Graph_Label = nil) -> Session {
	if !db.has_snap {
		snap, serr := record.store_latest(&db.st)
		assert(serr == .None, "tdb_session: store_latest failed")
		db.snap = snap
		db.has_snap = true
	}
	se: Session
	session_init(&se, db.snap, graph)
	return se
}

// tdb_release_snapshot lets a test drop the pin early — the model-outlives-
// the-store assertions close everything and then read the model.
@(private)
tdb_release_snapshot :: proc(db: ^Test_DB) {
	if db.has_snap {
		record.snapshot_release(&db.snap)
		db.has_snap = false
	}
}

@(private)
tdb_close :: proc(db: ^Test_DB) {
	tdb_release_snapshot(db)
	if db.ok {
		record.store_close(&db.st)
		db.ok = false
	}
	record.mem_fs_destroy(&db.fs)
}

// test_term materialises a term for rendering in an assertion. The decode
// borrows a stack buffer, so the term is cloned to the temp allocator —
// suites render it immediately and never keep one. An undecodable id yields
// a blank node named for the failure rather than a panic, so one broken read
// shows up as a mismatched expectation rather than as a lost test run.
@(private)
test_term :: proc(se: Session, id: record.Term_ID) -> rdf.Term {
	buf: Term_Buf
	term, ok := session_term(se, id, buf[:])
	if !ok {
		return rdf.Blank_Node("lookup-failed")
	}
	return rdf.clone_term(term, context.temp_allocator)
}

// tdb_compile compiles a shapes document from a store of its own and closes
// that store, so the caller holds a model that outlives the store it came
// from — the arrangement SHACL-A-0001 promises and every long-lived model
// (a Validator, an as-of audit) relies on.
@(private)
tdb_compile :: proc(t: ^testing.T, s: ^Shapes, source: string) -> bool {
	db: Test_DB
	defer tdb_close(&db)
	if !tdb_open(t, &db) || !tdb_load(t, &db, source, blank_prefix = "s_") {
		return false
	}
	err := compile(s, tdb_session(&db))
	return testing.expectf(t, err.kind == .None, "compile: %s", error_message(err.kind))
}
