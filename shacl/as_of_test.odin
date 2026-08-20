package shacl

import "core:testing"

import "rdf:rdf"
import "record:record"
import "record:record/ingest"

// Validating a **past** dataset (SHACL-T-0035; SHACL-T-0030's capability on
// the old store, carried over).
//
// The record never erases: a retraction ends a fact's lifetime and leaves it
// readable at every earlier epoch. So validating the past needs no API of
// its own — `record.store_at(s, epoch)` returns a snapshot pinned at that
// epoch, `session_init` binds it like any other, and every read through the
// session answers about that moment. These tests are the proof that it does,
// not machinery: the only thing they call that head validation does not is
// `store_at`.
//
// **The as-of coordinate is the epoch, not a wall-clock time.** The record
// deliberately has no `epoch_at(wall)` — a wall clock is advisory evidence
// in this store, not an index (RECORD-I-0003's non-goals) — so a caller
// holding a time finds its epoch by its own bookkeeping, or by walking
// `snapshot_epoch_meta`, whose `wall` is there to be compared against.
//
// # Why validate the past at all
//
// The record is immutable, so remediation is never the purpose. Validating
// past data under the *current* shapes explains the present — bisect for the
// epoch that introduced a violation, and `snapshot_epoch_meta` names who and
// why — and reports exposure windows for newly adopted rules. Validating
// past data under the *then-current* shapes is the accountability question
// ("did it conform to the rules in force at the time"), and it is the
// recomputation RECORD-A-0006 decision 5 relies on: the log does not record
// that a judge objected, so a verdict about the past is recoverable only by
// recomputing it over the epoch-pinned dataset. That is what keeps a
// conformance claim about the past independently checkable.
//
// # This is not validate-before-commit
//
// `validator_test.odin` is about a candidate and the future; nothing here is
// a candidate and nothing here commits or could — `store_at` is a read. Each
// test differs between head and the pinned epoch, in opposite directions, so
// a pinned read that quietly answered about head would fail here.
//
// # How the epochs are built
//
// Every `apply` is one epoch, so the fixtures hold epochs 1, 2, 3 by
// construction; epoch 0 is the empty world before the first commit.
// `visible` accompanies every verdict, because "conforms" over an empty
// graph and "conforms" over a populated one are the same boolean and
// different facts.
//
// **Terms are not epoch-scoped; facts are.** A pinned snapshot bounds which
// facts are visible, not which terms resolve: a term stays resolvable at
// every epoch, including epochs before it was first written (as the old
// store's dictionary was, STORE-A-0008 par. 7). So `session_init` finds a
// graph label at epoch 0 and reads an empty graph through it, and
// `bindings_init` resolves a model's terms at any epoch — which is what lets
// one model be validated at every epoch below without re-binding by hand.

@(private = "file")
EX :: "http://example.org/"

@(private = "file")
RDFS_SUBCLASSOF :: "http://www.w3.org/2000/01/rdf-schema#subClassOf"

// History is a record store whose epochs the tests build one apply at a
// time. Never copied after open: the writer points at the Mem_FS inside.
@(private = "file")
History :: struct {
	fs: record.Mem_FS,
	st: record.Store,
	ok: bool,
}

@(private = "file")
history_open :: proc(t: ^testing.T, h: ^History) -> bool {
	_, err, _, _ := record.store_open(&h.st, "history", record.mem_file_ops(&h.fs))
	h.ok = testing.expectf(t, err == .None, "store_open: %v", err)
	return h.ok
}

@(private = "file")
history_close :: proc(h: ^History) {
	if h.ok {
		record.store_close(&h.st)
		h.ok = false
	}
	record.mem_fs_destroy(&h.fs)
}

// epoch applies one Turtle document as one epoch — asserting or retracting
// its statements into `graph` — attributed to `actor` for `reason` (IRIs:
// the log cannot carry an inlined term, and a short literal would be one).
// Returns the epoch number, 0 on refusal.
@(private = "file")
epoch :: proc(
	t: ^testing.T,
	h: ^History,
	source: string,
	kind := record.Op_Kind.Assert,
	graph: rdf.Graph_Label = nil,
	actor: rdf.Term = nil,
	reason: rdf.Term = nil,
	loc := #caller_location,
) -> record.Epoch {
	ops, ierr := ingest.turtle(transmute([]byte)source, graph, context.allocator, kind = kind, blank_prefix = "h_")
	if !testing.expectf(t, ierr.kind == .None, "ingest: %v", ierr, loc = loc) {
		return 0
	}
	defer ingest.ops_destroy(ops, context.allocator)
	e, _, aerr := record.apply(&h.st, {ops = ops, actor = actor, reason = reason})
	testing.expectf(t, aerr == record.Apply_Error{}, "apply: %v", aerr, loc = loc)
	return e
}

