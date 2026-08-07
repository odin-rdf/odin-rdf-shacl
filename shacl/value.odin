package shacl

import "core:math"
import "core:strconv"
import "core:strings"

import rdf "rdf:rdf"

// Lexical-to-value conversion: comparing what literals *mean* rather than what
// they *are* (SHACL-T-0012).
//
// Everything else in this engine compares terms, and by `Term_ID` wherever it
// can — STORE-A-0001 exists so that a join, a set membership, and a node-kind
// test are all integer work. That is why the engine is fast, and it is exactly
// wrong for four of SHACL Core's components. `sh:minInclusive 4` must be
// satisfied by `"4.0"^^xsd:decimal`, which is a different term and the same
// number, and no comparison of IDs will ever say so.
//
// So this file is the one place a literal is opened up. It is small, pure, and
// non-generic: no store, no allocation, no `$MATCH` constants. The store hands
// the caller a term; everything here works on that.
//
//
// # Two questions, deliberately kept apart
//
// A literal raises two questions that look like one, and folding them together
// is how `sh:datatype` was wrong for a whole initiative:
//
//   - **What does it mean?** `value_of` answers with a `Value`, or with nothing
//     when there is no value this engine can produce. This is what the
//     value-range components compare.
//   - **Is its lexical form in its datatype's lexical space?** `lexical_status`
//     answers that, and it is the §4.1.2 half of `sh:datatype` the spine
//     recorded as debt: `"300"^^xsd:byte` and `"c"^^xsd:byte` must both violate
//     `sh:datatype xsd:byte` even though the datatype IRI matches exactly.
//
// They are not the same question, and the answers genuinely differ in both
// directions. `"99999999999999999999999"^^xsd:integer` is perfectly well-formed
// — xsd:integer is unbounded — and this engine cannot represent it, so it has a
// status and no value. `"<span>x</span>"^^rdf:HTML` has no value here either,
// but for the opposite reason: nothing is wrong with it, this engine simply
// does not model rdf:HTML.
//
// **Which is why `Lexical_Status` has three cases rather than two.** `.Unchecked`
// is the honest answer for a datatype this file does not model, and `sh:datatype`
// treats it as satisfied. Reporting a violation there would fail
// `sh:datatype rdf:HTML` on a perfectly good HTML literal, which is worse than
// under-reporting: an engine may only claim a lexical form is *outside* a
// lexical space it actually knows.
//
//
// # Bounded by the corpus, and loud outside it
//
// XSD's type system is large and the vendored suite measures a corner of it:
// xsd:string, xsd:boolean, xsd:integer with its derived types, xsd:decimal,
// xsd:dateTime, xsd:date, and rdf:langString. That set is what this file
// interprets. Everything else is `.Unchecked` and valueless — not silently
// accepted as zero, not approximated — and grows on evidence, which is the same
// rule the store's match interface is grown by.
//
// **Incomparable is a first-class answer** for the same reason. Two values can
// be ordered, or known not to be orderable; there is no third option where the
// primitive guesses. What a constraint does with `.Incomparable` is the
// constraint's business — for the value-range components it is a violation,
// since a node that cannot be shown to be in range is not in range — but the
// comparison itself must not invent an order.
//
//
// # Read from odin-rdf-sparql, not imported
//
// The query engine solved a version of this in its `value.odin`, and it was read
// before this was written: the numeric tower, the XSD partial order over
// partially-timezoned instants, and the lexical forms `strconv` accepts but XSD
// does not are all findings taken from there. None of it is imported. SHACL Core
// keeps zero dependency on the query engine at runtime and at link time, and
// `tests/purity` and the absent `sparql:` collection both say so.
//
// The two engines want different things from the same machinery, which is why
// this is a third of the size. SPARQL needs arithmetic, promotion rules that
// survive into a result's datatype, effective boolean value, and a term to
// render back; SHACL needs an order and a well-formedness verdict. Value
// identity, canonical lexical forms, and the numeric rungs above `i64`/`f64`
// are all absent here because nothing in SHACL Core asks for them.
//
//
// # Stated limitations
//
//   - **Integers beyond `i64` are well-formed and valueless.** xsd:integer is
//     unbounded and this holds 64 bits. The status is right, the comparison
//     answers `.Incomparable`, and nothing lies.
//   - **A mixed numeric comparison goes through `f64`.** Integer against integer
//     is exact; integer against decimal is exact only below 2^53. The alternative
//     is arbitrary precision, which no suite entry asks for.
//   - **`xsd:unsignedLong`'s upper bound is not enforced above `i64`'s.** A value
//     in that gap is unrepresentable and so already valueless.
//   - **Whitespace is trimmed, not collapsed.** XSD's `collapse` facet also folds
//     interior runs, which cannot change the verdict for any of the datatypes
//     here: every one of their lexical spaces rejects interior whitespace either
//     way.

