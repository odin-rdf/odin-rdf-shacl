package shacl_kvstore

// Small shims the ported suites need, so each file does not carry its own.
//
// The in-memory backend's lookup_term borrowed from the dictionary and could
// not fail, so the suites called it inline and used the result directly.
// kvstore copies each term out of the mapped pages into a caller allocator and
// reports store failures, which is two extra concerns at every call site — and
// the assertions those call sites belong to are about SHACL, not about term
// materialization. These wrap it once (odin-rdf-store STORE-A-0006,
// SHACL-T-0028).
//
// Terms come from the temp allocator: the suites render them to strings
// immediately and never keep one.
//
// Both go through the session's own reads rather than through kvstore
// directly, so they work on a transactional session as well as an autocommit
// one (SHACL-T-0029) — a helper that read `s.db` would see nil on the former.

import rdf "rdf:rdf"
import store "store:store"

// session_term materialises a term for rendering in an assertion message.
// A store failure yields a blank node named for the failure rather than
// panicking, so one broken read shows up as a mismatched expectation rather
// than as a lost test run.
@(private)
session_term :: proc(s: ^Session, id: store.Term_ID) -> rdf.Term {
	term, err := session_lookup(s, id, context.temp_allocator)
	if err != nil {
		return rdf.Blank_Node("lookup-failed")
	}
	return term
}

// session_find is find_term with the store error folded into found=false —
// the suites' focus-node lookups treat "absent" and "unreadable" the same way,
// and each site already asserts on found.
@(private)
session_find :: proc(s: ^Session, term: rdf.Term) -> (id: store.Term_ID, found: bool) {
	got, ok, err := session_find_term(s, term)
	if err != nil {
		return 0, false
	}
	return got, ok
}
