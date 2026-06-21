# Bug Fix: `x[I] == y[I]` parses as `(x[I] == y)[I]` — broken operator precedence

## Overview

When parsing `x[I] == y[I]`, the MiniDerp LR(1) parser incorrectly produces `(x[I] == y)[I]` instead of `(x[I]) == (y[I])`. Array indexing `[...]` should bind tighter than comparison `==`, but the grammar encodes both at the same level and the infix rule matches too eagerly.

## Root Cause

The issue is in [`scenes/lang_md.gd`](scenes/lang_md.gd), lines 99-100:

```gdscript
["expr", "OP", "expr", "*", "expr_infix"],       # line 99: infix binary ops (+, ==, etc.)
["expr", "/[", "expr", "/]", "*", "expr_infix"],  # line 100: array indexing
```

Both rules produce `expr_infix` and both use `*` (wildcard) as lookahead. The critical problem is at **line 99**: when the parser stack is `[expr(x[I]), OP(==), expr(y)]` and the lookahead is `[`, the `*` wildcard matches everything, so rule 99 triggers a reduction **before** the `[` of `y[I]` gets shifted onto the stack.

### Step-by-step trace for `x[I] == y[I]`

| Step | Stack | Lookahead | Action |
|------|-------|-----------|--------|
| 1 | `[expr(x), /[, expr(I), /]]` | `==` | Reduce `x[I]` → `expr_infix` → `expr` |
| 2 | `[expr(x[I]), OP(==), IDENT(y)]` | `[` | Reduce `y` → `expr_ident` → `expr` |
| 3 | `[expr(x[I]), OP(==), expr(y)]` | `[` | **BUG: rule 99 matches** (lookahead `*` matches `[`) → reduce to `(x[I] == y)` |
| 4 | `[expr(x[I]==y), /[, expr(I), /]]` | `;` | Reduce to `(x[I]==y)[I]` ❌ |

The correct behavior at step 3 is to **NOT reduce** — instead, shift the `[` so that `y[I]` is formed first, then compare.

## Proposed Fix: SHIFT-guard rules

Insert 2 SHIFT-guard rules **before** rule 99 in [`scenes/lang_md.gd`](scenes/lang_md.gd):

```gdscript
# -- expr_infix
["expr", "OP", "expr", "/[", "SHIFT"],    # NEW: don't reduce infix when [ follows
["expr", "OP", "expr", "/(", "SHIFT"],    # NEW: don't reduce infix when ( follows
["expr", "OP", "expr", "*", "expr_infix"],
["expr", "/[", "expr", "/]", "*", "expr_infix"],
```

### How it works

The parser checks rules **in order** and applies the **first match**. With the SHIFT-guard rules inserted before rule 99:

