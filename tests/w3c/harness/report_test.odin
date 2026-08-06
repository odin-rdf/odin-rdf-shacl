package w3c

import "core:strings"
import "core:testing"

import rdf "rdf:rdf"
import triples "rdf:rdf/triples"
import turtle "rdf:rdf/turtle"
import memstore "store:store/memstore"

import shacl "../../../shacl"
import shacl_memstore "../../../shacl/memstore"

// Report-graph tests live in the harness package because this is where the
// blank-node isomorphism comparison lives, and comparing a produced report to
// a hand-written expected one is exactly what the suite runner will do in
// SHACL-T-0007. Writing them here closes the loop between emitter and
// comparison before any suite entry depends on both.
//
// There is no validator yet, so results are constructed by hand. That is the
// point rather than a limitation: it pins the report shape independently of
// whatever produces the results.

REPORT_SHAPES :: `
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix ex: <http://example.org/> .

ex:PersonShape a sh:NodeShape ;
	sh:targetNode ex:alice ;
	sh:property ex:EmailShape .

ex:EmailShape a sh:PropertyShape ;
	sh:path ex:email ;
	sh:minCount 1 ;
	sh:message "needs an email"@en .

ex:InverseShape a sh:PropertyShape ;
	sh:path [ sh:inversePath ex:child ] ;
	sh:minCount 2 .

ex:SequenceShape a sh:PropertyShape ;
	sh:path ( ex:a ex:b ) ;
	sh:minCount 1 .

ex:AltShape a sh:PropertyShape ;
	sh:path [ sh:alternativePath ( ex:a ex:b ) ] ;
	sh:minCount 1 .

ex:QuietShape a sh:PropertyShape ;
	sh:path ex:quiet ;
	sh:minCount 1 .

ex:alice ex:name "Alice" .
`

@(private = "file")
Fixture :: struct {
	dictionary: memstore.Dictionary,
	dataset:    memstore.Dataset,
	shapes:     shacl.Shapes,
}

@(private = "file")
fixture_init :: proc(t: ^testing.T, f: ^Fixture) -> bool {
	memstore.dictionary_init(&f.dictionary)
	memstore.dataset_init(&f.dataset)
	_, load_err := memstore.load_turtle(&f.dictionary, &f.dataset, transmute([]byte)string(REPORT_SHAPES))
	if !testing.expectf(t, load_err.message == "", "load: %s", load_err.message) {
		return false
	}
	err := shacl_memstore.compile(&f.shapes, &f.dictionary, &f.dataset)
	return testing.expectf(t, err.kind == .None, "compile: %s", shacl.error_message(err.kind))
}

@(private = "file")
fixture_destroy :: proc(f: ^Fixture) {
	shacl.shapes_destroy(&f.shapes)
	memstore.dataset_destroy(&f.dataset)
	memstore.dictionary_destroy(&f.dictionary)
}

@(private = "file")
shape_index :: proc(f: ^Fixture, iri: string) -> int {
	for sh, i in f.shapes.shapes {
		if got, is_iri := sh.node.(rdf.IRI); is_iri && string(got) == iri {
			return i
		}
	}
	return -1
}

@(private = "file")
term_id :: proc(f: ^Fixture, iri: string) -> shacl.Node_Ref {
	id, found := memstore.find_term(&f.dictionary, rdf.IRI(iri))
	return shacl.Node_Ref{id = id, bound = found}
}

@(private = "file")
parse_expected :: proc(source: string) -> [dynamic]rdf.Triple {
	out := make([dynamic]rdf.Triple)
	p: turtle.Parser
	turtle.parser_init(&p, transmute([]byte)source, "https://report.invalid/")
	defer turtle.parser_destroy(&p)
	for {
		tr, ok := turtle.parser_next(&p)
		if !ok {
			break
		}
		append(&out, rdf.clone_triple(tr))
	}
	return out
}

@(private = "file")
destroy_graph :: proc(g: ^[dynamic]rdf.Triple) {
	for tr in g {
		rdf.destroy_triple(tr)
	}
	delete(g^)
}

EX_R :: "http://example.org/"

// A whole report, compared against a hand-written expected graph by
// isomorphism — including the declared message, which is the only message the
// report may carry.
@(test)
test_report_matches_expected_graph :: proc(t: ^testing.T) {
	f: Fixture
	if !fixture_init(t, &f) {
		fixture_destroy(&f)
		return
	}
	defer fixture_destroy(&f)

	email := shape_index(&f, EX_R + "EmailShape")
	if !testing.expect(t, email >= 0, "ex:EmailShape not compiled") {
		return
	}

	r: shacl.Report
	shacl.report_init(&r)
	defer shacl.report_destroy(&r)

	shacl_memstore.report_add(
		&r,
		&f.shapes,
		shacl.Result {
			focus = term_id(&f, EX_R + "alice"),
			path = f.shapes.shapes[email].path,
			shape = email,
			component = .Min_Count,
			severity = .Violation,
		},
		&f.dictionary,
	)
	shacl.report_finish(&r)

	expected := parse_expected(
		`@prefix sh: <http://www.w3.org/ns/shacl#> .
		 @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
		 @prefix ex: <http://example.org/> .
		 [] a sh:ValidationReport ;
			sh:conforms "false"^^xsd:boolean ;
			sh:result [
				a sh:ValidationResult ;
				sh:focusNode ex:alice ;
				sh:resultPath ex:email ;
				sh:resultSeverity sh:Violation ;
				sh:sourceConstraintComponent sh:MinCountConstraintComponent ;
				sh:sourceShape ex:EmailShape ;
				sh:message "needs an email"@en ;
			] .`,
	)
	defer destroy_graph(&expected)

	testing.expect(
		t,
		report_isomorphic(shacl.report_triples(&r), expected[:]),
		"the produced report is not isomorphic to the expected one",
	)
}

