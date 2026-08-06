// Package shacl_kvstore is the kvstore instantiation of the validation
// engine — the persistent twin of `shacl/memstore`. Read the two together:
// the core is shared and unchanged, and everything different here is a
// consequence of the backend, not of SHACL.
//
// Three differences this package absorbs, the same three odin-rdf-sparql
// found (SPARQL-T-0011):
//
//   - **One handle, not two.** kvstore keeps its dictionary and its quads in
//     one Store, where memstore keeps a Dictionary and a Dataset.
//   - **Operations can fail.** An LMDB read can return an error, and the
//     core's hot-path signatures have nowhere to put one. Swallowing it would
//     be the worst outcome — a failed read would be indistinguishable from a
//     pattern that matched nothing — so the handle the core is given carries
//     an error slot the adapters write.
//   - **Materialization allocates.** kvstore's lookup_term builds a term from
//     the database's bytes where memstore's borrows the dictionary's, so
//     whatever materializes terms here owns and frees them.
//
// Populated from SHACL-T-0003 on. The package exists now, with a linkage
// test, because it is the one package in this repo that pulls in the vendored
// LMDB archive: proving that link works on every CI platform before any
// deadline depends on it is cheaper than discovering it later
// (SHACL-T-0001).
package shacl_kvstore
