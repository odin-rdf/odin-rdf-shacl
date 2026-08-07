// Package shacl is the backend-independent core of the SHACL validation
// engine: shapes compilation, target resolution, path evaluation, constraint
// dispatch, validation results, and the validation report graph.
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
//
// # The shape of a validation
//
// Four objects and three steps. A caller compiles a shapes graph once, binds
// the model to the data store once, and then validates as often as it likes:
//
//	shapes   := compile(...)      // from a store holding the shapes graph
//	bindings := bind(...)         // the model's terms → the data store's IDs
//	validate(shapes, bindings, ..., visitor, data)
//
// `compile`, `bind`, and `validate` are supplied by the instantiation package,
// because each names a backend; everything they call is here. The three
// consumers most callers want — a raw result visitor, a `sh:ValidationReport`
// graph, and a conformance boolean — are also there, as `validate`,
// `validate_report`, and `conforms`.
//
// A fourth entry point answers a narrower question: `conforms_node` asks whether
// one node conforms to one *named* shape, producing no results at all. It is the
// public face of suppressed validation (SHACL-A-0002), which is also what
// `sh:not`, `sh:or`, `sh:xone`, `sh:node`, and `sh:qualifiedValueShape` are built
// on — the reason it exists before they do.
//
//
// # Memory contract
//
// The family's discipline is borrow-by-default (RDF-A-0001). This package
// deviates from it in exactly two places, both deliberately, and states the
// rule for everything else.
//
//   - **A compiled `Shapes` owns every term it holds** and frees them at
//     `shapes_destroy`. This is the deviation, and SHACL-A-0001 decision 3 is
//     why: the two backends disagree about what `lookup_term` returns —
//     memstore borrows its dictionary's storage, kvstore builds a term from
//     the database's bytes — so a borrowing model would have had a
//     backend-dependent lifetime rule in its public contract. Owning states
//     one rule instead: **the store a shapes graph was compiled from may be
//     destroyed immediately afterwards**, and the model stays valid until
//     `shapes_destroy`. Shapes graphs are small and bounded, so this costs a
//     copy of a handful of terms, once.
//
//   - **A produced `Report` owns every term in its graph**, including the
//     blank-node labels it mints, and frees them at `report_destroy`. Same
//     reason, and on kvstore it is not a nicety but the only workable rule:
//     the terms come from mapped database pages that closing the store
//     invalidates. The triples `report_triples` hands out borrow from the
//     report and die with it.
//
//   - **A `Result` borrows and owns nothing.** It names nodes by `Term_ID` and
//     the shape and path by index into the model; it allocates nothing and is
//     valid only for the duration of the visitor call. A caller keeping one
//     must copy what it needs — materialise the terms, or fold it into a
//     `Report`. The alternative, results owning materialised terms, would
//     allocate on the engine's hottest path to serve a case `Report` already
//     serves.
//
//   - **`Bindings` borrow nothing** from either the model or the store; they
//     hold IDs. `bindings_destroy` frees them, and the model and store are
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
//
// # Six contracts a caller should know
//
// The first two are this engine's answers to being incomplete, the next two are
// SHACL-A-0001 decisions, and the rest are the spec's; each surprises someone
// otherwise.
//
// **An unimplemented constraint parameter is ignored, and `shapes_ignored`
// says which.** Erroring on an unrecognised `sh:` parameter would reject the
// spec's own non-validating annotations — `sh:name`, `sh:description`,
// `sh:order`, `sh:group`, `sh:defaultValue` — and every vendor extension a real
// shapes graph carries, so ignoring is the only workable policy. Ignoring
// *silently* is what lets an engine implementing part of SHACL Core produce a
// conforming report and look complete, so compilation records what it passed
// over. While the constraint catalogue is incomplete, **a `sh:conforms true`
// means what it says only if `shapes_ignored` is empty**.
//
// **`sh:datatype` skips the lexical check for datatypes it does not model.**
// §4.3.1 requires the value's lexical form to lie in the datatype's lexical
// space as well as the IRI to match, and this engine enforces it — for
// xsd:string, xsd:boolean, the integer tower with its derived ranges,
// xsd:decimal, xsd:float, xsd:double, xsd:dateTime, xsd:date, and
// rdf:langString. Any other datatype passes on the IRI alone. Failing instead
// would reject `sh:datatype rdf:HTML` on a perfectly good HTML literal: a
// lexical form can only be called invalid against a space that is known. The
// same machinery decides `sh:minInclusive` and its three companions, so the two
// answers can never diverge.
//
// **One data graph.** SHACL is specified against a single RDF graph;
// odin-rdf-store holds a quad dataset. Validation reads one caller-named
// graph — the default graph, or one named graph — never a union of them. The
// core cannot even express a union: neither `Scan` nor `Step` takes a graph,
// because the instantiation package's adapter binds it.
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
// `sh:property` today, and through `sh:node` when the catalogue initiative
// adds it. Every path form is separately cycle-safe over data, by a visited
// set, so `sh:zeroOrMorePath` over the graph above terminates.
//
// Cycle-breaking ("assume valid on re-entry") remains addable later without
// redesign if evidence asks for it.
package shacl
