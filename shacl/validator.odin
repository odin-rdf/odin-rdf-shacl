package shacl

import "base:runtime"
import "core:strings"

import "rdf:rdf"
import "record:record"

// Validate-before-commit: a compiled shapes model bound as a
// `record.Validator` (SHACL-T-0034, the binding RECORD-A-0006 named this
// repository for).
//
// The record store has one write entrance, `apply`, and one validator per store,
// wired at `store_open` and consulted on every changeset between building
// the candidate and writing a byte. What the validator receives is the
// **post-state** — head plus changeset, as an ordinary `Snapshot` at the new
// epoch — through the same read API every other snapshot answers. So a
// `Validator` validates *the dataset the write would produce*: a `sh:maxCount`
// over a property the dataset already carries values for, a `sh:class`
// against a hierarchy that lives only in committed data, uniqueness across
// the dataset — every constraint that must consult existing data sees it.
// The obvious alternative, validating a candidate in a store of its own, is
// wrong rather than slow: each of those constraints reads an empty world and
// passes. (That was `session_init_txn`'s argument on the old store,
// SHACL-T-0029; this is the same argument on the mechanism built for it.)
//
// The verdict's effect is the changeset's `Mode`, not the validator's: under
// `.Enforce` a refusal is `apply`'s `.Rejected` and nothing is written —
// the store is exactly as it was; under `.Record` the epoch commits and
// `apply` returns `conforms = false`. **The log does not record that a validator
// objected** (RECORD-A-0006, decision 5): a `.Record`-mode epoch whose
// changeset did not conform is byte-for-byte the epoch a conforming one
// would have written. A consumer that wants the verdict durable writes the
// report as facts, in the same or a following changeset; this binding
// offers no helper for that.

// Validator is a compiled shapes model standing as a store's validator, plus
// the state one check leaves behind for the caller to read after `apply`
// returns: the verdict, the `Failure` if the engine could not answer, and —
// when reporting — the full `sh:ValidationReport` graph.
//
// **The model is borrowed and must outlive the validator**, and the validator must
// outlive the store it is wired into (`store_close` before `validator_destroy`).
// SHACL-A-0001's ownership is what makes the arrangement work: the model
// owns every term it holds, so it may be compiled from a snapshot of the
// same store, from another store since closed, or from a document — and it
// binds to each candidate afresh. One validator serves one store; its fields are
// written on the applying thread during `check`, and `apply` is not safe
// against itself, so neither is reading a validator while an `apply` on its
// store is in flight.
//
// **Reset per apply.** Every check starts by discarding the previous check's
// report and verdict. What a validator holds is therefore always *the last
// `apply`'s* — valid from the moment `apply` returns until the next `apply`
// on the store, or `validator_destroy`. A caller that wants to keep a report
// emits it (`report_triples` through any of odin-rdf-parser's emitters) or
// copies it before applying again.
Validator :: struct {
	shapes:     ^Shapes,
	graph:      rdf.Graph_Label, // owned copy; nil is the default graph
	graphs:     []rdf.Graph_Label, // owned copies; the union, when `scoped` (SHACL-T-0039)
	scoped:     bool, // validator_init_union: read the union of `graphs`, not `graph`
	reporting:  bool,
	report:     Report,
	has_report: bool,
	conforms:   bool, // the last check's verdict; meaningless before the first
	failure:    Failure, // the last check's Failure; `.None` when it could answer
	checks:     int, // how many changesets this validator has seen
	allocator:  runtime.Allocator,
}

// validator_init binds a compiled model as a validator over one graph of the store
// it will be wired into — nil for the default graph, or the graph's label;
// `validator_init_union` is the same over a set of graphs (SHACL-T-0039). The
// label is copied. `reporting` chooses between the full report graph per
// check (`validator_report`) and the verdict alone, which allocates nothing per
// result (`Conformance`, SHACL-A-0002) and is the shape a gate that only
// needs yes or no should take. Everything the validator allocates comes from
// `allocator` and is returned at `validator_destroy`.
validator_init :: proc(
	v: ^Validator,
	shapes: ^Shapes,
	graph: rdf.Graph_Label = nil,
	reporting := true,
	allocator := context.allocator,
) {
	v^ = {}
	v.shapes = shapes
	v.reporting = reporting
	v.allocator = allocator
	v.graph = label_clone(graph, allocator)
}

// validator_init_union binds a compiled model as a validator over the **union of
// a set of graphs** (SHACL-T-0039) — the data graph a workspace and its
// ancestors make together. The labels are copied (nil is the default graph)
// and resolved against each candidate at check time, so a graph the changeset
// itself is the first to name is validated rather than read as absent, and a
// label the candidate does not know contributes nothing. An empty set
// validates an empty data graph. Everything else is validator_init.
validator_init_union :: proc(
	v: ^Validator,
	shapes: ^Shapes,
	graphs: []rdf.Graph_Label,
	reporting := true,
	allocator := context.allocator,
) {
	v^ = {}
	v.shapes = shapes
	v.reporting = reporting
	v.allocator = allocator
	v.scoped = true
	v.graphs = make([]rdf.Graph_Label, len(graphs), allocator)
	for label, i in graphs {
		v.graphs[i] = label_clone(label, allocator)
	}
}

