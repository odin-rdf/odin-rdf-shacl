// SHACL-T-0031: proof that the `record:` collection is wired. One store
// opened over the memory seam, one changeset applied from a struct
// literal, matched back through the snapshot read API, and closed —
// the round trip every ported harness call site will make
// (SHACL-I-0004). This package moves into the ported suite once
// SHACL-T-0032/T-0033 land; until then it is the only consumer of the
// collection and exists so the plumbing is asserted rather than
// trusted.
package smoke

import "core:testing"

import "rdf:rdf"
import "record:record"

S_IRI :: "http://example.org/s"
P_IRI :: "http://example.org/p"
O_IRI :: "http://example.org/o"

@(test)
record_round_trip :: proc(t: ^testing.T) {
	fs: record.Mem_FS
	defer record.mem_fs_destroy(&fs)

	s: record.Store
	_, open_err, _, _ := record.store_open(&s, "smoke", record.mem_file_ops(&fs))
	testing.expect_value(t, open_err, record.Open_Error.None)
	if open_err != .None {
		return
	}
	defer record.store_close(&s)

	ops := []record.Op {
		{
			kind = .Assert,
			quad = rdf.Quad {
				triple = rdf.Triple {
					subject   = rdf.IRI(S_IRI),
					predicate = rdf.IRI(P_IRI),
					object    = rdf.IRI(O_IRI),
				},
			},
		},
	}
	epoch, _, apply_err := record.apply(&s, {ops = ops})
	testing.expect_value(t, apply_err, record.Apply_Error{})
	testing.expect_value(t, epoch, record.Epoch(1))

	snap, snap_err := record.store_latest(&s)
	testing.expect_value(t, snap_err, record.Snapshot_Error.None)
	if snap_err != .None {
		return
	}
	defer record.snapshot_release(&snap)

	sid, s_ok := record.snapshot_resolve(snap, rdf.IRI(S_IRI))
	pid, p_ok := record.snapshot_resolve(snap, rdf.IRI(P_IRI))
	oid, o_ok := record.snapshot_resolve(snap, rdf.IRI(O_IRI))
	testing.expect(t, s_ok && p_ok && o_ok, "the applied terms resolve")
	testing.expect_value(t, record.snapshot_kind(snap, sid), record.Term_Kind.IRI)

	rng := record.snapshot_match(snap, record.Pattern{s = sid})
	sc := record.range_iter(rng, record.Filter{origin = .Any})
	count := 0
	for {
		id, ok := record.scan_next(&sc)
		if !ok {
			break
		}
		f := record.snapshot_fact(snap, id)
		testing.expect_value(t, f.p, pid)
		testing.expect_value(t, f.o, oid)
		testing.expect_value(t, f.g, record.Term_ID(0)) // the default graph is stored as G = 0
		count += 1
	}
	testing.expect_value(t, count, 1)
}
