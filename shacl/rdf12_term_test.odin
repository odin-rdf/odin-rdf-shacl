package shacl

// RDF 1.2's two term kinds, in the data graph (SHACL-T-0038).
//
// odin-rdf-record v0.4.0 stores triple terms (encoding tag 0x07) and
// base-direction literals (0x08), where `apply` refused both before it. A value
// node can therefore be a triple term now, and every engine path that
// classifies or decodes one can meet it.
//
// **No entry in the vendored W3C corpus has that shape** — SHACL 1.0 predates
// RDF 1.2 by years — so the suite is silent here and stays silent however wrong
// this gets. What is pinned:
//
//  1. a triple term satisfies **no** `sh:nodeKind`, in the bound arm as in the
//     unbound one, and violates as an empty set should;
//  2. it is an ordinary value node otherwise — counted, reported, and rendered
//     into `sh:value` as the term it is;
//  3. **nothing leaks**, which is the assertion that cannot be written down.
//     Decoding a triple term *allocates* — the node and every component — where
//     every kind before it borrowed the store's arena, so the runner's memory
//     tracking is the test: `ODIN_TEST_FAIL_ON_BAD_MEMORY=true` is in the
//     Makefile, and a `session_term` left unpaired fails the run rather than
//     passing quietly. Every test in this file decodes at least one.
//
// A base-direction literal is the smaller half: it needs nothing from this
// engine (it is a literal with a language, which is what the engine already
// reads), and the test that says so is here to keep that a finding rather than
// an assumption.

import "core:testing"

import "rdf:rdf"
import "record:record"

@(private = "file")
EX :: "http://example.org/"

// `<<( s p o )>>` is RDF 1.2 Turtle's triple-term syntax and reaches a store in
// the object position — the only position the corpus obliges (RECORD-I-0004).
// The reifying form `ex:s ex:p << ex:a ex:b ex:c >>` expands to a blank reifier
// plus `rdf:reifies <<( … )>>`, which puts the triple term in the same place by
// a longer road.
@(private = "file")
TRIPLE_DATA :: `
@prefix ex: <http://example.org/> .
ex:s ex:p <<( ex:a ex:b ex:c )>> .
`

@(private = "file")
Fixture :: struct {
	db:       Test_DB,
	se:       Session,
	shapes:   Shapes,
	bindings: Bindings,
}

// Shapes and data live in separate stores, as they do in every semantics test
// here: the model owns its terms (SHACL-A-0001 decision 3), so it is bound
// against a dictionary it was never compiled from.
@(private = "file")
fixture_init :: proc(t: ^testing.T, f: ^Fixture, shapes_src, data_src: string) -> bool {
	{
		sdb: Test_DB
		defer tdb_close(&sdb)
		if !tdb_open(t, &sdb) {
			return false
		}
		if !tdb_load(t, &sdb, shapes_src, blank_prefix = "s_") {
			return false
		}
		err := compile(&f.shapes, tdb_session(&sdb))
		if !testing.expectf(t, err.kind == .None, "compile: %s", error_message(err.kind)) {
			return false
		}
	}
	if !tdb_open(t, &f.db) {
		return false
	}
	if !tdb_load(t, &f.db, data_src, blank_prefix = "d_") {
		return false
	}
	f.se = tdb_session(&f.db)
	bindings_init(&f.bindings, &f.shapes, f.se)
	return true
}

@(private = "file")
fixture_destroy :: proc(f: ^Fixture) {
	bindings_destroy(&f.bindings)
	shapes_destroy(&f.shapes)
	tdb_close(&f.db)
}

// Seen collects the components a validation reported, with the value node's
// kind beside each — which is the whole question here.
@(private = "file")
Seen :: struct {
	se:         Session,
	components: [dynamic]Constraint_Kind,
	kinds:      [dynamic]record.Term_Kind,
}

@(private = "file")
seen_visit :: proc(data: rawptr, result: Result) -> bool {
	s := cast(^Seen)data
	append(&s.components, result.component)
	if result.has_value && result.value.bound {
		append(&s.kinds, session_kind(s.se, result.value.id))
	}
	return true
}

