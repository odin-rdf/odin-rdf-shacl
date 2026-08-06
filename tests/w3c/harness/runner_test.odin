package w3c

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import shacl "../../../shacl"

// The conformance run itself: every entry of every enabled directory, against
// both backends, at whichever `Term_ID` width the build chose.
//
// **Enabled means fully green.** There is no skip list and no expected-failure
// file, so this test is the whole scoreboard: a directory either passes
// entirely or is not in `SUITES` with `enabled` set. What that costs is real —
// one entry short and the directory goes back off, with the reason recorded —
// and it is the reason a passing suite here means something.
//
// The entry count is asserted as well as the comparisons, because a runner that
// silently ran nothing would otherwise be indistinguishable from one that
// passed everything.

@(private = "file")
Counts :: struct {
	entries: int,
	passed:  int,
}

@(test)
test_enabled_suites_are_green :: proc(t: ^testing.T) {
	counts: Counts
	for backend in Backend {
		per_backend: Counts
		for suite in SUITES {
			if !suite.enabled {
				continue
			}
			run_suite(t, suite, backend, &per_backend)
		}
		testing.expectf(
			t,
			per_backend.entries == ENABLED_ENTRIES,
			"%s: ran %d entries, ENABLED_ENTRIES pinned at %d",
			backend_name(backend),
			per_backend.entries,
			ENABLED_ENTRIES,
		)
		counts.entries += per_backend.entries
		counts.passed += per_backend.passed
	}
	testing.expectf(
		t,
		counts.passed == counts.entries,
		"%d of %d entry runs matched their expected report",
		counts.passed,
		counts.entries,
	)
}

// The pinned enabled count and the pinned per-directory counts must agree, so
// enabling a directory without updating ENABLED_ENTRIES cannot pass quietly.
@(test)
test_enabled_entry_count_is_consistent :: proc(t: ^testing.T) {
	total := 0
	enabled := 0
	for suite in SUITES {
		total += suite.entries
		if suite.enabled {
			enabled += suite.entries
		}
	}
	testing.expect_value(t, total, TOTAL_ENTRIES)
	testing.expect_value(t, enabled, ENABLED_ENTRIES)
}

@(private = "file")
run_suite :: proc(t: ^testing.T, suite: Suite, backend: Backend, counts: ^Counts) {
	manifest_path, _ := filepath.join({SUITE_ROOT, suite.dir, "manifest.ttl"})
	defer delete(manifest_path)
	manifest, manifest_err := os.read_entire_file(manifest_path, context.allocator)
	if !testing.expectf(t, manifest_err == nil, "cannot read %s: %v", manifest_path, manifest_err) {
		return
	}
	defer delete(manifest)

	includes := parse_includes(string(manifest), "manifest.ttl")
	defer destroy_includes(&includes)

	for name in includes {
		file_path, _ := filepath.join({SUITE_ROOT, suite.dir, name})
		defer delete(file_path)
		source, err := os.read_entire_file(file_path, context.allocator)
		if !testing.expectf(t, err == nil, "cannot read %s: %v", file_path, err) {
			continue
		}
		defer delete(source)

		tf := parse_test_file(string(source), name)
		defer destroy_test_file(&tf)

		for e in tf.entries {
			counts.entries += 1
			if run_one(t, suite, backend, &tf, e) {
				counts.passed += 1
			}
		}
	}
}

@(private = "file")
run_one :: proc(t: ^testing.T, suite: Suite, backend: Backend, tf: ^Test_File, e: Entry) -> bool {
	origin := strings.concatenate({backend_name(backend), " ", suite.dir, "/", e.id})
	defer delete(origin)

	report: shacl.Report
	shacl.report_init(&report)
	defer shacl.report_destroy(&report)

	run := run_entry(&report, suite.dir, e, backend, e.id)
	if !testing.expectf(t, run.ok, "%s: could not be validated — %s", origin, run.detail) {
		return false
	}

	expected := expected_report(tf, e)
	defer delete(expected)

	produced := shacl.report_triples(&report)
	if report_isomorphic(produced, expected[:]) {
		return true
	}

	// A bare "not isomorphic" is unactionable, and these graphs are small.
	got := graph_text(produced)
	defer delete(got)
	want := graph_text(expected[:])
	defer delete(want)
	testing.expectf(t, false, "%s: report mismatch\n  produced:%s\n  expected:%s", origin, got, want)
	return false
}
