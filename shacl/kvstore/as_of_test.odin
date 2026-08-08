package shacl_kvstore

import "core:testing"

import rdf "rdf:rdf"
import store "store:store"
import kvstore "store:store/kvstore"

import shacl ".."

// Validating a **past** dataset (SHACL-T-0030, filed from odin-rdf-store's
// STORE-T-0052; the design is STORE-A-0008).
//
// odin-rdf-store gave every quad the epoch of the transaction that wrote it,
// and `txn_begin_as_of(db, horizon)` returns a transaction through which
// *every* read is as-of. Because `session_init_txn` already takes a
// `^kvstore.Txn`, a validation through such a transaction answers about the
// dataset as it was — **with no source change in this repository.** That claim
// is made in another repo's ADR about this one, so it is asserted here, where
// a future change that broke it would break.
//
// # This is not validate-before-commit, and the two do not compose
//
// `shacl/kvstore/txn_test.odin` covers validate-before-commit (SHACL-T-0029):
// a candidate assembled inside a **write** transaction and validated through
// that same transaction, so the validator sees the dataset the write *would
// produce*, and the answer decides whether it commits. There is a candidate,
// and it is about the future.
//
// What is here is a different feature reached through the same entry point.
// `txn_begin_as_of` takes no mode and always returns a **read** transaction,
// because an audit store must not expose an API for writing history
// (STORE-A-0008 §4) — a property of the signature rather than a runtime check.
// So there is no candidate anywhere below, nothing is being decided, and
// nothing here commits or could: these tests ask what the *committed* dataset
// looked like at an earlier epoch and whether it conformed then. Nothing in
// this file should be read as a candidate write, and no arrangement of the two
// features lets a caller assemble a candidate inside an as-of transaction.
//
// # How the epochs are built
//
// Only a quad write allocates an epoch, and each autocommit loader or `remove`
// is one write transaction, so the fixtures below hold epochs 1, 2, 3 by
// construction — the same way odin-rdf-store's own as-of suite builds a
// history. `epoch_at`, which turns a wall clock into a horizon, is deliberately
// not used: that translation is the store's concern and is tested there, and a
// suite here depending on two commits landing in distinguishable clock ticks
// would be a flake on the coarsest-clocked CI platform rather than a statement
// about validation.
//
// Each test differs between HEAD and the horizon, in opposite directions — one
// conforms now and violated then, the other violates now and conformed then.
// A validation returning the same answer either way would demonstrate nothing,
// and would be exactly what an as-of transaction quietly reading HEAD looks
// like.

@(private = "file")
EX :: "http://example.org/"

@(private = "file")
RDFS_SUBCLASSOF :: "http://www.w3.org/2000/01/rdf-schema#subClassOf"

// compile_as_of_shapes compiles a shapes graph from a store of its own, so the
// shapes never land in the data store and never consume one of its epochs. The
// model outlives that store, which is SHACL-A-0001's ownership property and is
// what lets one model be validated at four horizons below.
@(private = "file")
compile_as_of_shapes :: proc(t: ^testing.T, s: ^shacl.Shapes, source: string) -> bool {
	db, open_err := kvstore.open_ephemeral()
	if !testing.expectf(t, open_err == nil, "shapes store: %v", open_err) {
		return false
	}
	defer kvstore.close(db)

	err, load_err, db_err := compile_turtle(s, db, transmute([]byte)source)
	return testing.expectf(
		t,
		err.kind == .None && load_err.message == "" && db_err == nil,
		"shapes: %s / %s / %v",
		shacl.error_message(err.kind),
		load_err.message,
		db_err,
	)
}

// load_epoch loads a Turtle fragment as one autocommit transaction, which is
// one epoch. The returned count is the epoch's own contribution, not the
// dataset's size.
@(private = "file")
load_epoch :: proc(t: ^testing.T, db: ^kvstore.Store, source: string, what: string) -> bool {
	added, parse_err, err := kvstore.load_turtle(db, transmute([]byte)source)
	if !testing.expectf(t, parse_err.message == "" && err == nil, "%s: %s / %v", what, parse_err.message, err) {
		return false
	}
	return testing.expectf(t, added > 0, "%s: loaded nothing, so no epoch was allocated", what)
}

// retract_epoch retracts exactly one quad, as one autocommit transaction and
// therefore one epoch.
//
// **It is a retraction, not an erasure** — the quad stops being visible at
// HEAD and stays visible at every horizon before this epoch, which is what the
// tests below observe from the validator's side.
@(private = "file")
retract_epoch :: proc(t: ^testing.T, db: ^kvstore.Store, subject, predicate, object: rdf.Term) -> bool {
	terms := [3]rdf.Term{subject, predicate, object}
	ids: [3]store.Term_ID
	for term, i in terms {
		id, found, err := kvstore.find_term(db, term)
		if !testing.expectf(t, err == nil && found, "find_term %v: found=%v err=%v", term, found, err) {
			return false
		}
		ids[i] = id
	}

	pattern := store.Match_Pattern{ids[0], ids[1], ids[2], store.DEFAULT_GRAPH}
	removed, err := kvstore.remove(db, pattern)
	if !testing.expectf(t, err == nil, "remove: %v", err) {
		return false
	}
	return testing.expectf(t, removed == 1, "remove retracted %v quads, expected 1", removed)
}

