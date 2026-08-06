// Graph comparison for the SHACL suite: triple multisets equal up to a
// blank-node bijection.
//
// Ported from odin-rdf-parser's `tests/w3c/harness/compare.odin`, which has
// carried it across 1045 conformance tests. It is copied rather than imported
// for two reasons. That package is a *test* package with no stability
// contract — importing another repository's tests couples this repo's CI to a
// refactor nobody would think to coordinate — and a test build that imported
// it would drag the parser's own 1045-test harness into this binary, because
// `_test.odin` files come along in a test compilation. The same judgement
// odin-rdf-sparql made about the family's Error type, for the same reason.
//
// Two deliberate changes from the original: it operates on rdf.Triple rather
// than rdf.Quad, because a validation report is a graph and there is no graph
// position to bind; and the entry point is named report_isomorphic, because
// that is the only thing this repo compares.
//
// The algorithm is backtracking over triples grouped by a blank-node-masked
// skeleton key. Ground triples have unique skeletons, so only genuinely
// ambiguous blank-node triples ever branch — and SHACL reports are small,
// blank-node-heavy, and nested (`sh:resultPath [ sh:inversePath ex:child ]`),
// which is exactly the shape a first-occurrence label mapping gets wrong.
package w3c

import "core:strings"

import rdf "rdf:rdf"

// report_isomorphic reports whether the two triple lists denote the same
// graph up to a blank-node bijection. RDF graphs are SETS: exact duplicate
// triples collapse before comparison.
report_isomorphic :: proc(all_as, all_bs: []rdf.Triple) -> bool {
	as_list := dedupe(all_as)
	bs_list := dedupe(all_bs)
	defer delete(as_list)
	defer delete(bs_list)
	as, bs := as_list[:], bs_list[:]

	if len(as) != len(bs) {
		return false
	}
	if len(as) == 0 {
		return true
	}

	groups: map[string][dynamic]int
	defer {
		for key, idxs in groups {
			delete(key)
			delete(idxs)
		}
		delete(groups)
	}
	for t, j in bs {
		key := skeleton(t)
		if idxs, found := &groups[key]; found {
			append(idxs, j)
			delete(key)
		} else {
			lst: [dynamic]int
			append(&lst, j)
			groups[key] = lst
		}
	}

	used := make([]bool, len(bs))
	defer delete(used)
	fwd: map[string]string
	bwd: map[string]string
	trail: [dynamic]string
	defer delete(fwd)
	defer delete(bwd)
	defer delete(trail)

	return match_from(0, as, bs, &groups, used, &fwd, &bwd, &trail)
}

// dedupe drops triples whose exact serialization (labels included) was
// already seen.
@(private = "file")
dedupe :: proc(ts: []rdf.Triple) -> [dynamic]rdf.Triple {
	seen: map[string]bool
	defer {
		for key in seen {
			delete(key)
		}
		delete(seen)
	}
	out: [dynamic]rdf.Triple
	for t in ts {
		key := exact_key(t)
		if seen[key] {
			delete(key)
			continue
		}
		seen[key] = true
		append(&out, t)
	}
	return out
}

@(private = "file")
match_from :: proc(
	i: int,
	as, bs: []rdf.Triple,
	groups: ^map[string][dynamic]int,
	used: []bool,
	fwd, bwd: ^map[string]string,
	trail: ^[dynamic]string,
) -> bool {
	if i == len(as) {
		return true
	}
	key := skeleton(as[i])
	defer delete(key)
	idxs, found := groups[key]
	if !found {
		return false
	}
	for j in idxs {
		if used[j] {
			continue
		}
		mark := len(trail)
		if triple_match(as[i], bs[j], fwd, bwd, trail) {
			used[j] = true
			if match_from(i + 1, as, bs, groups, used, fwd, bwd, trail) {
				return true
			}
			used[j] = false
		}
		unwind(fwd, bwd, trail, mark)
	}
	return false
}

