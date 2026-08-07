package shacl

// The SHACL vocabulary, as IRI string constants.
//
// These are spec facts rather than design decisions, which is why they can
// land before the shapes model does: every one is fixed by the SHACL
// recommendation and none of them commits this package to a representation.
// The set here is what the spine needs — shapes, targets, paths, the
// constraint components in SHACL-T-0007's minimal set, and the validation
// report vocabulary. The catalogue initiative extends it.
//
// odin-rdf-parser sets the precedent for keeping vocabulary constants beside
// the model that uses them rather than in a separate package.

// NS is the SHACL namespace. Every constant below is this plus a local name.
NS :: "http://www.w3.org/ns/shacl#"

// Shapes and their parts.
NODE_SHAPE :: NS + "NodeShape"
PROPERTY_SHAPE :: NS + "PropertyShape"
PROPERTY :: NS + "property"
PATH :: NS + "path"
DEACTIVATED :: NS + "deactivated"
MESSAGE :: NS + "message"
SEVERITY :: NS + "severity"

// Severity levels.
VIOLATION :: NS + "Violation"
WARNING :: NS + "Warning"
INFO :: NS + "Info"

// Target declarations (SHACL 1.0 §2.1.3).
TARGET_NODE :: NS + "targetNode"
TARGET_CLASS :: NS + "targetClass"
TARGET_SUBJECTS_OF :: NS + "targetSubjectsOf"
TARGET_OBJECTS_OF :: NS + "targetObjectsOf"

// Property paths (§2.3.1). Predicate paths are bare IRIs and have no
// constant of their own.
INVERSE_PATH :: NS + "inversePath"
ALTERNATIVE_PATH :: NS + "alternativePath"
ZERO_OR_MORE_PATH :: NS + "zeroOrMorePath"
ONE_OR_MORE_PATH :: NS + "oneOrMorePath"
ZERO_OR_ONE_PATH :: NS + "zeroOrOnePath"

// The constraint components the spine implements (SHACL-T-0007). The rest of
// the Core catalogue belongs to the second initiative.
MIN_COUNT :: NS + "minCount"
MAX_COUNT :: NS + "maxCount"
CLASS :: NS + "class"
DATATYPE :: NS + "datatype"
NODE_KIND :: NS + "nodeKind"

// Added after SHACL-T-0002 measured what core/targets and core/path actually
// exercise: both were listed as catalogue non-goals, and both are needed to
// green the spine's exit-criteria directories.
HAS_VALUE :: NS + "hasValue"
IN :: NS + "in"

// The value-range components (§4.6.2–4.6.5), SHACL-T-0013. Their parameter is a
// single term compared by **value** rather than by term, which is the whole
// reason SHACL-T-0012 came first.
MIN_INCLUSIVE :: NS + "minInclusive"
MAX_INCLUSIVE :: NS + "maxInclusive"
MIN_EXCLUSIVE :: NS + "minExclusive"
MAX_EXCLUSIVE :: NS + "maxExclusive"

// The string-based components (§4.5), SHACL-T-0014. `sh:flags` is the only
// parameter here with no component of its own: it modifies `sh:pattern`, and a
// result from the pair names `sh:PatternConstraintComponent`.
MIN_LENGTH :: NS + "minLength"
MAX_LENGTH :: NS + "maxLength"
PATTERN :: NS + "pattern"
FLAGS :: NS + "flags"
LANGUAGE_IN :: NS + "languageIn"
UNIQUE_LANG :: NS + "uniqueLang"

// The property-pair components (§4.7), SHACL-T-0015. Their parameter is a
// *predicate*, not a value: it names a second set of nodes at the same focus
// node, which is why these are the first components to read the data graph
// twice.
EQUALS :: NS + "equals"
DISJOINT :: NS + "disjoint"
LESS_THAN :: NS + "lessThan"
LESS_THAN_OR_EQUALS :: NS + "lessThanOrEquals"

// The shape-expecting parameters (§2.1.1). A node that is the value of one of
// these **is a shape**, which is why they land here in SHACL-T-0010 — before
// the constraint components that read them (SHACL-T-0017 and SHACL-T-0018).
// Discovery has to know them first: nothing nests until the values that nest
// are compiled as shapes.
//
// `sh:and`, `sh:or`, and `sh:xone` take an RDF list and the *members* are the
// shapes; the other three name a shape directly.
NODE :: NS + "node"
NOT :: NS + "not"
AND :: NS + "and"
OR :: NS + "or"
XONE :: NS + "xone"
QUALIFIED_VALUE_SHAPE :: NS + "qualifiedValueShape"