// verdict_at validates through a read transaction opened at `horizon` and
// reports the verdict together with the size of the dataset that verdict is
// about.
//
// **The size is not decoration.** "Conforms" over an empty graph and
// "conforms" over a populated one are the same boolean and different facts, so
// every assertion below that expects conformance also pins how many quads were
// visible. Without it, an as-of read that returned nothing at all would look
// like a clean bill of health.
//
// Note what `bind` does here: it resolves the model's terms through this same
// as-of transaction, and it finds them, because the dictionary is deliberately
// outside the epoch model (STORE-A-0008 §7) — a term stays nameable in a read
// of the past even after the last quad mentioning it is retracted.
@(private = "file")
verdict_at :: proc(
	t: ^testing.T,
	shapes: ^shacl.Shapes,
	db: ^kvstore.Store,
	horizon: store.Epoch,
) -> (
	conforming: bool,
	visible: int,
) {
	tx, txn_err := kvstore.txn_begin_as_of(db, horizon)
	if !testing.expectf(t, txn_err == nil, "txn_begin_as_of(%v): %v", horizon, txn_err) {
		return false, -1
	}
	defer kvstore.txn_abort(&tx)

	n, count_err := kvstore.count_txn(&tx)
	testing.expectf(t, count_err == nil, "count_txn at horizon %v: %v", horizon, count_err)

	session: Session
	session_init_txn(&session, &tx)

	bindings: shacl.Bindings
	bind(&bindings, shapes, &session)
	defer shacl.bindings_destroy(&bindings)

	ok, failure := conforms(shapes, &bindings, &session)
	testing.expectf(t, failure == .None, "horizon %v: validation failed: %v", horizon, failure)
	testing.expectf(
		t,
		session_error(&session) == nil,
		"horizon %v: store read failed: %v",
		horizon,
		session_error(&session),
	)
	return ok, n
}

// One owner is allowed. A handover that recorded the new owner before
// retracting the old one spends a moment with two.
@(private = "file")
OWNER_SHAPES :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix ex: <http://example.org/> .

ex:AssetShape a sh:NodeShape ; sh:targetClass ex:Asset ;
	sh:property [ sh:path ex:owner ; sh:maxCount 1 ] .
`

@(private = "file")
OWNER_EPOCH_1 :: `
@prefix ex: <http://example.org/> .

ex:disk a ex:Asset ; ex:owner ex:alice .
`

@(private = "file")
OWNER_EPOCH_2 :: `
@prefix ex: <http://example.org/> .

