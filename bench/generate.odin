package main

import "core:fmt"
import "core:strings"

// The synthetic workload (SHACL-I-0003).
//
// **Why a generator rather than the corpus.** The vendored W3C suite is 98
// files chosen to exercise semantics; several are a dozen triples and the
// largest shapes graph is four hundred lines. Benchmarking against it would
// measure the harness. Validation cost is *shapes x data*, so a workload has to
// be built, and the point of building one is that every dimension can be held
// fixed but one.
//
// **What it therefore is not.** These numbers describe a workload this project
// chose. They are a regression instrument and a comparative one — the engine
// against itself over time, and with a change against without — not a claim
// about what SHACL costs in the world. That sentence belongs beside the numbers
// wherever they are quoted, which is why it is here rather than only in Metis.
//
//
// # The shape of the generated pair
//
// One node shape targets `ex:Thing`. It carries `shapes` property shapes, all
// of the same path form, each constraining its value nodes with
// `sh:class ex:Good`. The data holds `focus_nodes` instances, each reaching
// `fan_out` value nodes per property shape.
//
// **Every value node is an IRI, and that is a deliberate simplification.** It
// is what lets one data shape serve all five path forms: an IRI can be the
// subject of the inverse hop, it can carry the second predicate of a sequence,
// and it can be typed or not. A conforming value node is emitted with
// `a ex:Good`; a violating one is the same IRI without that triple. So
// violation density is a property of what the *data* omits, and no shape
// changes with it — which is what makes the density knob independent of the
// others.
//
// `sh:class` was chosen over `sh:datatype` for the constraint because it costs
// a match per value node rather than an inspection of a term already in hand,
// so the store sees the value-node set rather than only the path walk. It is
// also the component the package doc singles out as the most common way a
// shapes graph under-reports, so it is worth having in the measured path.

// Path_Form is which of the five path shapes every property shape in a
// configuration uses. One form per configuration rather than a mixture: the
// knob is only meaningful if changing it changes one thing.
Path_Form :: enum {
	Predicate,
	Inverse,
	Sequence,
	Alternative,
	Zero_Or_More,
}

// Qualified_Form is which shape of the qualified family a configuration
// carries. An enum rather than a bool since SHACL-T-0025, because the family
// has two *different* costs and lumping them together cannot answer that task's
// question.
//
//	None           absent entirely — the control that lets a measurement say no
//	Min            one property shape, one bound. The cheapest form that
//	               exercises the machinery at all
//	Min_And_Max    one property shape, both bounds, **sharing one
//	               sh:qualifiedValueShape**. This is the structural duplicate
//	               SHACL-T-0018 found and SHACL-A-0002 declined to memoise:
//	               check_qualified walks the value nodes once per bound, so the
//	               same (shape, node) question is asked twice with an answer that
//	               cannot have changed in between
//	Disjoint_Pair  two sibling shapes with sh:qualifiedValueShapesDisjoint, which
//	               multiplies the walk by the sibling count instead
//
// `Min_And_Max` minus `Min` is therefore the exact cost of the duplicate, and
// the only difference between those two configurations is the second bound.
Qualified_Form :: enum {
	None,
	Min,
	Min_And_Max,
	Disjoint_Pair,
}

// Config is the seven knobs, plus the seed and a name to report under.
//
// `violation_percent` is an integer rather than a fraction so that a
// configuration is reproducible without anyone having to think about floating
// point. It is compared against a value the generator's own PRNG produces, so
// the number of violating value nodes is a function of the seed and nothing
// else.
Config :: struct {
	name:              string,
	seed:              u64,
	focus_nodes:       int,
	fan_out:           int,
	shapes:            int,
	nesting:           int,
	path_form:         Path_Form,
	violation_percent: int,
	qualified:         Qualified_Form,
}

// Rng is splitmix64, written here rather than taken from `core:math/rand`.
//
// Determinism is not a convenience in this package, it is load-bearing: the two
// read-count invariants and the pinned counts all rest on one seed producing
// byte-identical graphs, on every platform and across toolchain versions. A
// local six-line generator with a specified algorithm cannot drift under us the
// way a core package's stream can. It is not cryptographic and does not need to
// be — nothing here is sampling anything subtle, it is deciding whether to emit
// a type triple.
Rng :: struct {
	state: u64,
}

@(private = "file")
next :: proc(r: ^Rng) -> u64 {
	r.state += 0x9E37_79B9_7F4A_7C15
	z := r.state
	z = (z ~ (z >> 30)) * 0xBF58_476D_1CE4_E5B9
	z = (z ~ (z >> 27)) * 0x94D0_49BB_1331_11EB
	return z ~ (z >> 31)
}

