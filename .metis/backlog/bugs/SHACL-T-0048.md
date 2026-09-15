---
id: sh-pattern-a-bare-is-a-comment-to
level: task
title: "sh:pattern: a bare # is a comment to core:text/regex, so a pattern containing one admits every string"
short_code: "SHACL-T-0048"
created_at: 2026-09-15T20:00:16.196447+00:00
updated_at: 2026-09-15T20:00:16.196447+00:00
parent: 
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/backlog"
  - "#bug"


exit_criteria_met: false
initiative_id: NULL
---

# sh:pattern: a bare # is a comment to core:text/regex, so a pattern containing one admits every string

## Objective

Make `sh:pattern` either match a literal `#` as XPath's `fn:matches` does, or
refuse a pattern it would silently change as `Pattern_Ill_Formed`. Today the
pattern is compiled into something weaker and validates as conforming.

## Backlog Item Details

### Type
- [x] Bug - Production issue that needs fixing

### Priority
- [x] P2 - Medium (nice to have)

### Impact Assessment
- **Affected Users**: any consumer whose shapes graph has a `#` in an
  `sh:pattern` outside a group or class. Found by `odin-rdf-app`, whose shape
  for a `#RRGGBB` colour admitted `"amber"`.
- **Reproduction Steps**:
  1. A property shape with `sh:pattern "^#[0-9A-Fa-f]{6}$"`.
  2. Validate a focus node whose value is `"amber"`.
  3. The report conforms.
- **Expected vs Actual**: `fn:matches` treats `#` as an ordinary character
  (XPath has no comment syntax without the `x` flag, and even with it `#` is
  not a comment), so `"amber"` violates. `core:text/regex`'s tokenizer
  (`tokenizer.odin`, the `t.ch == '#' && t.paren_depth == 0` branch) starts a
  comment on a bare `#` **whether or not `.Ignore_Whitespace` is set**, so the
  pattern compiles to `^` and every string matches.

Evidence, from `regex.create` then `regex.match` against the Odin toolchain
the family builds with:

```
^#[0-9A-Fa-f]{6}$    amber true    #F9A82 true    x#F9A825y true
^[#][0-9A-Fa-f]{6}$  amber false   #F9A825 true   #F9A82 false
^\#[0-9A-Fa-f]{6}$   amber false   #F9A825 true
^a#b$                amber true    a#b true
```

## Acceptance Criteria

- [ ] A `node/pattern` style test: `sh:pattern "^#[0-9]$"` rejects `"x"` and
      accepts `"#1"`.
- [ ] The fix is one of these: escape a bare `#` (outside a class) before
      `regex.create`, the same kind of dialect translation `regex_flags`
      already does; or refuse it with `Pattern_Ill_Formed`, per this package's
      rule that refusing beats ignoring.
- [ ] `shacl.odin`'s account of the dialect divergence names `#`.
- [ ] Consider reporting the tokenizer behaviour to Odin core, since a comment
      without the `x` flag is surprising in any caller.

## Status Updates

- Filed from a consumer's test. The consumer works around it with `[#]`.