@(private = "file")
seen_destroy :: proc(s: ^Seen) {
	delete(s.components)
	delete(s.kinds)
}

// triple_term_id is the id of `<<( ex:a ex:b ex:c )>>` in the data store, found
// the way any term is found — by resolving the term itself. That it resolves at
// all is record's `snapshot_resolve` recursing through the components
// (RECORD-A-0008); before v0.4.0 the term could not be encoded, so this asked a
// question with no answer.
@(private = "file")
triple_term_id :: proc(t: ^testing.T, se: Session, loc := #caller_location) -> (id: record.Term_ID, ok: bool) {
	tt := rdf.Triple {
		subject   = rdf.IRI(EX + "a"),
		predicate = rdf.IRI(EX + "b"),
		object    = rdf.IRI(EX + "c"),
	}
	id, ok = session_resolve(se, &tt)
	testing.expect(t, ok, "the data store does not hold <<( ex:a ex:b ex:c )>>", loc = loc)
	return id, ok
}

@(test)
test_triple_term_satisfies_no_node_kind :: proc(t: ^testing.T) {
	shapes := `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:S a sh:NodeShape ; sh:targetNode ex:s ;
		sh:property [ sh:path ex:p ; sh:nodeKind sh:IRI ] .
	`
	f: Fixture
	if !fixture_init(t, &f, shapes, TRIPLE_DATA) {
		fixture_destroy(&f)
		return
	}
	defer fixture_destroy(&f)

	seen: Seen
	seen.se = f.se
	defer seen_destroy(&seen)
	testing.expect_value(t, validate(&f.shapes, &f.bindings, f.se, seen_visit, &seen), Failure.None)

	// One violation, and it is the node kind: `sh:IRI` is a one-element set and
	// a triple term's kind set is empty, so the intersection is empty however
	// the shape is written. `sh:BlankNodeOrIRI` or all six would violate the
	// same way — there is no `sh:nodeKind` a triple term satisfies.
	testing.expect_value(t, len(seen.components), 1)
	if len(seen.components) == 1 {
		testing.expect_value(t, seen.components[0], Constraint_Kind.Node_Kind)
	}
	// The value node is bound, and it is the fourth kind. This is the assertion
	// that would have been unreachable before record v0.4.0 — and the one the
	// old `switch` in `node_kind_of` could not have answered, since it had no
	// arm for it.
	testing.expect_value(t, len(seen.kinds), 1)
	if len(seen.kinds) == 1 {
		testing.expect_value(t, seen.kinds[0], record.Term_Kind.Triple)
	}
}

@(test)
test_triple_term_is_an_ordinary_value_node :: proc(t: ^testing.T) {
	shapes := `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:S a sh:NodeShape ; sh:targetNode ex:s ;
		sh:property [ sh:path ex:p ; sh:minCount 1 ; sh:maxCount 1 ] .
	`
	f: Fixture
	if !fixture_init(t, &f, shapes, TRIPLE_DATA) {
		fixture_destroy(&f)
		return
	}
	defer fixture_destroy(&f)

	seen: Seen
	seen.se = f.se
	defer seen_destroy(&seen)
	testing.expect_value(t, validate(&f.shapes, &f.bindings, f.se, seen_visit, &seen), Failure.None)

	// Counted like anything else: one value node, so both bounds hold. A term
	// kind the engine cannot classify is still a term it can count, which is
	// the distinction §4.7 draws and this pins.
	testing.expect_value(t, len(seen.components), 0)
}