// validator_destroy frees the validator's report and its copies of the graph
// labels. The model is the caller's and is untouched. Close the store first: a
// store whose validator is gone would call into freed state on its next apply.
validator_destroy :: proc(v: ^Validator) {
	if v.has_report {
		report_destroy(&v.report)
	}
	label_delete(v.graph, v.allocator)
	for label in v.graphs {
		label_delete(label, v.allocator)
	}
	delete(v.graphs, v.allocator)
	v^ = {}
}

@(private = "file")
label_clone :: proc(label: rdf.Graph_Label, allocator: runtime.Allocator) -> rdf.Graph_Label {
	switch g in label {
	case rdf.IRI:
		return rdf.IRI(strings.clone(string(g), allocator))
	case rdf.Blank_Node:
		return rdf.Blank_Node(strings.clone(string(g), allocator))
	}
	return nil
}

@(private = "file")
label_delete :: proc(label: rdf.Graph_Label, allocator: runtime.Allocator) {
	switch g in label {
	case rdf.IRI:
		delete(string(g), allocator)
	case rdf.Blank_Node:
		delete(string(g), allocator)
	}
}

// validator_hook is the `record.Validator` to pass to `store_open`. The
// validator is referenced, not copied: it must stay where it is for as long as
// the store is open.
validator_hook :: proc(v: ^Validator) -> record.Validator {
	return record.Validator{check = validator_check, data = v}
}

// validator_report is the last check's `sh:ValidationReport`, finished and ready
// to read or emit, or nil for a validator that is not reporting or has not yet
// validated anything. Valid until the next `apply` on the store or
// `validator_destroy` — see the reset rule on `Validator`.
validator_report :: proc(v: ^Validator) -> ^Report {
	if !v.reporting || !v.has_report {
		return nil
	}
	return &v.report
}

// validator_check is the `record.Validator.check` a validator installs. It runs on
// the applying thread with the candidate snapshot — the post-state — and
// validates the validator's graph of it in full: every target of every shape,
// not only the nodes the changeset touched, because a change to one node
// can make another violate (`sh:uniqueLang` across values, an inverse
// path, a `sh:class` whose hierarchy moved). A consumer that knows its
// shapes well enough to narrow that has `validate_node` and the
// changeset's ops to build a narrower validator of its own.
//
// **The candidate is not retained.** Record hands it out without a
// reference of its own and publishes or frees it the moment this returns;
// the session over it, the bindings, and every read live inside this call.
// The pre-state, were a check to need it, is a `record.store_latest`
// acquire/release inside the call — apply holds no lock while the hook
// runs — and nothing here needs it: the candidate *is* head plus change.
// `allocator` is apply's scratch and serves the bindings and the
// validation's transients; the report, which outlives the call, comes from
// the validator's own.
//
// **A `Failure` is a refusal.** When the engine cannot answer
// (`Recursive_Shape`), the verdict is `false` and `failure` says why: a validator
// that cannot answer does not let a write through, and the caller can tell a
// refusal from a violation by reading `failure` after `apply` returns.
validator_check :: proc(
	data: rawptr,
	candidate: record.Snapshot,
	ops: []record.Resident_Op,
	allocator: runtime.Allocator,
) -> bool {
	v := (^Validator)(data)
	v.checks += 1
	v.conforms = false
	v.failure = .None

	// The graph — or every graph of the union — is resolved against the
	// candidate, so a graph the changeset is the first to name is validated
	// rather than read as absent.
	se: Session
	ids: [dynamic]record.Term_ID
	defer delete(ids)
	if v.scoped {
		ids = make([dynamic]record.Term_ID, allocator)
		session_resolve_graphs(candidate, v.graphs, &ids)
		session_init_union(&se, candidate, ids[:])
	} else {
		session_init(&se, candidate, v.graph)
	}

	b: Bindings
	bindings_init(&b, v.shapes, se, allocator)
	defer bindings_destroy(&b)

	if v.reporting {
		if v.has_report {
			report_destroy(&v.report)
		}
		report_init(&v.report, v.allocator)
		v.has_report = true
		v.failure = validate_report(&v.report, v.shapes, &b, se, allocator)
		v.conforms = report_conforms(&v.report)
	} else {
		v.conforms, v.failure = conforms(v.shapes, &b, se, allocator)
	}
	if v.failure != .None {
		v.conforms = false
	}
	return v.conforms
}
