# odin-rdf-shacl

[![CI](https://github.com/odin-rdf/odin-rdf-shacl/actions/workflows/ci.yml/badge.svg)](https://github.com/odin-rdf/odin-rdf-shacl/actions/workflows/ci.yml)

Shape-based validation for the Odin RDF family: a SHACL implementation that
validates RDF data graphs against shapes graphs. Shapes are themselves RDF,
parsed with [odin-rdf-parser](../odin-rdf-parser); the data graph is read
through [odin-rdf-store](../odin-rdf-store)'s match interface alone, so the
same shapes validate in-memory and LMDB-backed data identically. Written in
Odin with no external dependencies.

**Status: under construction.** The Core spine validates: shapes compilation,
target resolution, property paths, constraint dispatch, and
`sh:ValidationReport` emission all work end to end, and the W3C suite's
`core/targets` and `core/path` directories are green — every entry, against
both storage backends, at both `Term_ID` widths. What is missing is most of the
SHACL Core constraint catalogue: the spine implements `sh:minCount`,
`sh:maxCount`, `sh:class`, `sh:datatype`, `sh:nodeKind`, `sh:hasValue`, and
`sh:in`, which is what those two directories exercise. The value-range and
string components, `sh:closed`, the logical combinators, and the shape-based
constraints are the second initiative, and the remaining suite directories stay
disabled until they land. The public API and its documentation are
SHACL-T-0008. See `.metis/` for the vision, the initiative, and SHACL-A-0001.

This is a peer of [odin-rdf-sparql](../odin-rdf-sparql) on the same
foundation, not a layer above it. **SHACL Core has no dependency on the query
engine at all** — not at runtime, and not at link time: the `sparql:`
collection is deliberately absent from the `Makefile` until the SHACL-SPARQL
phase begins. Inference and entailment regimes, SHACL Advanced Features
(rules, functions), and any server or protocol layer are out of scope
permanently.

## Packages

| Package          | Description                                                     |
| ---------------- | --------------------------------------------------------------- |
| `shacl`          | The backend-independent core: shapes compilation, targets, paths, constraint dispatch, validation results |
| `shacl/memstore` | The validator instantiated against the in-memory backend        |
| `shacl/kvstore`  | The validator instantiated against the persistent (LMDB) backend |

`shacl` names no storage backend and imports none, so a program that only
wants an in-memory store never links LMDB. That property is asserted rather
than trusted — `make check` builds a core-plus-memstore consumer and fails if
the binary carries LMDB symbols.

## Building

The parser and the store are **sibling checkouts**, not vendored copies, and
are reached through Odin collections:

```
../odin-rdf-parser   -collection:rdf=../odin-rdf-parser
../odin-rdf-store    -collection:store=../odin-rdf-store
../odin-rdf-shacl    (this repository)
```

Both collections are required even though SHACL Core only names the store: the
store's own sources import `rdf:`, and a collection is resolved in the
*importing* compilation, not the imported checkout. The `Makefile` and
`ols.json` both declare them.

```
make test    # the full suite at both Term_ID widths (64-bit default, 32-bit opt-in)
make check   # vet every package, then assert the core links no LMDB
make bench   # build and run benchmarks with release flags (once bench/ exists)
make help    # list targets
```

`Term_ID` width is a build-time choice in odin-rdf-store (STORE-A-0001) and
this project compiles the store's sources into its own binaries, so validation
code must not assume 64-bit IDs. `make test` runs the whole matrix rather than
one configuration.

## Two things to know before writing shapes

Both are decided in SHACL-A-0001 and will surprise someone otherwise.

**Validation reads one graph.** SHACL is specified against a single RDF graph;
odin-rdf-store holds a quad dataset. The validator takes the graph to
read — the default graph, or one named graph — and never a union of them.

**`sh:class` needs the class hierarchy in the data graph.** It walks
`rdfs:subClassOf*` in the graph being validated, not in the shapes graph. A
shape that says `sh:class ex:ResourceAsset` will not see that
`ex:ResourceAsset` is a subclass of `ex:Asset` unless that triple is in the
data graph.

## License

See [LICENSE](LICENSE).
