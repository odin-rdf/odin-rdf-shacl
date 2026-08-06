// Package w3c runs the vendored W3C SHACL conformance suite. Manifests are
// parsed with the family's own Turtle parser, in the style odin-rdf-parser
// established and odin-rdf-sparql carried forward.
//
// Circularity guard, inherited from both: a Turtle parser bug that silently
// dropped manifest entries could mask conformance failures, so the suite
// registry pins the exact include and entry counts for every directory and
// the tests assert them.
//
// The SHACL suite is shaped differently from the query suites, and the
// difference is structural rather than cosmetic — see `tests/w3c/README.md`.
// Two things drive this reader's design:
//
//   - **Two manifest levels.** A directory's `manifest.ttl` is an index of
//     `mf:include <file>` references and holds no entries. Each included file
//     is itself an `mf:Manifest` with an `mf:entries` list.
//   - **The expected result is a subgraph, not a file.** `mf:result` points at
//     a blank node whose transitive closure *is* the expected
//     `sh:ValidationReport`. There is nothing to open; there is a graph to
//     extract and compare by isomorphism.
package w3c

import "core:strings"

import rdf "rdf:rdf"
import turtle "rdf:rdf/turtle"

// MANIFEST_BASE anchors the manifests' relative IRIs; file names are
// recovered by stripping it again. A test file is parsed with
// MANIFEST_BASE + its own name as the base, so `<>` — which is how nearly
// every entry names both its data graph and its shapes graph — resolves to
// the file itself.
MANIFEST_BASE :: "https://manifest.invalid/"

MF_NS :: "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#"
MF_MANIFEST :: rdf.IRI(MF_NS + "Manifest")
MF_ENTRIES :: rdf.IRI(MF_NS + "entries")
MF_INCLUDE :: rdf.IRI(MF_NS + "include")
MF_ACTION :: rdf.IRI(MF_NS + "action")
MF_RESULT :: rdf.IRI(MF_NS + "result")
MF_STATUS :: rdf.IRI(MF_NS + "status")

SHT_NS :: "http://www.w3.org/ns/shacl-test#"
SHT_VALIDATE :: rdf.IRI(SHT_NS + "Validate")
SHT_FAILURE :: rdf.IRI(SHT_NS + "Failure")
SHT_DATA_GRAPH :: rdf.IRI(SHT_NS + "dataGraph")
SHT_SHAPES_GRAPH :: rdf.IRI(SHT_NS + "shapesGraph")
SHT_APPROVED :: rdf.IRI(SHT_NS + "approved")

RDFS_LABEL :: rdf.IRI("http://www.w3.org/2000/01/rdf-schema#label")

// Expectation is what an entry says should happen. The suite's `core/`
// directories are entirely Report; Failure occurs only in the excluded
// `sparql/pre-binding/` directory, but it is modelled here so an entry
// carrying it is recognised rather than silently read as an empty report.
Expectation :: enum {
	Report,
	Failure,
}

Entry :: struct {
	id:           string, // entry IRI with the manifest base stripped
	label:        string, // rdfs:label
	type_str:     string, // full rdf:type IRI, e.g. ...shacl-test#Validate
	status:       string, // full mf:status IRI, e.g. ...shacl-test#approved
	data_graph:   string, // file name relative to the suite directory
	shapes_graph: string, // file name relative to the suite directory
	expectation:  Expectation,
	result_node:  rdf.Term, // borrows Test_File.statements; nil when Failure
}

// Test_File is one parsed suite file: the statements it asserts, and the
// entries its manifest declares. The statements are the file's whole content
// — data graph, shapes graph, manifest, and expected report together, which
// is how this suite is written — and entries borrow from them, so the file
// owns everything and frees it at destroy_test_file.
Test_File :: struct {
	statements: [dynamic]rdf.Triple,
	entries:    [dynamic]Entry,
	parse_ok:   bool,
}

destroy_test_file :: proc(tf: ^Test_File) {
	for e in tf.entries {
		delete(e.id)
		delete(e.label)
		delete(e.type_str)
		delete(e.status)
		delete(e.data_graph)
		delete(e.shapes_graph)
	}
	delete(tf.entries)
	for t in tf.statements {
		rdf.destroy_triple(t)
	}
	delete(tf.statements)
}

