package w3c

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import rdf "rdf:rdf"
import "record:record"
import "record:record/ingest"

import shacl "../../../shacl"

// Running one suite entry: data graph + shapes graph → validation report.
//
// That is the whole of a SHACL test, and it is why this repository had nothing
// gradable until SHACL-T-0007 — the suite cannot score a shapes model, a target
// resolver, or a path evaluator on their own, only a report.
//
// **The two graphs are loaded into two separate stores**, even in the common
// case where an entry names the same file for both (`sht:dataGraph <>`,
// `sht:shapesGraph <>`). Parsing it twice costs a few microseconds and buys the
// property the whole design rests on: the shapes model owns its terms
// (SHACL-A-0001 decision 3), so the shapes store is closed before the data
// store is even opened, and every run proves it rather than only the test that
// asserts it. Sharing one store would also silently merge the two graphs'
// blank-node label spaces, which is a bug waiting for the first entry whose
// shapes and data are different files.
//
// The store is odin-rdf-record over its memory seam (SHACL-I-0004): there is
// one backend, by decision, and the runner is one procedure rather than a
// switch over a seam no second backend will ever use.

// Graph_DB is one record store over the memory seam holding one loaded
// graph: open, load, session, close — the shape every store in this package
// takes. It is the harness's counterpart of the engine's own test helper,
// which package `w3c` cannot see.
//
// **Never copied or moved after `gdb_open`**: the writer holds a pointer to
// the `Mem_FS` inside the struct. Declare one where it lives and pass it by
// pointer.
@(private)
Graph_DB :: struct {
	fs:       record.Mem_FS,
	st:       record.Store,
	snap:     record.Snapshot,
	has_snap: bool,
	ok:       bool,
}

// GRAPH_BLANK_PREFIX is the load scope of every document this package loads.
// Label characters only, and beginning with neither `r` nor `s` — the
// report's own blank nodes and its relabelled shapes-graph ones are kept
// apart from a store's by prefix (`shacl/report.odin`), and the caller's
// ingest prefix is where that contract is honoured.
@(private)
GRAPH_BLANK_PREFIX :: "b_"

@(private)
gdb_open :: proc(db: ^Graph_DB, name: string) -> bool {
	_, err, _, _ := record.store_open(&db.st, name, record.mem_file_ops(&db.fs))
	db.ok = err == .None
	return db.ok
}

// Load_Outcome says which stage of a load refused, for a runner that must
// report "failed to parse" and "could not be loaded" as different things:
// the first is the entry's problem, the second is this harness's.
@(private)
Load_Outcome :: enum {
	Loaded,
	Syntax,
	Not_Loaded,
}

// gdb_load ingests one Turtle document into the default graph and applies it
// as one epoch. A document with no triples loads as nothing — `apply`
// refuses an empty changeset, and an empty graph is a graph. The ops are the
// document's *set* of statements — `ingest` deduplicates since odin-rdf-record
// `v0.2.0` (RECORD-T-0019, found by this suite: `core/complex/shacl-shacl`'s
// shapes graph states two triples twice, and `apply` refuses a second assert
// within one changeset), so they go to `apply` as they come.
@(private)
gdb_load :: proc(db: ^Graph_DB, source: string, base := "") -> Load_Outcome {
	if !db.ok {
		return .Not_Loaded
	}
	ops, ierr := ingest.turtle(
		transmute([]byte)source,
		nil,
		context.allocator,
		blank_prefix = GRAPH_BLANK_PREFIX,
		base = base,
	)
	switch ierr.kind {
	case .None:
	case .Syntax:
		return .Syntax
	case .Allocation:
		return .Not_Loaded
	}
	defer ingest.ops_destroy(ops, context.allocator)
	if len(ops) == 0 {
		return .Loaded
	}
	_, _, aerr := record.apply(&db.st, {ops = ops})
	return aerr == record.Apply_Error{} ? .Loaded : .Not_Loaded
}

// gdb_session binds a session over the head snapshot, pinning it on first
// use. Load before you session: an epoch applied after the pin is invisible
// to every session already handed out.
@(private)
gdb_session :: proc(db: ^Graph_DB) -> shacl.Session {
	if !db.has_snap {
		snap, serr := record.store_latest(&db.st)
		assert(serr == .None, "gdb_session: store_latest failed")
		db.snap = snap
		db.has_snap = true
	}
	se: shacl.Session
	shacl.session_init(&se, db.snap)
	return se
}

// gdb_close releases the snapshot before the store, the order record asserts,
// and is safe on a Graph_DB that never opened.
@(private)
gdb_close :: proc(db: ^Graph_DB) {
	if db.has_snap {
		record.snapshot_release(&db.snap)
		db.has_snap = false
	}
	if db.ok {
		record.store_close(&db.st)
		db.ok = false
	}
	record.mem_fs_destroy(&db.fs)
}

// Run is what happened mechanically, as distinct from whether the report was
// right — that is the caller's comparison to make.
//
// `ok` false means the entry could not be run at all: a file missing, a graph
// that would not parse, an ill-formed shapes graph, or a validation failure.
// None of those may be quietly treated as "no violations", which is exactly the
// shape of bug a suite runner is supposed to catch rather than commit.
//
// `ignored` is the entry's shapes graph read back through `shapes_ignored`: the
// `sh:` parameters this engine saw and does not implement, rendered for a
// failure message. It is **owned** — `run_destroy` frees it — and it is on Run
// rather than left in the model because the model is destroyed inside the run,
// while the question it answers belongs to the caller: an entry that passes
// with an unimplemented parameter in its shapes graph passed for a reason
// nobody checked.
Run :: struct {
	ok:      bool,
	detail:  string, // static description; "" when ok
	failure: shacl.Failure,
	ignored: string, // owned; "" when the shapes graph used nothing unimplemented
}