@(private = "file")
unwind :: proc(fwd, bwd: ^map[string]string, trail: ^[dynamic]string, mark: int) {
	for k in trail[mark:] {
		mapped := fwd[k]
		delete_key(fwd, k)
		delete_key(bwd, mapped)
	}
	resize(trail, mark)
}

@(private = "file")
triple_match :: proc(a, b: rdf.Triple, fwd, bwd: ^map[string]string, trail: ^[dynamic]string) -> bool {
	if !term_match(a.subject, b.subject, fwd, bwd, trail) {
		return false
	}
	if !term_match(a.predicate, b.predicate, fwd, bwd, trail) {
		return false
	}
	return term_match(a.object, b.object, fwd, bwd, trail)
}

@(private = "file")
term_match :: proc(a, b: rdf.Term, fwd, bwd: ^map[string]string, trail: ^[dynamic]string) -> bool {
	#partial switch va in a {
	case rdf.Blank_Node:
		vb, is_blank := b.(rdf.Blank_Node)
		return is_blank && blank_match(va, vb, fwd, bwd, trail)
	case ^rdf.Triple:
		vb, is_tt := b.(^rdf.Triple)
		if !is_tt {
			return false
		}
		return(
			term_match(va.subject, vb.subject, fwd, bwd, trail) &&
			term_match(va.predicate, vb.predicate, fwd, bwd, trail) &&
			term_match(va.object, vb.object, fwd, bwd, trail) \
		)
	}
	return rdf.equal_term(a, b)
}

@(private = "file")
blank_match :: proc(a, b: rdf.Blank_Node, fwd, bwd: ^map[string]string, trail: ^[dynamic]string) -> bool {
	la, lb := string(a), string(b)
	if mapped, has := fwd[la]; has {
		return mapped == lb
	}
	if _, taken := bwd[lb]; taken {
		return false
	}
	fwd[la] = lb
	bwd[lb] = la
	append(trail, la)
	return true
}

// skeleton is a structural key with blank nodes masked; triples can only
// match if their skeletons are equal (collisions merely widen the candidate
// set — triple_match re-verifies everything). exact_key keeps the labels, for
// set-dedupe.
@(private = "file")
skeleton :: proc(t: rdf.Triple) -> string {
	return serialize(t, false)
}

@(private = "file")
exact_key :: proc(t: rdf.Triple) -> string {
	return serialize(t, true)
}

@(private = "file")
serialize :: proc(t: rdf.Triple, with_labels: bool) -> string {
	sb := strings.builder_make()
	serialize_term(&sb, t.subject, with_labels)
	strings.write_byte(&sb, 0x1F)
	serialize_term(&sb, t.predicate, with_labels)
	strings.write_byte(&sb, 0x1F)
	serialize_term(&sb, t.object, with_labels)
	return strings.to_string(sb)
}

@(private = "file")
serialize_term :: proc(sb: ^strings.Builder, term: rdf.Term, with_labels: bool) {
	switch v in term {
	case rdf.IRI:
		strings.write_byte(sb, 'I')
		strings.write_string(sb, string(v))
	case rdf.Blank_Node:
		strings.write_byte(sb, '*')
		if with_labels {
			strings.write_string(sb, string(v))
		}
	case rdf.Literal:
		strings.write_byte(sb, 'L')
		strings.write_string(sb, v.lexical)
		strings.write_byte(sb, 0x1E)
		strings.write_string(sb, string(v.datatype))
		strings.write_byte(sb, 0x1E)
		strings.write_string(sb, v.language)
		strings.write_byte(sb, byte(v.direction))
	case ^rdf.Triple:
		strings.write_byte(sb, '(')
		serialize_term(sb, v.subject, with_labels)
		strings.write_byte(sb, 0x1E)
		serialize_term(sb, v.predicate, with_labels)
		strings.write_byte(sb, 0x1E)
		serialize_term(sb, v.object, with_labels)
		strings.write_byte(sb, ')')
	}
}
