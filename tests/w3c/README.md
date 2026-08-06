# W3C SHACL test suite

Reserved for **SHACL-T-0002**, which vendors the official W3C SHACL test suite
here and builds the manifest-driven harness that runs it.

Nothing lives here yet. When it does, this file is replaced by the provenance
record the family requires — upstream repository, pinned commit, retrieval
date, license, a local-directory-to-upstream-path table, and the explicit list
of what was excluded and why — in the shape odin-rdf-parser's
`tests/w3c/README.md` established.

Two things about this suite differ from the sibling projects', and both are
SHACL-T-0002's to resolve:

- It comes from a **different upstream repository** (`w3c/data-shapes`) than
  the `w3c/rdf-tests` commit odin-rdf-parser and odin-rdf-sparql share, so it
  carries its own pin.
- Every entry is *data graph + shapes graph → validation report*, so the
  harness needs **blank-node isomorphism** on report graphs from the outset
  rather than the string or result-set comparison the query suites use.
