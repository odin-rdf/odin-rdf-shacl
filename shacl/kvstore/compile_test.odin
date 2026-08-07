package shacl_kvstore

import "core:testing"

import rdf "rdf:rdf"
import kvstore "store:store/kvstore"

import shacl ".."

// The dual-backend discipline, applied to compilation: the same shapes graph
// must compile to the same model against the persistent backend as against
// the in-memory one. These are the assertions from
// `shacl/memstore/compile_test.odin` that are worth paying an LMDB round trip
// for — the structural ones, plus the two properties that differ by backend.
//
// The memstore file is the fuller suite. This one exists to catch anything
// that is true of one backend and not the other, and the two are meant to
// stay recognizably parallel.

PREFIX :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
@prefix ex: <http://example.org/> .
`

@(private = "file")
with_shapes :: proc(t: ^testing.T, name, source: string, s: ^shacl.Shapes) -> bool {
	path := temp_path(name)
	defer remove_store(path)

	st, open_err := kvstore.open(path)
	if !testing.expectf(t, open_err == nil, "kvstore.open failed: %v", open_err) {
		return false
	}
	defer kvstore.close(st)

	_, parse_err, load_err := kvstore.load_turtle(st, transmute([]byte)source)
	if !testing.expectf(t, parse_err.message == "", "shapes graph did not parse: %s", parse_err.message) {
		return false
	}
	if !testing.expectf(t, load_err == nil, "load failed: %v", load_err) {
		return false
	}

	session: Session
	session_init(&session, st)
	err := compile(s, &session)
	if !testing.expectf(
		t,
		err.kind == .None,
		"compile failed: %s",
		shacl.error_message(err.kind),
	) {
		return false
	}
	return testing.expectf(t, session_error(&session) == nil, "store error during compile: %v", session_error(&session))
}

@(private = "file")
find_shape :: proc(s: ^shacl.Shapes, iri: string) -> (shacl.Shape, bool) {
	if i, ok := shacl.shape_index_of(s, rdf.IRI(iri)); ok {
		return s.shapes[i], true
	}
	return {}, false
}

@(test)
test_kvstore_compiles_the_same_model :: proc(t: ^testing.T) {
	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)

	source :=
		PREFIX +
		`
		ex:PersonShape a sh:NodeShape ;
			sh:targetClass ex:Person ;
			sh:severity sh:Warning ;
			sh:property [
				sh:path [ sh:inversePath ex:child ] ;
				sh:minCount 2 ;
				sh:nodeKind sh:IRI ;
			] ;
			sh:property [
				sh:path ( ex:a ex:b ) ;
				sh:in ( ex:one ex:two ) ;
			] .
		`
	if !with_shapes(t, "compile-model", source, &s) {
		return
	}

	person, found := find_shape(&s, "http://example.org/PersonShape")
	if !testing.expect(t, found, "ex:PersonShape was not compiled") {
		return
	}
	testing.expect_value(t, person.kind, shacl.Shape_Kind.Node)
	testing.expect_value(t, person.severity, rdf.Term(rdf.IRI(shacl.WARNING)))
	testing.expect_value(t, len(shacl.shape_targets(&s, person)), 1)
	testing.expect_value(t, len(s.roots), 1)

	props := shacl.shape_properties(&s, person)
	if !testing.expect_value(t, len(props), 2) {
		return
	}

	kinds: map[shacl.Path_Kind]int
	defer delete(kinds)
	for pi in props {
		kinds[s.paths[s.shapes[pi].path].kind] += 1
	}
	testing.expect_value(t, kinds[.Inverse], 1)
	testing.expect_value(t, kinds[.Sequence], 1)

	seen: map[shacl.Constraint_Kind]int
	defer delete(seen)
	for pi in props {
		for c in shacl.shape_constraints(&s, s.shapes[pi]) {
			seen[c.kind] += 1
			if c.kind == .In {
				testing.expect_value(t, len(shacl.constraint_values(&s, c)), 2)
			}
			if c.kind == .Min_Count {
				testing.expect_value(t, c.count, 2)
			}
		}
	}
	testing.expect_value(t, seen[.Min_Count], 1)
	testing.expect_value(t, seen[.Node_Kind], 1)
	testing.expect_value(t, seen[.In], 1)
}

// The ownership property matters more here than on memstore. kvstore's
// lookup_term builds every term from database bytes that closing the store
// invalidates, so a model that borrowed would be dangling the moment the
// store closed. This closes it first and then reads the model.
@(test)
test_kvstore_model_outlives_the_store :: proc(t: ^testing.T) {
	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)

	path := temp_path("compile-outlives")
	defer remove_store(path)

	st, open_err := kvstore.open(path)
	if !testing.expectf(t, open_err == nil, "kvstore.open failed: %v", open_err) {
		return
	}

	source := PREFIX + `ex:S a sh:NodeShape ; sh:targetNode ex:n ; sh:property [ sh:path ex:p ] .`
	_, parse_err, load_err := kvstore.load_turtle(st, transmute([]byte)source)
	testing.expectf(t, parse_err.message == "", "parse failed: %s", parse_err.message)
	testing.expectf(t, load_err == nil, "load failed: %v", load_err)

	session: Session
	session_init(&session, st)
	err := compile(&s, &session)
	testing.expect_value(t, err.kind, shacl.Error_Kind.None)
	testing.expectf(t, session_error(&session) == nil, "store error: %v", session_error(&session))

	// Every term in the model came from bytes this invalidates.
	kvstore.close(st)

	sh, found := find_shape(&s, "http://example.org/S")
	if !testing.expect(t, found, "shape not found after the store was closed") {
		return
	}
	targets := shacl.shape_targets(&s, sh)
	if testing.expect_value(t, len(targets), 1) {
		testing.expect_value(t, targets[0].term, rdf.Term(rdf.IRI("http://example.org/n")))
	}
	props := shacl.shape_properties(&s, sh)
	if testing.expect_value(t, len(props), 1) {
		testing.expect_value(
			t,
			s.paths[s.shapes[props[0]].path].predicate,
			rdf.Term(rdf.IRI("http://example.org/p")),
		)
	}
}

// Compiling must not write. On a persistent backend that is not a style
// preference: interning inside a read would turn every query into a write
// transaction, and would fail outright against a read-only environment.
@(test)
test_kvstore_compilation_does_not_write :: proc(t: ^testing.T) {
	path := temp_path("compile-readonly")
	defer remove_store(path)

	source := PREFIX + `ex:S a sh:NodeShape ; sh:targetClass ex:C ; sh:property [ sh:path ex:p ] .`
	{
		st, open_err := kvstore.open(path)
		if !testing.expectf(t, open_err == nil, "kvstore.open failed: %v", open_err) {
			return
		}
		defer kvstore.close(st)
		_, parse_err, load_err := kvstore.load_turtle(st, transmute([]byte)source)
		testing.expectf(t, parse_err.message == "", "parse failed: %s", parse_err.message)
		testing.expectf(t, load_err == nil, "load failed: %v", load_err)
	}

	// Reopen read-only. A compile that interned anything cannot survive this.
	opts := kvstore.DEFAULT_OPTIONS
	opts.read_only = true
	st, open_err := kvstore.open(path, opts)
	if !testing.expectf(t, open_err == nil, "read-only open failed: %v", open_err) {
		return
	}
	defer kvstore.close(st)

	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)
	session: Session
	session_init(&session, st)
	err := compile(&s, &session)
	testing.expect_value(t, err.kind, shacl.Error_Kind.None)
	testing.expectf(t, session_error(&session) == nil, "store error: %v", session_error(&session))

	_, found := find_shape(&s, "http://example.org/S")
	testing.expect(t, found, "shape not compiled from a read-only environment")
}

// Widened discovery and the ignored-parameter record, against the persistent
// backend. Both are in this file rather than only the memstore one because of
// the property that differs by backend: kvstore's load_adapter answers
// `owned = true`, so every predicate the record inspects is a term built from
// database bytes that the compiler has to free. A leak there is invisible in
// memory, where nothing is owned, and this file runs under
// ODIN_TEST_FAIL_ON_BAD_MEMORY like the rest.
@(test)
test_kvstore_discovers_and_records_the_same :: proc(t: ^testing.T) {
	s: shacl.Shapes
	defer shacl.shapes_destroy(&s)
	if !with_shapes(
		t,
		"discovery",
		PREFIX +
		`
		ex:Root a sh:NodeShape ;
			sh:targetNode ex:n ;
			sh:node ex:ViaNode ;
			sh:xone ( ex:ViaXone ) ;
			sh:name "inert" ;
			sh:sparql ex:Query .
		`,
		&s,
	) {
		return
	}

	for iri in ([]string{"http://example.org/ViaNode", "http://example.org/ViaXone"}) {
		_, found := find_shape(&s, iri)
		testing.expectf(t, found, "%s is the value of a shape-expecting parameter but was not compiled", iri)
	}
	testing.expect_value(t, len(s.shapes), 3)

	// **Only `sh:sparql` is left**, and the shrinking of this list across three
	// tasks is the record working rather than the test rotting: SHACL-T-0017
	// implemented `sh:xone` and SHACL-T-0018 `sh:node`, so a shapes graph using
	// either is no longer using something this engine ignores. `sh:name` is inert
	// and `sh:targetNode` implemented, so neither ever appeared.
	//
	// With SHACL Core's catalogue complete, **a non-empty record now means a
	// vendor extension or SHACL-SPARQL** and nothing else. That is why the one
	// example left is `sh:sparql`: it belongs to a phase this initiative is
	// explicitly not part of, so it cannot go the way the other two did.
	//
	// The test's real subject is unchanged and is asserted above: a
	// shape-expecting parameter makes its value a shape. That held when nothing
	// validated the value and holds now that something does.
	ignored: map[string]bool
	defer delete(ignored)
	for term in shacl.shapes_ignored(&s) {
		if iri, is_iri := term.(rdf.IRI); is_iri {
			ignored[string(iri)] = true
		}
	}
	testing.expect_value(t, len(ignored), 1)
	testing.expect(t, shacl.NS + "sparql" in ignored, "sh:sparql should have been recorded as unimplemented")
	for iri in ([]string{shacl.NAME, shacl.TARGET_NODE, shacl.XONE, shacl.NODE}) {
		testing.expectf(t, !(iri in ignored), "%s should not be recorded as ignored", iri)
	}
}