// The XSD datatypes this file interprets. odin-rdf-parser's vocabulary carries
// the four the Turtle grammar abbreviates; the rest are local names off the same
// namespace, kept here rather than in `vocab.odin` because that file is the
// SHACL namespace and these are not.
@(private)
XSD_FLOAT :: rdf.IRI(rdf.XSD_NS + "float")
@(private)
XSD_DATE_TIME :: rdf.IRI(rdf.XSD_NS + "dateTime")
@(private)
XSD_DATE :: rdf.IRI(rdf.XSD_NS + "date")

// Lexical_Status is what this engine can say about a literal's lexical form
// against its datatype's lexical space.
//
// `.Unchecked` is not a weaker `.Well_Formed`: it says the question was not
// asked, because this engine does not model the datatype. A caller that treats
// the two alike is making a policy choice and should say so — `sh:datatype`
// does, in `check_datatype`.
@(private)
Lexical_Status :: enum u8 {
	Well_Formed,
	Ill_Formed,
	Unchecked,
}

// Comparison is the result of ordering two values. `.Incomparable` is an answer,
// not a failure: a number and a string have no order between them, and neither
// do two dateTimes whose timezone windows overlap.
@(private)
Comparison :: enum u8 {
	Less,
	Equal,
	Greater,
	Incomparable,
}

// Instant_Kind keeps xsd:date and xsd:dateTime apart. They are different types
// with the same internal shape, and comparing one to the other is incomparable
// rather than a date at midnight — which is what SPARQL's operator mapping, the
// one SHACL defers to, says.
@(private)
Instant_Kind :: enum u8 {
	Date_Time,
	Date,
}

// Instant is a parsed xsd:dateTime or xsd:date, reduced to the one number
// comparison needs.
//
// `has_tz` is kept because the *absence* of a timezone changes the comparison
// rather than defaulting it: a value written without one does not denote an
// instant but a 28-hour window around it, and XSD orders it against a timezoned
// value only when the whole window falls on one side. See `order_instants`.
@(private)
Instant :: struct {
	kind:    Instant_Kind,
	seconds: f64, // the instant relative to 1970-01-01T00:00:00Z
	has_tz:  bool,
}

// Value is a literal's meaning, in the only representations this engine
// compares. A nil Value is "no value" — an IRI, a blank node, a triple term, an
// ill-formed literal, a datatype this file does not model, or a number too large
// to hold.
//
// A `string` Value **borrows** the literal's lexical form and lives exactly as
// long as the term it came from, which for a value read from the store is the
// current visitor call. Every other case is a copy.
@(private)
Value :: union {
	i64, // xsd:integer and its derived integer types
	f64, // xsd:decimal, xsd:float, xsd:double
	bool, // xsd:boolean
	string, // xsd:string, which is also what a plain literal carries
	Instant, // xsd:dateTime, xsd:date
}

// value_of interprets a term. Only literals have values; an IRI, a blank node,
// and a triple term are all nil, which is what makes `sh:minInclusive` violate
// on `ex:John` without a case for it.
@(private)
value_of :: proc(term: rdf.Term) -> Value {
	literal, is_literal := term.(rdf.Literal)
	if !is_literal {
		return nil
	}
	value, _ := decode_literal(literal)
	return value
}