// percent returns a value in 0..<100, for comparing against
// `Config.violation_percent`.
@(private = "file")
percent :: proc(r: ^Rng) -> int {
	return int(next(r) % 100)
}

// Workload is one generated pair. Both strings are owned; `workload_destroy`
// frees them.
//
// `value_nodes` and `violating` are counted as the data is written rather than
// derived afterwards, because they are what the report normalises by and a
// recomputed count is a second implementation that can disagree with the first.
Workload :: struct {
	shapes_ttl:  string,
	data_ttl:    string,
	value_nodes: int,
	violating:   int,
}

workload_destroy :: proc(w: ^Workload) {
	delete(w.shapes_ttl)
	delete(w.data_ttl)
	w^ = {}
}

PREFIXES :: `@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
@prefix ex: <http://example.org/> .
`

// generate builds the shapes graph and the data graph for one configuration.
// Called twice with the same Config, it returns identical strings.
generate :: proc(c: Config) -> Workload {
	w: Workload
	w.shapes_ttl = generate_shapes(c)
	w.data_ttl, w.value_nodes, w.violating = generate_data(c)
	return w
}

// generate_shapes writes the shapes graph. It reads no randomness at all: the
// shapes are a pure function of the knobs, and only the data varies with the
// seed. That split is what makes `violation_percent` independent of everything
// else — turning it up changes which triples the data omits and leaves the
// compiled model identical.
@(private = "file")
generate_shapes :: proc(c: Config) -> string {
	sb := strings.builder_make()
	strings.write_string(&sb, PREFIXES)

	fmt.sbprintln(&sb, "\nex:Root a sh:NodeShape ;")
	fmt.sbprintln(&sb, "\tsh:targetClass ex:Thing ;")
	for i in 0 ..< c.shapes {
		fmt.sbprintfln(&sb, "\tsh:property [ sh:path %s ; sh:class ex:Good ] ;", path_expr(c.path_form, i))
	}

	// The qualified family, and the reason it is a knob at all: it is the
	// component the memoisation question (SHACL-T-0025) is about, and a
	// configuration *without* it is what lets that measurement say no. Two
	// sibling shapes rather than one, so `sh:qualifiedValueShapesDisjoint` has a
	// sibling to walk — with one, the disjointness test is free and the knob
	// would understate the cost it exists to expose.
	switch c.qualified {
	case .None:
	case .Min:
		fmt.sbprintln(&sb, "\tsh:property [")
		fmt.sbprintln(&sb, "\t\tsh:path ex:q ;")
		fmt.sbprintln(&sb, "\t\tsh:qualifiedValueShape [ sh:class ex:Good ] ;")
		fmt.sbprintln(&sb, "\t\tsh:qualifiedMinCount 1 ;")
		fmt.sbprintln(&sb, "\t] ;")
	case .Min_And_Max:
		// One shape, two bounds, one sh:qualifiedValueShape between them. The
		// engine walks the value nodes once per bound; this configuration
		// exists so that the second walk has a price attached to it.
		fmt.sbprintln(&sb, "\tsh:property [")
		fmt.sbprintln(&sb, "\t\tsh:path ex:q ;")
		fmt.sbprintln(&sb, "\t\tsh:qualifiedValueShape [ sh:class ex:Good ] ;")
		fmt.sbprintln(&sb, "\t\tsh:qualifiedMinCount 1 ;")
		fmt.sbprintln(&sb, "\t\tsh:qualifiedMaxCount 2 ;")
		fmt.sbprintln(&sb, "\t] ;")
	case .Disjoint_Pair:
		fmt.sbprintln(&sb, "\tsh:property [")
		fmt.sbprintln(&sb, "\t\tsh:path ex:q ;")
		fmt.sbprintln(&sb, "\t\tsh:qualifiedValueShape [ sh:class ex:Good ] ;")
		fmt.sbprintln(&sb, "\t\tsh:qualifiedMinCount 1 ;")
		fmt.sbprintln(&sb, "\t\tsh:qualifiedValueShapesDisjoint true ;")
		fmt.sbprintln(&sb, "\t] ;")
		fmt.sbprintln(&sb, "\tsh:property [")
		fmt.sbprintln(&sb, "\t\tsh:path ex:q ;")
		fmt.sbprintln(&sb, "\t\tsh:qualifiedValueShape [ sh:class ex:Other ] ;")
		fmt.sbprintln(&sb, "\t\tsh:qualifiedMaxCount 2 ;")
		fmt.sbprintln(&sb, "\t\tsh:qualifiedValueShapesDisjoint true ;")
		fmt.sbprintln(&sb, "\t] ;")
	}

	// Nesting is a *chain* — Root sh:node Nest0, Nest0 sh:node Nest1, and so on
	// — never a cycle. A shape that reaches itself is `Failure.Recursive_Shape`,
	// which abandons the traversal, and a benchmark that silently measured a
	// third of a walk would be worse than no benchmark.
	if c.nesting > 0 {
		fmt.sbprintfln(&sb, "\tsh:node ex:Nest0 ;")
	}
	fmt.sbprintln(&sb, "\t.")

	for d in 0 ..< c.nesting {
		fmt.sbprintfln(&sb, "\nex:Nest%d a sh:NodeShape ;", d)
		fmt.sbprintfln(
			&sb,
			"\tsh:property [ sh:path %s ; sh:class ex:Good ] ;",
			path_expr(c.path_form, 0),
		)
		if d + 1 < c.nesting {
			fmt.sbprintfln(&sb, "\tsh:node ex:Nest%d ;", d + 1)
		}
		fmt.sbprintln(&sb, "\t.")
	}

	return strings.to_string(sb)
}

