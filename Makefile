NAME  := shacl-bench
BENCH := bench

# Odin rejects an output path with no extension on Windows -- so every `-out:`
# in this file is spelled through EXE. `OS` is set to Windows_NT by Windows
# itself rather than by the shell, which is the one test that holds whether
# make is MSYS, MinGW, or native.
#
# Only the built benchmark binary needs it. `odin test` names its own output
# and `odin check` writes none, so the suite and the vet pass were never
# affected.
ifeq ($(OS),Windows_NT)
EXE := .exe
else
EXE :=
endif

OUT := build/$(NAME)$(EXE)

# Odin source collections. The parser and the store are sibling checkouts
# rather than vendored copies, so they are reached through collections instead
# of relative paths -- `import "rdf:rdf"` for the data model and `rdf:rdf/turtle`
# and friends for the four format packages, `import "store:store"` for the match
# interface and `store:store/kvstore` for the
# backends. Both collections are required even where this project only names the
# store: the store's own sources import `rdf:`, and a collection is resolved in
# the importing compilation, not the imported checkout. The SHACL-SPARQL phase
# adds `-collection:sparql=../odin-rdf-sparql` here and in ols.json; Core needs
# no query engine, so it stays out until there is something importing it.
#
# `record:` is odin-rdf-record, the store this repository is porting onto
# (SHACL-I-0004): `import "record:record"` for the store and `record:record/ingest`
# for the document loaders. `rdf:` stays required for the same
# resolved-in-the-importer reason -- record's own sources import it. `store:`
# leaves this line when SHACL-T-0032/T-0033 delete the last import of it.
COLL := -collection:rdf=../odin-rdf-parser -collection:store=../odin-rdf-store -collection:record=../odin-rdf-record

# Every package with tests, listed rather than discovered (SHACL-T-0001).
# `shacl` is the engine, one package over odin-rdf-record (SHACL-T-0032 —
# the instantiation split went with the backend seams); guards holds the
# allocation assertions; readme compiles the README's examples so the
# documentation cannot drift from the API; w3c/harness reads the vendored W3C
# SHACL suite (SHACL-T-0002) — **temporarily out of the list** while
# SHACL-T-0033 ports it onto the record store, and back in when it lands.
PKGS := shacl \
				tests/guards \
				tests/readme \
				tests/smoke

# STORE-A-0001 makes the store's Term_ID width a build-time choice, and this
# project compiles the store's sources into its own binaries. Validation code
# must not assume 64-bit IDs, so the suite runs once per configuration rather
# than once. This is what CI should invoke -- `make test`, the whole matrix.
WIDTHS := 64 32

.PHONY: all help test check bench build-bench clean

all: test

# The description of a target is the `##` on its own recipe line, which is what
# help greps for -- prose above a target is for a reader of this file, not the
# listing. A target with no `##` is internal and stays out of it.
help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "}; /^[a-zA-Z0-9_.-]+:.*## / {printf "%-16s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# The test runner tracks allocations per test but only warns about leaks and bad
# frees by default, which a passing build hides. Promote them to failures.
TEST_FLAGS := -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true $(COLL)

test: ## Run the full suite at both Term_ID widths
	@for width in $(WIDTHS); do \
		echo "== Term_ID $$width-bit =="; \
		for pkg in $(PKGS); do \
			echo "-- $$pkg --"; \
			odin test $$pkg $(TEST_FLAGS) \
				-define:RDF_STORE_TERM_ID_BITS=$$width || exit 1; \
		done; \
	done

# Vets every package including the ones the suite never instantiates.
#
# The `purity` target (grep a built binary for LMDB symbols) retired with
# SHACL-T-0032: it guarded the seam a second backend would bind to, and by
# owner decision there is no second backend and never will be —
# odin-rdf-record is the one and only store, and shacl imports it directly.
# With LMDB out of the link entirely the check was trivially true.
#
# bench/ is temporarily out of the vet loop while SHACL-T-0036 rebuilds it
# against the record store; the guard below comes back with it.
check: ## Vet every package at the default Term_ID width
	@for pkg in $(PKGS); do \
		echo "-- $$pkg --"; \
		odin check $$pkg -no-entry-point -vet -strict-style $(COLL) || exit 1; \
	done

# Benchmarks measure the validator, and a debug build measures the compiler
# instead, so they get the release flags.
#
# **Run at every Term_ID width, like the suite**, and for a reason beyond
# symmetry: the benchmark pins the number of store reads each configuration
# makes, and that number must be identical at 64- and 32-bit because ID width
# cannot reach the backend-independent core's control flow. Within one run the
# bench asserts the same pin across both *backends*; running the binary at each
# width is what asserts it across both widths. One integer, four ways -- and
# only this loop closes the second half.
bench: ## Build and run the benchmarks at both Term_ID widths, with release flags
	@test -d $(BENCH) || { echo "no $(BENCH)/ package yet"; exit 0; }; \
	mkdir -p build; \
	for width in $(WIDTHS); do \
		echo "== Term_ID $$width-bit =="; \
		odin run $(BENCH) -out:$(OUT) -o:speed -no-bounds-check $(COLL) \
			-define:RDF_STORE_TERM_ID_BITS=$$width || exit 1; \
	done

build-bench: ## Build the benchmark binary without running it
	@test -d $(BENCH) || { echo "no $(BENCH)/ package yet"; exit 0; }; \
	mkdir -p build && odin build $(BENCH) -out:$(OUT) -o:speed -no-bounds-check $(COLL)

clean: ## Remove build/
	rm -rf build
