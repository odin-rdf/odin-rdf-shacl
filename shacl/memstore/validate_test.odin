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
