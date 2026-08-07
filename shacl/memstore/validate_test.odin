package shacl_memstore

import "core:slice"
import "core:strings"
import "core:testing"

import rdf "rdf:rdf"
import memstore "store:store/memstore"

import shacl ".."

// Validation, end to end but in the small: the behaviours the W3C suite either
// cannot reach or would report as one opaque report mismatch.
//
// The suite is the scoreboard; this file is the microscope. Four things live
// here for reasons the suite cannot cover at all — an unbound focus node
// (impossible when an entry's shapes and data are the same document), a
// deactivated shape, recursion, and early exit, which by definition produces
// *fewer* results than the report the suite compares.
//
// The fixture keeps shapes and data in **separate stores** throughout, which is
// what SHACL-A-0001 decision 3 buys: the model owns its terms, so it is bound
// against a dictionary it was never compiled from.

@(private = "file")
Fixture :: struct {
	dictionary: memstore.Dictionary,
	dataset:    memstore.Dataset,
	shapes:     shacl.Shapes,
	bindings:   shacl.Bindings,
}

@(private = "file")
fixture_init :: proc(t: ^testing.T, f: ^Fixture, shapes_src, data_src: string) -> bool {
	// The shapes store is built, read, and destroyed before the data store
	// exists, so nothing the model hands out can be borrowing from it.
	{
		dictionary: memstore.Dictionary
		memstore.dictionary_init(&dictionary)
		defer memstore.dictionary_destroy(&dictionary)
		dataset: memstore.Dataset
		memstore.dataset_init(&dataset)
		defer memstore.dataset_destroy(&dataset)

		_, load_err := memstore.load_turtle(&dictionary, &dataset, transmute([]byte)shapes_src)
		if !testing.expectf(t, load_err.message == "", "shapes graph: %s", load_err.message) {
			return false
		}
		err := compile(&f.shapes, &dictionary, &dataset)
		if !testing.expectf(t, err.kind == .None, "compile: %s", shacl.error_message(err.kind)) {
			return false
		}
	}

	memstore.dictionary_init(&f.dictionary)
	memstore.dataset_init(&f.dataset)
	_, load_err := memstore.load_turtle(&f.dictionary, &f.dataset, transmute([]byte)data_src)
	if !testing.expectf(t, load_err.message == "", "data graph: %s", load_err.message) {
		return false
	}
	bind(&f.bindings, &f.shapes, &f.dictionary)
	return true
}

@(private = "file")
fixture_destroy :: proc(f: ^Fixture) {
	shacl.bindings_destroy(&f.bindings)
	shacl.shapes_destroy(&f.shapes)
	memstore.dataset_destroy(&f.dataset)
	memstore.dictionary_destroy(&f.dictionary)
}

// Seen records what the visitor was handed, materialised into strings so an
// assertion reads like the shapes graph that produced it.
@(private = "file")
Seen :: struct {
	fixture: ^Fixture,
	lines:   [dynamic]string,
	stop_at: int, // return false once this many results have arrived; 0 = never
}

@(private = "file")
seen_destroy :: proc(s: ^Seen) {
	for line in s.lines {
		delete(line)
	}
	delete(s.lines)
}

// record renders one result as "shape|component|focus|value", which is enough
// to pin every decision the dispatcher makes and short enough to write by hand
// in an expectation.
@(private = "file")
record :: proc(data: rawptr, result: shacl.Result) -> bool {
	s := cast(^Seen)data
	sb := strings.builder_make()

	write_term(&sb, shacl.result_source_shape(&s.fixture.shapes, result))
	strings.write_byte(&sb, '|')
	strings.write_string(&sb, local_name(shacl.component_iri(result.component)))
	strings.write_byte(&sb, '|')
	write_node(s, &sb, result.focus)
	strings.write_byte(&sb, '|')
	if result.has_value {
		write_node(s, &sb, result.value)
	} else {
		strings.write_string(&sb, "-")
	}
	// A fifth field, written only where there is one to write: `sh:closed` is
	// the one component whose `sh:resultPath` is a term of the data graph rather
	// than the shape's path (§4.8.1). Appending it unconditionally would have
	// meant editing every expectation in this file to say "no path".
	if result.has_path_predicate {
		strings.write_byte(&sb, '|')
		write_node(s, &sb, result.path_predicate)
	}

	append(&s.lines, strings.to_string(sb))
	if s.stop_at > 0 && len(s.lines) >= s.stop_at {
		return false
	}
	return true
}

@(private = "file")
write_node :: proc(s: ^Seen, sb: ^strings.Builder, ref: shacl.Node_Ref) {
	if !ref.bound {
		strings.write_string(sb, "?")
		write_term(sb, ref.term)
		return
	}
	write_term(sb, memstore.lookup_term(&s.fixture.dictionary, ref.id))
}

@(private = "file")
write_term :: proc(sb: ^strings.Builder, term: rdf.Term) {
	#partial switch v in term {
	case rdf.IRI:
		strings.write_string(sb, local_name(string(v)))
	case rdf.Blank_Node:
		// Deliberately label-free. A blank-node shape's label is whatever the
		// Turtle parser happened to mint, so pinning it in an expectation would
		// make these tests break on an unrelated parser change; the component
		// and the focus node already say which shape it is.
		strings.write_string(sb, "_:")
	case rdf.Literal:
		strings.write_byte(sb, '"')
		strings.write_string(sb, v.lexical)
		strings.write_byte(sb, '"')
	}
}

// local_name strips a namespace so an expectation reads `MinCount` rather than
// the full component IRI.
@(private = "file")
local_name :: proc(iri: string) -> string {
	if i := strings.last_index_any(iri, "#/"); i >= 0 {
		return iri[i + 1:]
	}
	return iri
}

@(private = "file")
expect_results :: proc(t: ^testing.T, seen: ^Seen, want: []string, what: string, loc := #caller_location) {
	got := slice.clone(seen.lines[:])
	defer delete(got)
	slice.sort(got)
	sorted_want := slice.clone(want)
	defer delete(sorted_want)
	slice.sort(sorted_want)

	joined_got := strings.join(got, "  ")
	defer delete(joined_got)
	joined_want := strings.join(sorted_want, "  ")
	defer delete(joined_want)
	testing.expectf(t, joined_got == joined_want, "%s:\n  got  [%s]\n  want [%s]", what, joined_got, joined_want, loc = loc)
}

@(private = "file")
validate_into :: proc(f: ^Fixture, seen: ^Seen) -> shacl.Failure {
	seen.fixture = f
	return validate(&f.shapes, &f.bindings, &f.dictionary, &f.dataset, record, seen)
}