// parse_includes reads a directory's manifest.ttl and returns the file names
// it includes, in document order. The result owns its strings.
parse_includes :: proc(source: string, base_name: string) -> [dynamic]string {
	out := make([dynamic]string)

	statements: [dynamic]rdf.Triple
	defer {
		for t in statements {
			rdf.destroy_triple(t)
		}
		delete(statements)
	}

	base := strings.concatenate({MANIFEST_BASE, base_name})
	defer delete(base)

	p: turtle.Parser
	turtle.parser_init(&p, transmute([]byte)source, base)
	defer turtle.parser_destroy(&p)
	for {
		t, ok := turtle.parser_next(&p)
		if !ok {
			break
		}
		append(&statements, rdf.clone_triple(t))
	}
	if p.err.kind != .None {
		// Callers assert on the count; an empty list fails loudly.
		return out
	}

	for t in statements {
		pred, is_iri := t.predicate.(rdf.IRI)
		if !is_iri || pred != MF_INCLUDE {
			continue
		}
		if obj, obj_iri := t.object.(rdf.IRI); obj_iri {
			append(&out, strings.clone(strip_base(string(obj))))
		}
	}
	return out
}

destroy_includes :: proc(includes: ^[dynamic]string) {
	for s in includes {
		delete(s)
	}
	delete(includes^)
}

// parse_test_file reads one suite file and walks its mf:entries collection,
// preserving manifest order.
parse_test_file :: proc(source: string, base_name: string) -> Test_File {
	tf: Test_File
	tf.entries = make([dynamic]Entry)

	base := strings.concatenate({MANIFEST_BASE, base_name})
	defer delete(base)

	p: turtle.Parser
	turtle.parser_init(&p, transmute([]byte)source, base)
	defer turtle.parser_destroy(&p)
	for {
		t, ok := turtle.parser_next(&p)
		if !ok {
			break
		}
		append(&tf.statements, rdf.clone_triple(t))
	}
	if p.err.kind != .None {
		return tf
	}
	tf.parse_ok = true

	idx := index_by_subject(tf.statements[:])
	defer destroy_index(&idx)

	manifest_subject: rdf.Term
	for t in tf.statements {
		if pred, is_iri := t.predicate.(rdf.IRI); is_iri && pred == rdf.RDF_TYPE {
			if obj, obj_iri := t.object.(rdf.IRI); obj_iri && obj == MF_MANIFEST {
				manifest_subject = t.subject
				break
			}
		}
	}
	if manifest_subject == nil {
		return tf
	}

	cell := object_of(tf.statements[:], &idx, manifest_subject, MF_ENTRIES)
	for cell != nil {
		if iri, is_iri := cell.(rdf.IRI); is_iri && iri == rdf.RDF_NIL {
			break
		}
		entry_node := object_of(tf.statements[:], &idx, cell, rdf.RDF_FIRST)
		if entry_node == nil {
			break
		}

		e: Entry
		if id, is_iri := entry_node.(rdf.IRI); is_iri {
			e.id = strings.clone(strip_base(string(id)))
		}
		e.type_str = iri_string(object_of(tf.statements[:], &idx, entry_node, rdf.RDF_TYPE))
		e.status = iri_string(object_of(tf.statements[:], &idx, entry_node, MF_STATUS))
		if lbl := object_of(tf.statements[:], &idx, entry_node, RDFS_LABEL); lbl != nil {
			if lit, is_lit := lbl.(rdf.Literal); is_lit {
				e.label = strings.clone(lit.lexical)
			}
		}
		if e.label == "" {
			e.label = strings.clone("")
		}

		// mf:action is a blank node carrying sht:dataGraph and
		// sht:shapesGraph. Both are usually `<>` — the file itself — but a
		// handful of entries point at side files, so both are resolved rather
		// than assumed.
		if action := object_of(tf.statements[:], &idx, entry_node, MF_ACTION); action != nil {
			e.data_graph = file_ref(object_of(tf.statements[:], &idx, action, SHT_DATA_GRAPH))
			e.shapes_graph = file_ref(object_of(tf.statements[:], &idx, action, SHT_SHAPES_GRAPH))
		} else {
			e.data_graph = strings.clone("")
			e.shapes_graph = strings.clone("")
		}

		// mf:result is either the sht:Failure sentinel or a blank node whose
		// closure is the expected report.
		result := object_of(tf.statements[:], &idx, entry_node, MF_RESULT)
		if iri, is_iri := result.(rdf.IRI); is_iri && iri == SHT_FAILURE {
			e.expectation = .Failure
		} else {
			e.expectation = .Report
			e.result_node = result
		}

		append(&tf.entries, e)
		cell = object_of(tf.statements[:], &idx, cell, rdf.RDF_REST)
	}
	return tf
}

