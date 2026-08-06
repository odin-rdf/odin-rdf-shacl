// Package guards holds allocation-guard tests: tracking-allocator assertions
// that the validator honours the memory contract it publishes — the shapes
// model owns the terms it interned and frees them at destroy, path evaluation
// frees what it allocates, and the streaming result path holds to its stated
// per-result allocation budget.
//
// The pattern comes from odin-rdf-parser's tests/guards by way of
// odin-rdf-sparql's. Populated from SHACL-T-0003 on; the package exists now so
// the Makefile's pinned package list is real from the first commit and the
// convention is established rather than retrofitted (SHACL-T-0001).
package guards

import "core:testing"

// A placeholder so the package has a test to run before the guards exist.
// Replaced, not added to, by the first real guard in SHACL-T-0003.
@(test)
test_guards_package_builds :: proc(t: ^testing.T) {
	testing.expect(t, true)
}