// ---- The dispatch seam ---------------------------------------------------

DISPATCH_SHAPES :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
@prefix ex: <http://example.org/> .

ex:Cardinality a sh:NodeShape ; sh:targetNode ex:one, ex:three ;
	sh:property [ sh:path ex:p ; sh:minCount 2 ; sh:maxCount 2 ] .

ex:Values a sh:NodeShape ; sh:targetNode ex:one ;
	sh:property ex:ValuesP .
ex:ValuesP a sh:PropertyShape ; sh:path ex:p ;
	sh:class ex:C ;
	sh:datatype xsd:string ;
	sh:nodeKind sh:IRI ;
	sh:in ( ex:a ) ;
	sh:hasValue ex:z .
`

DISPATCH_DATA :: `
@prefix ex: <http://example.org/> .

ex:a a ex:C .
ex:one   ex:p ex:a .
ex:three ex:p ex:a ; ex:p ex:b ; ex:p ex:c .
`

// Every component in the spine's set, checked at once, so the two things that
// are easy to get backwards are visible side by side: which components are
// asked once per value node and which once about the whole set, and therefore
// which results carry an `sh:value`.
@(test)
test_constraint_dispatch :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, DISPATCH_SHAPES, DISPATCH_DATA) {
		return
	}
	seen: Seen
	defer seen_destroy(&seen)
	testing.expect_value(t, validate_into(&f, &seen), shacl.Failure.None)

	expect_results(
		t,
		&seen,
		[]string {
			// ex:one has one ex:p, ex:three has three; both miss `2`.
			"_:|MinCountConstraintComponent|one|-",
			"_:|MaxCountConstraintComponent|three|-",
			// ex:a is a literal-free IRI of class ex:C and is in the list, so
			// only the two it genuinely fails are reported.
			"ValuesP|DatatypeConstraintComponent|one|a",
			"ValuesP|HasValueConstraintComponent|one|-",
		},
		"dispatch",
	)
}

// ---- Absence: emptiness on a path, failure in a constraint ---------------

ABSENCE_SHAPES :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix ex: <http://example.org/> .

ex:S a sh:NodeShape ; sh:targetNode ex:n ;
	sh:property [ sh:path ex:p ; sh:class ex:NeverMentioned ] ;
	sh:property [ sh:path ex:never_mentioned ; sh:minCount 1 ] .
`

ABSENCE_DATA :: `
@prefix ex: <http://example.org/> .
ex:n ex:p ex:v .
`

// The initiative's asymmetry, asserted rather than assumed: a term the data
// store has never seen makes a *path* reach nothing and makes a *constraint*
// violate. Both appear here, and they point in opposite directions.
@(test)
test_absent_terms_mean_opposite_things :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, ABSENCE_SHAPES, ABSENCE_DATA) {
		return
	}
	seen: Seen
	defer seen_destroy(&seen)
	testing.expect_value(t, validate_into(&f, &seen), shacl.Failure.None)

	expect_results(
		t,
		&seen,
		[]string {
			// sh:class of a class nothing mentions: the value node violates.
			"_:|ClassConstraintComponent|n|v",
			// A path through a predicate nothing mentions: no value nodes, so
			// sh:minCount 1 fails — emptiness, not an error.
			"_:|MinCountConstraintComponent|n|-",
		},
		"absence",
	)
}

// ---- A focus node the data graph never mentions --------------------------

UNBOUND_SHAPES :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix ex: <http://example.org/> .

ex:S_node a sh:NodeShape ; sh:targetNode ex:absent ;
	sh:class ex:C ;
	sh:in ( ex:absent ) .

ex:S_prop a sh:NodeShape ; sh:targetNode ex:absent ;
	sh:property [ sh:path ex:p ; sh:minCount 1 ] .
`

UNBOUND_DATA :: `
@prefix ex: <http://example.org/> .
ex:something ex:p ex:other .
`

// `sh:targetNode` targets a node, not its appearances, so a term the data graph
// never mentions is still a focus node — and validating it is meaningful rather
// than vacuous. Unreachable from the W3C suite, where an entry's shapes and
// data are usually the same document and every target is therefore in the
// dictionary.
@(test)
test_unbound_focus_node_is_validated :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, UNBOUND_SHAPES, UNBOUND_DATA) {
		return
	}
	seen: Seen
	defer seen_destroy(&seen)
	testing.expect_value(t, validate_into(&f, &seen), shacl.Failure.None)

	expect_results(
		t,
		&seen,
		[]string {
			// A node shape's value node is its focus node, so the unbound term
			// is what the constraints see — sh:in compares terms and passes,
			// sh:class has no types to find and fails.
			"S_node|ClassConstraintComponent|?absent|?absent",
			// A path from a node with no triples reaches nothing.
			"_:|MinCountConstraintComponent|?absent|-",
		},
		"unbound focus",
	)
}

// ---- sh:deactivated ------------------------------------------------------

DEACTIVATED_SHAPES :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix ex: <http://example.org/> .

ex:Off a sh:NodeShape ; sh:targetNode ex:n ; sh:deactivated true ;
	sh:class ex:NeverMentioned ;
	sh:property ex:OffChild .
ex:OffChild a sh:PropertyShape ; sh:path ex:p ; sh:minCount 99 .

ex:OffProperty a sh:NodeShape ; sh:targetNode ex:n ;
	sh:property [ sh:path ex:p ; sh:deactivated true ; sh:minCount 99 ] .

ex:On a sh:NodeShape ; sh:targetNode ex:n ; sh:deactivated false ;
	sh:class ex:NeverMentioned .
`

DEACTIVATED_DATA :: `
@prefix ex: <http://example.org/> .
ex:n ex:p ex:v .
`

// A deactivated shape produces no results (§2.1.1.4) — and, less obviously,
// neither do its `sh:property` children, because they are reached only through
// it. `sh:deactivated false` is the control: it must change nothing.
@(test)
test_deactivated_shapes_are_silent :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, DEACTIVATED_SHAPES, DEACTIVATED_DATA) {
		return
	}
	seen: Seen
	defer seen_destroy(&seen)
	testing.expect_value(t, validate_into(&f, &seen), shacl.Failure.None)

	// ex:On is a node shape, so its value node is its focus node.
	expect_results(t, &seen, []string{"On|ClassConstraintComponent|n|n"}, "deactivated")
}

// ---- sh:severity ---------------------------------------------------------