1. Stack `[expr, OP, expr]` + lookahead `[/]` → SHIFT-guard matches → shift `[` (don't reduce)
2. Stack `[expr, OP, expr]` + lookahead `/(` → SHIFT-guard matches → shift `(` (don't reduce)
3. Stack `[expr, OP, expr]` + any other lookahead → reduce to `expr_infix` (normal behavior)

The `SHIFT` keyword is already supported by the parser at [`scenes/parser_md.gd`](scenes/parser_md.gd):59:

```gdscript
if rule[-1] == "SHIFT": break; #(with stabilized == true)
```

When a SHIFT rule matches, the parser breaks out with `stabilized = true`, meaning the lookahead token gets shifted without any reduction — exactly the behavior we want.

### Trace with the fix applied

**`x[I] == y[I]` now parses correctly:**

| Step | Stack | Lookahead | Action |
|------|-------|-----------|--------|
| 1 | `[expr(x), /[, expr(I), /]]` | `==` | Reduce `x[I]` |
| 2 | `[expr(x[I]), OP(==), expr(y)]` | `[` | **SHIFT-guard** → shift `[` |
| 3 | `[expr(x[I]), OP(==), expr(y), /[, expr(I), /]]` | `;` | Reduce `y[I]` |
| 4 | `[expr(x[I]), OP(==), expr(y[I])]` | `;` | Reduce `x[I] == y[I]` ✓ |

**`x == f(y)` now parses correctly:**

| Step | Stack | Lookahead | Action |
|------|-------|-----------|--------|
| 1 | `[expr(x), OP(==), expr(f)]` | `(` | **SHIFT-guard** → shift `(` |
| 2 | `[expr(x), OP(==), expr(f), /(, expr(y), /)]` | `;` | Reduce `f(y)` |
| 3 | `[expr(x), OP(==), expr(f(y))]` | `;` | Reduce `x == f(y)` ✓ |

## Files Modified

**Only one file** — [`scenes/lang_md.gd`](scenes/lang_md.gd), lines 98-100.

Add 2 lines before the existing rule 99. No changes to parser, analyzer, codegen, or tokenizer.

## Why no analyzer changes?

The [`analyze_expr_infix`](scenes/analyzer_md.gd:177) function already handles both `==` and `[` through the same path — it reads `ast.children[0]` as expr1, `ast.children[1]` as the operator token, and `ast.children[2]` as expr2. The `op_map` maps both `==` to `EQUAL` and `[` to `INDEX`. The AST structure for `x[I]` remains `expr_infix(expr(x), OP([), expr(I))` — identical structure before and after the fix. Only the nesting of expressions changes.

## Side Effects Analysis

### 1. Chained comparisons (`a == b == c`)
- Stack `[expr(a), OP(==), expr(b)]` + lookahead `==` → not `/[//(` → normal reduce → `(a == b) == c` ✓

### 2. Mixed operators (`a + b[I]`)
- Stack `[expr(a), OP(+), expr(b)]` + lookahead `[` → SHIFT-guard → shift `[`
- Parse `I`, shift `]`, reduce `b[I]`
- Result: `a + (b[I])` ✓

### 3. Multiple indices (`a[I][J]`)
- After `a[I]`, stack `[expr(a[I])]` + lookahead `[` → shift `[`
- Parse `J`, shift `]`, reduce → `(a[I])[J]` ✓

### 4. Parenthesized comparison with index (`(x == y)[I]`)
- `(` triggers `expr_parenthesis` rule (not affected)
- After `(x == y)`, stack `[expr(x==y)]` + lookahead `[` → shift, parse → `(x==y)[I]` ✓

### 5. Infix inside index (`x[I + 1]`)
- After `x[`, stack `[expr(x), /[, expr(I), OP(+), expr(1)]` + lookahead `]`
- Rule 99 matches (not blocked since `]` is `/[/(`) → reduce `I + 1`
- Result: `x[I+1]` ✓

## Test Cases

### Test 1: Basic array comparison
```miniderp
func main():
    var x = "hello";
    var y = "hello";
    var I = 0;
    if x[I] == y[I]:
        print(1);
    else:
        print(0);
```
Expected: `1` (both index to `'h'`)

### Test 2: Array comparison returning false
```miniderp
func main():
    var x = "hello";
    var y = "world";
    var I = 0;
    if x[I] == y[I]:
        print(1);
    else:
        print(0);
```
Expected: `0` (`'h'` != `'w'`)

### Test 3: Comparison with function call
```miniderp
func get_zero():
    return 0;

func main():
    if get_zero() == 0:
        print(1);
```
Expected: `1`

### Test 4: `!=` with array index
```miniderp
func main():
    var x = "test";
    var I = 0;
    var J = 1;
    if x[I] != x[J]:
        print(1);
```
Expected: `1` (`'t'` != `'e'`)

### Test 5: Regression — existing `test_arr_if.md`
The file [`res/data/test_arr_if.md`](res/data/test_arr_if.md) contains `if(x[I] == y[I])` at line 10. It should now parse and execute correctly.

### Test 6: Infix on right side only
```miniderp
func main():
    var arr = "hello";
    var I = 0;
    if 104 == arr[I]:
        print(1);
```
Expected: `1` (104 is ASCII `'h'`, arr[0] is `'h'`)

## Implementation Order

1. **Grammar fix** ([`scenes/lang_md.gd`](scenes/lang_md.gd)): Add 2 SHIFT-guard rules before rule 99
2. **Test**: Compile and run `test_arr_if.md` — verify it works
3. **Regression test**: Run existing test programs to ensure nothing broke
4. **Document**: Mark the bug as fixed in [`docs/todo.md`](docs/todo.md)
