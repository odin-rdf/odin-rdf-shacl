package w3c

// SUITE_ROOT locates the vendored corpus from this source file rather than
// from the working directory, so `odin test` works from anywhere.
SUITE_ROOT :: #directory + ".."

// Suite is one vendored directory of the W3C SHACL test suite, with the
// counts that guard against a silently-truncated read.
//
// `includes` is how many `mf:include` references the directory's manifest.ttl
// holds; `entries` is how many `sht:Validate` entries those files declare
// between them. Both are pinned rather than computed: a Turtle parser bug
// that dropped statements would otherwise shrink the corpus and the suite
// would still pass. This is the circularity guard odin-rdf-parser introduced
// and odin-rdf-sparql inherited.
//
// `enabled` follows the family's rule exactly — **enabled means fully green**.
// There is no skip list and no expected-failure file; a directory is either
// entirely passing or entirely off, and turning one on is a deliberate act
// recorded in the task that did it.
//
// `floor` is how many entries a **disabled** directory passes today, pinned as
// a minimum rather than an equality. It enables nothing and excuses nothing; it
// exists because the catalogue initiative would otherwise run most of its
// length with no measured progress at all. An enabled directory leaves it 0 —
// it is fully green by definition. See floor_test.odin for what the number does
// and, more importantly, does not mean.
Suite :: struct {
	dir:      string,
	includes: int,
	entries:  int,
	enabled:  bool,
	floor:    int,
}

// The inventory, pinned at the commit recorded in tests/w3c/README.md.
//
// `core/targets` and `core/path` are the spine's exit criteria, enabled in
// SHACL-T-0007 when the validator that greens them landed.
//
// `core/misc` and `core/validation-reports` joined them in SHACL-T-0008.
// Neither exercises a constraint component outside the spine's seven, and the
// verification pass found both green — `core/misc` only after three bugs it
// alone catches were fixed: `sh:resultMessage` (the report renames
// `sh:message`), `sh:severity` accepting any IRI rather than three, and
// `sh:conforms` being false for *any* result rather than only violations.
// Leaving a green directory disabled would misstate the position as surely as
// enabling a broken one, so they are on.
//
// The three that remain need constraint components the spine deliberately does
// not implement, and after SHACL-T-0016 the list is down to the two structural
// families: the logical combinators and the shape-based constraints. They belong
// to the catalogue initiative, which turns the directories on one at a time under
// the same rule. `core/complex` additionally needs `sh:sparql`, so it belongs to
// the SHACL-SPARQL phase rather than to the catalogue.
// The floors were measured by this table's own instrumentation at SHACL-T-0009,
// and they reproduce the diagnostic figure SHACL-I-0001 closed on: 18 of the 69
// entries in `core/node` and `core/property`, which is why the catalogue's real
// work is 51 entries rather than 69.
//
// **`core/complex` is pinned at 0 deliberately, and it is the exception worth
// reading.** It scores 1 of 2 today, and that entry — `shacl-shacl`, SHACL's own
// shapes validating SHACL's own shapes — expects `sh:conforms true`. It needs
// `sh:sparql`, `sh:shapesGraph`, and `sh:entailment`, none of which exist here,
// so what the engine is doing is not validating it but ignoring most of it and
// finding nothing to report. Pinning that as a floor would pin the clearest
// example in the tree of an entry passing for the wrong reason — and it is
// fragile in the other direction too: as the catalogue lands components, that
// shapes graph starts producing real results and the entry may well go red
// before it goes green for the right reason. It belongs to the SHACL-SPARQL
// phase, and it is counted and printed here without being pinned.
SUITES := []Suite {
	{"core/targets", 7, 7, true, 0},
	{"core/path", 13, 13, true, 0},
	{"core/node", 32, 32, false, 24},
	{"core/property", 38, 38, false, 27},
	{"core/misc", 5, 5, true, 0},
	{"core/complex", 2, 2, false, 0},
	{"core/validation-reports", 1, 1, true, 0},
}

// TOTAL_ENTRIES is asserted against the sum of the table above, so adding a
// directory without updating the total — or vice versa — fails.
TOTAL_ENTRIES :: 98

// ENABLED_ENTRIES is how many entries actually run, pinned separately and
// asserted against both the table and the number the runner really executed.
// A directory that quietly stopped being enabled, or a runner that quietly
// skipped an entry, has to fail somewhere; this is where.
ENABLED_ENTRIES :: 26

// PROGRESS_FLOOR is the sum of the disabled directories' floors, pinned
// separately from them for the same reason ENABLED_ENTRIES is pinned separately
// from `enabled`: a number that can be edited in one place only is not a pin.
// Raising a directory's floor without raising this fails.
//
// It starts at the catalogue initiative's measured 18 — `core/node` 7 plus
// `core/property` 11 — and every component task is expected to move it.
//
// **21 at SHACL-T-0012**, and the four entries it moved split two ways, which is
// worth recording because only two of them are the engine getting better.
// `sh:datatype` gaining its §4.3.1 lexical check took `property/datatype-ill-formed`
// and `node/datatype-001`. The other two — `node/class-002` and the rest of
// `node/datatype-001`'s expected graph — came from a defect in this harness:
// `expected_report` followed `sh:focusNode` into the *data* graph whenever an
// entry's focus node was a blank node, so it demanded triples no report can
// contain. Every `core/node` value-range entry has that shape, so it would have
// been read as an engine failure for the whole of SHACL-T-0013.
//
// **31 at SHACL-T-0013**, which is every one of the ten value-range entries in
// the corpus and nothing else: `core/node` gained its six `min`/`maxInclusive`
// and `min`/`maxExclusive` entries, `core/property` its four.
//
// **42 at SHACL-T-0014**, again the whole family at once: the eleven remaining
// `minLength`, `maxLength`, `pattern`, `languageIn`, and `uniqueLang` entries.
// `property/uniqueLang-002` was already in the floor and stayed there for a
// different reason — it used to pass because nothing implemented `sh:uniqueLang`,
// and now passes because the implementation reads `"1"^^xsd:boolean` as not
// switching the component on, which is what that entry exists to check. It is
// the one entry in the tree that went from passing-by-inaction to
// passing-by-validation, which is the transition the note above `core/complex`
// warns can go the other way.
//
// **49 at SHACL-T-0015** — the seven property-pair entries. It moved by nothing
// at all on the first run, which is the failure mode worth recording here as
// well as in the code: `bindings_init` resolves a constraint's parameter to a
// data-store ID from a kind-switch, a component missing from it reads its
// parameter as unbound rather than erroring, and four components therefore
// dispatched, ran, and found an empty second set on every focus node. Twenty
// entries of the original 51 remain.
//
// **51 at SHACL-T-0016** — `node/closed-001` and `closed-002`, the whole of
// `sh:closed` in the two catalogue directories. It is the smallest move any
// component task has made and the only one that needed a new way to read the
// data graph: `Access` gained a fourth verb, because its three existing ones
// each yield a single quad position and this component wants a predicate and its
// object together. `core/complex` is unchanged at 1 of 2, still pinned at 0.
// Eighteen entries of the original 51 remain, all of them behind the logical
// combinators and the shape-based constraints.
PROGRESS_FLOOR :: 51