SEVERITY_SHAPES :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix ex: <http://example.org/> .

ex:Warns a sh:NodeShape ; sh:targetNode ex:n ; sh:severity sh:Warning ;
	sh:class ex:NeverMentioned .
ex:Informs a sh:NodeShape ; sh:targetNode ex:n ; sh:severity sh:Info ;
	sh:class ex:NeverMentioned .
ex:Custom a sh:NodeShape ; sh:targetNode ex:n ; sh:severity ex:Catastrophe ;
	sh:class ex:NeverMentioned .
`

SEVERITY_DATA :: `
@prefix ex: <http://example.org/> .
ex:n ex:p ex:v .
`

// Severity reaches the result unchanged, **including one the SHACL vocabulary
// never heard of**. §2.1.4 names `sh:Violation`, `sh:Warning`, and `sh:Info` as
// the built-ins but does not close the set, and the suite depends on it:
// `misc/severity-002` declares `sh:severity ex:MySeverity` and expects it
// echoed into the report. So severity is an `rdf.Term`, not an enum — a
// three-valued type would reject that shapes graph at compile time.
//
// And severity has **no say in conformance** (§3.1): `sh:conforms` is true if
// and only if there are no results at all. The opposite reading is tempting —
// a warning sounds like it should not count — and `misc/severity-001` settles
// it, producing one `sh:Warning` result and expecting `sh:conforms false`.
@(test)
test_severity_is_any_iri_and_always_breaks_conformance :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, SEVERITY_SHAPES, SEVERITY_DATA) {
		return
	}

	Severities :: struct {
		warning, info, custom, other: int,
	}
	count :: proc(data: rawptr, result: shacl.Result) -> bool {
		c := cast(^Severities)data
		switch {
		case shacl.severity_is(result.severity, shacl.WARNING):
			c.warning += 1
		case shacl.severity_is(result.severity, shacl.INFO):
			c.info += 1
		case shacl.severity_is(result.severity, "http://example.org/Catastrophe"):
			c.custom += 1
		case:
			c.other += 1
		}
		return true
	}

	counts: Severities
	testing.expect_value(
		t,
		validate(&f.shapes, &f.bindings, &f.dictionary, &f.dataset, count, &counts),
		shacl.Failure.None,
	)
	testing.expect_value(t, counts.warning, 1)
	testing.expect_value(t, counts.info, 1)
	testing.expect_value(t, counts.custom, 1)
	testing.expect_value(t, counts.other, 0)

	got, failure := conforms(&f.shapes, &f.bindings, &f.dictionary, &f.dataset)
	testing.expect_value(t, failure, shacl.Failure.None)
	testing.expectf(t, !got, "any result at all makes a graph non-conforming (§3.1)")
}

// ---- Early exit ----------------------------------------------------------

EARLY_EXIT_SHAPES :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix ex: <http://example.org/> .

ex:S a sh:NodeShape ; sh:targetSubjectsOf ex:p ;
	sh:class ex:NeverMentioned .
`

EARLY_EXIT_DATA :: `
@prefix ex: <http://example.org/> .
ex:n1 ex:p ex:v . ex:n2 ex:p ex:v . ex:n3 ex:p ex:v .
ex:n4 ex:p ex:v . ex:n5 ex:p ex:v . ex:n6 ex:p ex:v .
`

// A visitor that returns false stops the traversal where it stands, rather than
// the engine finishing and the caller discarding the rest.
//
// The evidence is the count: six focus nodes each violate, and a run that
// stopped at the first delivers exactly one result. `Conformance` then agrees
// with the run that saw everything, which is the property that makes stopping
// safe to do.
@(test)
test_early_exit_stops_the_traversal :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, EARLY_EXIT_SHAPES, EARLY_EXIT_DATA) {
		return
	}

	all: Seen
	defer seen_destroy(&all)
	testing.expect_value(t, validate_into(&f, &all), shacl.Failure.None)
	testing.expect_value(t, len(all.lines), 6)

	stopped := Seen {
		stop_at = 1,
	}
	defer seen_destroy(&stopped)
	testing.expect_value(t, validate_into(&f, &stopped), shacl.Failure.None)
	testing.expect_value(t, len(stopped.lines), 1)

	got, failure := conforms(&f.shapes, &f.bindings, &f.dictionary, &f.dataset)
	testing.expect_value(t, failure, shacl.Failure.None)
	testing.expectf(t, !got, "a violating graph must not conform")
}

// ---- Recursion -----------------------------------------------------------

RECURSIVE_SHAPES :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix ex: <http://example.org/> .

ex:S a sh:PropertyShape ; sh:targetNode ex:a ;
	sh:path ex:p ;
	sh:property ex:S .
