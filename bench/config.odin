package main

// The standing configurations, and their pinned read counts.
//
// **A pin, not a threshold.** The expected read count for each configuration is
// a constant here, asserted on every run, and it changes only by a deliberate
// edit with a diff behind it. That is this family's most characteristic
// mechanism — `TOTAL_ENTRIES`, `ENABLED_ENTRIES`, and the progress floor
// SHACL-T-0019 retired all work this way — applied to the one metric in this
// package that can carry it. A timing threshold would either flap or be set so
// loose it caught nothing; an exact integer does neither.
//
// **Re-pinning is not an admission of a bug.** An engine change that reads more
// may be entirely right — a component that was silently skipping work, say. The
// pin does not say the number must never move; it says the number must never
// move *unnoticed*. If you change one, say in the commit message what made the
// engine ask the store more or fewer questions.
//
// `UNPINNED` is for a configuration whose number has not been measured yet. It
// reports rather than fails, and leaving one in a committed tree is a bug: the
// point is the assertion, and a configuration that cannot fail is decoration.
UNPINNED :: -1

// Sizes are deliberately modest — but not *too* modest, and the floor was found
// by measurement rather than chosen.
//
// At 100 focus nodes a validation took a few hundred microseconds, and at that
// scale the numbers would not hold still: `dense` (1200 results) timed faster
// than `clean` (0 results) on an identical walk with an identical read count,
// which is impossible and was therefore noise wearing a result's clothes. At
// 500 the same measurement is milliseconds and the ordering is stable.
//
// That is the trade to keep in mind before shrinking these: too small is not
// merely imprecise, it is *confidently wrong*, and a benchmark's whole value is
// that you can believe what it says. Too large only costs wall clock — kvstore
// especially, where every read is an LMDB transaction. If a question needs more
// data, add a configuration rather than inflating these.
CONFIGS := []Config {
	// The reference configuration. This is the one quoted in the README
	// (SHACL-T-0024), because a single number a reader can extrapolate from
	// beats a matrix nobody reads — the matrix lives in Metis.
	//
	// **It is also the qualified-family-absent control**, which is not
	// incidental: SHACL-T-0025 has to be able to conclude that a `(shape, node)`
	// conformance cache is *not* worth it, and it can only do that against a
	// workload that does not stress the corner the cache exists for.
	{
		name = "baseline",
		seed = 0x5EED_0001,
		focus_nodes = 500,
		fan_out = 4,
		shapes = 3,
		nesting = 0,
		path_form = .Predicate,
		violation_percent = 20,
		qualified = .None,
	},

	// The same workload with the qualified family switched on, and nothing else
	// changed. The pair is the whole point: `qualified` minus `baseline` is what
	// the qualified family costs, and it is the number SHACL-T-0025 argues over.
	{
		name = "qualified",
		seed = 0x5EED_0001,
		focus_nodes = 500,
		fan_out = 4,
		shapes = 3,
		nesting = 0,
		path_form = .Predicate,
		violation_percent = 20,
		qualified = .Disjoint_Pair,
	},

	// Nesting exercises suppressed validation through `sh:node` — a sub-walk per
	// focus node per level, sharing the outer stack (SHACL-A-0002).
	{
		name = "nested",
		seed = 0x5EED_0001,
		focus_nodes = 500,
		fan_out = 4,
		shapes = 3,
		nesting = 3,
		path_form = .Predicate,
		violation_percent = 20,
		qualified = .None,
	},

	// Violation density at both ends. `dense` is what tests the package doc's
	// promise that memory stays flat *exactly when the data is worst*, and
	// `clean` is its control: same shapes, same paths, nothing to report.
	//
	// **Expect `dense` to be the fastest configuration here, and do not read
	// that as an artifact.** It reproduces to within a few percent across runs
	// and it has a cause: the constraint is `sh:class ex:Good`, a violating
	// value node is one whose type triple was never emitted, and a match with
	// no results terminates immediately. Conformance costs a yielded quad and a
	// comparison; violation costs an empty iterator. In *this* workload
	// violations really are cheaper to find than conformance, and the three
	// configurations sharing a read count is the evidence that nothing else
	// differs between them.
	{
		name = "dense",
		seed = 0x5EED_0001,
		focus_nodes = 500,
		fan_out = 4,
		shapes = 3,
		nesting = 0,
		path_form = .Predicate,
		violation_percent = 100,
		qualified = .None,
	},
	{
		name = "clean",
		seed = 0x5EED_0001,
		focus_nodes = 500,
		fan_out = 4,
		shapes = 3,
		nesting = 0,
		path_form = .Predicate,
		violation_percent = 0,
		qualified = .None,
	},

	// One non-trivial path form in the standing set. Alternative was chosen over
	// the other three because it costs the most per value node — an RDF list
	// walked at compile time and two branches walked at evaluation — so it is
	// the one most likely to show a regression. The other forms are a knob away
	// for anyone investigating.
	{
		name = "alternative-path",
		seed = 0x5EED_0001,
		focus_nodes = 500,
		fan_out = 4,
		shapes = 3,
		nesting = 0,
		path_form = .Alternative,
		violation_percent = 20,
		qualified = .None,
	},

	// **The pair SHACL-T-0025 exists to measure.** Identical in every knob but
	// the qualified form: one bound against two bounds sharing a single
	// `sh:qualifiedValueShape`. The difference is the structural duplicate and
	// nothing else, which is what makes it a measurement rather than an
	// argument.
	//
	// **They now measure the same thing, and that is the result rather than a
	// reason to drop one** (SHACL-T-0026). The duplicate is gone, so the pair has
	// become a regression test for its absence: a change that reintroduces a
	// per-bound walk separates two configurations that are supposed to agree, and
	// the two pins below catch it in the same run.
	{
		name = "qualified-min",
		seed = 0x5EED_0001,
		focus_nodes = 500,
		fan_out = 4,
		shapes = 3,
		nesting = 0,
		path_form = .Predicate,
		violation_percent = 20,
		qualified = .Min,
	},
	{
		name = "qualified-minmax",
		seed = 0x5EED_0001,
		focus_nodes = 500,
		fan_out = 4,
		shapes = 3,
		nesting = 0,
		path_form = .Predicate,
		violation_percent = 20,
		qualified = .Min_And_Max,
	},
}

