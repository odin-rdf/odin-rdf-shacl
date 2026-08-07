package w3c

import "core:strings"
import "core:testing"

import rdf "rdf:rdf"
import triples "rdf:rdf/triples"
import turtle "rdf:rdf/turtle"
import kvstore "store:store/kvstore"

import shacl "../../../shacl"
import shacl_kvstore "../../../shacl/kvstore"

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
	db:      ^kvstore.Store,
	path:    string,
	session: shacl_kvstore.Session,
	shapes:  shacl.Shapes,
}

@(private = "file")
fixture_init :: proc(t: ^testing.T, f: ^Fixture) -> bool {
	f.path = temp_store_path("report", "shapes")
	db, open_err := kvstore.open(f.path)
	if !testing.expectf(t, open_err == nil, "store: %v", open_err) {
		return false
	}
	f.db = db
	_, load_err, db_err := kvstore.load_turtle(db, transmute([]byte)string(REPORT_SHAPES))
	if !testing.expectf(t, load_err.message == "" && db_err == nil, "load: %s %v", load_err.message, db_err) {
		return false
	}
	shacl_kvstore.session_init(&f.session, db)
	err := shacl_kvstore.compile(&f.shapes, &f.session)
	return testing.expectf(t, err.kind == .None, "compile: %s", shacl.error_message(err.kind))
}