`

RECURSIVE_DATA :: `
@prefix ex: <http://example.org/> .
ex:a ex:p ex:b . ex:b ex:p ex:c . ex:c ex:p ex:a .
`

// A recursive shape is reported as a failure (§3.4), not hung on and not
// silently accepted — the decision SHACL-I-0001 recorded, and the one the
// explicit-stack evaluator makes free.
//
// The self-reference here goes through `sh:property` rather than `sh:node`,
// which is what the task named, because `sh:node` is a catalogue constraint the
// spine does not implement. The mechanism reached is identical: the shape is
// re-entered while already on the stack. That the data is cyclic is the point —
// without detection this does not terminate, so a test that finishes at all is
// already most of the assertion.
@(test)
test_recursive_shape_is_a_reported_failure :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, RECURSIVE_SHAPES, RECURSIVE_DATA) {
		return
	}
	seen: Seen
	defer seen_destroy(&seen)
	testing.expect_value(t, validate_into(&f, &seen), shacl.Failure.Recursive_Shape)

	// A failure is not a conformance answer, so nothing may be read from the
	// boolean — but the call must still return rather than run forever.
	_, failure := conforms(&f.shapes, &f.bindings, &f.dictionary, &f.dataset)
	testing.expect_value(t, failure, shacl.Failure.Recursive_Shape)
}

// A shape reached twice as a *sibling* is not recursion: the on-stack set is
// what is currently being validated, not what has ever been. Getting this wrong
// turns every reused property shape into a spurious failure.
@(test)
test_a_reused_shape_is_not_recursion :: proc(t: ^testing.T) {
	SHARED :: `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:A a sh:NodeShape ; sh:targetNode ex:n ; sh:property ex:Shared .
	ex:B a sh:NodeShape ; sh:targetNode ex:n ; sh:property ex:Shared .
	ex:Shared a sh:PropertyShape ; sh:path ex:p ; sh:minCount 5 .
	`
	DATA :: `
	@prefix ex: <http://example.org/> .
	ex:n ex:p ex:v .
	`
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, SHARED, DATA) {
		return
	}
	seen: Seen
	defer seen_destroy(&seen)
	testing.expect_value(t, validate_into(&f, &seen), shacl.Failure.None)
	expect_results(t, &seen, []string{"Shared|MinCountConstraintComponent|n|-", "Shared|MinCountConstraintComponent|n|-"}, "shared shape")
}

// ---- The report consumer -------------------------------------------------

// `sh:conforms` is emitted in both directions, and a conforming graph produces
// a report that is nothing but its head. The suite only ever compares
// non-conforming reports with results in them, so the empty one is asserted
// here.
@(test)
test_conforming_graph_reports_only_its_head :: proc(t: ^testing.T) {
	SHAPES :: `
	@prefix sh: <http://www.w3.org/ns/shacl#> .
	@prefix ex: <http://example.org/> .
	ex:S a sh:NodeShape ; sh:targetNode ex:n ; sh:property [ sh:path ex:p ; sh:minCount 1 ] .
	`
	DATA :: `
	@prefix ex: <http://example.org/> .
	ex:n ex:p ex:v .
	`
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, SHAPES, DATA) {
		return
	}

	report: shacl.Report
	shacl.report_init(&report)
	defer shacl.report_destroy(&report)

	testing.expect_value(
		t,
		validate_report(&report, &f.shapes, &f.bindings, &f.dictionary, &f.dataset),
		shacl.Failure.None,
	)
	testing.expect(t, shacl.report_conforms(&report))
	// rdf:type sh:ValidationReport, and sh:conforms true. Nothing else.
	testing.expect_value(t, len(shacl.report_triples(&report)), 2)
}

// ---- conforms_node: §3.4's question about one node and one shape ----------
//
// The public face of suppressed validation (SHACL-A-0002). The mechanism's own
// properties — that nothing leaks into a caller's stream, that an inner stop
// does not stop an outer traversal — are asserted in `shacl/suppress_test.odin`
// against a hand-built model, because they are about an in-flight `Validation`
// that no public entry point exposes. What is asserted here is that the entry
// point answers correctly over a real store, at both `Term_ID` widths, and that
// asking does not disturb an ordinary validation of the same model.

@(private = "file")
SUPPRESS_SHAPES :: PREFIX + `
# Targeted, so it is a root and an ordinary validation reports on it.
ex:Targeted a sh:NodeShape ; sh:targetNode ex:a ; sh:nodeKind sh:Literal .

# Not targeted: reachable only by naming it, which is what conforms_node is for.
ex:KindShape a sh:NodeShape ; sh:nodeKind sh:IRI .
ex:Nested a sh:NodeShape ;
	sh:property [ sh:path ex:p ; sh:minCount 1 ; sh:datatype xsd:string ] .
