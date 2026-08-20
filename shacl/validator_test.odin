package shacl

import "core:testing"

import "rdf:rdf"
import "record:record"
import "record:record/ingest"

// Validate-before-commit through the record's Validator hook (SHACL-T-0034).
//
// What these assert is the thing `session_init_txn` asserted on the old store
// (SHACL-T-0029), on the mechanism built for it: **a validator that reads the
// dataset a write would produce.** The central test is again the vacuity
// case rather than the happy path — a candidate that violates only because
// the committed data is visible, and conforms on its own — because the happy
// path passes without any of this code. Around it: Enforce writes nothing
// and leaves the store exactly as it was; Record commits and reports; a term
// the changeset introduces resolves in the candidate; a retraction is validated
// on the post-state; the report is the last apply's and no other's; and a
// validator that cannot answer refuses.

// One email is allowed, and the committed graph already spends it.
VALIDATOR_SHAPES :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix ex: <http://example.org/> .
ex:PersonShape a sh:NodeShape ; sh:targetClass ex:Person ;
	sh:property [ sh:path ex:email ; sh:maxCount 1 ] .
`

VALIDATOR_COMMITTED :: `
@prefix ex: <http://example.org/> .
ex:alice a ex:Person ; ex:email "alice@example.org" .
`

// The candidate is the *delta*: what the write adds to the committed
// dataset. It cannot repeat the type triple — apply refuses an assert of a
// live quad (`.Already_Live`) before any validator is consulted, where the old
// store's insert was idempotent — so on its own it targets nothing.
VALIDATOR_CANDIDATE :: `
@prefix ex: <http://example.org/> .
ex:alice ex:email "alice@work.example.org" .
`

// The same world built from nothing, for the isolation half: it carries its
// own type triple, so the shape's target resolves without the committed
// graph. Without that, the isolated validation would conform for the
// *uninteresting* reason — no focus node at all — and would prove nothing
// about seeing the write.
VALIDATOR_CANDIDATE_ALONE :: `
@prefix ex: <http://example.org/> .
ex:alice a ex:Person ; ex:email "alice@work.example.org" .
`

// Wired_Store is a record store opened with a validator wired in. Never copied after
// open: the writer points at the Mem_FS inside.
@(private = "file")
Wired_Store :: struct {
	fs: record.Mem_FS,
	st: record.Store,
	ok: bool,
}

@(private = "file")
wired_open :: proc(t: ^testing.T, ws: ^Wired_Store, v: ^Validator) -> bool {
	_, err, _, _ := record.store_open(&ws.st, "wired", record.mem_file_ops(&ws.fs), validator = validator_hook(v))
	ws.ok = testing.expectf(t, err == .None, "store_open: %v", err)
	return ws.ok
}

@(private = "file")
wired_close :: proc(ws: ^Wired_Store) {
	if ws.ok {
		record.store_close(&ws.st)
		ws.ok = false
	}
	record.mem_fs_destroy(&ws.fs)
}

// wired_apply ingests a document and applies it under `mode`, returning what
// apply returned. `graph` is the graph the document's statements go to.
@(private = "file")
wired_apply :: proc(
	t: ^testing.T,
	ws: ^Wired_Store,
	source: string,
	mode: record.Mode,
	graph: rdf.Graph_Label = nil,
	kind := record.Op_Kind.Assert,
	blank_prefix := "j_",
) -> (
	epoch: record.Epoch,
	conforms: bool,
	err: record.Apply_Error,
) {
	ops, ierr := ingest.turtle(transmute([]byte)source, graph, context.allocator, kind = kind, blank_prefix = blank_prefix)
	if !testing.expectf(t, ierr.kind == .None, "ingest: %v", ierr) {
		return 0, false, {.Empty, -1}
	}
	defer ingest.ops_destroy(ops, context.allocator)
	return record.apply(&ws.st, {ops = ops, mode = mode})
}

@(private = "file")
head_epoch :: proc(ws: ^Wired_Store) -> record.Epoch {
	snap, err := record.store_latest(&ws.st)
	if err != .None {
		return max(record.Epoch)
	}
	defer record.snapshot_release(&snap)
	return snap.epoch
}

// head_has reports whether the head holds a triple in `graph`.
@(private = "file")
head_has :: proc(ws: ^Wired_Store, s, p, o: rdf.Term, graph: rdf.Graph_Label = nil) -> bool {
	snap, err := record.store_latest(&ws.st)
	if err != .None {
		return false
	}
	defer record.snapshot_release(&snap)
	se: Session
	session_init(&se, snap, graph)
	pat: record.Pattern
	ok: bool
	if pat.s, ok = session_resolve(se, s); !ok {
		return false
	}
	if pat.p, ok = session_resolve(se, p); !ok {
		return false
	}
	if pat.o, ok = session_resolve(se, o); !ok {
		return false
	}
	pat.g = se.graph
	return record.snapshot_exists(snap, pat, {origin = .Any})
}

@(private = "file")
result_count :: proc(r: ^Report) -> int {
	if r == nil {
		return -1
	}
	n := 0
	for tr in report_triples(r) {
		if pred, is_iri := tr.predicate.(rdf.IRI); is_iri && string(pred) == RESULT {
			n += 1
		}
	}
	return n
}

EX_ALICE :: rdf.IRI("http://example.org/alice")
EX_EMAIL :: rdf.IRI("http://example.org/email")

// The item's own acceptance criterion, as one test: the candidate is refused
// only because the committed data is visible, and the same candidate into
// an empty store under the same validator is accepted.
@(test)
test_validator_sees_head_and_candidate_together :: proc(t: ^testing.T) {
	shapes: Shapes
	defer shapes_destroy(&shapes)
	if !tdb_compile(t, &shapes, VALIDATOR_SHAPES) {
		return
	}
	v: Validator
	validator_init(&v, &shapes)
	defer validator_destroy(&v)

	{
		ws: Wired_Store
		defer wired_close(&ws)
		if !wired_open(t, &ws, &v) {
			return
		}
		// The committed graph on its own conforms, so what follows is the
		// candidate's doing rather than the fixture's.
		_, ok, err := wired_apply(t, &ws, VALIDATOR_COMMITTED, .Enforce)
		testing.expect_value(t, err, record.Apply_Error{})
		testing.expect(t, ok, "the committed graph should conform")

		_, ok, err = wired_apply(t, &ws, VALIDATOR_CANDIDATE, .Enforce)
		testing.expect_value(t, err, record.Apply_Error{.Rejected, -1})
		testing.expect(
			t,
			!ok,
			"the candidate must violate sh:maxCount: it adds a second ex:email to a node the committed graph already gave one",
		)
		testing.expect_value(t, v.failure, Failure.None)
	}

	// The half that makes this a test of the feature: the same candidate, the
	// same validator, no committed data — accepted, which is the answer an
	// isolated-candidate validation would have given for the real dataset.
	{
		ws: Wired_Store
		defer wired_close(&ws)
		if !wired_open(t, &ws, &v) {
			return
		}
		_, ok, err := wired_apply(t, &ws, VALIDATOR_CANDIDATE_ALONE, .Enforce)
		testing.expect_value(t, err, record.Apply_Error{})
		testing.expect(t, ok, "the candidate alone must conform — otherwise this test no longer distinguishes the two worlds")
	}
	testing.expect_value(t, v.checks, 3)
}

// Enforce: a refusal writes nothing. The epoch is not issued, the quad is
// not there, and the store is not poisoned — the next conforming write goes
// through.
@(test)
test_enforce_refuses_and_the_store_is_as_it_was :: proc(t: ^testing.T) {
	shapes: Shapes
	defer shapes_destroy(&shapes)
	if !tdb_compile(t, &shapes, VALIDATOR_SHAPES) {
		return
	}
	v: Validator
	validator_init(&v, &shapes)
	defer validator_destroy(&v)
	ws: Wired_Store
	defer wired_close(&ws)
	if !wired_open(t, &ws, &v) {
		return
	}

	e1, _, _ := wired_apply(t, &ws, VALIDATOR_COMMITTED, .Enforce)
	before := head_epoch(&ws)
	testing.expect_value(t, before, e1)

	epoch, ok, err := wired_apply(t, &ws, VALIDATOR_CANDIDATE, .Enforce)
	testing.expect_value(t, err, record.Apply_Error{.Rejected, -1})
	testing.expect_value(t, epoch, 0)
	testing.expect(t, !ok)
	testing.expect_value(t, head_epoch(&ws), before)
	testing.expect(t, !head_has(&ws, EX_ALICE, EX_EMAIL, rdf.Literal{lexical = "alice@work.example.org"}), "the refused quad must not be at head")
	testing.expect(t, head_has(&ws, EX_ALICE, EX_EMAIL, rdf.Literal{lexical = "alice@example.org"}), "the committed quad must still be at head")

	// The validator reports the refusal for the caller to read after apply.
	r := validator_report(&v)
	testing.expect(t, r != nil, "a reporting validator holds the last check's report")
	testing.expect(t, !report_conforms(r))
	testing.expect_value(t, result_count(r), 1)

	// And the store goes on: a conforming write commits as the next epoch.
	e3, ok3, err3 := wired_apply(t, &ws, `@prefix ex: <http://example.org/> . ex:bob a ex:Person .`, .Enforce)
	testing.expect_value(t, err3, record.Apply_Error{})
	testing.expect(t, ok3)
	testing.expect_value(t, e3, before + 1)
}