@(test)
test_triple_term_renders_into_a_report :: proc(t: ^testing.T) {
	shapes := `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:S a sh:NodeShape ; sh:targetNode ex:s ;
		sh:property [ sh:path ex:p ; sh:nodeKind sh:IRI ] .
	`
	f: Fixture
	if !fixture_init(t, &f, shapes, TRIPLE_DATA) {
		fixture_destroy(&f)
		return
	}
	defer fixture_destroy(&f)

	r: Report
	report_init(&r)
	defer report_destroy(&r)
	testing.expect_value(t, validate_report(&r, &f.shapes, &f.bindings, f.se), Failure.None)
	testing.expect(t, !report_conforms(&r), "a triple term satisfies no sh:nodeKind, so the report must not conform")

	// `sh:value` names the node that violated, and here that node is a triple
	// term: the report has to decode one and keep it, which is the path where
	// an owned decode meets a table that owns its terms. The report is checked
	// *after* nothing else has run, and freed by `report_destroy` — a component
	// left borrowing the store's arena would be a use-after-free at that point,
	// not a leak.
	found := false
	for tr in report_triples(&r) {
		if iri, is_iri := tr.predicate.(rdf.IRI); !is_iri || string(iri) != VALUE {
			continue
		}
		node, is_triple := tr.object.(^rdf.Triple)
		if !testing.expect(t, is_triple, "sh:value should name the triple term itself") {
			continue
		}
		found = true
		testing.expect(t, rdf.equal_term(node.subject, rdf.IRI(EX + "a")), "sh:value subject")
		testing.expect(t, rdf.equal_term(node.predicate, rdf.IRI(EX + "b")), "sh:value predicate")
		testing.expect(t, rdf.equal_term(node.object, rdf.IRI(EX + "c")), "sh:value object")
	}
	testing.expect(t, found, "the report should carry an sh:value")
}

@(test)
test_session_term_owns_a_decoded_triple_term :: proc(t: ^testing.T) {
	db: Test_DB
	defer tdb_close(&db)
	if !tdb_open(t, &db) {
		return
	}
	if !tdb_load(t, &db, TRIPLE_DATA) {
		return
	}
	se := tdb_session(&db)

	id, ok := triple_term_id(t, se)
	if !ok {
		return
	}
	// The cheap question first: the kind, one arena byte, no decode.
	testing.expect_value(t, session_kind(se, id), record.Term_Kind.Triple)

	// Then the expensive one. The decode allocates a node and three components
	// from the context allocator, and `session_term_destroy` is what returns
	// them; the runner's memory tracking fails this test if it does not.
	buf: Term_Buf
	term, decoded := session_term(se, id, buf[:])
	defer session_term_destroy(se, id, term)
	if !testing.expect(t, decoded, "a triple term should decode") {
		return
	}
	node, is_triple := term.(^rdf.Triple)
	if !testing.expect(t, is_triple, "session_term should return a ^rdf.Triple") {
		return
	}
	testing.expect(t, rdf.equal_term(node.subject, rdf.IRI(EX + "a")), "subject")
	testing.expect(t, rdf.equal_term(node.predicate, rdf.IRI(EX + "b")), "predicate")
	testing.expect(t, rdf.equal_term(node.object, rdf.IRI(EX + "c")), "object")

	// Destroying an id that borrows is a no-op, and pairing it with *every*
	// decode is the rule that keeps the caller from having to know which kind
	// it has. `ex:s` borrows the arena; freeing it would be a crash if the verb
	// were not total.
	sid, sok := session_resolve(se, rdf.IRI(EX + "s"))
	testing.expect(t, sok, "ex:s should resolve")
	sbuf: Term_Buf
	sterm, sdecoded := session_term(se, sid, sbuf[:])
	defer session_term_destroy(se, sid, sterm)
	testing.expect(t, sdecoded, "ex:s should decode")
	testing.expect(t, rdf.equal_term(sterm, rdf.IRI(EX + "s")), "ex:s")
}