// lexical_status reports whether a literal's lexical form lies in its datatype's
// lexical space — the §4.1.2 question `sh:datatype` asks after the datatype IRI
// has already matched.
@(private)
lexical_status :: proc(literal: rdf.Literal) -> Lexical_Status {
	_, status := decode_literal(literal)
	return status
}

// decode_literal is the one decoder both entry points share, so a literal is
// never classified two ways by two code paths.
//
// The language tag is examined before the datatype because it decides the
// question by itself: RDF Concepts §3.3 gives rdf:langString the lexical space
// of every string, so a tagged literal is always well-formed and — since
// SPARQL's operator mapping orders only xsd:string — never has an order against
// anything, which is a value of nil.
@(private = "file")
decode_literal :: proc(literal: rdf.Literal) -> (value: Value, status: Lexical_Status) {
	if literal.language != "" {
		return nil, .Well_Formed
	}
	switch literal.datatype {
	case rdf.RDF_LANG_STRING, rdf.RDF_DIR_LANG_STRING:
		// A language-tagged datatype with no tag. RDF Concepts requires the
		// tag, so the term is ill-formed however it was written — and it can
		// be written: `"x"^^rdf:langString` is legal Turtle syntax.
		return nil, .Ill_Formed
	case rdf.XSD_STRING:
		return literal.lexical, .Well_Formed
	case rdf.XSD_BOOLEAN:
		switch strings.trim_space(literal.lexical) {
		case "true", "1":
			return true, .Well_Formed
		case "false", "0":
			return false, .Well_Formed
		}
		return nil, .Ill_Formed
	case XSD_DATE_TIME:
		return decode_instant(literal.lexical, .Date_Time)
	case XSD_DATE:
		return decode_instant(literal.lexical, .Date)
	}
	return decode_numeric(literal.lexical, literal.datatype)
}

// ---- The numeric tower -----------------------------------------------------

// Numeric_Family is how a numeric datatype's lexical form is *spelled*, which is
// the only thing the tower is needed for here: an exponent is legal in an
// xsd:double and not in an xsd:decimal, and `strconv` accepts both. SHACL needs
// no promotion rules, because a comparison's result has no datatype.
@(private = "file")
Numeric_Family :: enum u8 {
	None,
	Integer,
	Decimal,
	Floating,
}

// Integer_Bounds is a derived integer type's value space. The bounds are what
// makes `"300"^^xsd:byte` ill-formed rather than merely surprising, and they are
// the reason `sh:datatype` could not be finished without this file.
@(private = "file")
Integer_Bounds :: struct {
	low:      i64,
	high:     i64,
	has_low:  bool,
	has_high: bool,
}

// numeric_family classifies a datatype IRI and, for the integer types, gives its
// range in the same answer — the two are read together every time, and splitting
// them would mean walking the same table twice. A datatype outside the XSD
// namespace never reaches the table at all.
@(private = "file")
numeric_family :: proc(datatype: rdf.IRI) -> (family: Numeric_Family, bounds: Integer_Bounds) {
	if !strings.has_prefix(string(datatype), rdf.XSD_NS) {
		return .None, {}
	}
	switch string(datatype)[len(rdf.XSD_NS):] {
	case "integer":
		return .Integer, {}
	case "long":
		return .Integer, {min(i64), max(i64), true, true}
	case "int":
		return .Integer, {-2_147_483_648, 2_147_483_647, true, true}
	case "short":
		return .Integer, {-32_768, 32_767, true, true}
	case "byte":
		return .Integer, {-128, 127, true, true}
	case "nonNegativeInteger":
		return .Integer, {low = 0, has_low = true}
	case "positiveInteger":
		return .Integer, {low = 1, has_low = true}
	case "nonPositiveInteger":
		return .Integer, {high = 0, has_high = true}
	case "negativeInteger":
		return .Integer, {high = -1, has_high = true}
	// xsd:unsignedLong's upper bound is 2^64-1, which does not fit here. Only
	// the lower bound is enforced; a value in the gap overflows i64 and is
	// already valueless, so nothing is claimed that is not true.
	case "unsignedLong":
		return .Integer, {low = 0, has_low = true}
	case "unsignedInt":
		return .Integer, {0, 4_294_967_295, true, true}
	case "unsignedShort":
		return .Integer, {0, 65_535, true, true}
	case "unsignedByte":
		return .Integer, {0, 255, true, true}
	case "decimal":
		return .Decimal, {}
	case "float", "double":
		return .Floating, {}
	}
	return .None, {}
}