// Record: the same violation commits, and apply says so.
@(test)
test_record_commits_and_reports :: proc(t: ^testing.T) {
	shapes: Shapes
	defer shapes_destroy(&shapes)
	if !tdb_compile(t, &shapes, VALIDATOR_SHAPES) {
		return
	}
	v: Validator
	validator_init(&v, &shapes)
	defer validator_destroy(&v)
	ws: Wired_Store
	defer wired_close(&ws)
	if !wired_open(t, &ws, &v) {
		return
	}

	e1, _, _ := wired_apply(t, &ws, VALIDATOR_COMMITTED, .Record)
	epoch, ok, err := wired_apply(t, &ws, VALIDATOR_CANDIDATE, .Record)
	testing.expect_value(t, err, record.Apply_Error{})
	testing.expect(t, !ok, "Record commits but reports the verdict")
	testing.expect_value(t, epoch, e1 + 1)
	testing.expect_value(t, head_epoch(&ws), epoch)
	testing.expect(t, head_has(&ws, EX_ALICE, EX_EMAIL, rdf.Literal{lexical = "alice@work.example.org"}), "under Record the quad is at head")

	r := validator_report(&v)
	testing.expect(t, r != nil)
	testing.expect(t, !report_conforms(r))
	testing.expect_value(t, result_count(r), 1)
	testing.expect_value(t, v.failure, Failure.None)
}