// expected_report returns the transitive closure of the entry's result node:
// every triple reachable from it by following objects into further subjects.
// That closure is the expected sh:ValidationReport, which is what
// report_isomorphic compares against a produced one.
//
// The closure stops at IRIs deliberately. Following them would drag in the
// data graph, since a report names focus nodes and source shapes that are
// themselves subjects in the same document — the report is exactly the blank
// nodes hanging off mf:result plus the triples they assert.
//
// The returned slice borrows from the Test_File's statements; free the
// dynamic array itself, not the triples.
expected_report :: proc(tf: ^Test_File, e: Entry) -> [dynamic]rdf.Triple {
	out := make([dynamic]rdf.Triple)
	if e.result_node == nil {
		return out
	}
	idx := index_by_subject(tf.statements[:])
	defer destroy_index(&idx)

	seen: map[string]bool
	defer {
		for k in seen {
			delete(k)
		}
		delete(seen)
	}

	frontier: [dynamic]rdf.Term
	defer delete(frontier)
	append(&frontier, e.result_node)

	for len(frontier) > 0 {
		node := pop(&frontier)
		key := subject_key(node)
		if key == "" {
			continue
		}
		if seen[key] {
			delete(key)
			continue
		}
		seen[key] = true

		idxs, found := idx[key]
		if !found {
			continue
		}
		for i in idxs {
			t := tf.statements[i]
			append(&out, t)
			#partial switch o in t.object {
			case rdf.Blank_Node:
				append(&frontier, t.object)
			}
		}
	}
	return out
}

@(private = "file")
iri_string :: proc(term: rdf.Term) -> string {
	if iri, is_iri := term.(rdf.IRI); is_iri {
		return strings.clone(string(iri))
	}
	return strings.clone("")
}

@(private = "file")
file_ref :: proc(term: rdf.Term) -> string {
	if iri, is_iri := term.(rdf.IRI); is_iri {
		return strings.clone(strip_base(string(iri)))
	}
	return strings.clone("")
}

@(private)
index_by_subject :: proc(statements: []rdf.Triple) -> map[string][dynamic]int {
	idx: map[string][dynamic]int
	for t, i in statements {
		key := subject_key(t.subject)
		if key == "" {
			continue
		}
		if idxs, found := &idx[key]; found {
			append(idxs, i)
			delete(key)
		} else {
			lst: [dynamic]int
			append(&lst, i)
			idx[key] = lst
		}
	}
	return idx
}

@(private)
destroy_index :: proc(idx: ^map[string][dynamic]int) {
	for key, idxs in idx {
		delete(key)
		delete(idxs)
	}
	delete(idx^)
}

@(private)
object_of :: proc(
	statements: []rdf.Triple,
	idx: ^map[string][dynamic]int,
	subject: rdf.Term,
	predicate: rdf.IRI,
) -> rdf.Term {
	key := subject_key(subject)
	defer delete(key)
	idxs, found := idx[key]
	if !found {
		return nil
	}
	for i in idxs {
		if pred, is_iri := statements[i].predicate.(rdf.IRI); is_iri && pred == predicate {
			return statements[i].object
		}
	}
	return nil
}

@(private)
subject_key :: proc(term: rdf.Term) -> string {
	#partial switch v in term {
	case rdf.IRI:
		return strings.concatenate({"I", string(v)})
	case rdf.Blank_Node:
		return strings.concatenate({"B", string(v)})
	}
	return ""
}

@(private)
strip_base :: proc(iri: string) -> string {
	if strings.has_prefix(iri, MANIFEST_BASE) {
		return iri[len(MANIFEST_BASE):]
	}
	return iri
}