`

@(private = "file")
SUPPRESS_DATA :: PREFIX + `
ex:a ex:p "x" .
ex:b ex:q "y" .
`

@(private = "file")
shape_index :: proc(s: ^shacl.Shapes, iri: string) -> int {
	i, _ := shacl.shape_index_of(s, rdf.IRI(iri))
	return i
}

@(test)
test_conforms_node_answers_for_a_named_shape :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, SUPPRESS_SHAPES, SUPPRESS_DATA) {
		return
	}

	kind := shape_index(&f.shapes, "http://example.org/KindShape")
	nested := shape_index(&f.shapes, "http://example.org/Nested")
	if !testing.expect(t, kind >= 0 && nested >= 0, "fixture: both shapes must compile") {
		return
	}

	a := rdf.Term(rdf.IRI("http://example.org/a"))
	b := rdf.Term(rdf.IRI("http://example.org/b"))

	conforms, failure := conforms_node(&f.shapes, &f.bindings, &f.dictionary, &f.dataset, a, kind)
	testing.expect_value(t, failure, shacl.Failure.None)
	testing.expect(t, conforms, "ex:a is an IRI and satisfies sh:nodeKind sh:IRI")

	// The nested case: conformance counts the sh:property shapes below the
	// named shape, not only its own constraints. ex:a has an ex:p, ex:b does
	// not.
	conforms, failure = conforms_node(&f.shapes, &f.bindings, &f.dictionary, &f.dataset, a, nested)
	testing.expect_value(t, failure, shacl.Failure.None)
	testing.expect(t, conforms, "ex:a has one ex:p string value")

	conforms, failure = conforms_node(&f.shapes, &f.bindings, &f.dictionary, &f.dataset, b, nested)
	testing.expect_value(t, failure, shacl.Failure.None)
	testing.expect(t, !conforms, "ex:b has no ex:p at all, so sh:minCount 1 violates")

	// A node the data graph never mentions is still a focus node: unbound, and
	// its path reaches nothing, which is emptiness and violates the cardinality.
	absent := rdf.Term(rdf.IRI("http://example.org/never_mentioned"))
	conforms, failure = conforms_node(&f.shapes, &f.bindings, &f.dictionary, &f.dataset, absent, nested)
	testing.expect_value(t, failure, shacl.Failure.None)
	testing.expect(t, !conforms, "an absent node reaches nothing through ex:p")

	// An out-of-range index answers "does not conform" rather than reading
	// memory it has no business reading.
	conforms, failure = conforms_node(&f.shapes, &f.bindings, &f.dictionary, &f.dataset, a, len(f.shapes.shapes))
	testing.expect_value(t, failure, shacl.Failure.None)
	testing.expect(t, !conforms, "an out-of-range shape index is not a conformance")
}

// Asking does not disturb: an ordinary validation of the same model produces
// exactly the same results before and after a suppressed run, and the
// suppressed runs contribute none of their own.
@(test)
test_conforms_node_does_not_disturb_a_validation :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, SUPPRESS_SHAPES, SUPPRESS_DATA) {
		return
	}

	nested := shape_index(&f.shapes, "http://example.org/Nested")
	b := rdf.Term(rdf.IRI("http://example.org/b"))

	before: Seen
	before.fixture = &f
	defer seen_destroy(&before)
	testing.expect_value(
		t,
		validate(&f.shapes, &f.bindings, &f.dictionary, &f.dataset, record, &before),
		shacl.Failure.None,
	)

	// This produces results internally — ex:b fails the nested shape — and none
	// of them may show up anywhere.
	conforms, failure := conforms_node(&f.shapes, &f.bindings, &f.dictionary, &f.dataset, b, nested)
	testing.expect_value(t, failure, shacl.Failure.None)
	testing.expect(t, !conforms, "fixture: ex:b must fail the nested shape")

	after: Seen
	after.fixture = &f
	defer seen_destroy(&after)
	testing.expect_value(
		t,
		validate(&f.shapes, &f.bindings, &f.dictionary, &f.dataset, record, &after),
		shacl.Failure.None,
	)

	if !testing.expect_value(t, len(after.lines), len(before.lines)) {
		return
	}
	for line, i in after.lines {
		testing.expect_value(t, line, before.lines[i])
	}
	// One result, from the one targeted shape: ex:a is an IRI, not a literal.
	testing.expect_value(t, len(after.lines), 1)
	testing.expect_value(t, after.lines[0], "Targeted|NodeKindConstraintComponent|a|a")
}

@(private = "file")
RECURSIVE_SHAPES :: PREFIX + `
ex:P a sh:PropertyShape ; sh:targetNode ex:a ; sh:path ex:p ; sh:property ex:P .
`

// A shape that reaches itself is a failure, and the suppressed entry point
// reports it as one rather than answering a conformance it never established.
// The boolean is meaningless when the Failure is set — this is the test that
// says so out loud.
@(test)
test_conforms_node_reports_recursion_as_a_failure :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, RECURSIVE_SHAPES, SUPPRESS_DATA) {
		return
	}

	p := shape_index(&f.shapes, "http://example.org/P")
	if !testing.expect(t, p >= 0, "fixture: ex:P must compile") {
		return
	}
	a := rdf.Term(rdf.IRI("http://example.org/a"))

	_, failure := conforms_node(&f.shapes, &f.bindings, &f.dictionary, &f.dataset, a, p)
	testing.expect_value(t, failure, shacl.Failure.Recursive_Shape)
}

// ---- The value-range components (SHACL-T-0013) ---------------------------

@(private = "file")
RANGE_SHAPES :: PREFIX + `
ex:MinIncl a sh:NodeShape ; sh:targetNode 3, 4, 5 ; sh:minInclusive 4 .
ex:MaxIncl a sh:NodeShape ; sh:targetNode 3, 4, 5 ; sh:maxInclusive 4 .
ex:MinExcl a sh:NodeShape ; sh:targetNode 3, 4, 5 ; sh:minExclusive 4 .
ex:MaxExcl a sh:NodeShape ; sh:targetNode 3, 4, 5 ; sh:maxExclusive 4 .
`

@(private = "file")
RANGE_DATA :: PREFIX + `
ex:unused ex:p ex:q .
`

// All four bounds against the same three nodes, so the difference between them
// is one column of the expectation rather than four separate tests: inclusive
// and exclusive differ only at the bound itself, and that is the boundary a
// `<=` written as `<` moves.
//
// Every result names the node it blames, which is the value scope asserted
// rather than assumed — a set-scoped component would report once per shape with
// no `sh:value`, and the last column would read `-`.
//
// The `?` prefix is not noise: these focus nodes are named by `sh:targetNode`
// and appear nowhere in the data graph, so they are **unbound** and reach the
// comparison as terms rather than through the store's dictionary. That is the
// half of the path the suite cannot reach — an entry's shapes and data are the
// same document, so everything in it is bound — and it is the half where a
// value has to be decoded from a term the store has never interned.
@(test)
test_value_range_boundaries :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, RANGE_SHAPES, RANGE_DATA) {
		return
	}
	seen: Seen
	defer seen_destroy(&seen)
	testing.expect_value(t, validate_into(&f, &seen), shacl.Failure.None)

	expect_results(
		t,
		&seen,
		[]string {
			"MinIncl|MinInclusiveConstraintComponent|?\"3\"|?\"3\"",
			"MaxIncl|MaxInclusiveConstraintComponent|?\"5\"|?\"5\"",
			// The exclusive pair adds the bound itself, and only that.
			"MinExcl|MinExclusiveConstraintComponent|?\"3\"|?\"3\"",
			"MinExcl|MinExclusiveConstraintComponent|?\"4\"|?\"4\"",
			"MaxExcl|MaxExclusiveConstraintComponent|?\"4\"|?\"4\"",
			"MaxExcl|MaxExclusiveConstraintComponent|?\"5\"|?\"5\"",
		},
		"value ranges at the boundary",
	)
}

@(private = "file")
COMPARE_SHAPES :: PREFIX + `
ex:Compare a sh:NodeShape ; sh:minInclusive 4 ;
	sh:targetNode 4.0 ;                  # a decimal equal to an integer bound
	sh:targetNode "12"^^xsd:byte ;       # a derived integer above it
	sh:targetNode ex:John ;              # an IRI has no value
	sh:targetNode "Hello" ;              # a string has no order against a number
	sh:targetNode "abc"^^xsd:integer .   # ill-formed, so also no value

# A bound that is not a value either. Nothing can be shown to be in range, so
# nothing is.
ex:NoBound a sh:NodeShape ; sh:targetNode 4 ; sh:minInclusive ex:NotANumber .
`

// The two halves of "compares values, not terms", in one fixture.
//
// The first is that a bound is met by a different term denoting the same or a
// greater number — `"4.0"^^xsd:decimal` and `"12"^^xsd:byte` both satisfy
// `sh:minInclusive 4`, and term equality would have failed both.
//
// The second is that everything the comparison *cannot* place violates:
// §4.6.2's condition is that the comparison holds, and one that could not be
// made does not hold. It applies to a value node with no value and equally to a
// bound with none, which is the case the suite never exercises.
@(test)
test_value_range_incomparable_violates :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, COMPARE_SHAPES, RANGE_DATA) {
		return
	}
	seen: Seen
	defer seen_destroy(&seen)
	testing.expect_value(t, validate_into(&f, &seen), shacl.Failure.None)

	expect_results(
		t,
		&seen,
		[]string {
			"Compare|MinInclusiveConstraintComponent|?John|?John",
			"Compare|MinInclusiveConstraintComponent|?\"Hello\"|?\"Hello\"",
			"Compare|MinInclusiveConstraintComponent|?\"abc\"|?\"abc\"",
			"NoBound|MinInclusiveConstraintComponent|?\"4\"|?\"4\"",
		},
		"incomparable violates",
	)
}

// ---- The string components (SHACL-T-0014) --------------------------------

@(private = "file")
STRING_SHAPES :: PREFIX + `
# §4.5 asks all three of these for the value node's *string*, and the answer is
# not the same shape as "the lexical form": an IRI contributes itself, a blank
# node contributes nothing.
ex:Length a sh:NodeShape ; sh:minLength 4 ; sh:maxLength 5 ;
	sh:targetNode <a:b> ;                 # an IRI, three characters
	sh:targetNode <a:bcde> ;              # an IRI, six
	sh:targetNode "Hell" ;
	sh:targetNode "Hel" ;
	sh:targetNode "Hello!" ;
	sh:targetNode "2017-03-29"^^xsd:date ;  # ten characters of lexical form
	sh:targetNode "Hell"@en .