// sh:conforms is only knowable when the stream has drained, which is why the
// head trails the results. Both directions, because a report that always says
// false would pass the test above.
@(test)
test_conforms_both_directions :: proc(t: ^testing.T) {
	f: Fixture
	if !fixture_init(t, &f) {
		fixture_destroy(&f)
		return
	}
	defer fixture_destroy(&f)
	email := shape_index(&f, EX_R + "EmailShape")

	// No results at all: conforms.
	{
		r: shacl.Report
		shacl.report_init(&r)
		defer shacl.report_destroy(&r)
		shacl.report_finish(&r)
		testing.expect(t, shacl.report_conforms(&r), "an empty report should conform")

		expected := parse_expected(
			`@prefix sh: <http://www.w3.org/ns/shacl#> .
			 @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
			 [] a sh:ValidationReport ; sh:conforms "true"^^xsd:boolean .`,
		)
		defer destroy_graph(&expected)
		testing.expect(
			t,
			report_isomorphic(shacl.report_triples(&r), expected[:]),
			"empty report graph mismatch",
		)
	}

	// A warning does *not* break conformance — only sh:Violation does
	// (§3.1.2), which is easy to get wrong and changes what an early-exit
	// caller may stop on.
	{
		r: shacl.Report
		shacl.report_init(&r)
		defer shacl.report_destroy(&r)
		shacl_memstore.report_add(
			&r,
			&f.shapes,
			shacl.Result {
				focus = term_id(&f, EX_R + "alice"),
				path = f.shapes.shapes[email].path,
				shape = email,
				component = .Min_Count,
				severity = .Warning,
			},
			&f.dictionary,
		)
		shacl.report_finish(&r)
		testing.expect(t, shacl.report_conforms(&r), "a warning must not break conformance")
	}

	// A violation does.
	{
		r: shacl.Report
		shacl.report_init(&r)
		defer shacl.report_destroy(&r)
		shacl_memstore.report_add(
			&r,
			&f.shapes,
			shacl.Result {
				focus = term_id(&f, EX_R + "alice"),
				path = f.shapes.shapes[email].path,
				shape = email,
				component = .Min_Count,
				severity = .Violation,
			},
			&f.dictionary,
		)
		shacl.report_finish(&r)
		testing.expect(t, !shacl.report_conforms(&r), "a violation must break conformance")
	}
}

// Complex paths serialise back into RDF structures, which is why report
// comparison has to be isomorphism rather than a label match. Each of these
// contributes blank nodes and, for the list forms, a whole RDF list.
@(test)
test_result_path_serialisation :: proc(t: ^testing.T) {
	f: Fixture
	if !fixture_init(t, &f) {
		fixture_destroy(&f)
		return
	}
	defer fixture_destroy(&f)

	Case :: struct {
		shape:    string,
		expected: string,
	}
	cases := []Case {
		{"InverseShape", "sh:resultPath [ sh:inversePath ex:child ]"},
		{"SequenceShape", "sh:resultPath ( ex:a ex:b )"},
		{"AltShape", "sh:resultPath [ sh:alternativePath ( ex:a ex:b ) ]"},
	}

	for c in cases {
		index := shape_index(&f, strings.concatenate({EX_R, c.shape}, context.temp_allocator))
		if !testing.expectf(t, index >= 0, "%s not compiled", c.shape) {
			continue
		}

		r: shacl.Report
		shacl.report_init(&r)
		defer shacl.report_destroy(&r)
		shacl_memstore.report_add(
			&r,
			&f.shapes,
			shacl.Result {
				focus = term_id(&f, EX_R + "alice"),
				path = f.shapes.shapes[index].path,
				shape = index,
				component = .Min_Count,
				severity = .Violation,
			},
			&f.dictionary,
		)
		shacl.report_finish(&r)

		source := strings.concatenate(
			{
				`@prefix sh: <http://www.w3.org/ns/shacl#> .
				 @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
				 @prefix ex: <http://example.org/> .
				 [] a sh:ValidationReport ; sh:conforms "false"^^xsd:boolean ;
					sh:result [ a sh:ValidationResult ;
						sh:focusNode ex:alice ;
						`,
				c.expected,
				` ;
						sh:resultSeverity sh:Violation ;
						sh:sourceConstraintComponent sh:MinCountConstraintComponent ;
						sh:sourceShape ex:`,
				c.shape,
				` ] .`,
			},
			context.temp_allocator,
		)
		expected := parse_expected(source)
		defer destroy_graph(&expected)

		testing.expectf(
			t,
			report_isomorphic(shacl.report_triples(&r), expected[:]),
			"%s: produced path does not match %s",
			c.shape,
			c.expected,
		)
	}
}

