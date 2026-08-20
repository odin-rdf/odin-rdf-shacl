package shacl

// Read counting for the benchmark (SHACL-T-0036) — and nothing else.
//
// `bench/` reports how many times a validation asks the store a question: one
// tick per `session_scan`, `session_step`, `session_outgoing`, and
// `session_term` — the four ways the engine touches a snapshot, and the only
// ones. Not one per matched quad: the question is how often the engine *asks*,
// which is what a memoisation cache would change (SHACL-A-0002's trigger), and
// the number is pinned per configuration so that it cannot move unnoticed.
//
// On the old store the count came free of any change to shipped code: the
// engine read through a struct of procedure pointers, and the benchmark
// supplied counting ones. That seam is gone by decision (SHACL-I-0004 — the
// record is the one and only store, and the session verbs call it directly),
// so the count lives where the reads are, behind a build-time switch:
//
//	-define:SHACL_COUNT_READS=true
//
// **Off, it does not exist.** `when SHACL_COUNT_READS` is a compile-time
// branch, so a normal build carries no counter, no branch and no global — not
// a disabled one, none — and `make test` and every consumer build it off.
// **On, it is a process-wide tally**, not a per-session one: the benchmark
// validates serially, resets before a measured run and reads after, and that
// is the only caller this is for. It is not an API; a consumer that wants
// per-read accounting is asking for the seam this repository retired.
//
// `make bench` builds the benchmark twice — once without the switch, for
// timings, so that nothing is wrapped in a number anyone quotes; once with it,
// for reads, allocation and the assertions, where no timing is taken.
SHACL_COUNT_READS :: #config(SHACL_COUNT_READS, false)

// Read_Counts is the tally, kept per verb because a change that trades one
// kind of read for another is worth seeing rather than netting out to zero.
// `term` is a decode of an id into a term (`session_term`), which is a read
// of the dictionary rather than of the graph, and is counted for the same
// reason the old `load` was: it is a question asked of the store.
Read_Counts :: struct {
	scan:     int,
	step:     int,
	outgoing: int,
	term:     int,
}

when SHACL_COUNT_READS {
	@(private)
	read_counts: Read_Counts

	// read_counts_reset zeroes the tally. Call it immediately before the run
	// to be counted — compile reads the shapes graph through the same verbs.
	read_counts_reset :: proc() {
		read_counts = {}
	}

	// read_counts_get is the tally since the last reset.
	read_counts_get :: proc() -> Read_Counts {
		return read_counts
	}
}