// PINNED_READS is the expected total store reads per configuration.
//
// One integer per configuration. It used to hold across two backends and two
// `Term_ID` widths — see the history below — and now describes one engine over
// one store with fixed widths: the pin is what keeps the number from moving
// unnoticed, and nothing cross-checks it.
//
// A slice rather than a map: package-level map literals need
// `#+feature dynamic-literals` and would allocate into whatever allocator
// happened to be in scope, for a lookup over eight entries that a linear scan
// answers.
Pin :: struct {
	name:  string,
	reads: int,
}

// **Measured at SHACL-T-0036 over odin-rdf-record**, after the port; the
// instrumented build (`-define:SHACL_COUNT_READS=true`) counts one tick per
// `session_scan`, `session_step`, `session_outgoing` and `session_term`.
//
//	baseline          7503   500 focus nodes x 3 shapes x 4 values, plus targets
//	dense             7503   identical: density changes what is *reported*, not
//	clean             7503   what is *read*. Three configurations, one number —
//	                         which is itself a check on the density knob being
//	                         independent of everything else.
//	alternative-path  9003   +1500 = one extra step per focus node per shape,
//	                         the second branch of the alternative
//	qualified        11504   +4001 over baseline: what the qualified family
//	                         costs when it is present at all (SHACL-T-0025)
//	nested           11596   +4093 for three levels of sh:node, each a
//	                         suppressed sub-walk per focus node
//	qualified-min     9003   one bound, one walk of the value nodes
//	qualified-minmax  9003   two bounds sharing one sh:qualifiedValueShape --
//	                         and, since SHACL-T-0026, one walk between them
//
// **These are the integers odin-rdf-store produced, to the last one** (measured
// at SHACL-T-0023 over memstore and kvstore, re-pinned once at SHACL-T-0026,
// identical at both `Term_ID` widths). The port expected them to differ and
// said so in advance; they did not, and that is the strongest statement the
// port could make about itself: the engine asks the store exactly the
// questions it asked before -- the four session verbs map one-to-one onto the
// old seam's four -- and only what a question *costs* changed. A read on the
// old store was an LMDB cursor; here it is a range over a memory-resident
// permutation. So the pins survived a change of store, which is the invariant
// the old benchmark asserted across two backends and could no longer check
// after memstore was retired, re-established after the fact by a third.
// **Wall clock and allocation are the numbers that are not comparable across
// the port**, not these.
//
// The one re-pin in this file's history: `qualified-minmax` was 10003 before
// SHACL-T-0026. The +1000 was exactly the 1000 `ex:q` value nodes, walked a
// second time to answer a question whose answer could not have changed; the
// two counts now compile to a single constraint that counts once and tests
// the count twice. The pin falling to `qualified-min`'s was the prediction
// SHACL-T-0026 made in advance, and `qualified` not moving mattered as much:
// it is the `Disjoint_Pair` form, two property shapes with one bound each,
// where there is nothing to share.
PINNED_READS := []Pin {
	{"baseline", 7503},
	{"qualified", 11504},
	{"nested", 11596},
	{"dense", 7503},
	{"clean", 7503},
	{"alternative-path", 9003},
	{"qualified-min", 9003},
	{"qualified-minmax", 9003},
}

pinned_reads :: proc(name: string) -> (reads: int, found: bool) {
	for p in PINNED_READS {
		if p.name == name {
			return p.reads, true
		}
	}
	return 0, false
}