// visible counts the quads of a session's graph — the size of the dataset a
// verdict is about.
@(private = "file")
visible :: proc(se: Session) -> (n: int) {
	sc := record.range_iter(record.snapshot_match(se.snap, record.Pattern{g = se.graph}), {origin = .Any})
	for _ in record.scan_next(&sc) {
		n += 1
	}
	return
}

// verdict_at validates the whole graph at a pinned epoch, through the
// conformance consumer, and reports the verdict with the size of the dataset
// it is about. `store_at` is the only as-of call in it; the rest is what head
// validation does over `store_latest`.
@(private = "file")
verdict_at :: proc(
	t: ^testing.T,
	shapes: ^Shapes,
	h: ^History,
	at: record.Epoch,
	graph: rdf.Graph_Label = nil,
	loc := #caller_location,
) -> (
	conforming: bool,
	n: int,
) {
	snap, serr := record.store_at(&h.st, at)
	if !testing.expectf(t, serr == .None, "store_at(%d): %v", at, serr, loc = loc) {
		return false, -1
	}
	defer record.snapshot_release(&snap)

	se: Session
	session_init(&se, snap, graph)
	b: Bindings
	bindings_init(&b, shapes, se)
	defer bindings_destroy(&b)

	ok, failure := conforms(shapes, &b, se)
	testing.expectf(t, failure == .None, "epoch %d: validation failed: %v", at, failure, loc = loc)
	return ok, visible(se)
}

// result_count_at is the report path at a pinned epoch: how many results the
// `sh:ValidationReport` over that moment holds.
@(private = "file")
result_count_at :: proc(t: ^testing.T, shapes: ^Shapes, h: ^History, at: record.Epoch, loc := #caller_location) -> int {
	snap, serr := record.store_at(&h.st, at)
	if !testing.expectf(t, serr == .None, "store_at(%d): %v", at, serr, loc = loc) {
		return -1
	}
	defer record.snapshot_release(&snap)

	se: Session
	session_init(&se, snap)
	b: Bindings
	bindings_init(&b, shapes, se)
	defer bindings_destroy(&b)

	r: Report
	report_init(&r)
	defer report_destroy(&r)
	failure := validate_report(&r, shapes, &b, se)
	testing.expectf(t, failure == .None, "epoch %d: validation failed: %v", at, failure, loc = loc)
	n := 0
	for tr in report_triples(&r) {
		if pred, is_iri := tr.predicate.(rdf.IRI); is_iri && string(pred) == RESULT {
			n += 1
		}
	}
	return n
}

// One owner is allowed. A handover that recorded the new owner before
// retracting the old one spends an epoch with two.
@(private = "file")
OWNER_SHAPES :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix ex: <http://example.org/> .
ex:AssetShape a sh:NodeShape ; sh:targetClass ex:Asset ;
	sh:property [ sh:path ex:owner ; sh:maxCount 1 ] .
`

@(private = "file")
OWNER_EPOCH_1 :: `@prefix ex: <http://example.org/> . ex:disk a ex:Asset ; ex:owner ex:alice .`

@(private = "file")
OWNER_EPOCH_2 :: `@prefix ex: <http://example.org/> . ex:disk ex:owner ex:bob .`

@(private = "file")
OWNER_RETRACT_3 :: `@prefix ex: <http://example.org/> . ex:disk ex:owner ex:alice .`