ex:Blank a sh:NodeShape ; sh:minLength 0 ; sh:targetNode ex:hasBlank ;
	sh:property [ sh:path ex:p ; sh:minLength 0 ] .

# Length counts code points, not bytes: "æøå" is three characters and six bytes.
ex:Runes a sh:NodeShape ; sh:maxLength 3 ; sh:targetNode "æøå" .
`

@(private = "file")
STRING_DATA :: PREFIX + `
ex:hasBlank ex:p [ ex:q "irrelevant" ] .
`

// What §4.5 means by a value node's string, which is the part of these three
// components that is not obvious.
//
// A blank node has no string and so violates **even `sh:minLength 0`**, which
// every other reading would make vacuously true — that is the case worth a test,
// because an implementation that reached for the lexical form and defaulted to
// "" would pass every other assertion here and fail only this one.
@(test)
test_string_length_over_nodes_that_are_not_literals :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, STRING_SHAPES, STRING_DATA) {
		return
	}
	seen: Seen
	defer seen_destroy(&seen)
	testing.expect_value(t, validate_into(&f, &seen), shacl.Failure.None)

	expect_results(
		t,
		&seen,
		[]string {
			// <a:b> is three characters of IRI, so it is too short; <a:bcde> is
			// six, so it is too long. Neither is a literal.
			"Length|MinLengthConstraintComponent|?a:b|?a:b",
			"Length|MaxLengthConstraintComponent|?a:bcde|?a:bcde",
			"Length|MinLengthConstraintComponent|?\"Hel\"|?\"Hel\"",
			"Length|MaxLengthConstraintComponent|?\"Hello!\"|?\"Hello!\"",
			// A date's lexical form is ten characters; the tag on "Hell"@en is
			// not part of its string, so it passes at four.
			"Length|MaxLengthConstraintComponent|?\"2017-03-29\"|?\"2017-03-29\"",
			// The blank node reached by ex:p, against a bound of zero.
			"_:|MinLengthConstraintComponent|hasBlank|_:",
		},
		"string length",
	)
}

@(private = "file")
PATTERN_SHAPES :: PREFIX + `
ex:Anchored a sh:NodeShape ; sh:pattern "^[2-8][0-9]*$" ;
	sh:targetNode 42 ; sh:targetNode 9 ; sh:targetNode "3456" ; sh:targetNode ex:Test .

# Unanchored, so this is a search rather than a full match — which is what
# XPath's fn:matches does and what property/pattern-001 depends on.
ex:Contains a sh:NodeShape ; sh:pattern "Joh" ;
	sh:targetNode "John Doe" ; sh:targetNode "john doe" .

ex:Insensitive a sh:NodeShape ; sh:pattern "joh" ; sh:flags "i" ;
	sh:targetNode "John Doe" ; sh:targetNode "john doe" ; sh:targetNode "Jane" .
`

// sh:pattern, including the two things about it that are easy to get wrong: it
// searches rather than matching the whole string, and `sh:flags` is one
// parameter for the shape rather than one per pattern.
@(test)
test_pattern_searches_and_honours_flags :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, PATTERN_SHAPES, STRING_DATA) {
		return
	}
	seen: Seen
	defer seen_destroy(&seen)
	testing.expect_value(t, validate_into(&f, &seen), shacl.Failure.None)

	expect_results(
		t,
		&seen,
		[]string {
			"Anchored|PatternConstraintComponent|?\"9\"|?\"9\"",
			// An IRI is matched on the IRI, which no anchored numeric pattern fits.
			"Anchored|PatternConstraintComponent|?Test|?Test",
			"Contains|PatternConstraintComponent|?\"john doe\"|?\"john doe\"",
			"Insensitive|PatternConstraintComponent|?\"Jane\"|?\"Jane\"",
		},
		"pattern",
	)
}

// An `sh:flags` letter this engine's regex package does not have is an
// ill-formed shapes graph, not a silent downgrade.
//
// This is the whole reason the divergence is worth documenting: `s` is a legal
// XPath flag and SHACL defines `sh:pattern` by XPath, so a shapes graph is
// entitled to use it. Ignoring it would validate against a *different* pattern
// than the one that was written and then report conformance.
@(test)
test_an_unsupported_flag_is_an_error :: proc(t: ^testing.T) {
	f: Fixture
	defer shacl.shapes_destroy(&f.shapes)
	source := PREFIX + `ex:S a sh:NodeShape ; sh:targetNode ex:n ; sh:pattern "a.b" ; sh:flags "s" .`

	dictionary: memstore.Dictionary
	memstore.dictionary_init(&dictionary)
	defer memstore.dictionary_destroy(&dictionary)
	dataset: memstore.Dataset
	memstore.dataset_init(&dataset)
	defer memstore.dataset_destroy(&dataset)
	_, load_err := memstore.load_turtle(&dictionary, &dataset, transmute([]byte)source)
	if !testing.expectf(t, load_err.message == "", "fixture did not parse: %s", load_err.message) {
		return
	}

	err := compile(&f.shapes, &dictionary, &dataset)
	testing.expect_value(t, err.kind, shacl.Error_Kind.Flags_Unsupported)
}

@(private = "file")
LANGUAGE_SHAPES :: PREFIX + `
ex:Langs a sh:NodeShape ; sh:languageIn ( "en" "mi" ) ;
	sh:targetNode "Hill"@en-NZ ;      # basic filtering: a range matches a longer tag
	sh:targetNode "Mountain"@EN ;     # and does so case-insensitively
	sh:targetNode "Maunga"@mi ;
	sh:targetNode "Berg"@de ;
	sh:targetNode "Plain" ;           # no tag at all
	sh:targetNode ex:NotALiteral ;
	sh:targetNode "english"@english . # a prefix, but not at a subtag boundary

ex:Unique a sh:NodeShape ; sh:targetNode ex:one, ex:two, ex:three ;
	sh:property [ sh:path ex:p ; sh:uniqueLang true ] .

