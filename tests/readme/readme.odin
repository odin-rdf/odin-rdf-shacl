// Package readme compiles and asserts the README's examples, so the
// documentation cannot drift from the real API. The family's
// README-as-contract convention, established by odin-rdf-parser's
// tests/readme and carried into odin-rdf-sparql by SPARQL-T-0009.
//
// The README has no compiled example yet — the public API it would
// demonstrate arrives across SHACL-T-0003 through SHACL-T-0007, and
// SHACL-T-0008 writes the example and the contract documentation together.
// The package exists now so the convention is in the pinned package list from
// the first commit rather than remembered later (SHACL-T-0001).
package readme

import "core:testing"

// A placeholder so the package has a test to run before the README has an
// example to assert. Replaced by the real quick-start test in SHACL-T-0008.
@(test)
test_readme_package_builds :: proc(t: ^testing.T) {
	testing.expect(t, true)
}