@(test)
test_base_direction_literal_is_an_ordinary_literal :: proc(t: ^testing.T) {
	// RDF 1.2's other new term kind, and the half that asked nothing of this
	// engine: `sh:nodeKind sh:Literal` holds, `sh:languageIn` matches on the tag
	// as it does for `@fr`, and `sh:datatype rdf:langString` does *not* hold —
	// the datatype is `rdf:dirLangString`, which is the spec's answer and not a
	// special case anywhere in this engine.
	shapes := `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
	@prefix ex: <http://example.org/> .
	ex:Kind a sh:NodeShape ; sh:targetNode ex:s ;
		sh:property [ sh:path ex:p ; sh:nodeKind sh:Literal ; sh:languageIn ( "fr" ) ] .
	ex:Datatype a sh:NodeShape ; sh:targetNode ex:s ;
		sh:property [ sh:path ex:p ; sh:datatype rdf:langString ] .
	`
	data := `
	@prefix ex: <http://example.org/> .
	ex:s ex:p "chat"@fr--ltr .
	`
	f: Fixture
	if !fixture_init(t, &f, shapes, data) {
		fixture_destroy(&f)
		return
	}
	defer fixture_destroy(&f)

	seen: Seen
	seen.se = f.se
	defer seen_destroy(&seen)
	testing.expect_value(t, validate(&f.shapes, &f.bindings, f.se, seen_visit, &seen), Failure.None)

	testing.expect_value(t, len(seen.components), 1)
	if len(seen.components) == 1 {
		testing.expect_value(t, seen.components[0], Constraint_Kind.Datatype)
	}

	// And the decode round-trips the direction, which is the store's half: the
	// tag carries it, `rdf.Literal` already had the field, and nothing between
	// them had to learn a new shape.
	id, ok := session_resolve(f.se, rdf.Literal{lexical = "chat", datatype = rdf.RDF_DIR_LANG_STRING, language = "fr", direction = .LTR})
	if !testing.expect(t, ok, "the directional literal should resolve") {
		return
	}
	testing.expect_value(t, session_kind(f.se, id), record.Term_Kind.Literal)
	buf: Term_Buf
	term, decoded := session_term(f.se, id, buf[:])
	defer session_term_destroy(f.se, id, term)
	if !testing.expect(t, decoded, "the directional literal should decode") {
		return
	}
	lit, is_lit := term.(rdf.Literal)
	if !testing.expect(t, is_lit, "it is a literal") {
		return
	}
	testing.expect_value(t, lit.lexical, "chat")
	testing.expect_value(t, lit.language, "fr")
	testing.expect_value(t, lit.direction, rdf.Direction.LTR)
	testing.expect(t, lit.datatype == rdf.RDF_DIR_LANG_STRING, "datatype is rdf:dirLangString")
}

@(test)
test_triple_term_through_the_value_paths :: proc(t: ^testing.T) {
	// The components that *decode* a value node rather than classify it —
	// `materialize` and its pairing. Each of these asks the store for the term
	// behind the id, gets an owned tree back, and must give it up again; a
	// missing `materialize_destroy` shows up here as a leak per constraint per
	// value node rather than as a wrong verdict.
	//
	// All three violate, and for the same reason in three vocabularies: a
	// triple term is not a literal, has no string, and orders against nothing.
	shapes := `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
	@prefix ex: <http://example.org/> .
	ex:S a sh:NodeShape ; sh:targetNode ex:s ;
		sh:property [ sh:path ex:p ; sh:datatype xsd:string ] ;
		sh:property [ sh:path ex:p ; sh:minLength 1 ] ;
		sh:property [ sh:path ex:p ; sh:minInclusive 4 ] .
	`
	f: Fixture
	if !fixture_init(t, &f, shapes, TRIPLE_DATA) {
		fixture_destroy(&f)
		return
	}
	defer fixture_destroy(&f)

	seen: Seen
	seen.se = f.se
	defer seen_destroy(&seen)
	testing.expect_value(t, validate(&f.shapes, &f.bindings, f.se, seen_visit, &seen), Failure.None)

	testing.expect_value(t, len(seen.components), 3)
	for kind in seen.kinds {
		testing.expect_value(t, kind, record.Term_Kind.Triple)
	}
}

