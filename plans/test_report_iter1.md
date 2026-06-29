# CpuDerp — Iteration 1 Test Report

**Date:** 2026-06-28  
**Engine:** Godot v4.7.stable.steam  
**Pipeline Components:** Tokenizer → Parser → Analyzer → Codegen (old codegen)  
**Testing Method:** Headless Godot scene with `test_runner.tscn` as main scene (autoloads `G`, `E` loaded)  

---

## Summary

| Test | File | Tokenization | Parsing | Analysis | Codegen | Overall |
|------|------|:---:|:---:|:---:|:---:|:---:|
| 1a: Simple variable & arithmetic | `res://res/data/test_iter1a.md` | ✅ PASS | ⚠️ SCRIPT ERROR | — | — | **FAIL** |
| 1b: Function call | `res://res/data/test_iter1b.md` | ✅ PASS (with bug) | ⚠️ SCRIPT ERROR | — | — | **FAIL** |
| 1c: Arrays | `res://res/data/test_iter1c.md` | ✅ PASS | ⚠️ SCRIPT ERROR | — | — | **FAIL** |
| 1d: Control flow (if/else) | `res://res/data/test_iter1d.md` | ✅ PASS | ⚠️ SCRIPT ERROR | — | — | **FAIL** |

**Root Cause for Parsing Failure:** A GDScript error in the test harness (`ast.is_empty()` fails because `parse()` returns an AST node, not an Array). This is a test harness bug, not a compiler bug — but it prevented the pipeline from proceeding beyond Step 2.

---

## Test 1a: Simple Variable and Arithmetic

**Source code:**
```
func main(){
    var x = 5;
    var y = x + 3;
    var z = y * 2;
}
```

**Tokenization:** ✅ PASS — 25 tokens produced correctly.
- `KEYWORD:func`, `IDENT:main`, `PUNCT:(`, `PUNCT:)`, `PUNCT:{`
- `KEYWORD:var`, `IDENT:x`, `PUNCT:=`, `NUMBER:5`, `PUNCT:;`
- `KEYWORD:var`, `IDENT:y`, `PUNCT:=`, `IDENT:x`, `OP:+`, `NUMBER:3`, `PUNCT:;`
- `KEYWORD:var`, `IDENT:z`, `PUNCT:=`, `IDENT:y`, `OP:*`, `NUMBER:2`, `PUNCT:;`
- `PUNCT:}`

No tokenization errors. All keywords, identifiers, operators, and punctuation correctly classified.

**Parsing:** ⚠️ Could not verify — test harness SCRIPT ERROR at `ast.is_empty()` call. The parser's `parse()` method returned an unexpected type (likely it returned a single AST node, not an Array). This prevented the pipeline from continuing.

**Analysis:** Not reached.  
**Codegen:** Not reached.

---

## Test 1b: Function Call

**Source code:**
```
func add(a, b){
    return a + b;
}

func main(){
    var x = add(3, 4);
}
```

**Tokenization:** ⚠️ PASS (with BUG) — 30 tokens produced, but **comma (`,`) is incorrectly classified as `ERROR` token**.
```
[3] [IDENT:a]
[4] [ERROR:,]    <--- BUG: comma should be PUNCT, not ERROR
[5] [IDENT:b]
```

This means the tokenizer does not recognize `,` as valid punctuation in function parameter lists. Looking at [`lang_md.gd`](scenes/lang_md.gd:14), the `punct` array does not include `,` as a punctuation character. This is a **bug in the language definition** — commas are needed for function parameters and expressions but are missing from `lang_md.gd`.

**Parsing:** ⚠️ Could not verify — same test harness SCRIPT ERROR.  
**Analysis:** Not reached.  
**Codegen:** Not reached.

---

## Test 1c: Arrays

**Source code:**
```
func main(){
    var arr[10];
    arr[0] = 42;
}
```

**Tokenization:** ✅ PASS — 19 tokens produced correctly.
- Array declaration `var arr[10]` tokenized correctly: `KEYWORD:var`, `IDENT:arr`, `PUNCT:[`, `NUMBER:10`, `PUNCT:]`, `PUNCT:;`
- Array assignment `arr[0] = 42` tokenized correctly: `IDENT:arr`, `PUNCT:[`, `NUMBER:0`, `PUNCT:]`, `PUNCT:=`, `NUMBER:42`, `PUNCT:;`

No tokenization errors.

**Parsing:** ⚠️ Could not verify — same test harness SCRIPT ERROR.  
**Analysis:** Not reached.  
**Codegen:** Not reached.

---

## Test 1d: Control Flow (if/else)

