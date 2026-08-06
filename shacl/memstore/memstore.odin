// Package shacl_memstore is the memstore instantiation of the validation
// engine: the thin layer that binds package shacl's backend-independent core
// to odin-rdf-store's in-memory backend.
//
// The core names no backend. This package supplies the other half — the
// hot-path match adapters passed to the core as compile-time constants, term
// binding through memstore's dictionary, and materialization of result IDs
// back into RDF terms. `shacl/kvstore` is the same file against the
// persistent backend, and the two are meant to stay recognizably parallel: a
// change to one is a question about the other.
//
// The arrangement is odin-rdf-sparql's, resolved there in SPARQL-T-0011
// against this same store, and inherited here rather than re-decided. Its
// decisive finding applies unchanged: kvstore foreign-imports a static LMDB
// archive, so a core that imported it would put LMDB into the link of every
// consumer that only ever wanted an in-memory store.
//
// This package also owns the convenience path most callers want — a shapes
// graph in a Turtle file, parsed into a memstore and compiled — which lives
// here rather than in the core precisely so the core keeps no backend
// dependency (SHACL-A-0001 decision 1).
//
// Populated from SHACL-T-0003 on.
package shacl_memstore