// Conforming changesets commit under both modes, with conforms = true.
@(test)
test_conforming_commits_under_both_modes :: proc(t: ^testing.T) {
	shapes: Shapes
	defer shapes_destroy(&shapes)
	if !tdb_compile(t, &shapes, VALIDATOR_SHAPES) {
		return
	}
	v: Validator
	validator_init(&v, &shapes)
	defer validator_destroy(&v)
	ws: Wired_Store
	defer wired_close(&ws)
	if !wired_open(t, &ws, &v) {
		return
	}
	modes := [2]record.Mode{.Enforce, .Record}
	docs := [2]string {
		`@prefix ex: <http://example.org/> . ex:a a ex:Person ; ex:email "a@example.org" .`,
		`@prefix ex: <http://example.org/> . ex:b a ex:Person ; ex:email "b@example.org" .`,
	}
	for mode, i in modes {
		epoch, ok, err := wired_apply(t, &ws, docs[i], mode)
		testing.expect_value(t, err, record.Apply_Error{})
		testing.expect(t, ok)
		testing.expect_value(t, epoch, record.Epoch(i + 1))
		testing.expect(t, report_conforms(validator_report(&v)))
	}
	testing.expect_value(t, v.checks, 2)
}

// sh:class walks the hierarchy in the *data* graph, and here the hierarchy
// is committed while the instance arrives in the changeset — the validator sees
// both together, so the candidate conforms; in isolation it would violate.
@(test)
test_validator_sees_the_class_hierarchy_in_head :: proc(t: ^testing.T) {
	SHAPES :: `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:KnowsShape a sh:NodeShape ; sh:targetSubjectsOf ex:knows ;
		sh:property [ sh:path ex:knows ; sh:class ex:Person ] .
	`
	HIERARCHY :: `
	@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
	@prefix ex: <http://example.org/> .
	ex:Employee rdfs:subClassOf ex:Person . ex:carol a ex:Employee .
	`
	KNOWS :: `@prefix ex: <http://example.org/> . ex:dan ex:knows ex:carol .`

	shapes: Shapes
	defer shapes_destroy(&shapes)
	if !tdb_compile(t, &shapes, SHAPES) {
		return
	}
	v: Validator
	validator_init(&v, &shapes)
	defer validator_destroy(&v)

	{
		ws: Wired_Store
		defer wired_close(&ws)
		if !wired_open(t, &ws, &v) {
			return
		}
		_, _, err := wired_apply(t, &ws, HIERARCHY, .Enforce)
		testing.expect_value(t, err, record.Apply_Error{})
		_, ok, err2 := wired_apply(t, &ws, KNOWS, .Enforce)
		testing.expect_value(t, err2, record.Apply_Error{})
		testing.expect(t, ok, "ex:carol is a Person through the committed hierarchy")
	}
	{
		// The vacuity check in the other direction: without the hierarchy the
		// same changeset violates, so the pass above was the head's doing.
		ws: Wired_Store
		defer wired_close(&ws)
		if !wired_open(t, &ws, &v) {
			return
		}
		_, ok, err := wired_apply(t, &ws, KNOWS, .Enforce)
		testing.expect_value(t, err, record.Apply_Error{.Rejected, -1})
		testing.expect(t, !ok, "without the hierarchy ex:carol is not a Person")
	}
}

