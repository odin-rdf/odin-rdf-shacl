package shacl

import "core:strings"
import "core:testing"

// The vocabulary constants are spec facts, so the only thing worth asserting
// is that they are built from the namespace consistently — a typo in one
// local name would otherwise surface much later as a shape that silently
// fails to compile a parameter nobody spelled correctly.
@(test)
test_vocab_constants_share_the_namespace :: proc(t: ^testing.T) {
	all := []string {
		NODE_SHAPE,
		PROPERTY_SHAPE,
		PROPERTY,
		PATH,
		DEACTIVATED,
		MESSAGE,
		SEVERITY,
		VIOLATION,
		WARNING,
		INFO,
		TARGET_NODE,
		TARGET_CLASS,
		TARGET_SUBJECTS_OF,
		TARGET_OBJECTS_OF,
		INVERSE_PATH,
		ALTERNATIVE_PATH,
		ZERO_OR_MORE_PATH,
		ONE_OR_MORE_PATH,
		ZERO_OR_ONE_PATH,
		MIN_COUNT,
		MAX_COUNT,
		CLASS,
		DATATYPE,
		NODE_KIND,
		IRI_KIND,
		BLANK_NODE_KIND,
		LITERAL_KIND,
		BLANK_NODE_OR_IRI,
		BLANK_NODE_OR_LITERAL,
		IRI_OR_LITERAL,
		VALIDATION_REPORT,
		VALIDATION_RESULT,
		CONFORMS,
		RESULT,
		FOCUS_NODE,
		RESULT_PATH,
		VALUE,
		RESULT_SEVERITY,
		SOURCE_SHAPE,
		SOURCE_CONSTRAINT_COMPONENT,
	}

	for iri in all {
		testing.expectf(t, strings.has_prefix(iri, NS), "%q is not in the SHACL namespace", iri)
		local := iri[len(NS):]
		testing.expectf(t, local != "", "%q has an empty local name", iri)
	}

	// No duplicates: two constants resolving to the same IRI means one of
	// them is wrong, and a switch over them would have an unreachable arm.
	for iri, i in all {
		for other, j in all {
			if i < j {
				testing.expectf(t, iri != other, "duplicate vocabulary IRI %q", iri)
			}
		}
	}

	// Spot-check the exact spelling of the ones whose local name differs
	// from the constant name, which is where a rename would go wrong.
	testing.expect_value(t, TARGET_SUBJECTS_OF, "http://www.w3.org/ns/shacl#targetSubjectsOf")
	testing.expect_value(t, IRI_KIND, "http://www.w3.org/ns/shacl#IRI")
	testing.expect_value(t, SOURCE_CONSTRAINT_COMPONENT, "http://www.w3.org/ns/shacl#sourceConstraintComponent")
}
