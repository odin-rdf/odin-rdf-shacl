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
Suite :: struct {
	dir:      string,
	includes: int,
	entries:  int,
	enabled:  bool,
}

// The inventory, pinned at the commit recorded in tests/w3c/README.md.
//
// **Every directory is enabled at SHACL-T-0019, and the corpus is 98 of 98.**
// The order they came on records what each one cost:
//
//   - `core/targets` and `core/path` were the spine's exit criteria
//     (SHACL-T-0007), green when the validator that produces a report landed.
//   - `core/misc` and `core/validation-reports` joined at SHACL-T-0008, and
//     `core/misc` only after three bugs it alone catches were fixed:
//     `sh:resultMessage` (the report renames `sh:message`), `sh:severity`
//     accepting any IRI rather than three, and `sh:conforms` being false for
//     *any* result rather than only violations.
//   - `core/node` joined at SHACL-T-0018 — the first directory the catalogue
//     initiative enabled, and the first needing more than the spine's seven
//     components. All thirty-two entries went green at once when the
//     shape-based constraints landed.
//   - `core/property` and `core/complex` joined here, at SHACL-T-0019, and
//     **both were blocked by the same defect rather than by any missing
//     component**. A report names blank nodes from three graphs — its own, the
//     data graph's, and the shapes graph's — and both stores label loaded blank
//     nodes `b0`, `b1`, … from zero, per store. The report merged all three
//     namespaces without standardising them apart, so `property/nodeKind-001`
//     came out asserting `_:b3 sh:sourceShape _:b3` (a result node and the shape
//     it blamed collapsed into one node) and `complex/personexample` conflated a
//     blank-node source shape with a data-graph value. See `shacl/report.odin`
//     — `fresh_blank` and `shape_term` — for the fix and for the namespaces.
//
// **`core/complex` is the entry in this table that changed meaning, and it is
// worth reading before the SHACL-SPARQL phase starts.** It was carried through
// SHACL-I-0002 as belonging to that phase, on the documented belief that its two
// entries need `sh:sparql`, `sh:shapesGraph`, and `sh:entailment` — and that
// `shacl-shacl` passed only because an engine that ignores a constraint produces
// the conforming report it expects. Reading the corpus at SHACL-T-0019 says
// otherwise. `sh:sparql` occurs exactly once in `shacl-shacl-data-shapes.ttl`,
// as an object of `sh:targetSubjectsOf`; `sh:shapesGraph` and `sh:entailment`
// occur as objects of `sh:targetObjectsOf`. All three are *targeted vocabulary*,
// not constraint parameters, and nothing in that file asks for a query engine.
//
// The green is not inaction either, which was the standing worry and is now
// measured rather than argued: the ignored-parameter record is empty for both
// entries, and breaking `sh:datatype` or `sh:nodeKind` in the evaluator turns
// **both** of them red. An engine that was doing nothing would leave
// `shacl-shacl` green under any breakage at all.
SUITES := []Suite {
	{"core/targets", 7, 7, true},
	{"core/path", 13, 13, true},
	{"core/node", 32, 32, true},
	{"core/property", 38, 38, true},
	{"core/misc", 5, 5, true},
	{"core/complex", 2, 2, true},
	{"core/validation-reports", 1, 1, true},
}

// TOTAL_ENTRIES is asserted against the sum of the table above, so adding a
// directory without updating the total — or vice versa — fails.
TOTAL_ENTRIES :: 98

// ENABLED_ENTRIES is how many entries actually run, pinned separately and
// asserted against both the table and the number the runner really executed.
// A directory that quietly stopped being enabled, or a runner that quietly
// skipped an entry, has to fail somewhere; this is where.
//
// **98 at SHACL-T-0019**, up from 58: the whole vendored corpus. It stayed
// separate from TOTAL_ENTRIES rather than being replaced by it, because the
// SHACL-SPARQL phase vendors `sparql/` and the two part company again on that
// day.
ENABLED_ENTRIES :: 98

// **The progress floor was retired at SHACL-T-0019**, along with
// `floor_test.odin` and the `floor` field on Suite. It was SHACL-T-0009's whole
// task and it did the job it was built for: per-directory enablement gave the
// catalogue initiative no signal until nearly every component of §4 existed, so
// a non-gating per-entry count filled ten tasks' worth of silence, moving 18 →
// 21 → 31 → 42 → 49 → 51 → 63 as the families landed.
//
// It is gone because a floor measures *disabled* directories and there are none
// left. A floor over an empty set is a test that asserts nothing while looking
// like a scoreboard, which is the exact failure mode the floor's own header
// spent a page warning about.
//
// **The SHACL-SPARQL phase will want it back** the day it vendors `sparql/`, and
// should restore it rather than reinvent it: `git show SHACL-T-0019~1 --
// tests/w3c/harness/floor_test.odin`. What is worth carrying back with it is the
// caveat it printed on every run — a count is a direction of travel, not a
// conformance claim, because an entry expecting `sh:conforms true` passes
// whether it was validated or ignored.