// A term the changeset is the first to mention resolves in the candidate: a
// `sh:targetNode` the store has never seen is an unbound focus node until
// the changeset names it, and then it is a bound one with values.
@(test)
test_changeset_introduced_term_resolves_in_candidate :: proc(t: ^testing.T) {
	SHAPES :: `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:FreshShape a sh:NodeShape ; sh:targetNode ex:fresh ;
		sh:property [ sh:path ex:name ; sh:minCount 1 ] .
	`
	shapes: Shapes
	defer shapes_destroy(&shapes)
	if !tdb_compile(t, &shapes, SHAPES) {
		return
	}
	v: Validator
	validator_init(&v, &shapes)
	defer validator_destroy(&v)
	ws: Wired_Store
	defer wired_close(&ws)
	if !wired_open(t, &ws, &v) {
		return
	}

	// An unrelated write is refused: ex:fresh is a focus node whether or not
	// the data mentions it, and it has no name.
	_, ok, err := wired_apply(t, &ws, `@prefix ex: <http://example.org/> . ex:other ex:p ex:q .`, .Enforce)
	testing.expect_value(t, err, record.Apply_Error{.Rejected, -1})
	testing.expect(t, !ok)
	r := validator_report(&v)
	testing.expect_value(t, result_count(r), 1)

	// The write that names it, with a name, is accepted — the new term was
	// resolved in the candidate, its value found there.
	_, ok, err = wired_apply(t, &ws, `@prefix ex: <http://example.org/> . ex:fresh ex:name "fresh" .`, .Enforce)
	testing.expect_value(t, err, record.Apply_Error{})
	testing.expect(t, ok)
	testing.expect_value(t, result_count(validator_report(&v)), 0)
}

