package shacl

import "core:testing"

import rdf "rdf:rdf"

// Lexical-to-value conversion, tested directly (SHACL-T-0012).
//
// This is the one part of the engine with no store in it — no generics, no
// `$MATCH` constants, no backend — so it is tested as what it is: a pure
// function from a literal to a verdict. Going through a backend would test the
// same arithmetic through four layers and two Term_ID widths, and would say
// nothing extra.
//
// The cases that are here because a **suite entry** demands them are marked as
// such. They are the ones that must not be "simplified" later: every one of
// them is a place where the obvious implementation gives a different answer
// from the specification.

@(private = "file")
literal :: proc(lexical: string, datatype: rdf.IRI) -> rdf.Literal {
	return rdf.Literal{lexical = lexical, datatype = datatype}
}

@(private = "file")
XSD_INTEGER :: rdf.XSD_INTEGER
@(private = "file")
XSD_DECIMAL :: rdf.XSD_DECIMAL
@(private = "file")
XSD_DOUBLE :: rdf.XSD_DOUBLE
@(private = "file")
XSD_BOOLEAN :: rdf.XSD_BOOLEAN
@(private = "file")
XSD_STRING :: rdf.XSD_STRING
@(private = "file")
XSD_BYTE :: rdf.IRI(rdf.XSD_NS + "byte")
@(private = "file")
XSD_UNSIGNED_BYTE :: rdf.IRI(rdf.XSD_NS + "unsignedByte")
@(private = "file")
XSD_POSITIVE_INTEGER :: rdf.IRI(rdf.XSD_NS + "positiveInteger")
@(private = "file")
XSD_LONG :: rdf.IRI(rdf.XSD_NS + "long")
@(private = "file")
RDF_HTML :: rdf.IRI(rdf.RDF_NS + "HTML")

// ---- Well-formedness -------------------------------------------------------

@(test)
test_integer_lexical_forms :: proc(t: ^testing.T) {
	well_formed := []string{"0", "42", "-7", "+7", "0042", " 42 "}
	for lexical in well_formed {
		testing.expectf(
			t,
			lexical_status(literal(lexical, XSD_INTEGER)) == .Well_Formed,
			"%q should be a well-formed xsd:integer",
			lexical,
		)
	}
	// `datatype-001` in core/node is "aldi"; the rest are the forms strconv
	// would happily read as a number and XSD does not admit.
	ill_formed := []string{"aldi", "", "+", "-", "1.0", "1e5", "0x10", "1 2", "1,000"}
	for lexical in ill_formed {
		testing.expectf(
			t,
			lexical_status(literal(lexical, XSD_INTEGER)) == .Ill_Formed,
			"%q should be an ill-formed xsd:integer",
			lexical,
		)
	}
}

// The entry this whole task was named after: `core/property/datatype-ill-formed`
// declares `sh:datatype xsd:byte` and expects both "300" and "c" to violate it,
// though both name xsd:byte exactly. One is out of range and the other is not a
// number, and the derived integer bounds are what tell them apart from "55".
@(test)
test_derived_integer_bounds :: proc(t: ^testing.T) {
	testing.expect_value(t, lexical_status(literal("300", XSD_BYTE)), Lexical_Status.Ill_Formed)
	testing.expect_value(t, lexical_status(literal("c", XSD_BYTE)), Lexical_Status.Ill_Formed)
	testing.expect_value(t, lexical_status(literal("127", XSD_BYTE)), Lexical_Status.Well_Formed)
	testing.expect_value(t, lexical_status(literal("-128", XSD_BYTE)), Lexical_Status.Well_Formed)
	testing.expect_value(t, lexical_status(literal("-129", XSD_BYTE)), Lexical_Status.Ill_Formed)

	testing.expect_value(t, lexical_status(literal("255", XSD_UNSIGNED_BYTE)), Lexical_Status.Well_Formed)
	testing.expect_value(t, lexical_status(literal("-1", XSD_UNSIGNED_BYTE)), Lexical_Status.Ill_Formed)

	testing.expect_value(t, lexical_status(literal("1", XSD_POSITIVE_INTEGER)), Lexical_Status.Well_Formed)
	testing.expect_value(t, lexical_status(literal("0", XSD_POSITIVE_INTEGER)), Lexical_Status.Ill_Formed)

	// The extremes of the one derived type whose range is i64's own, which is
	// where an accumulator that could not reach min(i64) would show up.
	testing.expect_value(t, lexical_status(literal("-9223372036854775808", XSD_LONG)), Lexical_Status.Well_Formed)
	testing.expect_value(t, lexical_status(literal("9223372036854775807", XSD_LONG)), Lexical_Status.Well_Formed)
	testing.expect_value(t, lexical_status(literal("9223372036854775808", XSD_LONG)), Lexical_Status.Ill_Formed)
	testing.expect_value(t, lexical_status(literal("-9223372036854775809", XSD_LONG)), Lexical_Status.Ill_Formed)
}

