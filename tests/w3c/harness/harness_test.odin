package w3c

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import rdf "rdf:rdf"

import shacl "../../../shacl"

// The corpus is vendored but nothing validates it yet, so what this file
// asserts is that the harness can *read* the suite completely and correctly:
// the manifests parse with the family's own Turtle parser, the pinned counts
// hold, every entry has the shape the runner will rely on, every file an
// entry references exists, and the expected report extracts as a graph.
//
// That is the whole of SHACL-T-0002's testable surface. The pass/fail
// execution wires up in SHACL-T-0007, when there is an engine to run and the
// first two directories are enabled.

@(private = "file")
read_suite_file :: proc(t: ^testing.T, dir, name: string) -> (string, bool) {
	path, _ := filepath.join({SUITE_ROOT, dir, name})
	defer delete(path)
	data, err := os.read_entire_file(path, context.allocator)
	if !testing.expectf(t, err == nil, "cannot read %s: %v", path, err) {
		return "", false
	}
	return string(data), true
}

// Every directory's manifest parses, holds exactly the pinned number of
// includes, and those files declare exactly the pinned number of entries.
@(test)
test_suite_inventory :: proc(t: ^testing.T) {
	total := 0
	for suite in SUITES {
		source, ok := read_suite_file(t, suite.dir, "manifest.ttl")
		if !ok {
			continue
		}
		defer delete(source)

		includes := parse_includes(source, "manifest.ttl")
		defer destroy_includes(&includes)

		testing.expectf(
			t,
			len(includes) == suite.includes,
			"%s: manifest declares %d includes, pinned at %d",
			suite.dir,
			len(includes),
			suite.includes,
		)

		entries := 0
		for name in includes {
			file_source, file_ok := read_suite_file(t, suite.dir, name)
			if !file_ok {
				continue
			}
			defer delete(file_source)

			tf := parse_test_file(file_source, name)
			defer destroy_test_file(&tf)

			testing.expectf(t, tf.parse_ok, "%s/%s: Turtle parse failed", suite.dir, name)
			testing.expectf(
				t,
				len(tf.entries) > 0,
				"%s/%s: included by the manifest but declares no entries",
				suite.dir,
				name,
			)
			entries += len(tf.entries)
		}

		testing.expectf(
			t,
			entries == suite.entries,
			"%s: %d entries across included files, pinned at %d",
			suite.dir,
			entries,
			suite.entries,
		)
		total += entries
	}
	testing.expectf(
		t,
		total == TOTAL_ENTRIES,
		"corpus holds %d entries, TOTAL_ENTRIES pinned at %d",
		total,
		TOTAL_ENTRIES,
	)
}

// Every entry has the shape the runner will depend on, and an unrecognised
// type or status fails hard rather than being skipped — the family's
// "nothing may be silently skipped" rule, applied at read time.
@(test)
test_entry_shape :: proc(t: ^testing.T) {
	for suite in SUITES {
		source, ok := read_suite_file(t, suite.dir, "manifest.ttl")
		if !ok {
			continue
		}
		defer delete(source)
		includes := parse_includes(source, "manifest.ttl")
		defer destroy_includes(&includes)

		for name in includes {
			file_source, file_ok := read_suite_file(t, suite.dir, name)
			if !file_ok {
				continue
			}
			defer delete(file_source)
			tf := parse_test_file(file_source, name)
			defer destroy_test_file(&tf)

			for e in tf.entries {
				origin := strings.concatenate({suite.dir, "/", name, " (", e.id, ")"})
				defer delete(origin)

				testing.expectf(
					t,
					e.type_str == string(SHT_VALIDATE),
					"%s: unhandled entry type %q — nothing may be silently skipped",
					origin,
					e.type_str,
				)
				testing.expectf(
					t,
					e.status == string(SHT_APPROVED),
					"%s: unexpected status %q",
					origin,
					e.status,
				)
				testing.expectf(t, e.id != "", "%s: entry has no identifier", origin)
				testing.expectf(t, e.data_graph != "", "%s: entry names no data graph", origin)
				testing.expectf(t, e.shapes_graph != "", "%s: entry names no shapes graph", origin)
				testing.expectf(
					t,
					e.expectation == .Report,
					"%s: expected a report, got %v — sht:Failure should not occur in core/",
					origin,
					e.expectation,
				)
				testing.expectf(t, e.result_node != nil, "%s: no mf:result node", origin)
			}
		}
	}
}