// A retraction is validated on the post-state: the candidate snapshot hides the
// retracted quad, so taking away a required value is refused.
@(test)
test_retraction_is_validated_on_the_post_state :: proc(t: ^testing.T) {
	SHAPES :: `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:PersonShape a sh:NodeShape ; sh:targetClass ex:Person ;
		sh:property [ sh:path ex:name ; sh:minCount 1 ] .
	`
	NAMED :: `@prefix ex: <http://example.org/> . ex:alice a ex:Person ; ex:name "Alice" .`
	NAME_ONLY :: `@prefix ex: <http://example.org/> . ex:alice ex:name "Alice" .`

	shapes: Shapes
	defer shapes_destroy(&shapes)
	if !tdb_compile(t, &shapes, SHAPES) {
		return
	}
	v: Validator
	validator_init(&v, &shapes)
	defer validator_destroy(&v)
	ws: Wired_Store
	defer wired_close(&ws)
	if !wired_open(t, &ws, &v) {
		return
	}

	_, ok, err := wired_apply(t, &ws, NAMED, .Enforce)
	testing.expect_value(t, err, record.Apply_Error{})
	testing.expect(t, ok)

	_, ok, err = wired_apply(t, &ws, NAME_ONLY, .Enforce, kind = .Retract)
	testing.expect_value(t, err, record.Apply_Error{.Rejected, -1})
	testing.expect(t, !ok, "retracting the only ex:name violates sh:minCount 1 on the post-state")
	testing.expect(t, head_has(&ws, EX_ALICE, rdf.IRI("http://example.org/name"), rdf.Literal{lexical = "Alice"}), "the refused retraction left the name in place")

	// Under Record the retraction goes through, and the verdict says what it cost.
	_, ok, err = wired_apply(t, &ws, NAME_ONLY, .Record, kind = .Retract)
	testing.expect_value(t, err, record.Apply_Error{})
	testing.expect(t, !ok)
	testing.expect(t, !head_has(&ws, EX_ALICE, rdf.IRI("http://example.org/name"), rdf.Literal{lexical = "Alice"}))
}

// A validator is bound to one graph. Writes to other graphs are not its
// business; a write to its graph is validated even when the changeset is the
// first to name the graph at all.
@(test)
test_validator_on_a_named_graph_ignores_the_others :: proc(t: ^testing.T) {
	SHAPES :: `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:PersonShape a sh:NodeShape ; sh:targetClass ex:Person ;
		sh:property [ sh:path ex:name ; sh:minCount 1 ] .
	`
	NAMELESS :: `@prefix ex: <http://example.org/> . ex:bob a ex:Person .`
	G :: rdf.IRI("http://example.org/g")

	shapes: Shapes
	defer shapes_destroy(&shapes)
	if !tdb_compile(t, &shapes, SHAPES) {
		return
	}
	v: Validator
	validator_init(&v, &shapes, G)
	defer validator_destroy(&v)
	ws: Wired_Store
	defer wired_close(&ws)
	if !wired_open(t, &ws, &v) {
		return
	}

	// Into the default graph: not validated, accepted.
	_, ok, err := wired_apply(t, &ws, NAMELESS, .Enforce)
	testing.expect_value(t, err, record.Apply_Error{})
	testing.expect(t, ok)
	testing.expect_value(t, v.checks, 1)

	// Into ex:g, a graph nothing has named before this changeset: validated on
	// the candidate, where the graph exists, and refused.
	_, ok, err = wired_apply(t, &ws, NAMELESS, .Enforce, graph = G)
	testing.expect_value(t, err, record.Apply_Error{.Rejected, -1})
	testing.expect(t, !ok)
	testing.expect(t, !head_has(&ws, rdf.IRI("http://example.org/bob"), rdf.IRI(rdf.RDF_TYPE), rdf.IRI("http://example.org/Person"), G))
}