// run_destroy frees what a Run owns. Every caller of run_entry must call it,
// including on the failure paths.
run_destroy :: proc(run: ^Run) {
	if run.ignored != "" {
		delete(run.ignored)
	}
	run^ = {}
}

// run_entry validates one entry and folds the results into `r`, which the
// caller must have `report_init`ed and must destroy.
run_entry :: proc(r: ^shacl.Report, dir: string, e: Entry) -> Run {
	shapes_src, shapes_read := read_entry_file(dir, e.shapes_graph)
	defer delete(shapes_src)
	if !shapes_read {
		return Run{detail = "shapes graph could not be read"}
	}
	data_src, data_read := read_entry_file(dir, e.data_graph)
	defer delete(data_src)
	if !data_read {
		return Run{detail = "data graph could not be read"}
	}

	// The base each file is parsed with is the base its own manifest entry was
	// written against, so `<>` resolves to the file itself — which is how
	// nearly every entry names both of its graphs.
	shapes_base := strings.concatenate({MANIFEST_BASE, e.shapes_graph})
	defer delete(shapes_base)
	data_base := strings.concatenate({MANIFEST_BASE, e.data_graph})
	defer delete(data_base)

	return run_record(r, shapes_src, shapes_base, data_src, data_base)
}

// The run uses a named result rather than composing a Run at each return:
// from the moment the shapes graph compiles, the result owns a string, and a
// `return Run{...}` that forgot to carry it would leak silently.
@(private = "file")
run_record :: proc(r: ^shacl.Report, shapes_src, shapes_base, data_src, data_base: string) -> (run: Run) {
	model: shacl.Shapes
	defer shacl.shapes_destroy(&model)

	// The shapes store lives only as long as this block. The model compiled
	// from it is read for the rest of the run — the per-entry proof that it
	// owns its terms.
	{
		shapes_db: Graph_DB
		defer gdb_close(&shapes_db)
		if !gdb_open(&shapes_db, "shapes") {
			run.detail = "shapes store could not be opened"
			return
		}
		switch gdb_load(&shapes_db, shapes_src, shapes_base) {
		case .Loaded:
		case .Syntax:
			run.detail = "shapes graph failed to parse"
			return
		case .Not_Loaded:
			run.detail = "shapes graph could not be loaded"
			return
		}
		compile_err := shacl.compile(&model, gdb_session(&shapes_db))
		if compile_err.kind != .None {
			run.detail = shacl.error_message(compile_err.kind)
			return
		}
	}
	run.ignored = ignored_text(&model)

	db: Graph_DB
	defer gdb_close(&db)
	if !gdb_open(&db, "data") {
		run.detail = "data store could not be opened"
		return
	}
	switch gdb_load(&db, data_src, data_base) {
	case .Loaded:
	case .Syntax:
		run.detail = "data graph failed to parse"
		return
	case .Not_Loaded:
		run.detail = "data graph could not be loaded"
		return
	}
	session := gdb_session(&db)

	bindings: shacl.Bindings
	shacl.bindings_init(&bindings, &model, session)
	defer shacl.bindings_destroy(&bindings)

	failure := shacl.validate_report(r, &model, &bindings, session)
	if failure != .None {
		run.failure = failure
		run.detail = shacl.failure_message(failure)
		return
	}
	run.ok = true
	return
}

// ignored_text renders `shapes_ignored` for a failure message. Empty when the
// shapes graph used nothing this engine skips, which is the answer every
// enabled directory has to give.
@(private = "file")
ignored_text :: proc(model: ^shacl.Shapes) -> string {
	ignored := shacl.shapes_ignored(model)
	if len(ignored) == 0 {
		return ""
	}
	sb := strings.builder_make()
	for term, i in ignored {
		if i > 0 {
			strings.write_string(&sb, ", ")
		}
		if iri, is_iri := term.(rdf.IRI); is_iri {
			strings.write_string(&sb, string(iri))
		}
	}
	return strings.to_string(sb)
}

@(private = "file")
read_entry_file :: proc(dir, name: string) -> (source: string, ok: bool) {
	path, _ := filepath.join({SUITE_ROOT, dir, name})
	defer delete(path)
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		return "", false
	}
	return string(data), true
}

// graph_text renders a graph for a failure message. Diagnostics only: when a
// report does not match, the two graphs side by side are the whole story, and
// an isomorphism failure with no graphs in it is unactionable.
graph_text :: proc(triples: []rdf.Triple) -> string {
	sb := strings.builder_make()
	for t in triples {
		strings.write_string(&sb, "\n    ")
		write_term_text(&sb, t.subject)
		strings.write_byte(&sb, ' ')
		write_term_text(&sb, t.predicate)
		strings.write_byte(&sb, ' ')
		write_term_text(&sb, t.object)
	}
	return strings.to_string(sb)
}

@(private = "file")
write_term_text :: proc(sb: ^strings.Builder, term: rdf.Term) {
	switch v in term {
	case rdf.IRI:
		fmt.sbprintf(sb, "<%s>", string(v))
	case rdf.Blank_Node:
		fmt.sbprintf(sb, "_:%s", string(v))
	case rdf.Literal:
		fmt.sbprintf(sb, "%q", v.lexical)
		if v.language != "" {
			fmt.sbprintf(sb, "@%s", v.language)
		} else if v.datatype != "" {
			fmt.sbprintf(sb, "^^<%s>", string(v.datatype))
		}
	case ^rdf.Triple:
		strings.write_string(sb, "<<")
		write_term_text(sb, v.subject)
		strings.write_byte(sb, ' ')
		write_term_text(sb, v.predicate)
		strings.write_byte(sb, ' ')
		write_term_text(sb, v.object)
		strings.write_string(sb, ">>")
	}
}