@(test)
test_a_shapes_graph_may_name_a_triple_term :: proc(t: ^testing.T) {
	// The other direction: a triple term in the **shapes** graph, which the
	// compiler must materialise into the model's own storage. That is
	// `materialize_term` — decode, intern the copy, release the decode — and it
	// is the path where an owned decode meets a table that deep-frees what it
	// holds (SHACL-A-0001 decision 3: the model outlives the store it was
	// compiled from, so it can borrow nothing from it).
	//
	// `sh:hasValue` then compares by **id**: `bindings_init` resolves the
	// model's triple term against the *data* store's dictionary, which is
	// record's `snapshot_resolve` recursing through the components. Two
	// dictionaries, two id spaces, one term — and the comparison is an integer
	// one, as it is for every other kind.
	shapes := `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:S a sh:NodeShape ; sh:targetNode ex:s ;
		sh:property [ sh:path ex:p ; sh:hasValue <<( ex:a ex:b ex:c )>> ] .
	`
	{
		f: Fixture
		if !fixture_init(t, &f, shapes, TRIPLE_DATA) {
			fixture_destroy(&f)
			return
		}
		defer fixture_destroy(&f)

		seen: Seen
		seen.se = f.se
		defer seen_destroy(&seen)
		testing.expect_value(t, validate(&f.shapes, &f.bindings, f.se, seen_visit, &seen), Failure.None)
		testing.expect_value(t, len(seen.components), 0) // the value is there
	}

	// And the same shape against data whose triple term differs in one
	// component: a different term, a different id, `sh:hasValue` violates.
	other := `
	@prefix ex: <http://example.org/> .
	ex:s ex:p <<( ex:a ex:b ex:z )>> .
	`
	f: Fixture
	if !fixture_init(t, &f, shapes, other) {
		fixture_destroy(&f)
		return
	}
	defer fixture_destroy(&f)

	seen: Seen
	seen.se = f.se
	defer seen_destroy(&seen)
	testing.expect_value(t, validate(&f.shapes, &f.bindings, f.se, seen_visit, &seen), Failure.None)
	testing.expect_value(t, len(seen.components), 1)
	if len(seen.components) == 1 {
		testing.expect_value(t, seen.components[0], Constraint_Kind.Has_Value)
	}
}

@(test)
test_triple_term_through_the_pairwise_and_set_paths :: proc(t: ^testing.T) {
	// The two components that decode a value node somewhere other than the
	// single-value path: `sh:lessThan`, which materialises **both** sides of a
	// comparison, and `sh:uniqueLang`, which materialises every value node in a
	// loop before it looks at any of them. Both reach a triple term here, and
	// both are pairings a single-value test would leave unproven.
	//
	// `ex:q` carries a triple term too, and deliberately: the right-hand side of
	// `sh:lessThan` is decoded through `session_term` directly rather than
	// through `materialize`, so a literal there would have left that one pairing
	// unexercised while everything else in this file passed.
	shapes := `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:S a sh:NodeShape ; sh:targetNode ex:s ;
		sh:property [ sh:path ex:p ; sh:lessThan ex:q ; sh:uniqueLang true ] .
	`
	data := `
	@prefix ex: <http://example.org/> .
	ex:s ex:p <<( ex:a ex:b ex:c )>> .
	ex:s ex:q <<( ex:d ex:e ex:f )>> .
	`
	f: Fixture
	if !fixture_init(t, &f, shapes, data) {
		fixture_destroy(&f)
		return
	}
	defer fixture_destroy(&f)

	seen: Seen
	seen.se = f.se
	defer seen_destroy(&seen)
	testing.expect_value(t, validate(&f.shapes, &f.bindings, f.se, seen_visit, &seen), Failure.None)

	// A triple term orders against nothing — not even another triple term — so
	// the comparison does not hold and `sh:lessThan` reports, the same answer
	// `property/lessThan-002` pins for integers against strings.
	// `sh:uniqueLang` says nothing: a triple term has no language tag, so there
	// is no tag to repeat.
	testing.expect_value(t, len(seen.components), 1)
	if len(seen.components) == 1 {
		testing.expect_value(t, seen.components[0], Constraint_Kind.Less_Than)
	}
}
