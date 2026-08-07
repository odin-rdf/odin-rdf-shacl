package main

import "base:runtime"

import rdf "rdf:rdf"
import store "store:store"
import kvstore "store:store/kvstore"
import memstore "store:store/memstore"

import shacl "../shacl"

// Counting the store reads a validation makes.
//
// **This needs no change to any shipped code, and that is the whole reason it
// is possible.** `shacl.Access` is a struct of procedure pointers,
// `shacl.validate` takes one directly, and `Access` and its four verb types are
// exported. So this package supplies its own four adapters — calling the same
// public match interface the real ones call, and bumping a counter in the same
// body — and hands them to `shacl.validate`, bypassing
// `shacl_memstore.validate`, which builds the uncounted set. There is no
// `-define:` flag, no counter on a hot path in a release build, and nothing to
// compile out. `Access` was not designed for this; it falls out of its being a
// procedure set rather than an interface.
//
// **The instantiation packages' own adapters are `@(private)` and stay that
// way.** Widening a shipped API for a benchmark's convenience is the wrong
// trade, so these are written again here — about thirty lines per backend
// against the same `match`. This repository already has the precedent for
// copying a small thing rather than coupling to it: `tests/w3c/harness`'s
// `compare.odin` is a copy of odin-rdf-parser's, for reasons stated at the top
// of that file.
//
// **Do not take timings from a run that uses these.** An extra indirection per
// read is nothing next to a store lookup, but it is not nothing, and mixing the
// instrument with the measurement is exactly what the two-mode split exists to
// prevent.
//
//
// # What is counted, and why the count is an assertion
//
// One tick per call to `scan`, `step`, `outgoing`, and `load` — the four ways
// the core can touch the data graph, and the only ones. Not one per matched
// quad: the question is how often the engine *asks*, which is what a
// conformance cache would change, and it is the number that survives a change
// of backend.
//
// **It must be identical on memstore and kvstore**, and that follows from the
// architecture rather than from luck. The backend-independent core decides what
// to ask; the adapter decides only how. It must also be identical at 64- and
// 32-bit `Term_ID`, because ID width cannot reach the core's control flow. So
// one workload and seed yields **one integer, four ways**, and `main` asserts
// it rather than printing it side by side. A disagreement is a defect, not a
// measurement.

// Reads is the tally, kept per verb because a change that trades one kind of
// read for another is worth seeing rather than netting out to zero.
Reads :: struct {
	scan:     int,
	step:     int,
	outgoing: int,
	load:     int,
}

reads_total :: proc(r: Reads) -> int {
	return r.scan + r.step + r.outgoing + r.load
}

// Mem_Probe is the memstore counting context: the same two fields the real
// adapter's `Data` carries, plus the tally.
Mem_Probe :: struct {
	dataset:    ^memstore.Dataset,
	dictionary: ^memstore.Dictionary,
	graph:      store.Term_ID,
	reads:      Reads,
}

// mem_access builds an `Access` over a probe. The graph is bound into every
// pattern rather than left wildcard, exactly as the real adapters do
// (SHACL-A-0001 decision 5) — a benchmark that quietly widened to the whole
// dataset would measure a different engine.
mem_access :: proc(p: ^Mem_Probe) -> shacl.Access {
	return shacl.Access {
		scan = mem_scan,
		step = mem_step,
		outgoing = mem_outgoing,
		load = mem_load,
		data = p,
		load_data = p,
	}
}

@(private = "file")
mem_scan :: proc(
	data: rawptr,
	subject, predicate, object: store.Term_ID,
	position: int,
	visit: proc(data: rawptr, id: store.Term_ID) -> bool,
	visit_data: rawptr,
) -> bool {
	p := cast(^Mem_Probe)data
	p.reads.scan += 1
	it := memstore.match(p.dataset, store.Match_Pattern{subject, predicate, object, p.graph})
	defer memstore.match_destroy(&it)
	for {
		q, ok := memstore.match_next(&it)
		if !ok {
			return true
		}
		if !visit(visit_data, q[position]) {
			return false
		}
	}
}

@(private = "file")
mem_step :: proc(
	data: rawptr,
	from: store.Term_ID,
	predicate: store.Term_ID,
	inverted: bool,
	out: ^[dynamic]store.Term_ID,
) {
	p := cast(^Mem_Probe)data
	p.reads.step += 1
	pattern :=
		inverted \
		? store.Match_Pattern{store.WILDCARD, predicate, from, p.graph} \
		: store.Match_Pattern{from, predicate, store.WILDCARD, p.graph}
	position := inverted ? store.QUAD_S : store.QUAD_O

	it := memstore.match(p.dataset, pattern)
	defer memstore.match_destroy(&it)
	for {
		q, ok := memstore.match_next(&it)
		if !ok {
			return
		}
		append(out, q[position])
	}
}

