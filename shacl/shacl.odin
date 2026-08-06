// Package shacl is the backend-independent core of the SHACL validation
// engine: shapes compilation, target resolution, path evaluation, constraint
// dispatch, and validation results.
//
// It names no storage backend and imports none. Data reaches it through
// odin-rdf-store's published match contract, bound at compile time by a thin
// instantiation package — `shacl/memstore` for the in-memory backend,
// `shacl/kvstore` for the persistent one. That split is not stylistic:
// kvstore foreign-imports a static LMDB archive, so a core that imported it
// would put LMDB into the link of every consumer, including the ones that
// only ever want an in-memory store. `tests/purity` asserts the property
// rather than trusting it.
//
// The engine is deliberately validation-only. Inference and entailment
// regimes, SHACL Advanced Features (rules, functions), and any server or
// protocol layer are out of scope permanently; SHACL-SPARQL (`sh:sparql` and
// SPARQL-based constraint components) is a later phase that adds
// odin-rdf-sparql as an optional dependency, and SHACL Core never depends on
// it.
//
// Two contracts a caller should know before the API exists to state them
// (SHACL-A-0001):
//
//   - **One data graph.** SHACL is specified against a single RDF graph;
//     odin-rdf-store holds a quad dataset. Validation reads one caller-named
//     graph — the default graph, or one named graph — never a union of them.
//     A consequence worth knowing early: `sh:class` walks `rdfs:subClassOf*`
//     in the *data* graph, so a class hierarchy has to live in the graph
//     being validated, not in the shapes graph.
//   - **A compiled shapes model owns its terms.** It is compiled from a
//     store but does not borrow from one, so the store a shapes graph was
//     read from may be destroyed while the model is still in use.
//
// Populated from SHACL-T-0003 on; this file carries the package contract from
// the first commit so the Makefile's pinned package list is real and the
// documentation standard is set before there is code to document.
package shacl