@(private = "file")
fixture_destroy :: proc(f: ^Fixture) {
	shacl.shapes_destroy(&f.shapes)
	if f.db != nil {
		kvstore.close(f.db)
	}
	if f.path != "" {
		remove_temp_store(f.path)
	}
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
	id, found, _ := kvstore.find_term(f.db, rdf.IRI(iri))
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

	shacl_kvstore.report_add(
		&r,
		&f.shapes,
		shacl.Result {
			focus = term_id(&f, EX_R + "alice"),
			path = f.shapes.shapes[email].path,
			shape = email,
			component = .Min_Count,
			severity = rdf.IRI(shacl.VIOLATION),
		},
		&f.session,
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
				sh:resultMessage "needs an email"@en ;
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

	// A warning breaks conformance too. §3.1 makes `sh:conforms` true if and
	// only if there are **no results**, whatever severity they carry — the
	// opposite reading is tempting and wrong, and `misc/severity-001` settles
	// it: one `sh:Warning` result, `sh:conforms false` expected.
	{
		r: shacl.Report
		shacl.report_init(&r)
		defer shacl.report_destroy(&r)
		shacl_kvstore.report_add(
			&r,
			&f.shapes,
			shacl.Result {
				focus = term_id(&f, EX_R + "alice"),
				path = f.shapes.shapes[email].path,
				shape = email,
				component = .Min_Count,
				severity = rdf.IRI(shacl.WARNING),
			},
			&f.session,
		)
		shacl.report_finish(&r)
		testing.expect(t, !shacl.report_conforms(&r), "any result breaks conformance, warnings included")
	}

	// A violation does.
	{
		r: shacl.Report
		shacl.report_init(&r)
		defer shacl.report_destroy(&r)
		shacl_kvstore.report_add(
			&r,
			&f.shapes,
			shacl.Result {
				focus = term_id(&f, EX_R + "alice"),
				path = f.shapes.shapes[email].path,
				shape = email,
				component = .Min_Count,
				severity = rdf.IRI(shacl.VIOLATION),
			},
			&f.session,
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
		shacl_kvstore.report_add(
			&r,
			&f.shapes,
			shacl.Result {
				focus = term_id(&f, EX_R + "alice"),
				path = f.shapes.shapes[index].path,
				shape = index,
				component = .Min_Count,
				severity = rdf.IRI(shacl.VIOLATION),
			},
			&f.session,
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
	shacl_kvstore.report_add(
		&r,
		&f.shapes,
		shacl.Result {
			focus = term_id(&f, EX_R + "alice"),
			path = f.shapes.shapes[quiet].path,
			shape = quiet,
			component = .Min_Count,
			severity = rdf.IRI(shacl.VIOLATION),
		},
		&f.session,
	)
	shacl.report_finish(&r)

	for tr in shacl.report_triples(&r) {
		if pred, is_iri := tr.predicate.(rdf.IRI); is_iri {
			testing.expectf(
				t,
				string(pred) != shacl.RESULT_MESSAGE && string(pred) != shacl.MESSAGE,
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
	shacl_kvstore.report_add(
		&r,
		&f.shapes,
		shacl.Result {
			focus = term_id(&f, EX_R + "alice"),
			value = term_id(&f, EX_R + "alice"),
			has_value = true,
			path = f.shapes.shapes[alt].path,
			shape = alt,
			component = .Min_Count,
			severity = rdf.IRI(shacl.VIOLATION),
		},
		&f.session,
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

// Blank nodes from three graphs meet in one report, and they have to stay
// apart (SHACL-T-0019). This is the test the suite could not be: every `core/`
// entry names one file as both its data graph and its shapes graph, so the two
// loads assign identical labels and a report that merged the two namespaces
// would be accidentally right. Here they are two files, written so that both
// stores hand out `b0` for nodes that have nothing to do with each other — the
// shapes graph's blank property shape and the data graph's blank value.
//
// The property asserted is the merge rule itself rather than the labels that
// implement it: no blank node the report *borrowed* may be a blank node the
// report *built*, and the two borrowed graphs may not share one either. It
// bites in both directions — swapping `fresh_blank`'s prefix back to `b` fails
// it on the first clause, and dropping `shape_term`'s prefix fails it on the
// second.
@(test)
test_report_blank_nodes_are_standardised_apart :: proc(t: ^testing.T) {
	shapes_src := `
		@prefix sh: <http://www.w3.org/ns/shacl#> .
		@prefix ex: <http://example.org/> .
		ex:Shape a sh:NodeShape ;
			sh:targetClass ex:Thing ;
			sh:property [ sh:path ex:p ; sh:nodeKind sh:IRI ] .`
	data_src := `
		@prefix ex: <http://example.org/> .
		ex:thing a ex:Thing ; ex:p _:anon .`

	model: shacl.Shapes
	defer shacl.shapes_destroy(&model)
	{
		path := temp_store_path("blank-report", "shapes")
		defer remove_temp_store(path)
		db, open_err := kvstore.open(path)
		if !testing.expectf(t, open_err == nil, "shapes store: %v", open_err) {
			return
		}
		defer kvstore.close(db)
		_, load_err, db_err := kvstore.load_turtle(db, transmute([]byte)shapes_src)
		if !testing.expectf(t, load_err.message == "" && db_err == nil, "shapes load: %s %v", load_err.message, db_err) {
			return
		}
		session: shacl_kvstore.Session
		shacl_kvstore.session_init(&session, db)
		err := shacl_kvstore.compile(&model, &session)
		if !testing.expectf(t, err.kind == .None, "compile: %s", shacl.error_message(err.kind)) {
			return
		}
	}

	path := temp_store_path("blank-report", "data")
	defer remove_temp_store(path)
	db, open_err := kvstore.open(path)
	if !testing.expectf(t, open_err == nil, "data store: %v", open_err) {
		return
	}
	defer kvstore.close(db)
	_, load_err, db_err := kvstore.load_turtle(db, transmute([]byte)data_src)
	if !testing.expectf(t, load_err.message == "" && db_err == nil, "data load: %s %v", load_err.message, db_err) {
		return
	}
	session: shacl_kvstore.Session
	shacl_kvstore.session_init(&session, db)

	bindings: shacl.Bindings
	shacl_kvstore.bind(&bindings, &model, &session)
	defer shacl.bindings_destroy(&bindings)

	r: shacl.Report
	shacl.report_init(&r)
	defer shacl.report_destroy(&r)
	failure := shacl_kvstore.validate_report(&r, &model, &bindings, &session)
	if !testing.expectf(t, failure == .None, "validate: %s", shacl.failure_message(failure)) {
		return
	}

	// A blank node the report built is one it ever used as a subject; a report
	// never asserts anything about a node it borrowed.
	built: map[string]bool
	defer delete(built)
	for tr in shacl.report_triples(&r) {
		if b, is_blank := tr.subject.(rdf.Blank_Node); is_blank {
			built[string(b)] = true
		}
	}

	source_shape, value: string
	for tr in shacl.report_triples(&r) {
		pred, is_iri := tr.predicate.(rdf.IRI)
		if !is_iri {
			continue
		}
		b, is_blank := tr.object.(rdf.Blank_Node)
		if !is_blank {
			continue
		}
		switch string(pred) {
		case shacl.SOURCE_SHAPE:
			source_shape = string(b)
		case shacl.VALUE:
			value = string(b)
		}
	}

	// Vacuously passing is the failure mode worth guarding: if the entry stopped
	// producing a blank source shape or a blank value, the rest proves nothing.
	if !testing.expect(t, source_shape != "", "expected a blank-node sh:sourceShape") {
		return
	}
	if !testing.expect(t, value != "", "expected a blank-node sh:value") {
		return
	}

	testing.expectf(
		t,
		!built[source_shape],
		"sh:sourceShape _:%s is also a node the report built — the shapes graph's "+
		"blank nodes and the report's own share a label space",
		source_shape,
	)
	testing.expectf(
		t,
		!built[value],
		"sh:value _:%s is also a node the report built — the data graph's blank "+
		"nodes and the report's own share a label space",
		value,
	)
	testing.expectf(
		t,
		source_shape != value,
		"sh:sourceShape and sh:value are both _:%s — a shape in one graph and a "+
		"value in another, merged into one node",
		source_shape,
	)
}

// The conformance-only consumer: it stops at the first result, which is what
// early exit is for. Asserted here on a synthetic stream;
// `shacl/kvstore/validate_semantics_test.odin` asserts it end to end, on a traversal
// that actually stops.
@(test)
test_conformance_consumer_stops_at_the_first_result :: proc(t: ^testing.T) {
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

	// Every severity stops it, including one the vocabulary never heard of:
	// §3.1 makes conformance a question about whether there are results, not
	// about what they say.
	severities := []string{shacl.VIOLATION, shacl.WARNING, shacl.INFO, EX_R + "Catastrophe"}
	for severity in severities {
		c: shacl.Conformance
		shacl.conformance_init(&c)
		one := result
		one.severity = rdf.IRI(severity)
		delivered := 0
		for _ in 0 ..< 3 {
			if !shacl.conformance_visitor(&c, one) {
				break
			}
			delivered += 1
		}
		testing.expectf(t, !c.conforms, "%s must break conformance", severity)
		testing.expectf(
			t,
			delivered == 0,
			"%s: expected to stop before consuming any result, consumed %d",
			severity,
			delivered,
		)
	}
}