// The non-validating annotation properties (§2.3.2, §2.3.3). No conforming
// engine acts on these, so seeing one is not evidence of an unimplemented
// component — which is exactly why they are named rather than left to fall into
// the ignored-parameter record. `core/property` uses `sh:name`, so a record
// that flagged them would cry wolf on a directory that is already green.
//
// Keep this list short and spec-cited. Every SHACL revision adds annotations,
// and the failure mode of a too-generous list is silence about a component that
// really is missing.
NAME :: NS + "name"
DESCRIPTION :: NS + "description"
ORDER :: NS + "order"
GROUP :: NS + "group"
DEFAULT_VALUE :: NS + "defaultValue"

// Node kinds (§4.4.2).
IRI_KIND :: NS + "IRI"
BLANK_NODE_KIND :: NS + "BlankNode"
LITERAL_KIND :: NS + "Literal"
BLANK_NODE_OR_IRI :: NS + "BlankNodeOrIRI"
BLANK_NODE_OR_LITERAL :: NS + "BlankNodeOrLiteral"
IRI_OR_LITERAL :: NS + "IRIOrLiteral"

// The constraint components, as the IRIs a validation result names in
// sh:sourceConstraintComponent (§4). One per Constraint_Kind, and the
// catalogue initiative extends both together.
MIN_COUNT_COMPONENT :: NS + "MinCountConstraintComponent"
MAX_COUNT_COMPONENT :: NS + "MaxCountConstraintComponent"
CLASS_COMPONENT :: NS + "ClassConstraintComponent"
DATATYPE_COMPONENT :: NS + "DatatypeConstraintComponent"
NODE_KIND_COMPONENT :: NS + "NodeKindConstraintComponent"
HAS_VALUE_COMPONENT :: NS + "HasValueConstraintComponent"
IN_COMPONENT :: NS + "InConstraintComponent"
MIN_INCLUSIVE_COMPONENT :: NS + "MinInclusiveConstraintComponent"
MAX_INCLUSIVE_COMPONENT :: NS + "MaxInclusiveConstraintComponent"
MIN_EXCLUSIVE_COMPONENT :: NS + "MinExclusiveConstraintComponent"
MAX_EXCLUSIVE_COMPONENT :: NS + "MaxExclusiveConstraintComponent"
MIN_LENGTH_COMPONENT :: NS + "MinLengthConstraintComponent"
MAX_LENGTH_COMPONENT :: NS + "MaxLengthConstraintComponent"
PATTERN_COMPONENT :: NS + "PatternConstraintComponent"
LANGUAGE_IN_COMPONENT :: NS + "LanguageInConstraintComponent"
UNIQUE_LANG_COMPONENT :: NS + "UniqueLangConstraintComponent"
EQUALS_COMPONENT :: NS + "EqualsConstraintComponent"
DISJOINT_COMPONENT :: NS + "DisjointConstraintComponent"
LESS_THAN_COMPONENT :: NS + "LessThanConstraintComponent"
LESS_THAN_OR_EQUALS_COMPONENT :: NS + "LessThanOrEqualsConstraintComponent"

// The validation report vocabulary (§3).
VALIDATION_REPORT :: NS + "ValidationReport"
VALIDATION_RESULT :: NS + "ValidationResult"
CONFORMS :: NS + "conforms"
RESULT :: NS + "result"
FOCUS_NODE :: NS + "focusNode"
RESULT_PATH :: NS + "resultPath"
VALUE :: NS + "value"
RESULT_SEVERITY :: NS + "resultSeverity"
SOURCE_SHAPE :: NS + "sourceShape"
SOURCE_CONSTRAINT_COMPONENT :: NS + "sourceConstraintComponent"

// RESULT_MESSAGE is where a shape's `sh:message` lands in a result — the
// report vocabulary renames it, and getting that wrong is invisible until a
// suite entry with a message runs. `core/misc`'s `message-001` is that entry,
// and it says so in a comment: "this test verifies that the sh:message is
// copied into sh:resultMessage".
RESULT_MESSAGE :: NS + "resultMessage"