# §4.5.5 is a property-shape component; on a node shape it asks nothing.
ex:UniqueOnANodeShape a sh:NodeShape ; sh:targetNode ex:one ; sh:uniqueLang true .
`

@(private = "file")
LANGUAGE_DATA :: PREFIX + `
ex:one   ex:p "Me"@en , "Myself"@en , "Moi"@fr , "untagged" .
ex:two   ex:p "I"@en , "Ich"@de , "Me"@EN , "Mich"@de , "Myself"@en .
ex:three ex:p "Me"@en , "Moi"@fr , "untagged" , "also untagged" .
`

// sh:languageIn's RFC 4647 basic filtering and sh:uniqueLang's set scope, in one
// fixture because they are the two components that read a language tag.
//
// **Neither can fire the family's language-tag trigger**, and this fixture is
// where that is demonstrated rather than asserted in prose: `@EN` appears on
// both sides — matched against the range `en`, and counted as a duplicate of
// `@en` — and both comparisons are case-insensitive by specification (RFC 4647
// for the range, RDF Concepts for tag identity). There is no comparison here
// whose answer depends on whether the parser folded the tag's case.
@(test)
test_language_in_and_unique_lang :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, LANGUAGE_SHAPES, LANGUAGE_DATA) {
		return
	}
	seen: Seen
	defer seen_destroy(&seen)
	testing.expect_value(t, validate_into(&f, &seen), shacl.Failure.None)

	expect_results(
		t,
		&seen,
		[]string {
			"Langs|LanguageInConstraintComponent|?\"Berg\"|?\"Berg\"",
			"Langs|LanguageInConstraintComponent|?\"Plain\"|?\"Plain\"",
			"Langs|LanguageInConstraintComponent|?NotALiteral|?NotALiteral",
			// "en" is a prefix of "english" and not a subtag of it.
			"Langs|LanguageInConstraintComponent|?\"english\"|?\"english\"",
			// ex:one repeats @en once; ex:two repeats @en (three times, one
			// result) and @de (twice, one result); ex:three repeats nothing.
			// No result carries an sh:value: the fault is that two nodes agree.
			"_:|UniqueLangConstraintComponent|one|-",
			"_:|UniqueLangConstraintComponent|two|-",
			"_:|UniqueLangConstraintComponent|two|-",
		},
		"languageIn and uniqueLang",
	)
}

// `sh:uniqueLang "1"^^xsd:boolean` does not switch the component on, though "1"
// is the same *value* as "true".
//
// §4.5.5 names the value `true`, and `property/uniqueLang-002` exists to pin
// exactly this: it declares the "1" form over two `@en` literals and expects a
// conforming report, with a comment in the corpus saying why. It is the one
// place in this engine where a boolean parameter is read as a term rather than
// a value, and it would otherwise look like an oversight.
@(test)
test_unique_lang_is_switched_on_by_the_term_true :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	shapes := PREFIX + `
	ex:S a sh:NodeShape ; sh:targetNode ex:one ;
		sh:property [ sh:path ex:p ; sh:uniqueLang "1"^^xsd:boolean ] .
	`
	if !fixture_init(t, &f, shapes, LANGUAGE_DATA) {
		return
	}
	seen: Seen
	defer seen_destroy(&seen)
	testing.expect_value(t, validate_into(&f, &seen), shacl.Failure.None)
	expect_results(t, &seen, []string{}, "uniqueLang \"1\" is not true")
}

// ---- The property-pair components (SHACL-T-0015) -------------------------

@(private = "file")
PAIR_SHAPES :: PREFIX + `
# A node shape: the value-node set is the focus node itself, compared against
# the values of ex:q at that same node.
ex:NodeEquals a sh:NodeShape ; sh:equals ex:q ;
	sh:targetNode ex:same, ex:extra, ex:none .

ex:PropEquals a sh:NodeShape ; sh:targetNode ex:pairs ;
	sh:property [ sh:path ex:p ; sh:equals ex:q ] .

ex:PropDisjoint a sh:NodeShape ; sh:targetNode ex:pairs ;
	sh:property [ sh:path ex:p ; sh:disjoint ex:q ] .

# The parameter names a predicate the data graph never mentions, so the second
# set is empty rather than unknown.
ex:MissingPredicate a sh:NodeShape ; sh:targetNode ex:pairs ;
	sh:property [ sh:path ex:p ; sh:equals ex:never_mentioned ] .
`

@(private = "file")
PAIR_DATA :: PREFIX + `
ex:same  ex:q ex:same .
ex:extra ex:q ex:extra ; ex:q ex:other .
# ex:none has no ex:q at all.
ex:none  ex:unrelated ex:x .

ex:pairs ex:p "A" ; ex:p "B" ; ex:q "B" ; ex:q "C" .
`

// sh:equals and sh:disjoint, and the thing about them that breaks the seam's
// old rule: a set-scoped component whose results name a node.
//
// The `sh:equals` results include **`ex:other` and `"C"`, which are not value
// nodes** — they are members of the other predicate's set, reported because the
// symmetric difference runs in both directions. An implementation that only
// walked the value nodes would produce a strict subset of this and look right.
@(test)
test_property_pair_equality :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, PAIR_SHAPES, PAIR_DATA) {
		return
	}
	seen: Seen
	defer seen_destroy(&seen)
	testing.expect_value(t, validate_into(&f, &seen), shacl.Failure.None)

	expect_results(
		t,
		&seen,
		[]string {
			// ex:same equals its own ex:q, so nothing. ex:extra has one extra.
			"NodeEquals|EqualsConstraintComponent|extra|other",
			// ex:none has no ex:q, so the focus node itself is the difference.
			"NodeEquals|EqualsConstraintComponent|none|none",
			// {"A","B"} against {"B","C"}: "A" is only a value node, "C" is only
			// in the other set, and both are reported.
			"_:|EqualsConstraintComponent|pairs|\"A\"",
			"_:|EqualsConstraintComponent|pairs|\"C\"",
			// Disjointness fails on the shared "B", and on nothing else.
			"_:|DisjointConstraintComponent|pairs|\"B\"",
			// An absent predicate is an empty set, so every value node differs.
			"_:|EqualsConstraintComponent|pairs|\"A\"",
			"_:|EqualsConstraintComponent|pairs|\"B\"",
		},
		"equals and disjoint",
	)
}

@(private = "file")
ORDER_SHAPES :: PREFIX + `
ex:Order a sh:NodeShape ; sh:targetNode ex:ok, ex:bad, ex:mixed ;
	sh:property [ sh:path ex:p ; sh:lessThan ex:q ] ;
	sh:property [ sh:path ex:p ; sh:lessThanOrEquals ex:q ] .