// An xsd:integer too large to hold is **well-formed and valueless** — the
// header's split between "is this spelled right" and "can this engine say what
// it means". Getting this backwards would report a violation on a perfectly good
// literal.
@(test)
test_unrepresentable_integer_is_well_formed_without_a_value :: proc(t: ^testing.T) {
	huge := literal("99999999999999999999999", XSD_INTEGER)
	testing.expect_value(t, lexical_status(huge), Lexical_Status.Well_Formed)
	testing.expect(t, value_of(huge) == nil, "an unrepresentable integer has no value")
	testing.expect_value(t, compare_values(value_of(huge), i64(1)), Comparison.Incomparable)
}

@(test)
test_decimal_and_double_lexical_forms :: proc(t: ^testing.T) {
	testing.expect_value(t, lexical_status(literal("3.9", XSD_DECIMAL)), Lexical_Status.Well_Formed)
	testing.expect_value(t, lexical_status(literal("-.5", XSD_DECIMAL)), Lexical_Status.Well_Formed)
	testing.expect_value(t, lexical_status(literal("4.", XSD_DECIMAL)), Lexical_Status.Well_Formed)
	// An exponent is a double's and not a decimal's, which is the distinction
	// strconv erases.
	testing.expect_value(t, lexical_status(literal("1e5", XSD_DECIMAL)), Lexical_Status.Ill_Formed)
	testing.expect_value(t, lexical_status(literal("1e5", XSD_DOUBLE)), Lexical_Status.Well_Formed)
	testing.expect_value(t, lexical_status(literal("1.5E-3", XSD_DOUBLE)), Lexical_Status.Well_Formed)
	testing.expect_value(t, lexical_status(literal("1e", XSD_DOUBLE)), Lexical_Status.Ill_Formed)
	testing.expect_value(t, lexical_status(literal("1e5.5", XSD_DOUBLE)), Lexical_Status.Ill_Formed)
	testing.expect_value(t, lexical_status(literal("1.5.5", XSD_DOUBLE)), Lexical_Status.Ill_Formed)
	testing.expect_value(t, lexical_status(literal(".", XSD_DECIMAL)), Lexical_Status.Ill_Formed)
	// XSD spells the specials in capitals, and signs only the infinities: the
	// asymmetry is the reason the specials are matched before the sign is
	// stripped, and it is what lets strconv read everything that gets past.
	testing.expect_value(t, lexical_status(literal("INF", XSD_DOUBLE)), Lexical_Status.Well_Formed)
	testing.expect_value(t, lexical_status(literal("-INF", XSD_DOUBLE)), Lexical_Status.Well_Formed)
	testing.expect_value(t, lexical_status(literal("+INF", XSD_DOUBLE)), Lexical_Status.Well_Formed)
	testing.expect_value(t, lexical_status(literal("NaN", XSD_DOUBLE)), Lexical_Status.Well_Formed)
	testing.expect_value(t, lexical_status(literal("-NaN", XSD_DOUBLE)), Lexical_Status.Ill_Formed)
	testing.expect_value(t, lexical_status(literal("+NaN", XSD_DOUBLE)), Lexical_Status.Ill_Formed)
	testing.expect_value(t, lexical_status(literal("inf", XSD_DOUBLE)), Lexical_Status.Ill_Formed)
	testing.expect_value(t, lexical_status(literal("INF", XSD_DECIMAL)), Lexical_Status.Ill_Formed)
}