// The report carries nothing the shapes graph did not declare. A shape with
// no sh:message contributes no sh:message triple — no processor-generated
// text, which is what keeps suite comparison exact.
@(test)
test_no_undeclared_messages :: proc(t: ^testing.T) {
	f: Fixture
	if !fixture_init(t, &f) {
		fixture_destroy(&f)
		return
	}
	defer fixture_destroy(&f)

	quiet := shape_index(&f, EX_R + "QuietShape")
	r: shacl.Report
	shacl.report_init(&r)
	defer shacl.report_destroy(&r)
	shacl_memstore.report_add(
		&r,
		&f.shapes,
		shacl.Result {
			focus = term_id(&f, EX_R + "alice"),
			path = f.shapes.shapes[quiet].path,
			shape = quiet,
			component = .Min_Count,
			severity = .Violation,
		},
		&f.dictionary,
	)
	shacl.report_finish(&r)

	for tr in shacl.report_triples(&r) {
		if pred, is_iri := tr.predicate.(rdf.IRI); is_iri {
			testing.expectf(
				t,
				string(pred) != shacl.MESSAGE,
				"a shape with no sh:message produced one: %v",
				tr.object,
			)
		}
	}
}

// The report round-trips: emitted through odin-rdf-parser and parsed back, it
// denotes the same graph. That is the property the suite runner depends on,
// and it exercises the emitter rather than only the builder.
@(test)
test_report_round_trips_through_the_emitter :: proc(t: ^testing.T) {
	f: Fixture
	if !fixture_init(t, &f) {
		fixture_destroy(&f)
		return
	}
	defer fixture_destroy(&f)

	alt := shape_index(&f, EX_R + "AltShape")
	r: shacl.Report
	shacl.report_init(&r)
	defer shacl.report_destroy(&r)
	shacl_memstore.report_add(
		&r,
		&f.shapes,
		shacl.Result {
			focus = term_id(&f, EX_R + "alice"),
			value = term_id(&f, EX_R + "alice"),
			has_value = true,
			path = f.shapes.shapes[alt].path,
			shape = alt,
			component = .Min_Count,
			severity = .Violation,
		},
		&f.dictionary,
	)
	shacl.report_finish(&r)

	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)
	err := triples.emit_all(strings.to_writer(&sb), shacl.report_triples(&r))
	testing.expectf(t, err == nil, "emitting the report failed: %v", err)

	// N-Triples is Turtle, so the family's Turtle parser reads it back.
	parsed := parse_expected(strings.to_string(sb))
	defer destroy_graph(&parsed)

	testing.expectf(
		t,
		len(parsed) == len(shacl.report_triples(&r)),
		"round trip changed the triple count: %d out, %d back",
		len(shacl.report_triples(&r)),
		len(parsed),
	)
	testing.expect(
		t,
		report_isomorphic(shacl.report_triples(&r), parsed[:]),
		"the report does not survive emit and re-parse",
	)
}

// The conformance-only consumer: it stops at the first violation, which is
// what early exit is for. Asserted here on a synthetic stream; SHACL-T-0007
// asserts it end to end, when there is a validator whose traversal actually
// stops.
@(test)
test_conformance_consumer_stops_at_first_violation :: proc(t: ^testing.T) {
	f: Fixture
	if !fixture_init(t, &f) {
		fixture_destroy(&f)
		return
	}
	defer fixture_destroy(&f)

	email := shape_index(&f, EX_R + "EmailShape")
	result := shacl.Result {
		focus     = term_id(&f, EX_R + "alice"),
		path      = f.shapes.shapes[email].path,
		shape     = email,
		component = .Min_Count,
	}

	// A warning does not break conformance, so the stream continues.
	{
		c: shacl.Conformance
		shacl.conformance_init(&c)
		warning := result
		warning.severity = .Warning
		delivered := 0
		for _ in 0 ..< 3 {
			if !shacl.conformance_visitor(&c, warning) {
				break
			}
			delivered += 1
		}
		testing.expect(t, c.conforms, "warnings must not break conformance")
		testing.expect_value(t, delivered, 3)
	}

	// A violation stops it at the first one.
	{
		c: shacl.Conformance
		shacl.conformance_init(&c)
		violation := result
		violation.severity = .Violation
		delivered := 0
		for _ in 0 ..< 3 {
			if !shacl.conformance_visitor(&c, violation) {
				break
			}
			delivered += 1
		}
		testing.expect(t, !c.conforms, "a violation must break conformance")
		testing.expectf(t, delivered == 0, "expected to stop before consuming any result, consumed %d", delivered)
	}
}