// Every file an entry names is on disk. Most name the file they live in, but
// a handful use side files, and a typo there would otherwise surface as a
// mysterious empty graph much later.
@(test)
test_referenced_files_exist :: proc(t: ^testing.T) {
	for suite in SUITES {
		source, ok := read_suite_file(t, suite.dir, "manifest.ttl")
		if !ok {
			continue
		}
		defer delete(source)
		includes := parse_includes(source, "manifest.ttl")
		defer destroy_includes(&includes)

		for name in includes {
			file_source, file_ok := read_suite_file(t, suite.dir, name)
			if !file_ok {
				continue
			}
			defer delete(file_source)
			tf := parse_test_file(file_source, name)
			defer destroy_test_file(&tf)

			for e in tf.entries {
				for ref in ([]string{e.data_graph, e.shapes_graph}) {
					path, _ := filepath.join({SUITE_ROOT, suite.dir, ref})
					defer delete(path)
					testing.expectf(
						t,
						os.exists(path),
						"%s/%s (%s): references missing file %q",
						suite.dir,
						name,
						e.id,
						ref,
					)
				}
			}
		}
	}
}

// The expected report extracts as a graph, on an entry whose shape is known
// by hand. path-inverse-001 expects sh:conforms false and two
// sh:ValidationResult nodes, one MinCount and one MaxCount, each carrying a
// blank-node sh:resultPath — which is precisely why comparison has to be
// isomorphism rather than a label match.
@(test)
test_expected_report_extraction :: proc(t: ^testing.T) {
	source, ok := read_suite_file(t, "core/path", "path-inverse-001.ttl")
	if !ok {
		return
	}
	defer delete(source)

	tf := parse_test_file(source, "path-inverse-001.ttl")
	defer destroy_test_file(&tf)

	if !testing.expect_value(t, len(tf.entries), 1) {
		return
	}
	e := tf.entries[0]
	testing.expect_value(t, e.id, "path-inverse-001")
	testing.expect_value(t, e.data_graph, "path-inverse-001.ttl")
	testing.expect_value(t, e.shapes_graph, "path-inverse-001.ttl")

	report := expected_report(&tf, e)
	defer delete(report)

	conforms_false, results, result_paths, min_count, max_count := 0, 0, 0, 0, 0
	for tr in report {
		pred, is_iri := tr.predicate.(rdf.IRI)
		if !is_iri {
			continue
		}
		switch string(pred) {
		case shacl.CONFORMS:
			if lit, is_lit := tr.object.(rdf.Literal); is_lit && lit.lexical == "false" {
				conforms_false += 1
			}
		case shacl.RESULT:
			results += 1
		case shacl.RESULT_PATH:
			// A blank node, not an IRI: [ sh:inversePath ex:child ].
			#partial switch _ in tr.object {
			case rdf.Blank_Node:
				result_paths += 1
			}
		case shacl.SOURCE_CONSTRAINT_COMPONENT:
			if obj, obj_iri := tr.object.(rdf.IRI); obj_iri {
				switch string(obj) {
				case shacl.NS + "MinCountConstraintComponent":
					min_count += 1
				case shacl.NS + "MaxCountConstraintComponent":
					max_count += 1
				}
			}
		}
	}

	testing.expect_value(t, conforms_false, 1)
	testing.expect_value(t, results, 2)
	testing.expect_value(t, result_paths, 2)
	testing.expect_value(t, min_count, 1)
	testing.expect_value(t, max_count, 1)

	// The closure is the report and not the whole document: the file also
	// asserts the data graph and the shapes graph, which are far larger.
	testing.expectf(
		t,
		len(report) < len(tf.statements) / 2,
		"closure took %d of %d statements — it is following IRIs into the data graph",
		len(report),
		len(tf.statements),
	)
}

// Exactly the directories that are green are enabled, and no others. Turning
// one on is a deliberate act with a task behind it, so it has to be a visible
// change here as well as in the table.
//
// Four came from the spine (SHACL-T-0007 and SHACL-T-0008) and cover what its
// seven constraint components could green. **`core/node` joined them at
// SHACL-T-0018**, when the last of §4's non-SPARQL catalogue landed and its
// thirty-two entries went green together — the first directory the catalogue
// initiative enabled, and the first that needed more than the spine.
//
// `core/property` is deliberately still out at 37 of 38: `nodeKind-001` is red
// and uses nothing beyond the spine, so it is a separate diagnosis rather than a
// missing component. `core/complex` needs SHACL-SPARQL.
@(test)
test_exactly_the_green_directories_are_enabled :: proc(t: ^testing.T) {
	GREEN :: []string{"core/targets", "core/path", "core/misc", "core/validation-reports", "core/node"}

	for suite in SUITES {
		want := false
		for dir in GREEN {
			if suite.dir == dir {
				want = true
			}
		}
		testing.expectf(
			t,
			suite.enabled == want,
			"%s: enabled = %v, but the enabled set is the directories that are "+
			"fully green — enabling means every entry passes, and leaving a green "+
			"directory off misstates the position as surely as enabling a broken one",
			suite.dir,
			suite.enabled,
		)
	}
}