@(test)
test_boolean_lexical_forms :: proc(t: ^testing.T) {
	well_formed := []string{"true", "false", "1", "0"}
	for lexical in well_formed {
		testing.expectf(
			t,
			lexical_status(literal(lexical, XSD_BOOLEAN)) == .Well_Formed,
			"%q should be a well-formed xsd:boolean",
			lexical,
		)
	}
	ill_formed := []string{"TRUE", "yes", "2", ""}
	for lexical in ill_formed {
		testing.expectf(
			t,
			lexical_status(literal(lexical, XSD_BOOLEAN)) == .Ill_Formed,
			"%q should be an ill-formed xsd:boolean",
			lexical,
		)
	}
	testing.expect_value(t, value_of(literal("1", XSD_BOOLEAN)), Value(true))
	testing.expect_value(t, value_of(literal("0", XSD_BOOLEAN)), Value(false))
}

@(test)
test_date_and_date_time_lexical_forms :: proc(t: ^testing.T) {
	well_formed_date_times := []string {
		"2002-10-10T12:00:00",
		"2002-10-10T12:00:00Z",
		"2002-10-10T12:00:00-05:00",
		"2002-10-10T12:00:00.125+01:30",
		"2002-10-10T24:00:00",
		"-0044-03-15T12:00:00",
		"20002-10-10T12:00:00",
	}
	for lexical in well_formed_date_times {
		testing.expectf(
			t,
			lexical_status(literal(lexical, XSD_DATE_TIME)) == .Well_Formed,
			"%q should be a well-formed xsd:dateTime",
			lexical,
		)
	}
	ill_formed_date_times := []string {
		"2002-10-10", // a date is not a dateTime, which is datatype-001
		"2002-13-10T12:00:00", // no thirteenth month
		"2011-02-30T12:00:00", // no thirtieth of February
		"2002-10-10T25:00:00", // no twenty-fifth hour
		"2002-10-10T24:00:01", // 24:00 is midnight and nothing else
		"2002-10-10T12:60:00",
		"2002-10-10T12:00:60",
		"2002-10-10T12:00:00+15:00", // no timezone that far out
		"2002-10-10T12:00:00+0500",
		"2002-10-10T12:00:123",
		"202-10-10T12:00:00", // a year is at least four digits
		"aldi",
		"",
	}
	for lexical in ill_formed_date_times {
		testing.expectf(
			t,
			lexical_status(literal(lexical, XSD_DATE_TIME)) == .Ill_Formed,
			"%q should be an ill-formed xsd:dateTime",
			lexical,
		)
	}

	testing.expect_value(t, lexical_status(literal("2014-09-01", XSD_DATE)), Lexical_Status.Well_Formed)
	testing.expect_value(t, lexical_status(literal("2014-09-01Z", XSD_DATE)), Lexical_Status.Well_Formed)
	testing.expect_value(t, lexical_status(literal("2012-02-29", XSD_DATE)), Lexical_Status.Well_Formed)
	testing.expect_value(t, lexical_status(literal("2013-02-29", XSD_DATE)), Lexical_Status.Ill_Formed)
	testing.expect_value(t, lexical_status(literal("2014-09-01T00:00:00", XSD_DATE)), Lexical_Status.Ill_Formed)
}

// The three answers that are not about parsing at all: a string is always
// well-formed, a datatype this engine does not model is unchecked rather than
// either, and a language tag decides the question before the datatype does.
@(test)
test_unmodelled_and_tagged_literals :: proc(t: ^testing.T) {
	testing.expect_value(t, lexical_status(literal("anything at all", XSD_STRING)), Lexical_Status.Well_Formed)
	testing.expect_value(t, lexical_status(literal("", XSD_STRING)), Lexical_Status.Well_Formed)

	// `core/node/datatype-002` carries an rdf:HTML literal. Nothing here models
	// rdf:HTML, so nothing here may call it malformed.
	testing.expect_value(t, lexical_status(literal("<span>Hello</span>", RDF_HTML)), Lexical_Status.Unchecked)
	testing.expect_value(t, lexical_status(literal("x", rdf.IRI("http://example.org/MyType"))), Lexical_Status.Unchecked)

	tagged := rdf.Literal {
		lexical  = "G'day",
		datatype = rdf.RDF_LANG_STRING,
		language = "en-AU",
	}
	testing.expect_value(t, lexical_status(tagged), Lexical_Status.Well_Formed)
	testing.expect(t, value_of(tagged) == nil, "a language-tagged literal has no order")

	// rdf:langString without a tag is legal Turtle syntax and not a legal term.
	untagged := literal("G'day", rdf.RDF_LANG_STRING)
	testing.expect_value(t, lexical_status(untagged), Lexical_Status.Ill_Formed)
}