ex:disk ex:owner ex:bob .
`

// HEAD conforms; the epoch in the middle does not.
//
// The interesting direction: a violation that no longer exists is still
// reachable, because retraction is logical rather than physical. An auditor
// asking "was this ever in a state our shapes reject?" gets a different answer
// from the past than from the present, which is the whole point of the time
// dimension and is invisible to a validator that can only read HEAD.
@(test)
test_as_of_validation_sees_the_dataset_as_it_was :: proc(t: ^testing.T) {
	shapes: shacl.Shapes
	if !compile_as_of_shapes(t, &shapes, OWNER_SHAPES) {
		return
	}
	defer shacl.shapes_destroy(&shapes)

	db, open_err := kvstore.open_ephemeral()
	if !testing.expectf(t, open_err == nil, "data store: %v", open_err) {
		return
	}
	defer kvstore.close(db)

	// Epoch 1: the asset and its owner.
	if !load_epoch(t, db, OWNER_EPOCH_1, "epoch 1") {
		return
	}
	// Epoch 2: the new owner is recorded, and for this epoch there are two.
	if !load_epoch(t, db, OWNER_EPOCH_2, "epoch 2") {
		return
	}
	// Epoch 3: the old owner is retracted, and the handover is complete.
	if !retract_epoch(t, db, rdf.IRI(EX + "disk"), rdf.IRI(EX + "owner"), rdf.IRI(EX + "alice")) {
		return
	}

	// Before anything. store.EPOCH_NEVER is the horizon a caller reaches by
	// forgetting to set one, so its meaning is worth pinning: the empty
	// dataset, which conforms for the vacuous reason and not for a good one.
	// The count is what says which of the two this is.
	vacuous, empty := verdict_at(t, &shapes, db, store.EPOCH_NEVER)
	testing.expect_value(t, empty, 0)
	testing.expect(t, vacuous, "an empty dataset has no focus nodes, so it conforms vacuously")

	// Epoch 1: one owner, and a real focus node to reach it from.
	before, before_n := verdict_at(t, &shapes, db, 1)
	testing.expect_value(t, before_n, 2)
	testing.expect(t, before, "at epoch 1 the asset had one owner and conformed — non-vacuously, per the count above")

	// Epoch 2: the moment the handover was half-done.
	during, during_n := verdict_at(t, &shapes, db, 2)
	testing.expect_value(t, during_n, 3)
	testing.expect(t, !during, "at epoch 2 the asset had two owners and must violate sh:maxCount")

	// Epoch 3 is HEAD, reached both ways: through the horizon and through an
	// ordinary autocommit session. They must agree, and they must disagree
	// with epoch 2 — a suite where every horizon gave the same verdict would
	// be exactly what an as-of transaction silently reading HEAD looks like.
	after, after_n := verdict_at(t, &shapes, db, 3)
	testing.expect_value(t, after_n, 2)
	testing.expect(t, after, "at epoch 3 the old owner is retracted and one remains")

	head: Session
	session_init(&head, db)
	head_bindings: shacl.Bindings
	bind(&head_bindings, &shapes, &head)
	defer shacl.bindings_destroy(&head_bindings)
	head_answer, head_failure := conforms(&shapes, &head_bindings, &head)
	testing.expectf(t, head_failure == .None, "HEAD: validation failed: %v", head_failure)
	testing.expectf(t, session_error(&head) == nil, "HEAD: store read failed: %v", session_error(&head))
	testing.expect(t, head_answer, "HEAD conforms")
	testing.expect(
		t,
		head_answer != during,
		"HEAD and epoch 2 must disagree, or this test is not reading the past at all",
	)
}

// sh:class over a hierarchy that lives in the validated graph, which is where
// SHACL-A-0001 decision 5 forces it to live: validation reads exactly one
// caller-named graph, so `ex:Report rdfs:subClassOf ex:Document` is only seen
// if it is in that graph.
@(private = "file")
CLASS_SHAPES :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix ex: <http://example.org/> .

ex:JobShape a sh:NodeShape ; sh:targetClass ex:Job ;
	sh:property [ sh:path ex:input ; sh:class ex:Document ] .
`

@(private = "file")
CLASS_EPOCH_1 :: `
@prefix ex: <http://example.org/> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

ex:job1 a ex:Job ; ex:input ex:report1 .
ex:report1 a ex:Report .
ex:Report rdfs:subClassOf ex:Document .
`

// HEAD violates; the earlier epoch conforms — the reverse of the test above,
// and the one that turns on decision 5.
//
// Nothing about the job or the report changes between the two epochs. The only
// thing retracted is the subclass edge, and retracting it out of the validated
// graph is retracting the shape's ability to see that a report is a document.
// This is the failure mode the README and the package doc warn about — a
// shapes graph silently under-reporting because the hierarchy is not in the
// graph being validated — arrived at through time rather than through a
// misplaced import, and it is worth having the two epochs prove that the
// validator's answer really does hang on that one triple.
@(test)
test_as_of_validation_sees_a_retracted_class_hierarchy :: proc(t: ^testing.T) {
	shapes: shacl.Shapes
	if !compile_as_of_shapes(t, &shapes, CLASS_SHAPES) {
		return
	}
	defer shacl.shapes_destroy(&shapes)

	db, open_err := kvstore.open_ephemeral()
	if !testing.expectf(t, open_err == nil, "data store: %v", open_err) {
		return
	}
	defer kvstore.close(db)

	// Epoch 1: the job, its input, and the hierarchy that makes the input a
	// document.
	if !load_epoch(t, db, CLASS_EPOCH_1, "epoch 1") {
		return
	}
	// Epoch 2: the subclass edge is retracted. The data is untouched.
	if !retract_epoch(
		t,
		db,
		rdf.IRI(EX + "Report"),
		rdf.IRI(RDFS_SUBCLASSOF),
		rdf.IRI(EX + "Document"),
	) {
		return
	}

	before, before_n := verdict_at(t, &shapes, db, 1)
	testing.expect_value(t, before_n, 4)
	testing.expect(t, before, "at epoch 1 ex:Report was a subclass of ex:Document, so the input conformed")

	now, now_n := verdict_at(t, &shapes, db, 2)
	testing.expect_value(t, now_n, 3)
	testing.expect(
		t,
		!now,
		"with the subclass edge retracted, sh:class ex:Document no longer reaches ex:report1 and must violate",
	)

	testing.expect(
		t,
		before != now,
		"the two epochs must disagree: one retracted triple is the only difference between them",
	)
}
