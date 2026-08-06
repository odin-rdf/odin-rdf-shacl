package w3c

import "core:testing"

import rdf "rdf:rdf"
import turtle "rdf:rdf/turtle"

// The comparison tests are written as pairs of Turtle documents rather than
// hand-built triple arrays: it keeps them readable, it exercises the real
// parse path the runner will use, and differently-named blank nodes in the
// two documents give the relabelling case for free.

@(private = "file")
parse_graph :: proc(source: string) -> [dynamic]rdf.Triple {
	out := make([dynamic]rdf.Triple)
	p: turtle.Parser
	turtle.parser_init(&p, transmute([]byte)source, "https://compare.invalid/")
	defer turtle.parser_destroy(&p)
	for {
		t, ok := turtle.parser_next(&p)
		if !ok {
			break
		}
		append(&out, rdf.clone_triple(t))
	}
	return out
}

@(private = "file")
destroy_graph :: proc(g: ^[dynamic]rdf.Triple) {
	for t in g {
		rdf.destroy_triple(t)
	}
	delete(g^)
}

@(private = "file")
expect_iso :: proc(t: ^testing.T, a_src, b_src: string, want: bool, msg: string) {
	a := parse_graph(a_src)
	defer destroy_graph(&a)
	b := parse_graph(b_src)
	defer destroy_graph(&b)

	testing.expectf(
		t,
		len(a) > 0 || len(b) == 0,
		"%s: left graph parsed to nothing — the fixture is wrong, not the comparison",
		msg,
	)
	got := report_isomorphic(a[:], b[:])
	testing.expectf(t, got == want, "%s: isomorphic=%v, expected %v", msg, got, want)
}

PREFIX :: "@prefix sh: <http://www.w3.org/ns/shacl#> .\n@prefix ex: <http://example.org/> .\n"

@(test)
test_iso_identical_ground_graphs :: proc(t: ^testing.T) {
	g := PREFIX + "ex:a ex:p ex:b . ex:b ex:q ex:c ."
	expect_iso(t, g, g, true, "a ground graph is isomorphic to itself")
}

@(test)
test_iso_blank_nodes_relabelled :: proc(t: ^testing.T) {
	a := PREFIX + "ex:report sh:result _:r1 . _:r1 sh:focusNode ex:x ."
	b := PREFIX + "ex:report sh:result _:zzz . _:zzz sh:focusNode ex:x ."
	expect_iso(t, a, b, true, "the same graph with different blank-node labels")
}

// The case a first-occurrence label mapping gets wrong: two results whose
// labels appear in the opposite order, so a greedy pairing binds _:r1 to the
// wrong one and has to backtrack.
@(test)
test_iso_requires_backtracking :: proc(t: ^testing.T) {
	a :=
		PREFIX +
		`ex:report sh:result _:r1, _:r2 .
		 _:r1 sh:focusNode ex:alpha ; sh:resultSeverity sh:Violation .
		 _:r2 sh:focusNode ex:beta ; sh:resultSeverity sh:Warning .`
	b :=
		PREFIX +
		`ex:report sh:result _:first, _:second .
		 _:first sh:focusNode ex:beta ; sh:resultSeverity sh:Warning .
		 _:second sh:focusNode ex:alpha ; sh:resultSeverity sh:Violation .`
	expect_iso(t, a, b, true, "two results presented in the opposite order")
}

// Nested blank nodes: sh:resultPath is itself a blank-node structure in the
// suite (`[ sh:inversePath ex:child ]`), so the bijection has to reach
// through more than one level.
@(test)
test_iso_nested_blank_nodes :: proc(t: ^testing.T) {
	a := PREFIX + "ex:report sh:result [ sh:resultPath [ sh:inversePath ex:child ] ] ."
	b := PREFIX + "ex:report sh:result [ sh:resultPath [ sh:inversePath ex:child ] ] ."
	expect_iso(t, a, b, true, "nested blank-node structures")

	c := PREFIX + "ex:report sh:result [ sh:resultPath [ sh:inversePath ex:parent ] ] ."
	expect_iso(t, a, c, false, "nested structures differing at the leaf")
}

// The negative that matters most: same shape, same number of triples, same
// skeletons — but no bijection exists. A comparison that only counted or only
// matched skeletons would pass this.
@(test)
test_iso_same_skeleton_no_bijection :: proc(t: ^testing.T) {
	a :=
		PREFIX +
		`_:x sh:focusNode ex:alpha .
		 _:x sh:value ex:one .
		 _:y sh:focusNode ex:beta .
		 _:y sh:value ex:two .`
	// The same four triples, but with the values swapped between the two
	// subjects, so no relabelling makes the graphs equal.
	b :=
		PREFIX +
		`_:x sh:focusNode ex:alpha .
		 _:x sh:value ex:two .
		 _:y sh:focusNode ex:beta .
		 _:y sh:value ex:one .`
	expect_iso(t, a, b, false, "identical skeletons with no valid bijection")
}

@(test)
test_iso_different_sizes :: proc(t: ^testing.T) {
	a := PREFIX + "ex:a ex:p ex:b ."
	b := PREFIX + "ex:a ex:p ex:b . ex:a ex:p ex:c ."
	expect_iso(t, a, b, false, "a strict subgraph is not isomorphic")
}

// RDF graphs are sets, so a document asserting the same triple twice denotes
// the same graph as one asserting it once.
@(test)
test_iso_duplicates_collapse :: proc(t: ^testing.T) {
	a := PREFIX + "ex:a ex:p ex:b . ex:a ex:p ex:b ."
	b := PREFIX + "ex:a ex:p ex:b ."
	expect_iso(t, a, b, true, "duplicate triples collapse before comparison")
}

// Literals compare on all four components, so a language tag or datatype
// difference is a real difference. Recorded here because SHACL-I-0001's
// language-tag decision is about *interning*, not about this: whatever the
// family decides, comparison stays exact.
@(test)
test_iso_literals_compare_exactly :: proc(t: ^testing.T) {
	a := PREFIX + `ex:a ex:p "Hill"@en-NZ .`
	b := PREFIX + `ex:a ex:p "Hill"@en-nz .`
	expect_iso(t, a, b, false, "language tags differing in case are different terms today")

	c := PREFIX + `ex:a ex:p "1" .`
	d := PREFIX + `ex:a ex:p 1 .`
	expect_iso(t, c, d, false, "a string and an integer are different terms")
}

@(test)
test_iso_empty_graphs :: proc(t: ^testing.T) {
	expect_iso(t, PREFIX, PREFIX, true, "two empty graphs")
}
