package shacl

import "base:runtime"
import "core:strings"

import rdf "rdf:rdf"
import store "store:store"

// Term_Table is the model's term storage: it owns a cloned copy of every term
// the compiled shapes model holds, and frees them all at destroy.
//
// This is what makes a Shapes independent of the store it was compiled from
// (SHACL-A-0001 decision 3). The alternative — borrowing from the shapes
// store's dictionary — would have made the lifetime rule backend-dependent
// and part of the public contract, because memstore's `lookup_term` borrows
// while kvstore's allocates. Owning states one rule instead: the model is
// valid until `shapes_destroy`, whatever it was compiled from.
//
// Identical terms are interned to one copy. Shapes graphs repeat a small
// vocabulary heavily — every property shape names `sh:path`, every constraint
// names its component — so this is a real saving on a small table, not
// premature thrift.
Term_Table :: struct {
	terms:     [dynamic]rdf.Term,
	strings:   [dynamic]string,
	index:     map[string]int,
	allocator: runtime.Allocator,
}

term_table_init :: proc(tt: ^Term_Table, allocator := context.allocator) {
	tt.allocator = allocator
	tt.terms = make([dynamic]rdf.Term, allocator)
	tt.strings = make([dynamic]string, allocator)
	tt.index = make(map[string]int, allocator)
}

term_table_destroy :: proc(tt: ^Term_Table) {
	context.allocator = tt.allocator
	for t in tt.terms {
		rdf.destroy_term(t, tt.allocator)
	}
	delete(tt.terms)
	for s in tt.strings {
		delete(s, tt.allocator)
	}
	delete(tt.strings)
	for key in tt.index {
		delete(key, tt.allocator)
	}
	delete(tt.index)
	tt^ = {}
}

// intern returns the table's own copy of term, cloning it on first sight.
// The returned term is valid until term_table_destroy.
intern :: proc(tt: ^Term_Table, term: rdf.Term) -> rdf.Term {
	if term == nil {
		return nil
	}
	key := term_key(term, tt.allocator)
	if i, found := tt.index[key]; found {
		delete(key, tt.allocator)
		return tt.terms[i]
	}
	cloned := rdf.clone_term(term, tt.allocator)
	append(&tt.terms, cloned)
	tt.index[key] = len(tt.terms) - 1
	return cloned
}

// materialize_term resolves a store ID into the model's own storage: load it
// from the backend, intern it, and free the loader's copy if it owned one.
// Every term the compiler keeps goes through here, which is exactly what makes
// a compiled model independent of the store it came from.
@(private)
materialize_term :: proc(s: ^Shapes, load: Term_Loader, load_data: rawptr, id: store.Term_ID) -> rdf.Term {
	term, owned := load(load_data, id, s.allocator)
	result := intern(&s.terms, term)
	if owned {
		rdf.destroy_term(term, s.allocator)
	}
	return result
}

// intern_string returns the table's own copy of s. Used for message text and
// language tags, which are not terms but have the same lifetime.
intern_string :: proc(tt: ^Term_Table, s: string) -> string {
	if s == "" {
		return ""
	}
	cloned := strings.clone(s, tt.allocator)
	append(&tt.strings, cloned)
	return cloned
}

// term_key is a serialization that distinguishes terms exactly: two terms
// share a key iff they are the same RDF term. All four literal components
// participate, so `"x"@en` and `"x"@EN` are distinct keys today — whatever
// the family decides about language-tag folding belongs at literal
// construction in odin-rdf-parser, not here.
@(private = "file")
term_key :: proc(term: rdf.Term, allocator: runtime.Allocator) -> string {
	sb := strings.builder_make(allocator)
	write_term_key(&sb, term)
	return strings.to_string(sb)
}

@(private = "file")
write_term_key :: proc(sb: ^strings.Builder, term: rdf.Term) {
	switch v in term {
	case rdf.IRI:
		strings.write_byte(sb, 'I')
		strings.write_string(sb, string(v))
	case rdf.Blank_Node:
		strings.write_byte(sb, 'B')
		strings.write_string(sb, string(v))
	case rdf.Literal:
		strings.write_byte(sb, 'L')
		strings.write_string(sb, v.lexical)
		strings.write_byte(sb, 0x1E)
		strings.write_string(sb, string(v.datatype))
		strings.write_byte(sb, 0x1E)
		strings.write_string(sb, v.language)
		strings.write_byte(sb, byte(v.direction))
	case ^rdf.Triple:
		strings.write_byte(sb, '(')
		write_term_key(sb, v.subject)
		strings.write_byte(sb, 0x1E)
		write_term_key(sb, v.predicate)
		strings.write_byte(sb, 0x1E)
		write_term_key(sb, v.object)
		strings.write_byte(sb, ')')
	}
}