// decode_numeric handles every datatype the switch in decode_literal did not,
// which is the numeric tower plus everything this engine does not model.
@(private = "file")
decode_numeric :: proc(lexical: string, datatype: rdf.IRI) -> (value: Value, status: Lexical_Status) {
	family, bounds := numeric_family(datatype)
	text := strings.trim_space(lexical)
	switch family {
	case .Integer:
		n, representable, well_formed := parse_integer(text)
		if !well_formed {
			return nil, .Ill_Formed
		}
		if !representable {
			// The digits are digits and there are too many of them. An
			// unrepresentable magnitude is out of range for any type whose
			// bound it overflowed, and merely unrepresentable for the rest.
			if bounds.has_low && bounds.has_high {
				return nil, .Ill_Formed
			}
			if text[0] == '-' && bounds.has_low {
				return nil, .Ill_Formed
			}
			if text[0] != '-' && bounds.has_high {
				return nil, .Ill_Formed
			}
			return nil, .Well_Formed
		}
		if bounds.has_low && n < bounds.low {
			return nil, .Ill_Formed
		}
		if bounds.has_high && n > bounds.high {
			return nil, .Ill_Formed
		}
		return n, .Well_Formed
	case .Decimal, .Floating:
		// The lexical check is what decides this, not the parse: `strconv`
		// reads "1e5" as a number and XSD does not read it as a decimal, and it
		// reads XSD's own `INF`/`-INF`/`+INF`/`NaN` exactly as spelled. So
		// everything `valid_numeric_lexical` admits, `parse_f64` can also read,
		// and the `!ok` below is a belt-and-braces check rather than a case.
		if !valid_numeric_lexical(text, family) {
			return nil, .Ill_Formed
		}
		x, ok := strconv.parse_f64(text)
		if !ok {
			return nil, .Ill_Formed
		}
		return x, .Well_Formed
	case .None:
	}
	return nil, .Unchecked
}

// parse_integer reads `[+-]?[0-9]+` and nothing else, detecting overflow rather
// than wrapping.
//
// `well_formed` is about the *spelling* and `representable` about the magnitude,
// which is the same split the file header draws: "1.0" and "1e5" are not
// integers at all, while a hundred digits is a perfectly good xsd:integer this
// engine cannot hold. `strconv.parse_i64_of_base` distinguishes neither.
//
// The accumulator runs negative so that `min(i64)` — whose magnitude has no
// positive counterpart — is reachable rather than being reported as overflow.
@(private = "file")
parse_integer :: proc(s: string) -> (value: i64, representable: bool, well_formed: bool) {
	digits := s
	negative := false
	if len(digits) > 0 && (digits[0] == '+' || digits[0] == '-') {
		negative = digits[0] == '-'
		digits = digits[1:]
	}
	if len(digits) == 0 {
		return 0, false, false
	}
	// Below this, multiplying by ten cannot overflow; at or below it, it can.
	MULTIPLY_LIMIT :: min(i64) / 10
	accumulator: i64
	overflowed := false
	for i in 0 ..< len(digits) {
		c := digits[i]
		if c < '0' || c > '9' {
			return 0, false, false
		}
		if overflowed {
			continue // keep reading: the rest still has to be digits
		}
		digit := i64(c - '0')
		if accumulator < MULTIPLY_LIMIT {
			overflowed = true
			continue
		}
		accumulator *= 10
		if accumulator < min(i64) + digit {
			overflowed = true
			continue
		}
		accumulator -= digit
	}
	if overflowed {
		return 0, false, true
	}
	if !negative {
		if accumulator == min(i64) {
			return 0, false, true // one past max(i64), written positive
		}
		return -accumulator, true, true
	}
	return accumulator, true, true
}

