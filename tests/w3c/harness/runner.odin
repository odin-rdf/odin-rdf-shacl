package w3c

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import rdf "rdf:rdf"
import kvstore "store:store/kvstore"
import memstore "store:store/memstore"

import shacl "../../../shacl"
import shacl_kvstore "../../../shacl/kvstore"
import shacl_memstore "../../../shacl/memstore"

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

Backend :: enum {
	Memstore,
	Kvstore,
}

backend_name :: proc(b: Backend) -> string {
	switch b {
	case .Memstore:
		return "memstore"
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
Run :: struct {
	ok:      bool,
	detail:  string, // static description; "" when ok
	failure: shacl.Failure,
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
	case .Memstore:
		return run_memstore(r, shapes_src, shapes_base, data_src, data_base)
	case .Kvstore:
		return run_kvstore(r, shapes_src, shapes_base, data_src, data_base, tag)
	}
	return Run{detail = "unknown backend"}
}

@(private = "file")
run_memstore :: proc(r: ^shacl.Report, shapes_src, shapes_base, data_src, data_base: string) -> Run {
	model: shacl.Shapes
	defer shacl.shapes_destroy(&model)

	// The shapes store lives exactly as long as the compile. Everything the
	// model needs afterwards it owns.
	shapes_parsed := false
	compile_err := shacl.Error{}
	{
		dictionary: memstore.Dictionary
		memstore.dictionary_init(&dictionary)
		defer memstore.dictionary_destroy(&dictionary)
		dataset: memstore.Dataset
		memstore.dataset_init(&dataset)
		defer memstore.dataset_destroy(&dataset)

		_, load_err := memstore.load_turtle(
			&dictionary,
			&dataset,
			transmute([]byte)shapes_src,
			shapes_base,
		)
		shapes_parsed = load_err.message == ""
		if shapes_parsed {
			compile_err = shacl_memstore.compile(&model, &dictionary, &dataset)
		}
	}
	if !shapes_parsed {
		return Run{detail = "shapes graph failed to parse"}
	}
	if compile_err.kind != .None {
		return Run{detail = shacl.error_message(compile_err.kind)}
	}

	dictionary: memstore.Dictionary
	memstore.dictionary_init(&dictionary)
	defer memstore.dictionary_destroy(&dictionary)
	dataset: memstore.Dataset
	memstore.dataset_init(&dataset)
	defer memstore.dataset_destroy(&dataset)

	if _, load_err := memstore.load_turtle(&dictionary, &dataset, transmute([]byte)data_src, data_base);
	   load_err.message != "" {
		return Run{detail = "data graph failed to parse"}
	}

	bindings: shacl.Bindings
	shacl_memstore.bind(&bindings, &model, &dictionary)
	defer shacl.bindings_destroy(&bindings)

	failure := shacl_memstore.validate_report(r, &model, &bindings, &dictionary, &dataset)
	if failure != .None {
		return Run{failure = failure, detail = shacl.failure_message(failure)}
	}
	return Run{ok = true}
}

@(private = "file")
run_kvstore :: proc(
	r: ^shacl.Report,
	shapes_src, shapes_base, data_src, data_base: string,
	tag: string,
) -> Run {
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
			return Run{detail = "shapes store could not be opened"}
		}
		defer kvstore.close(db)

		_, parse_err, load_err := kvstore.load_turtle(db, transmute([]byte)shapes_src, shapes_base)
		if load_err != nil {
			return Run{detail = "shapes graph could not be loaded"}
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
		return Run{detail = "shapes graph failed to parse"}
	}
	if shapes_store_err != nil {
		return Run{detail = "a store read failed while compiling the shapes graph"}
	}
	if compile_err.kind != .None {
		return Run{detail = shacl.error_message(compile_err.kind)}
	}

	path := temp_store_path(tag, "data")
	defer remove_temp_store(path)
	db, open_err := kvstore.open(path)
	if open_err != nil {
		return Run{detail = "data store could not be opened"}
	}
	defer kvstore.close(db)

	_, parse_err, load_err := kvstore.load_turtle(db, transmute([]byte)data_src, data_base)
	if load_err != nil {
		return Run{detail = "data graph could not be loaded"}
	}
	if parse_err.message != "" {
		return Run{detail = "data graph failed to parse"}
	}

	session: shacl_kvstore.Session
	shacl_kvstore.session_init(&session, db)

	bindings: shacl.Bindings
	shacl_kvstore.bind(&bindings, &model, &session)
	defer shacl.bindings_destroy(&bindings)

	failure := shacl_kvstore.validate_report(r, &model, &bindings, &session)
	if failure != .None {
		return Run{failure = failure, detail = shacl.failure_message(failure)}
	}
	// An LMDB read that failed yields no value nodes, which is exactly what a
	// conforming graph looks like. Reporting the report without this check
	// would turn a broken store into a green suite.
	if shacl_kvstore.session_error(&session) != nil {
		return Run{detail = "a store read failed during validation"}
	}
	return Run{ok = true}
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
@(private = "file")
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
	return fmt.aprintf("%s/odin-rdf-shacl-w3c-%s-%s", tmp, tag, role)
}

@(private = "file")
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
