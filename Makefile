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

# Odin source collections. The parser and the record store are sibling
# checkouts rather than vendored copies, so they are reached through
# collections instead of relative paths -- `import "rdf:rdf"` for the data
# model and `rdf:rdf/turtle` and friends for the four format packages;
# `import "record:record"` for the store and `record:record/ingest` for the
# document loaders. Both collections are required even where a package only
# names the record: record's own sources import `rdf:`, and a collection is
# resolved in the importing compilation, not the imported checkout.
#
# `store:` (odin-rdf-store) left this line with SHACL-T-0033, the last step of
# the SHACL-I-0004 port: odin-rdf-record is the one and only store, and no
# LMDB is in any link. The SHACL-SPARQL phase adds
# `-collection:sparql=../odin-rdf-sparql` here and in ols.json; Core needs no
# query engine, so it stays out until there is something importing it.
COLL := -collection:rdf=../odin-rdf-parser -collection:record=../odin-rdf-record

# Every package with tests, listed rather than discovered (SHACL-T-0001).
# `shacl` is the engine, one package over odin-rdf-record (SHACL-T-0032 --
# the instantiation split went with the backend seams); guards holds the
# allocation assertions; readme compiles the README's examples so the
# documentation cannot drift from the API; smoke opens a record store over
# the memory seam, the port's first proof; w3c/harness runs the vendored W3C
# SHACL suite (SHACL-T-0002) -- all 98 `core/` entries, no skip list.
PKGS := shacl \
				tests/guards \
				tests/readme \
				tests/smoke \
				tests/w3c/harness

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

# One run, not a width matrix. The `Term_ID` width loop (`WIDTHS := 64 32`)
# was odin-rdf-store's build-time choice compiled into this repository's
# binaries; the record store's id widths are fixed by design (its inline
# encoding is frozen at first write), so there is nothing to run twice.
test: ## Run the full suite
	@for pkg in $(PKGS); do \
		echo "-- $$pkg --"; \
		odin test $$pkg $(TEST_FLAGS) || exit 1; \
	done

# Vets every package including the ones the suite never instantiates.
#
# The `purity` target (grep a built binary for LMDB symbols) retired with
# SHACL-T-0032: it guarded the seam a second backend would bind to, and by
# owner decision there is no second backend and never will be --
# odin-rdf-record is the one and only store, and shacl imports it directly.
# With LMDB out of the link entirely the check was trivially true.
#
# bench/ is temporarily out of the vet loop while SHACL-T-0036 rebuilds it
# against the record store; the guard below comes back with it.
#
# The last step is a style rule the vet cannot express: Odin binds an import to
# the last component of its path, so `import rdf "rdf:rdf"` says nothing that
# `import "rdf:rdf"` does not, and a reader wonders what the alias is for. The
# family inherited the habit from its first repositories; it was swept out of
# this one after SHACL-T-0034 and the grep keeps it out. An alias that differs
# from the last component (`import rec "record:record"`) is not flagged -- that
# one is doing something.
check: ## Vet every package
	@for pkg in $(PKGS); do \
		echo "-- $$pkg --"; \
		odin check $$pkg -no-entry-point -vet -strict-style $(COLL) || exit 1; \
	done
	@echo "-- import aliases --"
	@if grep -rnE '^import ([A-Za-z_]+) "([^"]*[:/])?\1"' --include='*.odin' shacl tests; then \
		echo "error: redundant import alias -- Odin already binds the last path component"; exit 1; \
	fi

# Benchmarks measure the validator, and a debug build measures the compiler
# instead, so they get the release flags.
#
# **Unbuildable until SHACL-T-0036.** bench/ still binds odin-rdf-store and
# the `Access` seam the port collapsed (SHACL-I-0004 design par. 8), so it is
# rebuilt against the record store rather than patched -- read counting
# rehomed onto record's read API, baselines re-measured, the old numbers
# standing as the record. Until then the target says so instead of failing on
# a collection this repository no longer declares.
bench: ## Build and run the benchmarks with release flags (pending SHACL-T-0036)
	@echo "bench/ is being rebuilt against odin-rdf-record (SHACL-T-0036); it does not build until that lands"; exit 1

build-bench: ## Build the benchmark binary without running it (pending SHACL-T-0036)
	@echo "bench/ is being rebuilt against odin-rdf-record (SHACL-T-0036); it does not build until that lands"; exit 1

clean: ## Remove build/
	rm -rf build