// valid_numeric_lexical rejects the forms `strconv` accepts and XSD does not.
// "1e5" is not an xsd:decimal, "0x10" is not any of these, and an empty
// mantissa is not a number — and every one of them would otherwise turn an
// ill-typed literal into a number, which is the whole failure this file exists
// to stop.
@(private = "file")
valid_numeric_lexical :: proc(s: string, family: Numeric_Family) -> bool {
	if family == .Floating {
		// XSD spells the specials in capitals and signs only the infinities:
		// `+INF` and `-INF` are in the lexical space and `-NaN` is not. Matched
		// here, before the sign is stripped, so that asymmetry survives — and
		// once it does, `strconv.parse_f64` reads every form this procedure
		// admits, which is why there is no decoder for them on the other side.
		switch s {
		case "INF", "+INF", "-INF", "NaN":
			return true
		}
	}
	body := s
	if len(body) > 0 && (body[0] == '+' || body[0] == '-') {
		body = body[1:]
	}
	if len(body) == 0 {
		return false
	}
	// The mantissa runs to the end or to the exponent marker: digits with at
	// most one dot, and at least one digit.
	end := 0
	digits, dots := 0, 0
	for ; end < len(body); end += 1 {
		c := body[end]
		switch {
		case c >= '0' && c <= '9':
			digits += 1
			continue
		case c == '.':
			dots += 1
			continue
		}
		break
	}
	if digits == 0 || dots > 1 {
		return false
	}
	if end == len(body) {
		return true
	}

	// An exponent, and only for the floating types: `1e5` is not an
	// xsd:decimal, and neither is `1.5.5` or `1e5.5` an xsd:double.
	if family != .Floating || (body[end] != 'e' && body[end] != 'E') {
		return false
	}
	exponent := body[end + 1:]
	if len(exponent) > 0 && (exponent[0] == '+' || exponent[0] == '-') {
		exponent = exponent[1:]
	}
	if len(exponent) == 0 {
		return false
	}
	for i in 0 ..< len(exponent) {
		if exponent[i] < '0' || exponent[i] > '9' {
			return false
		}
	}
	return true
}

// ---- Dates and times -------------------------------------------------------

// decode_instant reads an xsd:dateTime or xsd:date lexical form.
@(private = "file")
decode_instant :: proc(lexical: string, kind: Instant_Kind) -> (value: Value, status: Lexical_Status) {
	instant, ok := parse_instant(strings.trim_space(lexical), kind)
	if !ok {
		return nil, .Ill_Formed
	}
	return instant, .Well_Formed
}

