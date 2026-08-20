// Package shacl is the SHACL Core validation engine: shapes compilation,
// target resolution, path evaluation, constraint dispatch, validation
// results, and the validation report graph.
//
// Data reaches it from **odin-rdf-record** — the family's system of record,
// and the one and only store, by decision (SHACL-I-0004): an append-only,
// hash-chained log replayed into a memory-resident projection serving
// epoch-pinned snapshots. The engine reads a snapshot through the session
// verbs in session.odin and nothing else; there is no backend abstraction,
// because there is no other backend and none is planned. (The engine was
// built backend-independent against odin-rdf-store's match interface, with
// `shacl/kvstore` binding it; the port that collapsed those seams is
// SHACL-I-0004, and the old shape survives in this repository's history.)
//
// The engine is deliberately validation-only. Inference and entailment
// regimes, SHACL Advanced Features (rules, functions), and any server or
// protocol layer are out of scope permanently; SHACL-SPARQL (`sh:sparql` and
// SPARQL-based constraint components) is a later phase that adds
// odin-rdf-sparql as an optional dependency, and SHACL Core never depends on
// it.
//
//
// # The shape of a validation
//
// Four objects and three steps. A caller compiles a shapes graph once, binds
// the model to the data snapshot once, and then validates as often as it
// likes:
//
//	se := session over a snapshot   // record.store_latest / store_at + session_init
//	compile(&shapes, se)            // from the graph holding the shapes
//	bindings_init(&b, &shapes, se)  // the model's terms → the snapshot's ids
//	validate(&shapes, &b, se, visitor, data)
//
// The shapes session and the data session may be the same, two graphs of one
// store, or two stores entirely: the model owns every term it holds
// (SHACL-A-0001), so it binds to whatever snapshot it is given. The three
// consumers most callers want — a raw result visitor, a `sh:ValidationReport`
// graph, and a conformance boolean — are `validate`, `validate_report`, and
// `conforms`.
//
// A fourth entry point answers a narrower question: `conforms_node` asks whether
// one node conforms to one *named* shape, producing no results at all. It is the
// public face of suppressed validation (SHACL-A-0002), which is also what
// `sh:not`, `sh:and`, `sh:or`, `sh:xone`, `sh:node`, and `sh:qualifiedValueShape`
// are built on. `validate_node` is the same walk with the results streamed.
//
// A snapshot is a value: acquire it, build sessions over it, release it. The
// engine never retains one past the call it received it in — which is also
// what makes it usable inside a `record.Validator`, whose candidate snapshot
// must not be retained.
//
// That binding is the `Validator` (validator.odin): a compiled model wired into a
// store at `record.store_open`, so every `apply` is validated against the
// dataset it would produce — head plus changeset — before a byte is written.
// Under `.Enforce` a violation is refused; under `.Record` it commits and is
// reported. It is how validate-before-commit is done here, and the one place
// the engine is called by the store rather than the other way round.
//
// The past is the same code over `record.store_at(&db, epoch)`: the snapshot
// is pinned, the session binds it, and every read answers about that moment.
// The coordinate is the **epoch** — the record keeps no wall-clock index, and a
// caller holding a time finds its epoch through `snapshot_epoch_meta`. Terms
// are not epoch-scoped, only facts are, so one compiled model binds at any
// epoch; and a model compiled from a pinned snapshot's shapes graph validates
// that snapshot's data under the rules in force at the time (as_of_test.odin).
//
//
// # Memory contract
//
// The family's discipline is borrow-by-default (RDF-A-0001). This package
// deviates from it in exactly two places, both deliberately, and states the
// rule for everything else.
//
//   - **A compiled `Shapes` owns every term it holds** and frees them at
//     `shapes_destroy` (SHACL-A-0001 decision 3). The terms the store hands
//     out are decoded from its dictionary arena, which closing the store
//     frees — so the model interns copies, and **the store a shapes graph was
//     compiled from may be closed immediately afterwards**; the model stays
//     valid until `shapes_destroy`. Shapes graphs are small and bounded, so
//     this costs a copy of a handful of terms, once.
//
//   - **A produced `Report` owns every term in its graph**, including the
//     blank-node labels it mints, and frees them at `report_destroy`. Same
//     reason: the terms come from arena bytes that closing the store
//     invalidates. The triples `report_triples` hands out borrow from the
//     report and die with it.
//
//   - **A `Result` borrows and owns nothing.** It names nodes by resident id
//     and the shape and path by index into the model; it allocates nothing and
//     is valid only for the duration of the visitor call. A caller keeping one
//     must copy what it needs — materialise the terms, or fold it into a
//     `Report`. The alternative, results owning materialised terms, would
//     allocate on the engine's hottest path to serve a case `Report` already
//     serves.
//
//   - **`Bindings` borrow nothing** from either the model or the store; they
//     hold ids. `bindings_destroy` frees them, and the model and store are
//     untouched.
//
//   - **`Error` terms borrow the model's table.** A failed compile still
//     returns a model, precisely so the error stays readable — so the failure
//     path still calls `shapes_destroy`.
//
// Every `*_init` takes a trailing `allocator := context.allocator` and the
// object frees what it took at its `*_destroy`. `tests/guards` asserts this
// with a tracking allocator over compilation, path evaluation, target
// resolution, report building, and validation — including validation's two
// abnormal exits, early stop and recursion failure, which unwind by hand.
//
// **Allocation budgets.** Validation allocates per focus node (a value-node
// set), per reachability round (a frontier), and per shape entered (a stack
// frame), and returns all of it. The two streaming consumers hold to a tighter
// promise: `Conformance` allocates **nothing at all**, whatever the violation
// count, and the result stream itself buffers no results, so memory stays flat
// exactly when the data is worst. A `Report` is the one thing that grows with
// the violation count — it is a graph, and that is what it is for.
//
// **Suppressed validation adds no budget of its own** (SHACL-A-0002), which is
// the practical payoff of reusing the in-flight `Validation` rather than
// building a second one. A `sh:not`, an `sh:or` branch, or a
// `sh:qualifiedValueShape` check costs the same per-focus-node and per-shape
// allocations any other walk of those shapes would, and nothing besides: the
// probe that stands in for the caller's visitor is three saved fields and holds
// no results, and the subclass cache, the recursion set, and the allocator are
// shared rather than duplicated. Six components nesting arbitrarily deep was the
// easiest place in the engine to strand memory, so `tests/guards` runs a
// tracking allocator over the nested forms as well as the flat ones.
//
//
// # Nine contracts a caller should know
//
// The first four are this engine's answers to being incomplete, to being
// written in Odin, or to what RDF leaves open, the next two are SHACL-A-0001
// decisions, and the rest are the spec's; each surprises someone otherwise.
//
// **An unimplemented constraint parameter is ignored, and `shapes_ignored`
// says which.** Erroring on an unrecognised `sh:` parameter would reject the
// spec's own non-validating annotations — `sh:name`, `sh:description`,
// `sh:order`, `sh:group`, `sh:defaultValue` — and every vendor extension a real
// shapes graph carries, so ignoring is the only workable policy. Ignoring
// *silently* is what lets an engine implementing part of SHACL Core produce a
// conforming report and look complete, so compilation records what it passed
// over: **a `sh:conforms true` means what it says only if `shapes_ignored` is
// empty**.
//
// SHACL Core's catalogue is complete as of SHACL-T-0018, so a non-empty list now
// means a vendor extension or `sh:sparql` rather than a missing Core component.
// The record covers `sh:` predicates on the nodes compilation recognised as
// shapes (§2.1.1) and nothing else, which is the right scope and worth saying
// plainly: a `sh:` predicate on a node that is not a shape is not a parameter
// anybody skipped. It is empty for all 98 entries of the vendored suite, and
// the suite harness asserts that rather than trusting it.
//
// **Blank nodes in a report come from three graphs and are standardised apart.**
// A report names its own structure, nodes of the data graph (`sh:focusNode`,
// `sh:value`), and nodes of the shapes graph (`sh:sourceShape`) — three separate
// label spaces merged into one graph. The labels are made disjoint on the way
// in: a data-graph blank node keeps the label the store holds for it, because
// that is what lets a consumer say *which* unnamed node failed; a shapes-graph
// blank node is prefixed with `s`; and the report's own are `r0`, `r1`, ….
// Reading a blank-node `sh:sourceShape` back against the shapes graph means
// stripping the `s`. The record store interns labels as given, so keeping the
// spaces apart *between documents* is the loader's `blank_prefix` — and a
// caller's prefixes must not begin with `r` or `s`.
//
// **`sh:datatype` skips the lexical check for datatypes it does not model.**
// §4.1.2 requires the value's lexical form to lie in the datatype's lexical
// space as well as the IRI to match, and this engine enforces it — for
// xsd:string, xsd:boolean, the integer tower with its derived ranges,
// xsd:decimal, xsd:float, xsd:double, xsd:dateTime, xsd:date, and
// rdf:langString. Any other datatype passes on the IRI alone. Failing instead
// would reject `sh:datatype rdf:HTML` on a perfectly good HTML literal: a
// lexical form can only be called invalid against a space that is known. The
// same machinery decides `sh:minInclusive` and its three companions, so the two
// answers can never diverge.
//
// **`sh:pattern` is a different regular-expression dialect, and says so.**
// SHACL defines it by XPath `fn:matches` — XML Schema regular expressions, flags
// `i s m x q`. This engine uses `core:text/regex`, which keeps the family free of
// external dependencies and is not that dialect. The common subset agrees;
// beyond it, behaviour may differ. `i`, `m`, and `x` map across, and **`s` and
// `q` are rejected at compile time** (`Error_Kind.Flags_Unsupported`), as is a
// pattern the engine cannot compile (`Error_Kind.Pattern_Ill_Formed`). Refusing
// beats ignoring: a silently-dropped flag validates against a pattern nobody
// wrote and then reports conformance.
//
// **One data graph.** SHACL is specified against a single RDF graph;
// odin-rdf-record holds a quad dataset. Validation reads one caller-named
// graph — the default graph, or one named graph — never a union of them. The
// session is where that is enforced: the graph is bound into every pattern in
// session.odin, and nothing above it ever writes one.
//
// **`sh:class` needs the class hierarchy in the *data* graph.** It walks
// `rdfs:subClassOf*` in the graph being validated, not in the shapes graph, so
// a shape saying `sh:class ex:Asset` will not see that `ex:ResourceAsset` is a
// subclass of `ex:Asset` unless that triple is in the data graph. This follows
// from the single-graph decision and is the most common way a shapes graph
// silently under-reports. `sh:targetClass` walks the same closure, so a target
// that finds nothing usually has the same cause.
//
// **Conformance is about results, not severities.** `sh:conforms` is true if
// and only if validation produced no results at all (§3.1) — a warning breaks
// it exactly as a violation does. `Conformance` therefore stops at the first
// result of any kind. Relatedly, `sh:severity` is an **arbitrary IRI**:
// `sh:Violation`, `sh:Warning`, and `sh:Info` are the built-ins but not the
// whole set, which is why `Shape.severity` and `Result.severity` are
// `rdf.Term` rather than an enum. `severity_is` compares one against a
// vocabulary constant.
//
// **A `sh:closed` result's path is a term, not the shape's path.** §4.8.1 makes
// the result blame the triple it objected to — `sh:resultPath` is that triple's
// predicate and `sh:value` its object — and that predicate belongs to the data
// graph, so no index into the compiled model can name it. `Result.path` is
// therefore -1 for these and `has_path_predicate` is true instead, with the
// predicate in `path_predicate`; a caller reading `path` alone will conclude
// there is no path, and on a node shape that is exactly the wrong conclusion.
// `Report` handles it. Relatedly, `sh:closed` is switched on by the term
// `"true"^^xsd:boolean` and by nothing else — `"1"^^xsd:boolean` leaves the shape
// open — which is the reading `sh:uniqueLang` takes for the same wording, on the
// authority of a suite entry.
//
// **Recursive shapes are reported as a failure, not validated.** §3.4 leaves
// recursion undefined and explicitly permits a processor to signal a failure,
// which is what this does: `validate` returns `Failure.Recursive_Shape` at the
// first re-entry of a shape already being validated, having produced whatever
// results it found before that. A failure is **not** a conformance answer — a
// caller must check it before reading the boolean or the report.
//
// **Cycles in data are not recursion.** A graph where `ex:a` is `ex:partOf`
// `ex:b` which is `ex:partOf` `ex:a` is ordinary, and validates: recursion is
// a property of the *shapes*, and detection is on the set of shapes currently
// on the stack. What triggers it is a shape that reaches itself — through
// `sh:property`, through any of the logical combinators, through `sh:node`, or
// through `sh:qualifiedValueShape`. A suppressed run shares the outer walk's
// stack (SHACL-A-0002), so `ex:S sh:node ex:S` is recursion exactly as
// `ex:S sh:property [ ... ex:S ... ]` is, and so is a mutual pair. **`sh:node`
// is how a user writes one by accident**, on data where an asset points at an
// asset. Every path form is separately cycle-safe over data, by a visited set,
// so `sh:zeroOrMorePath` over the graph above terminates.
//
// Cycle-breaking ("assume valid on re-entry") remains addable later without
// redesign if evidence asks for it.
package shacl
