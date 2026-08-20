package shacl

import "core:testing"

import "rdf:rdf"
import "record:record"

// Compilation against the record store — the structural assertions, plus the
// two properties that used to differ by backend and are now simply the
// contract: the model owns its terms and outlives the store, and compiling
// never writes.

PREFIX :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
@prefix ex: <http://example.org/> .
`

@(private = "file")
with_shapes :: proc(t: ^testing.T, db: ^Test_DB, source: string, s: ^Shapes) -> bool {
	if !tdb_open(t, db) {
		return false
	}
	if !tdb_load(t, db, source) {
		return false
	}
	err := compile(s, tdb_session(db))
	return testing.expectf(t, err.kind == .None, "compile failed: %s", error_message(err.kind))
}

@(private = "file")
find_shape :: proc(s: ^Shapes, iri: string) -> (Shape, bool) {
	if i, ok := shape_index_of(s, rdf.IRI(iri)); ok {
		return s.shapes[i], true
	}
	return {}, false
}

@(test)
test_record_compiles_the_model :: proc(t: ^testing.T) {
	s: Shapes
	defer shapes_destroy(&s)
	db: Test_DB
	defer tdb_close(&db)

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
	if !with_shapes(t, &db, source, &s) {
		return
	}

	person, found := find_shape(&s, "http://example.org/PersonShape")
	if !testing.expect(t, found, "ex:PersonShape was not compiled") {
		return
	}
	testing.expect_value(t, person.kind, Shape_Kind.Node)
	testing.expect_value(t, person.severity, rdf.Term(rdf.IRI(WARNING)))
	testing.expect_value(t, len(shape_targets(&s, person)), 1)
	testing.expect_value(t, len(s.roots), 1)

	props := shape_properties(&s, person)
	if !testing.expect_value(t, len(props), 2) {
		return
	}

	kinds: map[Path_Kind]int
	defer delete(kinds)
	for pi in props {
		kinds[s.paths[s.shapes[pi].path].kind] += 1
	}
	testing.expect_value(t, kinds[.Inverse], 1)
	testing.expect_value(t, kinds[.Sequence], 1)

	seen: map[Constraint_Kind]int
	defer delete(seen)
	for pi in props {
		for c in shape_constraints(&s, s.shapes[pi]) {
			seen[c.kind] += 1
			if c.kind == .In {
				testing.expect_value(t, len(constraint_values(&s, c)), 2)
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

// The ownership property (SHACL-A-0001 decision 3): every term the model
// holds is decoded from the store's arena, which closing the store frees —
// so this closes the store, snapshot and all, and then reads the model.
@(test)
test_record_model_outlives_the_store :: proc(t: ^testing.T) {
	s: Shapes
	defer shapes_destroy(&s)
	db: Test_DB
	defer tdb_close(&db)

	source := PREFIX + `ex:S a sh:NodeShape ; sh:targetNode ex:n ; sh:property [ sh:path ex:p ] .`
	if !with_shapes(t, &db, source, &s) {
		return
	}

	// Every term in the model came from arena bytes this invalidates.
	tdb_close(&db)

	sh, found := find_shape(&s, "http://example.org/S")
	if !testing.expect(t, found, "shape not found after the store was closed") {
		return
	}
	targets := shape_targets(&s, sh)
	if testing.expect_value(t, len(targets), 1) {
		testing.expect_value(t, targets[0].term, rdf.Term(rdf.IRI("http://example.org/n")))
	}
	props := shape_properties(&s, sh)
	if testing.expect_value(t, len(props), 1) {
		testing.expect_value(
			t,
			s.paths[s.shapes[props[0]].path].predicate,
			rdf.Term(rdf.IRI("http://example.org/p")),
		)
	}
}

// Compiling must not write. On record that holds by construction — the read
// side has no way to reach the writer — so what is asserted is the observable
// half: the published epoch is the same after a compile as before it.
@(test)
test_record_compilation_does_not_write :: proc(t: ^testing.T) {
	s: Shapes
	defer shapes_destroy(&s)
	db: Test_DB
	defer tdb_close(&db)

	source := PREFIX + `ex:S a sh:NodeShape ; sh:targetClass ex:C ; sh:property [ sh:path ex:p ] .`
	if !with_shapes(t, &db, source, &s) {
		return
	}
	epoch_before := db.snap.epoch

	_, found := find_shape(&s, "http://example.org/S")
	testing.expect(t, found, "shape not compiled")

	after, serr := record.store_latest(&db.st)
	testing.expect_value(t, serr, record.Snapshot_Error.None)
	if serr == .None {
		defer record.snapshot_release(&after)
		testing.expect_value(t, after.epoch, epoch_before)
	}
}

// Widened discovery and the ignored-parameter record. The record inspects a
// term per predicate on every shape node; this is the compile path that
// touches the most decoded terms, so it runs under
// ODIN_TEST_FAIL_ON_BAD_MEMORY like the rest.
@(test)
test_record_discovers_and_records_the_same :: proc(t: ^testing.T) {
	s: Shapes
	defer shapes_destroy(&s)
	db: Test_DB
	defer tdb_close(&db)
	if !with_shapes(
		t,
		&db,
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
	ignored: map[string]bool
	defer delete(ignored)
	for term in shapes_ignored(&s) {
		if iri, is_iri := term.(rdf.IRI); is_iri {
			ignored[string(iri)] = true
		}
	}
	testing.expect_value(t, len(ignored), 1)
	testing.expect(t, NS + "sparql" in ignored, "sh:sparql should have been recorded as unimplemented")
	for iri in ([]string{NAME, TARGET_NODE, XONE, NODE}) {
		testing.expectf(t, !(iri in ignored), "%s should not be recorded as ignored", iri)
	}
}
