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
