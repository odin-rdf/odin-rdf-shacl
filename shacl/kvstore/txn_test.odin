package shacl_kvstore

import "core:testing"

import rdf "rdf:rdf"
import store "store:store"
import kvstore "store:store/kvstore"

import shacl ".."

// Validation through a caller's transaction (SHACL-T-0029).
//
// What these assert is the thing that was inexpressible before odin-rdf-store
// v0.3.0: **a validator that can read the dataset a write would produce.** The
// central test is deliberately the vacuity case rather than the happy path,
// because the happy path passes without any of this code. A candidate is
// validated twice against the same shapes — once inside the write transaction
// that carries it, where the committed data is visible and the shape is
// violated, and once in isolation, where it is not and the same candidate
// conforms. That second assertion is what makes this a test of the feature
// rather than a test of `sh:maxCount`: the isolated answer is the wrong one,
// and it is the answer the old API steered a caller toward.
//
// The autocommit path is what every other file in this package exercises, so
// nothing here re-asserts it except where the two are compared directly.

// One value is allowed. The committed graph already spends it.
TXN_SHAPES :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix ex: <http://example.org/> .

ex:PersonShape a sh:NodeShape ; sh:targetClass ex:Person ;
	sh:property [ sh:path ex:email ; sh:maxCount 1 ] .
`

TXN_COMMITTED :: `
@prefix ex: <http://example.org/> .

ex:alice a ex:Person ; ex:email "alice@example.org" .
`

// Self-contained: it carries its own type triple, so the shape's target
// resolves whether or not the committed graph is visible. Without that, the
// isolated validation would conform for the *uninteresting* reason — no focus
// node at all — and would prove nothing about seeing the write.
TXN_CANDIDATE :: `
@prefix ex: <http://example.org/> .