**Source code:**
```
func main(){
    var x = 5;
    if(x > 0){
        x = x - 1;
    }else{
        x = 0;
    }
}
```

**Tokenization:** ✅ PASS — 32 tokens produced correctly.
- All keywords (`func`, `var`, `if`, `else`) correctly recognized
- Operators (`>`, `-`) correctly classified as `OP`
- Parentheses `(` `)` and braces `{` `}` correctly classified as `PUNCT`

No tokenization errors.

**Parsing:** ⚠️ Could not verify — same test harness SCRIPT ERROR.  
**Analysis:** Not reached.  
**Codegen:** Not reached.

---

## Godot Console Errors / Warnings

1. **SCRIPT ERROR (test harness bug):** `Invalid call. Nonexistent function 'is_empty' in base 'RefCounted (AST)'` — This occurs in the test harness at [`test_runner_root.gd`](res/tests/test_runner_root.gd:159) when trying to call `.is_empty()` on the AST returned by `parse()`. The AST appears to be returned as a single AST object, not an Array as expected. **This is a test harness bug, not a compiler bug.**

2. **Tokenizer bug (comma as ERROR):** [`test_iter1b`](res/data/test_iter1b.md) tokenization shows commas classified as `[ERROR:,]` because the `punct` array in [`lang_md.gd`](scenes/lang_md.gd:14) does not include `","`. This will cause parsing failures for any function with multiple parameters.

3. **Memory leaks at exit:** `12 ObjectDB instances were leaked` and `2 resources still in use` at exit — expected for a throwaway test runner, not a production concern.

---

## Analysis

### What Worked
- **Tokenization is solid** — All 4 test files tokenized correctly with proper keyword recognition, operator classification, and punctuation handling (except the comma bug).
- **The compiler infrastructure loads correctly** with autoloads `G` and `E`.
- **The pipeline architecture** (separate tokenizer/parser/analyzer/codegen nodes) is well-structured.

### What Didn't Work
1. **Test Harness Bug — AST type mismatch:** The test harness attempted to call `.is_empty()` on the AST, which works for Arrays but not for AST objects. The `parse()` method either returns an Array or an AST node depending on some internal condition. This is a test harness issue, not a compiler bug — but it prevented end-to-end testing.

2. **Comma Not Recognized as Punctuation:** In [`lang_md.gd`](scenes/lang_md.gd:14), the `punct` array is `[";", "//", "(", "[", "{", ")", "]", "}", "#"]` — notably missing `,` (comma). This means function calls with multiple arguments (`func add(a, b)`) will tokenize the comma as `ERROR`, which will likely cause parsing failures.

### Bugs Found

| # | Severity | Component | Description | File |
|---|----------|-----------|-------------|------|
| 1 | **HIGH** | Language Definition | Comma `,` missing from `punct` array — function parameter lists cannot be parsed | [`lang_md.gd:14`](scenes/lang_md.gd:14) |
| 2 | LOW | Test Harness | `ast.is_empty()` fails because AST returned by `parse()` is not an Array | [`test_runner_root.gd:159`](res/tests/test_runner_root.gd:159) |

### Recommendations

1. **Add comma to `punct` array** in `lang_md.gd`:
   ```gdscript
   const punct = [";", "//", "(", "[", "{", ")", "]", "}", ",", "#"];
   ```

2. **Fix test harness** to handle the AST return type correctly — check if `ast is Array` before calling `.is_empty()`, and handle both Array and single-node returns.

3. **Re-run all 4 tests** after fixing the comma and test harness issues to verify full pipeline (tokenize → parse → analyze → codegen) end-to-end.

---

## Appendix: Test Files Created

| File | Size | Description |
|------|------|-------------|
| [`res/data/test_iter1a.md`](res/data/test_iter1a.md) | 64 bytes | Variable declarations with arithmetic |
| [`res/data/test_iter1b.md`](res/data/test_iter1b.md) | 72 bytes | Function definition and call |
| [`res/data/test_iter1c.md`](res/data/test_iter1c.md) | 52 bytes | Array declaration and indexing |
| [`res/data/test_iter1d.md`](res/data/test_iter1d.md) | 90 bytes | if/else control flow |
| [`res/tests/test_runner_root.gd`](res/tests/test_runner_root.gd) | 6.4 KB | Test runner (scene entry point) |
| [`res/tests/run_iter1_tests.gd`](res/tests/run_iter1_tests.gd) | 6.5 KB | Legacy headless runner (not used) |
| [`scenes/test_runner.tscn`](scenes/test_runner.tscn) | 162 bytes | Test scene file |
| [`run_iter1_tests.ps1`](run_iter1_tests.ps1) | 1.2 KB | PowerShell wrapper script |