// The report is the last apply's: a violation committed under Record, then
// repaired by the next write, leaves a conforming report with no results —
// not an accumulation, and not the previous verdict. (The repair has to be a
// repair: the violation *committed*, so an unrelated write after it would be
// validated against a dataset that still violates, and rightly refused.)
@(test)
test_report_is_reset_per_apply :: proc(t: ^testing.T) {
	shapes: Shapes
	defer shapes_destroy(&shapes)
	if !tdb_compile(t, &shapes, VALIDATOR_SHAPES) {
		return
	}
	v: Validator
	validator_init(&v, &shapes)
	defer validator_destroy(&v)
	ws: Wired_Store
	defer wired_close(&ws)
	if !wired_open(t, &ws, &v) {
		return
	}
	testing.expect(t, validator_report(&v) == nil, "no report before the first check")

	wired_apply(t, &ws, VALIDATOR_COMMITTED, .Record)
	wired_apply(t, &ws, VALIDATOR_CANDIDATE, .Record)
	testing.expect_value(t, result_count(validator_report(&v)), 1)

	_, ok, err := wired_apply(t, &ws, VALIDATOR_CANDIDATE, .Record, kind = .Retract)
	testing.expect_value(t, err, record.Apply_Error{})
	testing.expect(t, ok, "retracting the second email repairs the dataset")
	testing.expect_value(t, result_count(validator_report(&v)), 0)
	testing.expect(t, report_conforms(validator_report(&v)))
	testing.expect_value(t, v.checks, 3)
}

// A validator that cannot answer refuses: a recursive shape is a Failure, not a
// verdict, and under Enforce nothing is written — with `failure` telling the
// caller it was a refusal rather than a violation.
@(test)
test_failure_refuses_under_enforce :: proc(t: ^testing.T) {
	RECURSIVE :: `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:R a sh:PropertyShape ; sh:targetNode ex:a ; sh:path ex:p ; sh:property ex:R .
	`
	shapes: Shapes
	defer shapes_destroy(&shapes)
	if !tdb_compile(t, &shapes, RECURSIVE) {
		return
	}
	v: Validator
	validator_init(&v, &shapes)
	defer validator_destroy(&v)
	ws: Wired_Store
	defer wired_close(&ws)
	if !wired_open(t, &ws, &v) {
		return
	}
	_, ok, err := wired_apply(t, &ws, `@prefix ex: <http://example.org/> . ex:a ex:p ex:b .`, .Enforce)
	testing.expect_value(t, err, record.Apply_Error{.Rejected, -1})
	testing.expect(t, !ok)
	testing.expect_value(t, v.failure, Failure.Recursive_Shape)
	testing.expect_value(t, head_epoch(&ws), 0)
}

// The verdict-only validator: no report, the same refusals.
@(test)
test_verdict_only_validator_keeps_no_report :: proc(t: ^testing.T) {
	shapes: Shapes
	defer shapes_destroy(&shapes)
	if !tdb_compile(t, &shapes, VALIDATOR_SHAPES) {
		return
	}
	v: Validator
	validator_init(&v, &shapes, reporting = false)
	defer validator_destroy(&v)
	ws: Wired_Store
	defer wired_close(&ws)
	if !wired_open(t, &ws, &v) {
		return
	}
	_, ok, err := wired_apply(t, &ws, VALIDATOR_COMMITTED, .Enforce)
	testing.expect_value(t, err, record.Apply_Error{})
	testing.expect(t, ok)
	_, ok, err = wired_apply(t, &ws, VALIDATOR_CANDIDATE, .Enforce)
	testing.expect_value(t, err, record.Apply_Error{.Rejected, -1})
	testing.expect(t, !ok)
	testing.expect(t, !v.conforms)
	testing.expect(t, validator_report(&v) == nil, "a verdict-only validator holds no report")
}