// Head conforms; the epoch in the middle does not.
//
// The interesting direction: a violation that no longer exists is still
// reachable, because retraction is logical. An auditor asking "was this ever
// in a state our shapes reject?" gets a different answer from the past than
// from the present — the whole point of the time dimension, and invisible to
// a validator that can only read head.
@(test)
test_as_of_validation_sees_the_dataset_as_it_was :: proc(t: ^testing.T) {
	shapes: Shapes
	defer shapes_destroy(&shapes)
	if !tdb_compile(t, &shapes, OWNER_SHAPES) {
		return
	}
	h: History
	defer history_close(&h)
	if !history_open(t, &h) {
		return
	}

	testing.expect_value(t, epoch(t, &h, OWNER_EPOCH_1), 1)
	testing.expect_value(t, epoch(t, &h, OWNER_EPOCH_2), 2)
	testing.expect_value(t, epoch(t, &h, OWNER_RETRACT_3, kind = .Retract), 3)

	// Epoch 0 is the empty world: it conforms for the vacuous reason and not
	// a good one, and the count is what says which of the two this is.
	vacuous, empty := verdict_at(t, &shapes, &h, 0)
	testing.expect_value(t, empty, 0)
	testing.expect(t, vacuous, "an empty dataset has no focus nodes, so it conforms vacuously")

	before, before_n := verdict_at(t, &shapes, &h, 1)
	testing.expect_value(t, before_n, 2)
	testing.expect(t, before, "at epoch 1 the asset had one owner and conformed — non-vacuously, per the count")

	during, during_n := verdict_at(t, &shapes, &h, 2)
	testing.expect_value(t, during_n, 3)
	testing.expect(t, !during, "at epoch 2 the asset had two owners and must violate sh:maxCount")
	testing.expect_value(t, result_count_at(t, &shapes, &h, 2), 1)

	// Epoch 3 is head, reached both ways; they must agree with each other and
	// disagree with epoch 2 — a suite where every epoch gave the same verdict
	// is what a pinned read silently answering about head looks like.
	after, after_n := verdict_at(t, &shapes, &h, 3)
	testing.expect_value(t, after_n, 2)
	testing.expect(t, after, "at epoch 3 the old owner is retracted and one remains")

	head, herr := record.store_latest(&h.st)
	testing.expect_value(t, herr, record.Snapshot_Error.None)
	defer record.snapshot_release(&head)
	testing.expect_value(t, head.epoch, 3)
	se: Session
	session_init(&se, head)
	b: Bindings
	bindings_init(&b, &shapes, se)
	defer bindings_destroy(&b)
	head_answer, head_failure := conforms(&shapes, &b, se)
	testing.expect_value(t, head_failure, Failure.None)
	testing.expect(t, head_answer, "head conforms")
	testing.expect(t, head_answer != during, "head and epoch 2 must disagree, or this test is not reading the past at all")

	// The future is not readable: store_at refuses rather than clamps.
	_, future := record.store_at(&h.st, 4)
	testing.expect_value(t, future, record.Snapshot_Error.Future_Epoch)
}

// sh:class over a hierarchy that lives in the validated graph, which is where
// SHACL-A-0001 decision 5 forces it to live.
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

@(private = "file")
CLASS_RETRACT_2 :: `
@prefix ex: <http://example.org/> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
ex:Report rdfs:subClassOf ex:Document .
`

// Head violates; the earlier epoch conforms — the reverse direction. Nothing
// about the job or the report changes between the two epochs; the one
// retracted triple is the subclass edge, and retracting it out of the
// validated graph retracts the shape's ability to see that a report is a
// document. The report path at both epochs, so the results themselves differ.
@(test)
test_as_of_validation_sees_a_retracted_class_hierarchy :: proc(t: ^testing.T) {
	shapes: Shapes
	defer shapes_destroy(&shapes)
	if !tdb_compile(t, &shapes, CLASS_SHAPES) {
		return
	}
	h: History
	defer history_close(&h)
	if !history_open(t, &h) {
		return
	}
	testing.expect_value(t, epoch(t, &h, CLASS_EPOCH_1), 1)
	testing.expect_value(t, epoch(t, &h, CLASS_RETRACT_2, kind = .Retract), 2)

	before, before_n := verdict_at(t, &shapes, &h, 1)
	testing.expect_value(t, before_n, 4)
	testing.expect(t, before, "at epoch 1 ex:Report was a subclass of ex:Document, so the input conformed")
	testing.expect_value(t, result_count_at(t, &shapes, &h, 1), 0)

	now, now_n := verdict_at(t, &shapes, &h, 2)
	testing.expect_value(t, now_n, 3)
	testing.expect(t, !now, "with the subclass edge retracted, sh:class ex:Document no longer reaches ex:report1")
	testing.expect_value(t, result_count_at(t, &shapes, &h, 2), 1)
	testing.expect(t, before != now, "the two epochs must disagree: one retracted triple is the only difference")
}