// ---- Comparison ------------------------------------------------------------

// `maxExclusive-001` and `maxInclusive-001` both set the bound to the integer 4
// and target the decimals 3.9, 4.0, and 4.1. Every one of those pairs crosses
// datatypes, and comparing the terms would answer "different" for all of them.
@(test)
test_numeric_comparison_crosses_datatypes :: proc(t: ^testing.T) {
	four := value_of(literal("4", XSD_INTEGER))
	testing.expect_value(t, compare_values(value_of(literal("4.0", XSD_DECIMAL)), four), Comparison.Equal)
	testing.expect_value(t, compare_values(value_of(literal("3.9", XSD_DECIMAL)), four), Comparison.Less)
	testing.expect_value(t, compare_values(value_of(literal("4.1", XSD_DECIMAL)), four), Comparison.Greater)
	testing.expect_value(t, compare_values(value_of(literal("4E0", XSD_DOUBLE)), four), Comparison.Equal)

	// `datatype-ill-formed`'s data also holds "55"^^xsd:integer beside its
	// bytes: a derived type compares as the number it is.
	testing.expect_value(
		t,
		compare_values(value_of(literal("55", XSD_INTEGER)), value_of(literal("55", XSD_BYTE))),
		Comparison.Equal,
	)
	testing.expect_value(
		t,
		compare_values(value_of(literal("12", XSD_BYTE)), value_of(literal("55", XSD_INTEGER))),
		Comparison.Less,
	)
}

// NaN is unordered against everything, itself included — `.Incomparable` and
// not `.Equal`, which is what a plain `<`/`>` pair would produce.
@(test)
test_nan_is_unordered :: proc(t: ^testing.T) {
	nan := value_of(literal("NaN", XSD_DOUBLE))
	testing.expect_value(t, compare_values(nan, nan), Comparison.Incomparable)
	testing.expect_value(t, compare_values(nan, i64(0)), Comparison.Incomparable)
	// The infinities are ordinary values and do order.
	testing.expect_value(t, compare_values(value_of(literal("INF", XSD_DOUBLE)), i64(0)), Comparison.Greater)
	testing.expect_value(t, compare_values(value_of(literal("-INF", XSD_DOUBLE)), i64(0)), Comparison.Less)
}

// Everything with no order between it and the other side. `maxExclusive-001`
// targets `ex:John`, a blank node, and `"Hello"` against a numeric bound and
// expects all three to violate — which they do because the comparison declines,
// not because a rule was written for each.
@(test)
test_incomparable_pairs :: proc(t: ^testing.T) {
	four := value_of(literal("4", XSD_INTEGER))
	testing.expect_value(t, compare_values(value_of(rdf.IRI("http://example.org/John")), four), Comparison.Incomparable)
	testing.expect_value(t, compare_values(value_of(rdf.Blank_Node("b0")), four), Comparison.Incomparable)
	testing.expect_value(t, compare_values(value_of(literal("Hello", XSD_STRING)), four), Comparison.Incomparable)
	testing.expect_value(t, compare_values(value_of(literal("aldi", XSD_INTEGER)), four), Comparison.Incomparable)
	testing.expect_value(t, compare_values(value_of(literal("true", XSD_BOOLEAN)), four), Comparison.Incomparable)

	// A date is not a dateTime at midnight; the two are different types.
	testing.expect_value(
		t,
		compare_values(value_of(literal("2002-10-10", XSD_DATE)), value_of(literal("2002-10-10T00:00:00", XSD_DATE_TIME))),
		Comparison.Incomparable,
	)
}