// parse_instant reads `-?yyyy+-MM-dd` followed, for a dateTime, by
// `Thh:mm:ss(.s+)?`, and then an optional timezone.
//
// The field *ranges* are checked as well as the shape, which is what makes this
// a well-formedness test rather than a parse: `"2011-02-30"^^xsd:date` has the
// right shape, no thirtieth of February, and must be ill-formed.
//
// It allocates nothing. Completing a date into a dateTime by concatenation
// would be shorter and would put an allocation on a path `tests/guards`
// promises is flat.
@(private = "file")
parse_instant :: proc(s: string, kind: Instant_Kind) -> (instant: Instant, ok: bool) {
	instant.kind = kind
	rest := s
	negative_year := false
	if strings.has_prefix(rest, "-") {
		negative_year = true
		rest = rest[1:]
	}

	// The year is four digits or more, so it is read to the separator rather
	// than sliced at a fixed width. Scanning for the last '-' instead would
	// find the timezone's.
	year_digits := 0
	for year_digits < len(rest) && rest[year_digits] >= '0' && rest[year_digits] <= '9' {
		year_digits += 1
	}
	if year_digits < 4 || year_digits >= len(rest) || rest[year_digits] != '-' {
		return {}, false
	}
	year := parse_field(rest[:year_digits]) or_return
	rest = rest[year_digits + 1:]
	if negative_year {
		year = -year
	}

	if len(rest) < 5 || rest[2] != '-' {
		return {}, false
	}
	month := parse_field(rest[0:2]) or_return
	day := parse_field(rest[3:5]) or_return
	rest = rest[5:]
	if month < 1 || month > 12 || day < 1 || day > days_in_month(year, month) {
		return {}, false
	}

	hour, minute := 0, 0
	second := f64(0)
	if kind == .Date_Time {
		if len(rest) < 9 || rest[0] != 'T' || rest[3] != ':' || rest[6] != ':' {
			return {}, false
		}
		hour = parse_field(rest[1:3]) or_return
		minute = parse_field(rest[4:6]) or_return
		rest = rest[7:]
		// Two digits, then an optional fraction of at least one digit. The
		// width is fixed, so "12:00:123" is not a time however it parses.
		parse_field(rest[0:2]) or_return
		seconds_end := 2
		if seconds_end < len(rest) && rest[seconds_end] == '.' {
			seconds_end += 1
			fraction_start := seconds_end
			for seconds_end < len(rest) && rest[seconds_end] >= '0' && rest[seconds_end] <= '9' {
				seconds_end += 1
			}
			if seconds_end == fraction_start {
				return {}, false
			}
		}
		second = strconv.parse_f64(rest[:seconds_end]) or_return
		rest = rest[seconds_end:]
		// 24:00:00 is XSD's spelling of the next day's midnight, and the only
		// hour above 23 it admits.
		if hour == 24 && (minute != 0 || second != 0) {
			return {}, false
		}
		if hour > 24 || minute > 59 || second >= 60 {
			return {}, false
		}
	}

	offset := 0
	switch {
	case rest == "":
	case rest == "Z":
		instant.has_tz = true
	case len(rest) == 6 && (rest[0] == '+' || rest[0] == '-') && rest[3] == ':':
		zone_hours := parse_field(rest[1:3]) or_return
		zone_minutes := parse_field(rest[4:6]) or_return
		if zone_minutes > 59 || zone_hours * 60 + zone_minutes > 14 * 60 {
			return {}, false
		}
		offset = zone_hours * 60 + zone_minutes
		if rest[0] == '-' {
			offset = -offset
		}
		instant.has_tz = true
	case:
		return {}, false
	}

	instant.seconds = f64(days_from_civil(year, month, day)) * 86_400
	instant.seconds += f64(hour) * 3_600 + f64(minute) * 60 + second
	instant.seconds -= f64(offset) * 60
	return instant, true
}

// parse_field reads a run of digits with no sign and no whitespace, which is
// what every fixed-width field of a date is. `strconv.parse_int` would accept
// "+1" and " 1" and so would let "2011-+1-01" through.
@(private = "file")
parse_field :: proc(s: string) -> (value: int, ok: bool) {
	if len(s) == 0 {
		return 0, false
	}
	n := 0
	for i in 0 ..< len(s) {
		c := s[i]
		if c < '0' || c > '9' {
			return 0, false
		}
		n = n * 10 + int(c - '0')
	}
	return n, true
}

@(private = "file")
days_in_month :: proc(year, month: int) -> int {
	switch month {
	case 1, 3, 5, 7, 8, 10, 12:
		return 31
	case 4, 6, 9, 11:
		return 30
	case 2:
		leap := year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
		return 29 if leap else 28
	}
	return 0
}

// days_from_civil is Howard Hinnant's civil-to-days algorithm: days since
// 1970-01-01 for a proleptic Gregorian date. Written out rather than taken from
// core:time, which cannot hold the years outside its own range that XSD permits.
@(private = "file")
days_from_civil :: proc(y, m, d: int) -> int {
	year := y
	year -= 1 if m <= 2 else 0
	era := (year if year >= 0 else year - 399) / 400
	year_of_era := year - era * 400
	day_of_year := (153 * (m + (-3 if m > 2 else 9)) + 2) / 5 + d - 1
	day_of_era := year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year
	return era * 146_097 + day_of_era - 719_468
}

// ---- Comparison ------------------------------------------------------------