// A graph whose quads were all retracted is empty at head and populated at
// the epoch before: the graph's label is still a term, so a session binds to
// it and reads nothing — conformance for the vacuous reason, which the count
// exposes — while the pinned read sees the graph as it was.
@(test)
test_as_of_validation_of_a_retracted_graph :: proc(t: ^testing.T) {
	G :: rdf.IRI(EX + "assets")
	shapes: Shapes
	defer shapes_destroy(&shapes)
	if !tdb_compile(t, &shapes, OWNER_SHAPES) {
		return
	}
	h: History
	defer history_close(&h)
	if !history_open(t, &h) {
		return
	}
	TWO_OWNERS :: `@prefix ex: <http://example.org/> . ex:disk a ex:Asset ; ex:owner ex:alice, ex:bob .`
	testing.expect_value(t, epoch(t, &h, TWO_OWNERS, graph = G), 1)
	testing.expect_value(t, epoch(t, &h, TWO_OWNERS, kind = .Retract, graph = G), 2)

	then, then_n := verdict_at(t, &shapes, &h, 1, graph = G)
	testing.expect_value(t, then_n, 3)
	testing.expect(t, !then, "at epoch 1 the graph held an asset with two owners")

	now, now_n := verdict_at(t, &shapes, &h, 2, graph = G)
	testing.expect_value(t, now_n, 0)
	testing.expect(t, now, "at head the graph is empty and conforms vacuously — the count is what says so")

	// The label resolves at head — a retracted graph is still a named term —
	// so this is an empty graph, not an absent one.
	head, _ := record.store_latest(&h.st)
	defer record.snapshot_release(&head)
	se: Session
	testing.expect(t, session_init(&se, head, G), "the graph label is still a term after its quads are retracted")
}

// Epoch metadata is the audit trail beside the verdict: who committed the
// epoch that introduced the violation, why, and when.
@(test)
test_as_of_verdict_with_epoch_metadata :: proc(t: ^testing.T) {
	shapes: Shapes
	defer shapes_destroy(&shapes)
	if !tdb_compile(t, &shapes, OWNER_SHAPES) {
		return
	}
	h: History
	defer history_close(&h)
	if !history_open(t, &h) {
		return
	}
	alice := rdf.IRI(EX + "alice")
	ops_team := rdf.IRI(EX + "ops")
	handover := rdf.IRI(EX + "handover-2026-08")
	testing.expect_value(t, epoch(t, &h, OWNER_EPOCH_1, actor = alice), 1)
	testing.expect_value(t, epoch(t, &h, OWNER_EPOCH_2, actor = ops_team, reason = handover), 2)
	testing.expect_value(t, epoch(t, &h, OWNER_RETRACT_3, kind = .Retract, actor = ops_team, reason = handover), 3)

	// Bisect by hand: the first epoch that violates is 2.
	first_bad: record.Epoch
	for e in record.Epoch(1) ..= 3 {
		ok, _ := verdict_at(t, &shapes, &h, e)
		if !ok {
			first_bad = e
			break
		}
	}
	testing.expect_value(t, first_bad, 2)

	// Who, why, when — read from the pinned snapshot, decoded through the
	// session like any other term.
	snap, serr := record.store_at(&h.st, first_bad)
	testing.expect_value(t, serr, record.Snapshot_Error.None)
	defer record.snapshot_release(&snap)
	se: Session
	session_init(&se, snap)
	meta := record.snapshot_epoch_meta(snap, first_bad)
	testing.expect(t, meta.wall > 0, "an epoch carries its wall time")
	testing.expect_value(t, test_term(se, meta.actor), rdf.Term(ops_team))
	testing.expect_value(t, test_term(se, meta.reason), rdf.Term(handover))

	// Epoch 1 named an actor and no reason — 0, "none", as the log records it.
	first := record.snapshot_epoch_meta(snap, 1)
	testing.expect_value(t, test_term(se, first.actor), rdf.Term(alice))
	testing.expect_value(t, first.reason, 0)
}

