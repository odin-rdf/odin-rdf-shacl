NAME  := shacl-bench
BENCH := bench
OUT   := build/$(NAME)

# Odin source collections. The parser and the store are sibling checkouts
# rather than vendored copies, so they are reached through collections instead
# of relative paths -- `import "rdf:rdf"` for the data model and `rdf:rdf/turtle`
# and friends for the four format packages, `import "store:store"` for the match
# interface with `store:store/memstore` and `store:store/kvstore` for the two
# backends. Both collections are required even where this project only names the
# store: the store's own sources import `rdf:`, and a collection is resolved in
# the importing compilation, not the imported checkout. The SHACL-SPARQL phase
# adds `-collection:sparql=../odin-rdf-sparql` here and in ols.json; Core needs
# no query engine, so it stays out until there is something importing it.
COLL := -collection:rdf=../odin-rdf-parser -collection:store=../odin-rdf-store

# Every package with tests, listed rather than discovered (SHACL-T-0001).
# `shacl` is the backend-independent core; the two instantiation packages bind
# it to a backend each and are peers, so each carries its own tests; guards
# holds the allocation assertions; readme compiles the README's examples so the
# documentation cannot drift from the API. SHACL-T-0002 adds tests/w3c/harness.
PKGS := shacl \
				shacl/memstore \
				shacl/kvstore \
				tests/guards \
				tests/readme

# Packages that are built rather than tested, and so are vetted separately.
BUILD_PKGS := tests/purity

# STORE-A-0001 makes the store's Term_ID width a build-time choice, and this
# project compiles the store's sources into its own binaries. Validation code
# must not assume 64-bit IDs, so the suite runs once per configuration rather
# than once. This is what CI should invoke -- `make test`, the whole matrix.
WIDTHS := 64 32

.PHONY: all help test check purity bench build-bench clean

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

# Vets every package including the ones the suite never instantiates, then runs
# the linkage property check -- a vet-clean tree that quietly links LMDB into
# the core would pass `check` without it.
check: ## Vet every package at the default Term_ID width, then check core purity
	@for pkg in $(PKGS); do \
		echo "-- $$pkg --"; \
		odin check $$pkg -no-entry-point -vet -strict-style $(COLL) || exit 1; \
	done
	@for pkg in $(BUILD_PKGS); do \
		echo "-- $$pkg --"; \
		odin check $$pkg -vet -strict-style $(COLL) || exit 1; \
	done
	@test -d $(BENCH) && odin check $(BENCH) -vet -strict-style $(COLL) || true
	@$(MAKE) --no-print-directory purity

# SHACL-A-0001's linkage property, asserted rather than trusted: a consumer of
# the SHACL core and the in-memory backend must not carry LMDB. The core is
# what protects this -- one convenience import of `store:store/kvstore` inside
# `shacl` would put a static archive into every consumer's link, including the
# ones that only ever want an in-memory store, and nothing else in the build
# would complain.
#
# `nm` is not available everywhere (notably on the Windows runner), so its
# absence skips the check with a message rather than failing the build. The
# property is platform-independent, so checking it on the platforms that can is
# enough.
purity: ## Assert the core links no LMDB (builds tests/purity and inspects it)
	@mkdir -p build
	@odin build tests/purity -out:build/purity $(COLL) || exit 1
	@if ! command -v nm >/dev/null 2>&1; then \
		echo "purity: nm unavailable, skipping symbol check"; \
		exit 0; \
	fi; \
	if nm build/purity 2>/dev/null | grep -qi 'mdb_'; then \
		echo "purity: FAIL -- LMDB symbols found in a core+memstore consumer."; \
		echo "         Something under package shacl imports store:store/kvstore."; \
		nm build/purity | grep -i 'mdb_' | head; \
		exit 1; \
	fi; \
	echo "purity: ok -- no LMDB symbols in a core+memstore consumer"

# Benchmarks measure the validator, and a debug build measures the compiler
# instead, so they get the release flags.
bench: ## Build and run the benchmarks with release flags
	@test -d $(BENCH) || { echo "no $(BENCH)/ package yet"; exit 0; }; \
	mkdir -p build && odin run $(BENCH) -out:$(OUT) -o:speed -no-bounds-check $(COLL)

build-bench: ## Build the benchmark binary without running it
	@test -d $(BENCH) || { echo "no $(BENCH)/ package yet"; exit 0; }; \
	mkdir -p build && odin build $(BENCH) -out:$(OUT) -o:speed -no-bounds-check $(COLL)

clean: ## Remove build/
	rm -rf build
