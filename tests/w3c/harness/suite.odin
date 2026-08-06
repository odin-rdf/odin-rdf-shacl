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
// `core/targets` and `core/path` are the spine's exit criteria, enabled in
// SHACL-T-0007 when the validator that greens them landed. Every remaining
// directory needs constraint components the spine deliberately does not
// implement — the logical combinators, the value-range and string families,
// `sh:node`, `sh:closed` — and belongs to the catalogue initiative, which turns
// them on one at a time under the same rule.
SUITES := []Suite {
	{"core/targets", 7, 7, true},
	{"core/path", 13, 13, true},
	{"core/node", 32, 32, false},
	{"core/property", 38, 38, false},
	{"core/misc", 5, 5, false},
	{"core/complex", 2, 2, false},
	{"core/validation-reports", 1, 1, false},
}

// TOTAL_ENTRIES is asserted against the sum of the table above, so adding a
// directory without updating the total — or vice versa — fails.
TOTAL_ENTRIES :: 98

// ENABLED_ENTRIES is how many entries actually run, pinned separately and
// asserted against both the table and the number the runner really executed.
// A directory that quietly stopped being enabled, or a runner that quietly
// skipped an entry, has to fail somewhere; this is where.
ENABLED_ENTRIES :: 20