@(private = "file")
mem_outgoing :: proc(
	data: rawptr,
	subject: store.Term_ID,
	visit: proc(data: rawptr, predicate, object: store.Term_ID) -> bool,
	visit_data: rawptr,
) -> bool {
	p := cast(^Mem_Probe)data
	p.reads.outgoing += 1
	it := memstore.match(
		p.dataset,
		store.Match_Pattern{subject, store.WILDCARD, store.WILDCARD, p.graph},
	)
	defer memstore.match_destroy(&it)
	for {
		q, ok := memstore.match_next(&it)
		if !ok {
			return true
		}
		if !visit(visit_data, q[store.QUAD_P], q[store.QUAD_O]) {
			return false
		}
	}
}

// memstore's `lookup_term` borrows its dictionary's storage, so `owned` is
// false and the caller must not free what comes back. kvstore's below is the
// other half of the asymmetry SHACL-A-0001 decision 3 exists to hide.
@(private = "file")
mem_load :: proc(
	data: rawptr,
	id: store.Term_ID,
	allocator: runtime.Allocator,
) -> (
	term: rdf.Term,
	owned: bool,
) {
	p := cast(^Mem_Probe)data
	p.reads.load += 1
	return memstore.lookup_term(p.dictionary, id), false
}

// Kv_Probe is the kvstore counting context.
//
// `err` is sticky, and it matters more here than anywhere else in this package:
// a failed LMDB read yields no value nodes, which is exactly what a conforming
// graph looks like. A benchmark that reported a fast, silent, empty validation
// would be reporting a broken store as good news, so `main` checks this before
// it believes a number.
Kv_Probe :: struct {
	db:    ^kvstore.Store,
	graph: store.Term_ID,
	err:   kvstore.Error,
	reads: Reads,
}

kv_access :: proc(p: ^Kv_Probe) -> shacl.Access {
	return shacl.Access {
		scan = kv_scan,
		step = kv_step,
		outgoing = kv_outgoing,
		load = kv_load,
		data = p,
		load_data = p,
	}
}

@(private = "file")
kv_note :: proc(p: ^Kv_Probe, err: kvstore.Error) -> bool {
	if err != nil {
		if p.err == nil {
			p.err = err
		}
		return true
	}
	return false
}

@(private = "file")
kv_scan :: proc(
	data: rawptr,
	subject, predicate, object: store.Term_ID,
	position: int,
	visit: proc(data: rawptr, id: store.Term_ID) -> bool,
	visit_data: rawptr,
) -> bool {
	p := cast(^Kv_Probe)data
	p.reads.scan += 1
	it, err := kvstore.match(p.db, store.Match_Pattern{subject, predicate, object, p.graph})
	if kv_note(p, err) {
		return true
	}
	defer kvstore.match_destroy(&it)
	for {
		q, ok := kvstore.match_next(&it)
		if !ok {
			return true
		}
		if !visit(visit_data, q[position]) {
			return false
		}
	}
}

@(private = "file")
kv_step :: proc(
	data: rawptr,
	from: store.Term_ID,
	predicate: store.Term_ID,
	inverted: bool,
	out: ^[dynamic]store.Term_ID,
) {
	p := cast(^Kv_Probe)data
	p.reads.step += 1
	pattern :=
		inverted \
		? store.Match_Pattern{store.WILDCARD, predicate, from, p.graph} \
		: store.Match_Pattern{from, predicate, store.WILDCARD, p.graph}
	position := inverted ? store.QUAD_S : store.QUAD_O

	it, err := kvstore.match(p.db, pattern)
	if kv_note(p, err) {
		return
	}
	defer kvstore.match_destroy(&it)
	for {
		q, ok := kvstore.match_next(&it)
		if !ok {
			return
		}
		append(out, q[position])
	}
}

@(private = "file")
kv_outgoing :: proc(
	data: rawptr,
	subject: store.Term_ID,
	visit: proc(data: rawptr, predicate, object: store.Term_ID) -> bool,
	visit_data: rawptr,
) -> bool {
	p := cast(^Kv_Probe)data
	p.reads.outgoing += 1
	it, err := kvstore.match(
		p.db,
		store.Match_Pattern{subject, store.WILDCARD, store.WILDCARD, p.graph},
	)
	if kv_note(p, err) {
		return true
	}
	defer kvstore.match_destroy(&it)
	for {
		q, ok := kvstore.match_next(&it)
		if !ok {
			return true
		}
		if !visit(visit_data, q[store.QUAD_P], q[store.QUAD_O]) {
			return false
		}
	}
}

// kvstore builds a term from database bytes, so `owned` is true and the core
// frees it after interning. The opposite of memstore's, and the reason a
// compiled model owns its terms rather than borrowing.
@(private = "file")
kv_load :: proc(
	data: rawptr,
	id: store.Term_ID,
	allocator: runtime.Allocator,
) -> (
	term: rdf.Term,
	owned: bool,
) {
	p := cast(^Kv_Probe)data
	p.reads.load += 1
	t, err := kvstore.lookup_term(p.db, id, allocator)
	if kv_note(p, err) {
		return nil, false
	}
	return t, true
}