@(test)
test_ordered_within_a_kind :: proc(t: ^testing.T) {
	testing.expect_value(t, compare_values(Value(false), Value(true)), Comparison.Less)
	testing.expect_value(t, compare_values(Value(true), Value(true)), Comparison.Equal)
	testing.expect_value(t, compare_values(Value("Aldi"), Value("Bldi")), Comparison.Less)
	testing.expect_value(t, compare_values(Value("Ald"), Value("Aldi")), Comparison.Less)
	// Two empty strings from different backings, which is the case
	// strings.compare gets wrong by answering from the data pointers.
	empty := literal("", XSD_STRING)
	testing.expect_value(t, compare_values(value_of(empty), Value("")), Comparison.Equal)
}

// XSD's partial order over instants, which is the rule `minInclusive-002` and
// `-003` are built on and the one an implicit-timezone reading gets wrong.
//
// A dateTime written without a timezone denotes a 28-hour window, so it orders
// against a timezoned one only when the window clears it entirely. Both entries
// expect a violation for a pair whose windows overlap — the naive reading calls
// one of them *later* than the bound and would report conformance.
@(test)
test_instants_without_a_timezone_are_a_window :: proc(t: ^testing.T) {
	zoned :: proc(lexical: string) -> Value {
		return value_of(literal(lexical, XSD_DATE_TIME))
	}
	// minInclusive-002: the bound carries a timezone.
	bound := zoned("2002-10-10T12:00:00-05:00")
	testing.expect_value(t, compare_values(zoned("2002-10-10T12:00:00-05:00"), bound), Comparison.Equal)
	testing.expect_value(t, compare_values(zoned("2002-10-10T12:00:01-05:00"), bound), Comparison.Greater)
	testing.expect_value(t, compare_values(zoned("2002-10-09T12:00:00-05:00"), bound), Comparison.Less)
	testing.expect_value(t, compare_values(zoned("2002-10-10T12:00:00"), bound), Comparison.Incomparable)

	// minInclusive-003: the bound does not, and the same pairs invert.
	naive := zoned("2002-10-10T12:00:00")
	testing.expect_value(t, compare_values(zoned("2002-10-10T12:00:00-05:00"), naive), Comparison.Incomparable)
	testing.expect_value(t, compare_values(zoned("2002-10-10T12:00:01-05:00"), naive), Comparison.Incomparable)
	testing.expect_value(t, compare_values(zoned("2002-10-10T12:00:00"), naive), Comparison.Equal)
	// Far enough out that no legal timezone could close the gap: a definite
	// answer even though only one side carries one.
	testing.expect_value(t, compare_values(zoned("2002-10-09T12:00:00-05:00"), naive), Comparison.Less)
	testing.expect_value(t, compare_values(zoned("2002-10-11T12:00:00-05:00"), naive), Comparison.Greater)

	// Timezones are applied, not ignored: the same instant written two ways.
	testing.expect_value(t, compare_values(zoned("2002-10-10T17:00:00Z"), zoned("2002-10-10T12:00:00-05:00")), Comparison.Equal)
}

@(test)
test_dates_order_by_their_day :: proc(t: ^testing.T) {
	earlier := value_of(literal("2014-09-01", XSD_DATE))
	later := value_of(literal("2014-09-02", XSD_DATE))
	testing.expect_value(t, compare_values(earlier, later), Comparison.Less)
	testing.expect_value(t, compare_values(later, earlier), Comparison.Greater)
	testing.expect_value(t, compare_values(earlier, earlier), Comparison.Equal)
	// The epoch and the days either side of it, which is where an off-by-one
	// in the civil-to-days conversion would show.
	testing.expect_value(
		t,
		compare_values(value_of(literal("1969-12-31", XSD_DATE)), value_of(literal("1970-01-01", XSD_DATE))),
		Comparison.Less,
	)
	testing.expect_value(
		t,
		compare_values(value_of(literal("2000-02-29", XSD_DATE)), value_of(literal("2000-03-01", XSD_DATE))),
		Comparison.Less,
	)
}
