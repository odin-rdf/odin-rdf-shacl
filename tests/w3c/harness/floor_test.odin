package w3c

import "core:log"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import shacl "../../../shacl"

// The progress floor: what the *disabled* directories score today, pinned as a
// minimum and asserted to only ever go up.
//
// **Why this exists at all.** The family's incrementality mechanism is
// per-directory enablement under "enabled means fully green", and for the
// catalogue initiative (SHACL-I-0002) that mechanism gives no signal: two
// directories remain, and neither can be enabled until nearly every constraint
// component of §4 exists. A ten-task initiative whose suite tells it nothing
// until task nine is the shape that goes wrong quietly, so this fills the gap —
// a number that every component task must move, without enabling anything.
//
// **What it is not.** It is not a second scoreboard, and it must not be read as
// one. Three reasons, and the third is the one that bites:
//
//   - A directory in the floor is still **disabled**. Nothing here enables,
//     skips, or excuses an entry; `test_exactly_the_spine_directories_are_enabled`
//     and `ENABLED_ENTRIES` are untouched, and the only claim this repository
//     makes about conformance remains the set of enabled directories.
//   - The floor is a **minimum, not an equality**. Exceeding it passes silently
//     — the count is printed either way, so a task that moved it by three can
//     see that it moved it by three — and raising it is a deliberate edit,
//     exactly as enabling a directory is.
//   - **An entry can pass for the wrong reason.** Two of the entries in the
//     starting floor (`property/minCount-002`, `property/uniqueLang-002`) expect
//     a *conforming* report, and an engine that silently ignores a constraint it
//     has not implemented produces a conforming report too. They cannot
//     distinguish validation from inaction, and no count can. "40 of 69" is a
//     direction of travel; only a green directory is a claim. The starkest case
//     is `core/complex/shacl-shacl`, which is counted here but pinned at 0 for
//     exactly this reason — see the note above SUITES.
//
// Deliberately absent: a list of which entries pass. That would be a skip list
// by another name — it would encode an expectation per entry, which is the
// thing the family's rule exists to avoid. A monotonic number carries the
// progress signal without carrying the temptation.

// FLOOR_CAVEAT is printed with the counts rather than only written here,
// because the number travels (into status updates, into handover notes) and the
// caveat has to travel with it.
FLOOR_CAVEAT ::
	"FLOOR is a progress metric, not a conformance claim: these directories are " +
	"DISABLED, the counts are minimums, and an entry expecting a conforming report " +
	"passes whether it was validated or ignored."

// Every disabled directory's entries are run and counted, against both
// backends, at whichever `Term_ID` width the build chose. Three things are
// asserted, and nothing about enablement is:
//
//   - the count is at least the pinned floor,
//   - the runner really ran the whole directory,
//   - and the two backends agree. The runner is one procedure with a switch on
//     the backend, so a divergence is a bug rather than a lower floor — the
//     same reasoning that makes both backends run the enabled entries.
//
// The width dimension is covered by the pin itself: the floor is one constant
// asserted at 64- and 32-bit alike, so a width that scores lower fails here.
@(test)
test_disabled_suites_meet_their_progress_floor :: proc(t: ^testing.T) {
	log.info(FLOOR_CAVEAT)

	total := 0
	for suite in SUITES {
		if suite.enabled {
			continue
		}

		agreed := -1
		for backend in Backend {
			passed, ran := count_passing(t, suite, backend)

			log.infof(
				// Right-aligned counts: %-3d pads on the right with '0', so 1
				// and 10 both render as "100" and a directory that moved by one
				// reads as if it moved by ten. odin-rdf-sparql's survey line
				// carries the same note, having made the mistake first.
				"FLOOR %-14s %-9s %3d/%3d pass, floor %3d",
				suite.dir,
				backend_name(backend),
				passed,
				ran,
				suite.floor,
			)

			testing.expectf(
				t,
				ran == suite.entries,
				"%s (%s): ran %d entries, the table pins %d — the floor is only "+
				"meaningful over the whole directory",
				suite.dir,
				backend_name(backend),
				ran,
				suite.entries,
			)
			testing.expectf(
				t,
				passed >= suite.floor,
				"%s (%s): %d entries pass, below the pinned floor of %d — this is a "+
				"regression, not a lower floor",
				suite.dir,
				backend_name(backend),
				passed,
				suite.floor,
			)
			if agreed < 0 {
				agreed = passed
				total += passed
				continue
			}
			testing.expectf(
				t,
				passed == agreed,
				"%s: backends disagree — %d entries pass here, %d on the first "+
				"backend. The runner is one procedure; a divergence is a bug",
				suite.dir,
				passed,
				agreed,
			)
		}
	}

	// Printed last so it is the line a reader takes away, and asserted so the
	// per-directory floors and the initiative-level number cannot drift apart
	// in opposite directions.
	log.infof("FLOOR total %d/%d disabled entries pass (floor %d)", total, disabled_entries(), PROGRESS_FLOOR)
}

// The pinned per-directory floors and the pinned total agree, an enabled
// directory carries no floor, and no floor exceeds its directory. Same shape as
// test_enabled_entry_count_is_consistent, and for the same reason: a pin that
// can be edited in one place only is not a pin.
@(test)
test_progress_floor_is_consistent :: proc(t: ^testing.T) {
	sum := 0
	for suite in SUITES {
		if suite.enabled {
			testing.expectf(
				t,
				suite.floor == 0,
				"%s is enabled, so it is fully green and its floor is meaningless — "+
				"leave it 0 rather than restating the entry count",
				suite.dir,
			)
			continue
		}
		testing.expectf(
			t,
			suite.floor <= suite.entries,
			"%s: floor %d exceeds the directory's %d entries",
			suite.dir,
			suite.floor,
			suite.entries,
		)
		sum += suite.floor
	}
	testing.expect_value(t, sum, PROGRESS_FLOOR)
}

@(private = "file")
disabled_entries :: proc() -> (n: int) {
	for suite in SUITES {
		if !suite.enabled {
			n += suite.entries
		}
	}
	return
}

// count_passing runs a directory's entries and counts the reports that match.
// It asserts nothing about any individual entry — that is the whole difference
// from `run_suite`, which is the enabled directories' scoreboard and fails on
// the first mismatch it sees. An entry that cannot be run at all (a shapes
// graph this engine rejects, most likely) simply does not count towards the
// floor; it is not a failure here, because that is precisely the state these
// directories are in.
@(private = "file")
count_passing :: proc(t: ^testing.T, suite: Suite, backend: Backend) -> (passed, ran: int) {
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
			ran += 1
			if entry_matches(suite.dir, backend, &tf, e) {
				passed += 1
			}
		}
	}
	return
}

@(private = "file")
entry_matches :: proc(dir: string, backend: Backend, tf: ^Test_File, e: Entry) -> bool {
	report: shacl.Report
	shacl.report_init(&report)
	defer shacl.report_destroy(&report)

	// The tag names the persistent backend's temporary store, and entry ids
	// repeat across directories (`core/node/and-001` and `core/property/and-001`
	// both exist). The Odin test runner runs tests concurrently, so a tag shared
	// with `run_suite`'s would have two tests opening one LMDB path. The prefix
	// keeps this test's stores to itself.
	tag := strings.concatenate({"floor-", e.id})
	defer delete(tag)

	run := run_entry(&report, dir, e, backend, tag)
	if !run.ok {
		return false
	}

	expected := expected_report(tf, e)
	defer delete(expected)
	return report_isomorphic(shacl.report_triples(&report), expected[:])
}
