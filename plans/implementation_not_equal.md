# Bug Fix: `!=` Operator

## Root Cause Analysis

The `!=` (not-equal) operator fails to compile due to **two independent issues** in different stages of the compiler pipeline.

### Issue 1 (Primary): Token misclassification in `reclassify_tokens()`

**File**: `scenes/md_tokenizer.gd`, line 8 — `assign_ops` constant

The tokenizer pipeline for `!=` works correctly through most stages:

1. **`basic_tokenize()`**: The word-boundary tokenizer classifies both `!` and `=` as `PUNCT` (since `get_all_punct()` in `lang_md.gd` adds all ops characters including `!` and `=` to the punctuation character set). ✅

2. **`recombine_tokens()`**: The `recombinations` array includes `["!", "="]`, so adjacent `!` and `=` tokens are correctly merged into a single token with `text = "!="` and `tok_class = "PUNCT"`. ✅

3. **`reclassify_tokens()` (line 173)** ❌ — This is where the bug lives:
   ```gdscript
   elif tok.tok_class == "PUNCT":
       if tok.text in lang.ops and tok.text not in assign_ops:
           tok.tok_class = "OP";
   ```

   The condition checks: is this PUNCT token in `lang.ops` AND NOT in `assign_ops`? If so, reclassify to `OP`.

   The `assign_ops` constant at line 8 is:
   ```gdscript
   const assign_ops = ["=", "+=", "-=", "*=", "/=", "%=","!="];
   ```

   Since `"!="` IS in `assign_ops`, the condition `tok.text not in assign_ops` evaluates to `false`, so the token **stays as `PUNCT`** instead of being reclassified to `OP`. ❌

4. **Impact on parser**: The parser's infix rule in `lang_md.gd` (line 99):
   ```gdscript
   ["expr", "OP", "expr", "*", "expr_infix"],
   ```
   
   This rule expects the operator to have class `OP`. Since `!=` is still `PUNCT`, this rule never matches. The parser either produces a wrong parse tree or errors out.

**Why was `!=` in `assign_ops`?** — Likely someone grouped it there by mistake because `!=` contains a `=` sign, assuming it was an "assignment-like" operator. But `!=` is a comparison operator, not an assignment operator.

---

### Issue 2 (Secondary): Missing codegen entry for `NOT_EQUAL`

**File**: `scenes/codegen_md.gd`, lines 12-24 — `op_map` constant

The codegen's `op_map` defines how IR operators map to assembly instructions:
```gdscript
const op_map = {
    "ADD": "add %a, %b;\n",
    "SUB": "sub %a, %b;\n",
    ...
    "EQUAL": "cmp %a, %b; mov %a, CTRL; band %a, CMP_Z; bnot %a; bnot %a;\n",
    # NOT_EQUAL is MISSING!
};
```

Even if Issue 1 is fixed and the token flows correctly through the pipeline, the analyzer would emit:
```
IR: ["OP", "NOT_EQUAL", arg1, arg2, res]
```

But the codegen at line 293 would hit:
```gdscript
if op not in op_map: push_error("codegen: can't generate op ["+op+"]"); return;
```

There is no `NOT_EQUAL` entry, so compilation would fail at the codegen stage.

**What parts already work correctly (no changes needed):**

| File | Why it's fine |
|------|---------------|
| `scenes/lang_md.gd` (line 12) | `!=` is already in the `ops` list |
| `scenes/lang_md.gd` (line 99) | Parser rule `["expr", "OP", "expr", "*", "expr_infix"]` will match once token is correctly classed as `OP` |
| `scenes/parser_md.gd` (line 111-116) | `token_match()` correctly handles class-based matching (`ref == tok.tok_class`) |
| `scenes/analyzer_md.gd` (line 28) | `op_map` already maps `"!="` → `"NOT_EQUAL"` |
| `scenes/analyzer_md.gd` (line 177-188) | `analyze_expr_infix()` already handles arbitrary ops via `op_map` |

---

## Changes Required

### Change 1: [`scenes/md_tokenizer.gd`](scenes/md_tokenizer.gd) — Remove `!=` from `assign_ops`

**Line**: 8

**Before**:
```gdscript
const assign_ops = ["=", "+=", "-=", "*=", "/=", "%=","!="];
```

**After**:
```gdscript
const assign_ops = ["=", "+=", "-=", "*=", "/=", "%="];
```

**Effect**: When `reclassify_tokens()` processes the recombined `!=` token (class `PUNCT`), it will check:
- `tok.text in lang.ops` → `true` (`!=` is in the ops list)
- `tok.text not in assign_ops` → `true` (removed from assign_ops)
- Result: token is reclassified to `OP` ✅

### Change 2: [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — Add `NOT_EQUAL` to `op_map`

**Lines**: 12-24 (within the `op_map` constant)

Add a new entry after `EQUAL`:

```gdscript
"NOT_EQUAL":"cmp %a, %b; mov %a, CTRL; band %a, CMP_Z; bnot %a;\n",
```

**Rationale**: The existing `EQUAL` implementation extracts the `CMP_Z` flag (set when values are equal) via `band %a, CMP_Z`. The double `bnot %a; bnot %a` in `EQUAL` is a no-op that the original author likely used for boolean normalization (turning any non-zero into 1, zero into 0). However, `bnot` on a bitmask already produces 0 or 1 since `CMP_Z` is a single bit.

For `NOT_EQUAL`, we simply invert the `CMP_Z` bit once with `bnot`:
- When values are NOT equal: `CMP_Z = 0` → `bnot` → `1` (true)
- When values ARE equal: `CMP_Z = 1` → `bnot` → `0` (false)

---

## Pipeline Flow After Fix

```
Source: if (x != y) { ... }
  ↓ basic_tokenize():      [PUNCT:!] [PUNCT:=]
  ↓ recombine_tokens():    → [PUNCT:!=]
  ↓ reclassify_tokens():   → [OP:!=]           ← Fix 1: != removed from assign_ops
  ↓ Parser:                → expr_infix        ← matches ["expr", "OP", "expr", ...]
  ↓ Analyzer:              → IR: ["OP", "NOT_EQUAL", ...]  ← already correct
  ↓ Codegen:               → assembly          ← Fix 2: NOT_EQUAL added to op_map
```

---

## Test Cases

### Test 1: Basic `!=` (true case)
```
func main():
    var x = 5;
    var y = 3;
    if x != y:
        print(1);
    else:
        print(0);
```
Expected output: `1`

### Test 2: `!=` returning false
```
func main():
    var x = 5;
    var y = 5;
    if x != y:
        print(1);
    else:
        print(0);
```
Expected output: `0`

### Test 3: `!=` in while loop
```
func main():
    var x = 0;
    while x != 3:
        print(x);
        x += 1;
```
Expected output: `0` `1` `2`

### Test 4: Combined `==` and `!=`
```
func main():
    var a = 10;
    var b = 20;
    var c = 10;
    if a == c && a != b:
        print(1);
    else:
        print(0);
```
Expected output: `1`

---

## Implementation Order

1. **Token fix** ([`scenes/md_tokenizer.gd`](scenes/md_tokenizer.gd)): Remove `"!="` from `assign_ops` (one character deletion)
2. **Codegen fix** ([`scenes/codegen_md.gd`](scenes/codegen_md.gd)): Add `"NOT_EQUAL"` entry to `op_map` (one line addition)
3. **Test**: Compile and run test cases