// path_expr is the `sh:path` object for one property shape under one form.
@(private = "file")
path_expr :: proc(form: Path_Form, i: int) -> string {
	switch form {
	case .Predicate:
		return fmt.tprintf("ex:p%d", i)
	case .Inverse:
		return fmt.tprintf("[ sh:inversePath ex:back%d ]", i)
	case .Sequence:
		return fmt.tprintf("( ex:hop ex:p%d )", i)
	case .Alternative:
		return fmt.tprintf("[ sh:alternativePath ( ex:p%d ex:alt%d ) ]", i, i)
	case .Zero_Or_More:
		return fmt.tprintf("[ sh:zeroOrMorePath ex:p%d ]", i)
	}
	return ""
}

// generate_data writes the data graph and reports how many value nodes it
// created and how many of them violate.
//
// The value-node IRIs are unique per (focus node, property shape, index) rather
// than shared, so the value-node set really is `focus_nodes * shapes * fan_out`
// and not a much smaller set reached many times. Sharing them would make the
// subclass-closure cache and the store's own locality flatter the engine.
@(private = "file")
generate_data :: proc(c: Config) -> (ttl: string, value_nodes: int, violating: int) {
	r := Rng {
		state = c.seed,
	}

	sb := strings.builder_make()
	strings.write_string(&sb, PREFIXES)
	fmt.sbprintln(&sb, "\nex:Good rdfs:subClassOf ex:Resource .")
	fmt.sbprintln(&sb, "ex:Other rdfs:subClassOf ex:Resource .")

	for k in 0 ..< c.focus_nodes {
		fmt.sbprintfln(&sb, "\nex:n%d a ex:Thing .", k)

		// The sequence form needs one IRI hop between the focus node and its
		// value nodes; every other form reaches them from the focus node
		// directly.
		if c.path_form == .Sequence {
			fmt.sbprintfln(&sb, "ex:n%d ex:hop ex:mid%d .", k, k)
		}

		for i in 0 ..< c.shapes {
			for j in 0 ..< c.fan_out {
				value := fmt.tprintf("ex:v%d_%d_%d", k, i, j)
				value_nodes += 1

				// Conformance is carried by the presence of the type triple and
				// nothing else, so density moves without any other edge moving.
				if percent(&r) < c.violation_percent {
					violating += 1
				} else {
					fmt.sbprintfln(&sb, "%s a ex:Good .", value)
				}

				switch c.path_form {
				case .Predicate, .Zero_Or_More:
					fmt.sbprintfln(&sb, "ex:n%d ex:p%d %s .", k, i, value)
				case .Inverse:
					fmt.sbprintfln(&sb, "%s ex:back%d ex:n%d .", value, i, k)
				case .Sequence:
					fmt.sbprintfln(&sb, "ex:mid%d ex:p%d %s .", k, i, value)
				case .Alternative:
					// Split across the two branches so both are walked; an
					// alternative whose second branch is always empty measures
					// a predicate path with extra list-walking.
					if j % 2 == 0 {
						fmt.sbprintfln(&sb, "ex:n%d ex:p%d %s .", k, i, value)
					} else {
						fmt.sbprintfln(&sb, "ex:n%d ex:alt%d %s .", k, i, value)
					}
				}
			}
		}

		// The qualified family reads `ex:q`, which exists whether or not the
		// shapes graph asks for it — the data is the same either way, so the
		// two configurations differ in the shapes and nowhere else.
		fmt.sbprintfln(&sb, "ex:n%d ex:q ex:qa%d, ex:qb%d .", k, k, k)
		fmt.sbprintfln(&sb, "ex:qa%d a ex:Good .", k)
		fmt.sbprintfln(&sb, "ex:qb%d a ex:Other .", k)
	}

	return strings.to_string(sb), value_nodes, violating
}
