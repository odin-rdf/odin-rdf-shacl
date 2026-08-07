package w3c

import "core:fmt"
import "core:os"
import "core:sync"
import "core:path/filepath"
import "core:strings"

import rdf "rdf:rdf"
import kvstore "store:store/kvstore"

import shacl "../../../shacl"
import shacl_kvstore "../../../shacl/kvstore"

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
// (SHACL-A-0001 decision 3), so the shapes store is destroyed before the data
// store is even opened, and every run proves it rather than only the test that
// asserts it. Sharing one store would also silently merge the two graphs'
// blank-node label spaces, which is a bug waiting for the first entry whose
// shapes and data are different files.
//
// **Both backends run the same entries**, and the runner is one procedure with
// a switch rather than two, so a divergence between them has to be deliberate.

// One arm today. Kept rather than collapsed: it is the seam a second
// backend would use, the same reason odin-rdf-store retained its
// conformance Backend adapter when it became a single-backend library
// (STORE-A-0006).
Backend :: enum {
	Kvstore,
}

backend_name :: proc(b: Backend) -> string {
	switch b {
	case .Kvstore:
		return "kvstore"
	}
	return "unknown"
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
//
// `tag` distinguishes the temporary store this run opens on the persistent
// backend; it is ignored in memory.
run_entry :: proc(r: ^shacl.Report, dir: string, e: Entry, backend: Backend, tag: string) -> Run {
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

	switch backend {
	case .Kvstore:
		return run_kvstore(r, shapes_src, shapes_base, data_src, data_base, tag)
	}
	return Run{detail = "unknown backend"}
}

// The two backend runs use a named result rather than composing a Run at each
// return: from the moment the shapes graph compiles, the result owns a string,
// and a `return Run{...}` that forgot to carry it would leak silently.
@(private = "file")
run_kvstore :: proc(
	r: ^shacl.Report,
	shapes_src, shapes_base, data_src, data_base: string,
	tag: string,
) -> (
	run: Run,
) {
	model: shacl.Shapes
	defer shacl.shapes_destroy(&model)

	shapes_parsed := false
	compile_err := shacl.Error{}
	shapes_store_err: kvstore.Error
	{
		path := temp_store_path(tag, "shapes")
		defer remove_temp_store(path)
		db, open_err := kvstore.open(path)
		if open_err != nil {
			run.detail = "shapes store could not be opened"
			return
		}
		defer kvstore.close(db)

		_, parse_err, load_err := kvstore.load_turtle(db, transmute([]byte)shapes_src, shapes_base)
		if load_err != nil {
			run.detail = "shapes graph could not be loaded"
			return
		}
		shapes_parsed = parse_err.message == ""
		if shapes_parsed {
			session: shacl_kvstore.Session
			shacl_kvstore.session_init(&session, db)
			compile_err = shacl_kvstore.compile(&model, &session)
			shapes_store_err = shacl_kvstore.session_error(&session)
		}
	}
	if !shapes_parsed {
		run.detail = "shapes graph failed to parse"
		return
	}
	if shapes_store_err != nil {
		run.detail = "a store read failed while compiling the shapes graph"
		return
	}
	if compile_err.kind != .None {
		run.detail = shacl.error_message(compile_err.kind)
		return
	}
	run.ignored = ignored_text(&model)

	path := temp_store_path(tag, "data")
	defer remove_temp_store(path)
	db, open_err := kvstore.open(path)
	if open_err != nil {
		run.detail = "data store could not be opened"
		return
	}
	defer kvstore.close(db)

	_, parse_err, load_err := kvstore.load_turtle(db, transmute([]byte)data_src, data_base)
	if load_err != nil {
		run.detail = "data graph could not be loaded"
		return
	}
	if parse_err.message != "" {
		run.detail = "data graph failed to parse"
		return
	}

	session: shacl_kvstore.Session
	shacl_kvstore.session_init(&session, db)

	bindings: shacl.Bindings
	shacl_kvstore.bind(&bindings, &model, &session)
	defer shacl.bindings_destroy(&bindings)

	failure := shacl_kvstore.validate_report(r, &model, &bindings, &session)
	if failure != .None {
		run.failure = failure
		run.detail = shacl.failure_message(failure)
		return
	}
	// An LMDB read that failed yields no value nodes, which is exactly what a
	// conforming graph looks like. Reporting the report without this check
	// would turn a broken store into a green suite.
	if shacl_kvstore.session_error(&session) != nil {
		run.detail = "a store read failed during validation"
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

// temp_store_path joins the OS temp directory with a run-unique name.
//
// The separator is added here rather than assumed, and the fallback order
// matters: macOS exports TMPDIR with a trailing slash, Linux usually exports
// nothing at all, and Windows names the variable TEMP or TMP and has no /tmp to
// fall back to. The same helper `shacl/kvstore`'s tests carry, for the same
// reason — it is private to that package, and a test package cannot import
// another's.
// The counter is what actually separates two concurrent stores. `tag` and
// `role` are for a human reading a leftover directory; they are not unique
// on their own, and were not required to be while the entry tag came from a
// single-threaded suite walk. The report tests share one tag across five
// parallel tests, so a deterministic path collided as a directory that
// already exists (STORE-A-0006 port, SHACL-T-0028).
@(private)
store_path_counter: u64

temp_store_path :: proc(tag, role: string) -> string {
	tmp := os.get_env("TMPDIR", context.temp_allocator)
	if tmp == "" {
		tmp = os.get_env("TEMP", context.temp_allocator)
	}
	if tmp == "" {
		tmp = os.get_env("TMP", context.temp_allocator)
	}
	if tmp == "" {
		tmp = "/tmp"
	}
	if tmp[len(tmp) - 1] == '/' || tmp[len(tmp) - 1] == '\\' {
		tmp = tmp[:len(tmp) - 1]
	}
	n := sync.atomic_add(&store_path_counter, 1)
	return fmt.aprintf("%s/odin-rdf-shacl-w3c-%s-%s-%d-%d", tmp, tag, role, os.get_pid(), n)
}

remove_temp_store :: proc(path: string) {
	os.remove(fmt.tprintf("%s/data.mdb", path))
	os.remove(fmt.tprintf("%s/lock.mdb", path))
	os.remove(path)
	delete(path)
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