ex:alice a ex:Person ; ex:email "alice@work.example.org" .
`

// txn_shapes compiles TXN_SHAPES from a store of its own and closes it, so
// every test below holds a model that outlives the store it came from — the
// arrangement SHACL-A-0001 promises and the one a long-lived validator uses.
@(private = "file")
txn_shapes :: proc(t: ^testing.T, s: ^shacl.Shapes) -> bool {
	db, open_err := kvstore.open_ephemeral()
	if !testing.expectf(t, open_err == nil, "shapes store: %v", open_err) {
		return false
	}
	defer kvstore.close(db)

	err, load_err, db_err := compile_turtle(s, db, transmute([]byte)string(TXN_SHAPES))
	if !testing.expectf(
		t,
		err.kind == .None && load_err.message == "" && db_err == nil,
		"shapes: %s / %s / %v",
		shacl.error_message(err.kind),
		load_err.message,
		db_err,
	) {
		return false
	}
	return true
}

// conforms_in reports whether the graph a session reads conforms to `shapes`,
// with the store error folded in — every caller here treats an unreadable
// store as a failed test rather than as an answer.
@(private = "file")
conforms_in :: proc(t: ^testing.T, shapes: ^shacl.Shapes, session: ^Session, what: string) -> bool {
	bindings: shacl.Bindings
	bind(&bindings, shapes, session)
	defer shacl.bindings_destroy(&bindings)

	ok, failure := conforms(shapes, &bindings, session)
	testing.expectf(t, failure == .None, "%s: validation failed: %v", what, failure)
	testing.expectf(t, session_error(session) == nil, "%s: store read failed: %v", what, session_error(session))
	return ok
}

// The item's own acceptance criterion, as one test: the candidate violates
// only because the committed data is visible, and validating it in isolation
// passes.
@(test)
test_validate_before_commit_sees_the_committed_data :: proc(t: ^testing.T) {
	shapes: shacl.Shapes
	if !txn_shapes(t, &shapes) {
		return
	}
	defer shacl.shapes_destroy(&shapes)

	// The dataset the write would join.
	db, open_err := kvstore.open_ephemeral()
	if !testing.expectf(t, open_err == nil, "data store: %v", open_err) {
		return
	}
	defer kvstore.close(db)

	_, parse_err, load_err := kvstore.load_turtle(db, transmute([]byte)string(TXN_COMMITTED))
	if !testing.expectf(t, parse_err.message == "" && load_err == nil, "committed graph: %s", parse_err.message) {
		return
	}

	// The committed dataset on its own conforms, so the violation below is the
	// candidate's doing rather than the fixture's.
	{
		session: Session
		session_init(&session, db)
		testing.expect(t, conforms_in(t, &shapes, &session, "committed alone"), "committed graph should conform")
	}

	// The candidate, inside the write transaction that carries it.
	tx, txn_err := kvstore.txn_begin(db, .Write)
	if !testing.expectf(t, txn_err == nil, "txn_begin: %v", txn_err) {
		return
	}
	defer kvstore.txn_abort(&tx)

	_, cand_parse, cand_err := kvstore.load_turtle_txn(&tx, transmute([]byte)string(TXN_CANDIDATE))
	if !testing.expectf(t, cand_parse.message == "" && cand_err == nil, "candidate: %s", cand_parse.message) {
		return
	}

	session: Session
	session_init_txn(&session, &tx)
	testing.expect(
		t,
		!conforms_in(t, &shapes, &session, "candidate in txn"),
		"the candidate must violate sh:maxCount: it adds a second ex:email to a node the committed graph already gave one",
	)

	// The half that makes this a test of the feature. The same candidate, the
	// same shapes, no committed data — and it conforms, which is the answer the
	// isolated-candidate workaround would have returned for the real dataset.
	iso, iso_open := kvstore.open_ephemeral()
	if !testing.expectf(t, iso_open == nil, "isolated store: %v", iso_open) {
		return
	}
	defer kvstore.close(iso)

	_, iso_parse, iso_err := kvstore.load_turtle(iso, transmute([]byte)string(TXN_CANDIDATE))
	if !testing.expectf(t, iso_parse.message == "" && iso_err == nil, "isolated candidate: %s", iso_parse.message) {
		return
	}

	iso_session: Session
	session_init(&iso_session, iso)
	testing.expect(
		t,
		conforms_in(t, &shapes, &iso_session, "candidate alone"),
		"the candidate alone must conform — if it does not, this test no longer distinguishes the two worlds",
	)
}

// Deciding not to keep a write is the other half of the pattern, and it must
// leave nothing behind.
@(test)
test_aborting_discards_the_rejected_candidate :: proc(t: ^testing.T) {
	shapes: shacl.Shapes
	if !txn_shapes(t, &shapes) {
		return
	}
	defer shacl.shapes_destroy(&shapes)

	db, open_err := kvstore.open_ephemeral()
	if !testing.expectf(t, open_err == nil, "data store: %v", open_err) {
		return
	}
	defer kvstore.close(db)

	_, parse_err, load_err := kvstore.load_turtle(db, transmute([]byte)string(TXN_COMMITTED))
	if !testing.expectf(t, parse_err.message == "" && load_err == nil, "committed graph: %s", parse_err.message) {
		return
	}
	before, count_err := kvstore.count(db)
	testing.expectf(t, count_err == nil, "count: %v", count_err)

	{
		tx, txn_err := kvstore.txn_begin(db, .Write)
		if !testing.expectf(t, txn_err == nil, "txn_begin: %v", txn_err) {
			return
		}
		_, _, cand_err := kvstore.load_turtle_txn(&tx, transmute([]byte)string(TXN_CANDIDATE))
		testing.expectf(t, cand_err == nil, "candidate: %v", cand_err)

		session: Session
		session_init_txn(&session, &tx)
		testing.expect(t, !conforms_in(t, &shapes, &session, "candidate in txn"), "candidate should violate")

		kvstore.txn_abort(&tx)
	}

	after, after_err := kvstore.count(db)
	testing.expectf(t, after_err == nil, "count after abort: %v", after_err)
	testing.expect_value(t, after, before)

	session: Session
	session_init(&session, db)
	testing.expect(t, conforms_in(t, &shapes, &session, "after abort"), "the committed graph must conform again")
}

// A read transaction is the other mode, and it must answer exactly as
// autocommit does on a store nobody is writing to — the two branches of every
// adapter, over one dataset, compared directly.
@(test)
test_read_txn_answers_as_autocommit_does :: proc(t: ^testing.T) {
	shapes: shacl.Shapes
	if !txn_shapes(t, &shapes) {
		return
	}
	defer shacl.shapes_destroy(&shapes)

	db, open_err := kvstore.open_ephemeral()
	if !testing.expectf(t, open_err == nil, "data store: %v", open_err) {
		return
	}
	defer kvstore.close(db)

	// Two emails on one focus node: a violation both ways, so this compares the
	// interesting answer rather than the empty one.
	_, parse_err, load_err := kvstore.load_turtle(
		db,
		transmute([]byte)string(TXN_COMMITTED + TXN_CANDIDATE),
	)
	if !testing.expectf(t, parse_err.message == "" && load_err == nil, "data graph: %s", parse_err.message) {
		return
	}

	auto: Session
	session_init(&auto, db)
	auto_answer := conforms_in(t, &shapes, &auto, "autocommit")

	tx, txn_err := kvstore.txn_begin(db, .Read)
	if !testing.expectf(t, txn_err == nil, "txn_begin: %v", txn_err) {
		return
	}
	defer kvstore.txn_abort(&tx)

	snapshot: Session
	session_init_txn(&snapshot, &tx)
	snapshot_answer := conforms_in(t, &shapes, &snapshot, "read txn")

	testing.expect_value(t, snapshot_answer, auto_answer)
	testing.expect(t, !auto_answer, "two ex:email values must violate sh:maxCount either way")
}

// A read transaction is a snapshot, and a validation through one is an answer
// about one dataset rather than about however many the reads happened to land
// on. Nothing single-threaded can observe a torn read, so what this asserts is
// the property that makes it impossible: a commit through the store does not
// reach a session already reading through an open snapshot.
@(test)
test_read_txn_does_not_see_a_later_commit :: proc(t: ^testing.T) {
	shapes: shacl.Shapes
	if !txn_shapes(t, &shapes) {
		return
	}
	defer shacl.shapes_destroy(&shapes)

	// A real store, not an ephemeral one: this holds a read transaction
	// open across a commit, and open_ephemeral opens with NOLOCK, whose
	// contract says the caller must ensure no reader holds an old
	// transaction while a writer is active. Without the reader table the
	// writer cannot know which pages this reader still needs.
	path := temp_path("snapshot-data")
	defer remove_store(path)
	db, open_err := kvstore.open(path)
	if !testing.expectf(t, open_err == nil, "data store: %v", open_err) {
		return
	}
	defer kvstore.close(db)

	_, parse_err, load_err := kvstore.load_turtle(db, transmute([]byte)string(TXN_COMMITTED))
	if !testing.expectf(t, parse_err.message == "" && load_err == nil, "committed graph: %s", parse_err.message) {
		return
	}

	tx, txn_err := kvstore.txn_begin(db, .Read)
	if !testing.expectf(t, txn_err == nil, "txn_begin: %v", txn_err) {
		return
	}
	defer kvstore.txn_abort(&tx)

	snapshot: Session
	session_init_txn(&snapshot, &tx)
	testing.expect(t, conforms_in(t, &shapes, &snapshot, "snapshot before"), "the snapshot's graph conforms")

	// A write lands, and conflicts with what the snapshot is reading.
	_, cand_parse, cand_err := kvstore.load_turtle(db, transmute([]byte)string(TXN_CANDIDATE))
	if !testing.expectf(t, cand_parse.message == "" && cand_err == nil, "later commit: %s", cand_parse.message) {
		return
	}

	testing.expect(
		t,
		conforms_in(t, &shapes, &snapshot, "snapshot after"),
		"the snapshot must still see the dataset it opened on, not the committed write",
	)

	// And the same store, read fresh, does see it.
	now: Session
	session_init(&now, db)
	testing.expect(t, !conforms_in(t, &shapes, &now, "after commit"), "a fresh read must see the committed write")
}

// compile_turtle_txn: shapes loaded and compiled without leaving the
// transaction, and a model that survives the transaction being thrown away.
@(test)
test_compile_turtle_txn_compiles_uncommitted_shapes :: proc(t: ^testing.T) {
	db, open_err := kvstore.open_ephemeral()
	if !testing.expectf(t, open_err == nil, "store: %v", open_err) {
		return
	}
	defer kvstore.close(db)

	shapes_graph := rdf.Graph_Label(rdf.IRI("http://example.org/shapes"))

	shapes: shacl.Shapes
	{
		tx, txn_err := kvstore.txn_begin(db, .Write)
		if !testing.expectf(t, txn_err == nil, "txn_begin: %v", txn_err) {
			return
		}

		err, load_err, db_err := compile_turtle_txn(
			&shapes,
			&tx,
			transmute([]byte)string(TXN_SHAPES),
			shapes_graph,
		)
		if !testing.expectf(
			t,
			err.kind == .None && load_err.message == "" && db_err == nil,
			"compile_turtle_txn: %s / %s / %v",
			shacl.error_message(err.kind),
			load_err.message,
			db_err,
		) {
			kvstore.txn_abort(&tx)
			shacl.shapes_destroy(&shapes)
			return
		}
		testing.expect(t, len(shapes.shapes) > 0, "a shape should have been compiled")

		// Thrown away: the shapes graph never lands, and the model does not care.
		kvstore.txn_abort(&tx)
	}
	defer shacl.shapes_destroy(&shapes)

	n, count_err := kvstore.count(db)
	testing.expectf(t, count_err == nil, "count: %v", count_err)
	testing.expect_value(t, n, 0)

	// The aborted model still validates, against data it never shared a
	// transaction with.
	_, parse_err, load_err := kvstore.load_turtle(
		db,
		transmute([]byte)string(TXN_COMMITTED + TXN_CANDIDATE),
	)
	if !testing.expectf(t, parse_err.message == "" && load_err == nil, "data graph: %s", parse_err.message) {
		return
	}

	session: Session
	session_init(&session, db, store.DEFAULT_GRAPH)
	testing.expect(
		t,
		!conforms_in(t, &shapes, &session, "aborted shapes"),
		"a model compiled inside an aborted transaction is still a model",
	)
}

// The two sessions, side by side, over one store at one moment — which is the
// whole feature in a single assertion.
//
// **An autocommit read under an open write transaction is not refused.** Only
// writes are (`.Write_Txn_Open`, STORE-A-0007); a bare read opens a read
// transaction of its own, succeeds, and sees the last committed dataset. So the
// wrong session does not announce itself — it returns an answer, and the answer
// is about a dataset that is not the one being decided on. That is the failure
// mode this feature exists to remove, and it is worth pinning as behaviour
// rather than leaving as an inference.
@(test)
test_autocommit_session_cannot_see_the_open_write :: proc(t: ^testing.T) {
	shapes: shacl.Shapes
	if !txn_shapes(t, &shapes) {
		return
	}
	defer shacl.shapes_destroy(&shapes)

	// Durable for the same reason as the snapshot test above: the
	// autocommit session below opens a read transaction while this
	// test's write transaction is still open, which NOLOCK forbids.
	path := temp_path("two-sessions-data")
	defer remove_store(path)
	db, open_err := kvstore.open(path)
	if !testing.expectf(t, open_err == nil, "store: %v", open_err) {
		return
	}
	defer kvstore.close(db)

	_, parse_err, load_err := kvstore.load_turtle(db, transmute([]byte)string(TXN_COMMITTED))
	if !testing.expectf(t, parse_err.message == "" && load_err == nil, "committed graph: %s", parse_err.message) {
		return
	}

	tx, txn_err := kvstore.txn_begin(db, .Write)
	if !testing.expectf(t, txn_err == nil, "txn_begin: %v", txn_err) {
		return
	}
	defer kvstore.txn_abort(&tx)

	_, cand_parse, cand_err := kvstore.load_turtle_txn(&tx, transmute([]byte)string(TXN_CANDIDATE))
	if !testing.expectf(t, cand_parse.message == "" && cand_err == nil, "candidate: %s", cand_parse.message) {
		return
	}

	// Same store, same shapes, same instant, two answers.
	in_txn: Session
	session_init_txn(&in_txn, &tx)
	testing.expect(t, !conforms_in(t, &shapes, &in_txn, "through the txn"), "the transaction sees its own write")

	autocommit: Session
	session_init(&autocommit, db)
	testing.expect(
		t,
		conforms_in(t, &shapes, &autocommit, "autocommit"),
		"an autocommit read is not refused and does not see the open write — it answers about the committed dataset",
	)
}