# §4.7.3: a node shape may not use the ordering pair, so this asks nothing.
ex:OrderOnANodeShape a sh:NodeShape ; sh:targetNode ex:bad ; sh:lessThan ex:q .
`

@(private = "file")
ORDER_DATA :: PREFIX + `
ex:ok    ex:p 1 ; ex:q 2 .
ex:bad   ex:p 2 ; ex:q 2 .
ex:mixed ex:p 1 ; ex:p 2 ; ex:q "a" ; ex:q "b" .
`

// The ordering pair: value comparison, one result per **failing pair**, and the
// property-shape restriction.
//
// ex:mixed is the shape of `property/lessThan-002` — two numbers against two
// strings, every pair incomparable — and it is what makes the per-pair rule
// visible: four results from two value nodes, with each `sh:value` repeated. A
// per-value-node loop that stopped at the first failure would produce two.
@(test)
test_property_pair_ordering :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, ORDER_SHAPES, ORDER_DATA) {
		return
	}
	seen: Seen
	defer seen_destroy(&seen)
	testing.expect_value(t, validate_into(&f, &seen), shacl.Failure.None)

	expect_results(
		t,
		&seen,
		[]string {
			// ex:ok: 1 < 2 and 1 <= 2, so nothing.
			// ex:bad: 2 < 2 is false; 2 <= 2 holds, so only lessThan reports.
			"_:|LessThanConstraintComponent|bad|\"2\"",
			// ex:mixed: numbers against strings are incomparable, so every pair
			// fails for both components — four results each.
			"_:|LessThanConstraintComponent|mixed|\"1\"",
			"_:|LessThanConstraintComponent|mixed|\"1\"",
			"_:|LessThanConstraintComponent|mixed|\"2\"",
			"_:|LessThanConstraintComponent|mixed|\"2\"",
			"_:|LessThanOrEqualsConstraintComponent|mixed|\"1\"",
			"_:|LessThanOrEqualsConstraintComponent|mixed|\"1\"",
			"_:|LessThanOrEqualsConstraintComponent|mixed|\"2\"",
			"_:|LessThanOrEqualsConstraintComponent|mixed|\"2\"",
		},
		"lessThan and lessThanOrEquals",
	)
}

@(private = "file")
CLOSED_SHAPES :: PREFIX + `
@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .

# The shape of node/closed-001: rdf:type is an ordinary predicate and is
# reported like any other.
ex:Closed a sh:NodeShape ; sh:targetNode ex:strict ; sh:closed true ;
	sh:property [ sh:path ex:allowed ] .

# The shape of node/closed-002: the same data, one predicate ignored.
ex:ClosedIgnoring a sh:NodeShape ; sh:targetNode ex:ignoring ; sh:closed true ;
	sh:ignoredProperties ( rdf:type ) ;
	sh:property [ sh:path ex:allowed ] .

# A property shape whose path is compound declares no predicate at all, so this
# shape allows nothing. core/complex's personexample.ttl is the corpus instance.
ex:ClosedCompound a sh:NodeShape ; sh:targetNode ex:compound ; sh:closed true ;
	sh:property [ sh:path [ sh:inversePath ex:parent ] ] .

# sh:closed false switches the component off rather than configuring it.
ex:NotClosed a sh:NodeShape ; sh:targetNode ex:open ; sh:closed false .

# sh:closed at a *property* shape: the subjects are its value nodes, and the
# focus node the results name is still ex:owner.
ex:ClosedOnProperty a sh:NodeShape ; sh:targetNode ex:owner ;
	sh:property [ sh:path ex:child ; sh:closed true ;
		sh:property [ sh:path ex:allowed ] ] .
`

@(private = "file")
CLOSED_DATA :: PREFIX + `
ex:strict   a ex:C ; ex:allowed 1 ; ex:extra 2 .
ex:ignoring a ex:C ; ex:allowed 1 ; ex:extra 2 .
ex:compound   ex:allowed 1 .
ex:open       ex:anything 1 ; ex:whatever 2 .
ex:owner      ex:child ex:kid .
ex:kid        ex:allowed 1 ; ex:extra 2 .
`

// sh:closed and sh:ignoredProperties (§4.8.1) — the component that asks the
// data graph which predicates a node actually uses.
//
// Five things, of which the suite measures only the first two:
//
//   - **rdf:type is not ignored by default.** ex:strict reports it, exactly as
//     `node/closed-001` expects, and ex:ignoring does not, exactly as
//     `closed-002` expects. Assuming otherwise is the obvious mistake, and it
//     would still pass `closed-002`.
//   - **The result names the triple, not the shape.** `sh:resultPath` is the
//     offending predicate and `sh:value` its object — the fifth field below —
//     and every one of these is on a node shape, whose own path is -1.
//   - **A compound path declares nothing.** ex:ClosedCompound's only property
//     shape is an inverse path, which is a blank node in the shapes graph and
//     can never equal a triple's predicate, so ex:compound's one triple
//     violates. No enabled entry reaches this; `core/complex` has the case.
//   - **`sh:closed false` compiles to no constraint**, so ex:open reports
//     nothing despite using two undeclared predicates.
//   - **It is scoped to value nodes, not focus nodes.** ex:ClosedOnProperty
//     closes a *property* shape, so the node inspected is ex:kid while the node
//     blamed is ex:owner. The two coincide on every node shape, which is every
//     entry the corpus has, so this is the spec's wording pinned rather than the
//     suite's.
@(test)
test_closed :: proc(t: ^testing.T) {
	f: Fixture
	defer fixture_destroy(&f)
	if !fixture_init(t, &f, CLOSED_SHAPES, CLOSED_DATA) {
		return
	}
	seen: Seen
	defer seen_destroy(&seen)
	testing.expect_value(t, validate_into(&f, &seen), shacl.Failure.None)

	expect_results(
		t,
		&seen,
		[]string {
			"Closed|ClosedConstraintComponent|strict|C|type",
			"Closed|ClosedConstraintComponent|strict|\"2\"|extra",
			"ClosedIgnoring|ClosedConstraintComponent|ignoring|\"2\"|extra",
			"ClosedCompound|ClosedConstraintComponent|compound|\"1\"|allowed",
			"_:|ClosedConstraintComponent|owner|\"2\"|extra",
		},
		"closed and ignoredProperties",
	)
}