// compare_values orders two values, and says so when it cannot.
//
// A pair from different families is `.Incomparable` rather than ordered by some
// arbitrary rule — a number has no position among strings — and so is a pair
// where either side has no value at all. That is the case the value-range
// components lean on hardest: `sh:minInclusive 4` against `ex:John` and against
// `"abc"^^xsd:integer` are both "cannot be shown to be in range", and both
// violate, without either needing a case of its own.
@(private)
compare_values :: proc(a, b: Value) -> Comparison {
	#partial switch left in a {
	case i64:
		#partial switch right in b {
		case i64:
			return order_i64(left, right)
		case f64:
			return order_f64(f64(left), right)
		}
	case f64:
		#partial switch right in b {
		case i64:
			return order_f64(left, f64(right))
		case f64:
			return order_f64(left, right)
		}
	case bool:
		#partial switch right in b {
		case bool:
			if left == right {
				return .Equal
			}
			return .Less if right else .Greater
		}
	case string:
		#partial switch right in b {
		case string:
			return order_text(left, right)
		}
	case Instant:
		#partial switch right in b {
		case Instant:
			return order_instants(left, right)
		}
	}
	return .Incomparable
}

@(private = "file")
order_i64 :: proc(a, b: i64) -> Comparison {
	switch {
	case a < b:
		return .Less
	case a > b:
		return .Greater
	}
	return .Equal
}

// order_f64 is where NaN earns its case: it is unordered against every value
// including itself, so it is `.Incomparable` rather than `.Equal`.
@(private = "file")
order_f64 :: proc(a, b: f64) -> Comparison {
	if math.is_nan(a) || math.is_nan(b) {
		return .Incomparable
	}
	switch {
	case a < b:
		return .Less
	case a > b:
		return .Greater
	}
	return .Equal
}

// order_text compares by code point, which for UTF-8 is byte order.
//
// Written out rather than calling `strings.compare`, which reaches
// `runtime.memory_compare` and answers from the data pointers before it looks at
// the lengths — so two empty strings with different backing pointers compare as
// unequal. odin-rdf-sparql hit exactly that and it silently matched nothing.
@(private = "file")
order_text :: proc(a, b: string) -> Comparison {
	shared := min(len(a), len(b))
	for i in 0 ..< shared {
		if a[i] != b[i] {
			return .Less if a[i] < b[i] else .Greater
		}
	}
	switch {
	case len(a) < len(b):
		return .Less
	case len(a) > len(b):
		return .Greater
	}
	return .Equal
}

// order_instants applies XSD's partial order over dates and times.
//
// A value written without a timezone does not denote one instant but any instant
// within ±14 hours of it — the range of legal timezones — so it orders
// definitely against a timezoned value only when the whole window falls on one
// side. Overlapping windows are **indeterminate**, which is `.Incomparable` and
// not `.Equal`.
//
// This is not the rule a reasonable person would guess, and two suite entries
// are built on it. `minInclusive-002` sets a timezoned minimum and expects
// `"2002-10-10T12:00:00"^^xsd:dateTime` to violate it; `minInclusive-003`
// inverts the pair and expects `"2002-10-10T12:00:01-05:00"^^xsd:dateTime` — a
// value a naive implicit-UTC reading would call *later* — to violate too. Both
// fall out of indeterminacy, and neither falls out of picking an implicit
// timezone.
@(private = "file")
order_instants :: proc(a, b: Instant) -> Comparison {
	// A date is not a dateTime, whatever the two denote.
	if a.kind != b.kind {
		return .Incomparable
	}
	if a.has_tz == b.has_tz {
		return order_f64(a.seconds, b.seconds)
	}
	MAX_TIMEZONE_SECONDS :: f64(14 * 3_600)
	a_low, a_high := a.seconds, a.seconds
	b_low, b_high := b.seconds, b.seconds
	if a.has_tz {
		b_low -= MAX_TIMEZONE_SECONDS
		b_high += MAX_TIMEZONE_SECONDS
	} else {
		a_low -= MAX_TIMEZONE_SECONDS
		a_high += MAX_TIMEZONE_SECONDS
	}
	if a_high < b_low {
		return .Less
	}
	if a_low > b_high {
		return .Greater
	}
	return .Incomparable
}