// Shapes-as-of-then. The shapes live in the same store as the data, in a
// graph of their own, and they tighten across epochs; one pinned snapshot
// feeds both the shapes session and the data session, so the question "did
// it conform to the rules in force at the time" is answered over a single
// moment — and it differs from the same pinned data under head's shapes,
// which is the decision-5 recomputation. The suppressed path (`conforms_node`)
// carries this one.
@(test)
test_as_of_validation_under_the_shapes_of_the_time :: proc(t: ^testing.T) {
	SHAPES_G :: rdf.IRI(EX + "shapes")
	// Property shapes named by IRI rather than blank, so a later epoch can
	// retract one parameter and assert another.
	SHAPES_V1 :: `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:AssetShape a sh:NodeShape ; sh:targetClass ex:Asset ; sh:property ex:OwnerProp .
	ex:OwnerProp sh:path ex:owner ; sh:maxCount 2 .
	`
	LOOSEN_OUT :: `@prefix sh: <http://www.w3.org/ns/shacl#> . @prefix ex: <http://example.org/> . ex:OwnerProp sh:maxCount 2 .`
	TIGHTEN_IN :: `@prefix sh: <http://www.w3.org/ns/shacl#> . @prefix ex: <http://example.org/> . ex:OwnerProp sh:maxCount 1 .`
	DATA :: `@prefix ex: <http://example.org/> . ex:disk a ex:Asset ; ex:owner ex:alice, ex:bob .`

	h: History
	defer history_close(&h)
	if !history_open(t, &h) {
		return
	}
	testing.expect_value(t, epoch(t, &h, SHAPES_V1, graph = SHAPES_G), 1)
	testing.expect_value(t, epoch(t, &h, DATA), 2)
	// Epoch 3 tightens the rule: two owners were allowed, now one is.
	testing.expect_value(t, epoch(t, &h, LOOSEN_OUT, kind = .Retract, graph = SHAPES_G), 3)
	testing.expect_value(t, epoch(t, &h, TIGHTEN_IN, graph = SHAPES_G), 4)

	// node_conforms_at compiles the shapes graph of `shapes_at` and asks whether
	// ex:disk conforms to ex:AssetShape in the data graph of `data_at`. The
	// model owns its terms, so the shapes snapshot is released the moment
	// compile returns, whichever epoch it was.
	node_conforms_at :: proc(t: ^testing.T, h: ^History, shapes_at, data_at: record.Epoch) -> bool {
		shapes: Shapes
		defer shapes_destroy(&shapes)
		{
			ssnap, serr := record.store_at(&h.st, shapes_at)
			testing.expect_value(t, serr, record.Snapshot_Error.None)
			defer record.snapshot_release(&ssnap)
			sse: Session
			session_init(&sse, ssnap, rdf.IRI(EX + "shapes"))
			err := compile(&shapes, sse)
			testing.expectf(t, err.kind == .None, "compile at %d: %s", shapes_at, error_message(err.kind))
		}
		dsnap, derr := record.store_at(&h.st, data_at)
		testing.expect_value(t, derr, record.Snapshot_Error.None)
		defer record.snapshot_release(&dsnap)
		dse: Session
		session_init(&dse, dsnap)
		b: Bindings
		bindings_init(&b, &shapes, dse)
		defer bindings_destroy(&b)
		shape, found := shape_index_of(&shapes, rdf.IRI(EX + "AssetShape"))
		testing.expect(t, found, "ex:AssetShape compiled")
		ok, failure := conforms_node(&shapes, &b, dse, shape, node_focus(dse, rdf.IRI(EX + "disk")))
		testing.expect_value(t, failure, Failure.None)
		return ok
	}

	// The data at epoch 2, under the shapes of epoch 2: conformed to the rules
	// in force at the time.
	testing.expect(t, node_conforms_at(t, &h, 2, 2), "two owners conformed to the maxCount 2 in force at epoch 2")
	// The same pinned data under head's shapes: violates — the present rule
	// applied to the past, the exposure-window question.
	testing.expect(t, !node_conforms_at(t, &h, 4, 2), "two owners violate the maxCount 1 in force now")
	// And head under head: the data never changed, so it violates today.
	testing.expect(t, !node_conforms_at(t, &h, 4, 4), "head violates under head's shapes")
	// Before the shapes existed there was no shape to violate — nothing
	// compiled targets ex:disk, and the question is vacuous; the count of
	// shapes says so rather than the boolean. (The graph label resolves at
	// epoch 0 — terms are not epoch-scoped, see the header — and the graph
	// it names is empty there.)
	{
		snap, _ := record.store_at(&h.st, 0)
		defer record.snapshot_release(&snap)
		sse: Session
		testing.expect(t, session_init(&sse, snap, SHAPES_G), "the label is a term at every epoch; the graph is empty at this one")
		testing.expect_value(t, visible(sse), 0)
		empty: Shapes
		defer shapes_destroy(&empty)
		testing.expect_value(t, compile(&empty, sse).kind, Error_Kind.None)
		testing.expect_value(t, len(empty.shapes), 0)
	}
}
