package shacl_kvstore

import "core:fmt"
import "core:os"
import "core:sync"
import "core:testing"

import kvstore "store:store/kvstore"

// temp_path joins the OS temp directory with a run-unique name.
//
// **Two tests use this, and everything else in the suite opens an ephemeral
// store instead** (odin-rdf-store v0.3.0, `kvstore.open_ephemeral` — no path to
// name, make unique, or clean up, and a 16 MiB map rather than 1 GiB). What is
// left here are the two cases that genuinely need a path on disk: the linkage
// proof below, which is worth running against the constructor a consumer
// actually uses, and `test_kvstore_compilation_does_not_write`, which closes a
// store and reopens the same path read-only.
//
// The separator is added here rather than assumed, and the fallback order
// matters: macOS exports TMPDIR with a trailing slash, Linux usually exports
// nothing at all, and Windows names the variable TEMP or TMP and has no /tmp
// to fall back to. Concatenating straight onto the variable yields a path at
// the filesystem root on Linux, which a non-root user cannot create. Copied
// deliberately from odin-rdf-store's own test helper, which is private to
// that package.
//
// The counter is what makes two concurrent stores distinct, and it stays even
// at two callers: the runner is threaded, and a name-only path would also
// inherit a stale directory from a previous run.
@(private)
path_counter: u64

@(private)
temp_path :: proc(name: string) -> string {
	tmp := os.get_env("TMPDIR", context.temp_allocator)
	if tmp == "" {
		tmp = os.get_env("TEMP", context.temp_allocator)
	}
	if tmp == "" {
		tmp = os.get_env("TMP", context.temp_allocator)
	}
	if tmp == "" {
		tmp = "/tmp"
	}
	if tmp[len(tmp) - 1] == '/' || tmp[len(tmp) - 1] == '\\' {
		tmp = tmp[:len(tmp) - 1]
	}
	n := sync.atomic_add(&path_counter, 1)
	return fmt.aprintf("%s/odin-rdf-shacl-%s-%d-%d", tmp, name, os.get_pid(), n)
}

@(private)
remove_store :: proc(path: string) {
	os.remove(fmt.tprintf("%s/data.mdb", path))
	os.remove(fmt.tprintf("%s/lock.mdb", path))
	os.remove(path)
	delete(path)
}

// The LMDB linkage proof.
//
// This package is the only one in the repo that pulls in the vendored LMDB
// archive, and it is the reason CI carries odin-rdf-store's platform matrix
// from the first commit rather than "once a backend is actually linked". A
// package that merely imports kvstore would compile without ever proving the
// foreign archive resolves and runs, so this opens a real store, reads
// through it, and closes it.
//
// **A real one, on a real path, deliberately.** The rest of the suite moved to
// open_ephemeral, which opens with NOSUBDIR | NOLOCK | NOSYNC — a different
// flag set, no lock file, and on POSIX an unlinked inode. That is the right
// default for a test, but it is not the configuration a consumer runs, and
// proving the archive works is exactly the claim that should be made against
// the configuration a consumer runs.
//
// It is a scaffolding test (SHACL-T-0001), not a validation test: it asserts
// the link, not any SHACL behaviour. It stays after SHACL-T-0003 fills this
// package, because what it guards — that the archive is present and working
// on this platform at this Term_ID width — is not something the validation
// tests would report clearly if it broke.
@(test)
test_lmdb_links_and_runs :: proc(t: ^testing.T) {
	path := temp_path("link")
	defer remove_store(path)

	s, err := kvstore.open(path)
	if !testing.expectf(t, err == nil, "kvstore.open failed: %v", err) {
		return
	}
	defer kvstore.close(s)

	n, count_err := kvstore.count(s)
	testing.expectf(t, count_err == nil, "kvstore.count failed: %v", count_err)
	testing.expect_value(t, n, 0)
}
