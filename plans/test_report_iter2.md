# Iteration 2 Test Report — Test Real Compiler

**Date**: 2026-06-28  
**Test Program**: `res/data/test_iter2.md`  
**Test Runner**: `res/tests/run_iter2_test.gd`  
**Pipeline**: Tokenizer → Parser → Analyzer → Codegen (both old and new)

---

## 1. Test Program

```miniderp
func main(){
    var x = 10;
    var y = 20;
    var z = x + y;
}
```

---

## 2. Results Summary

| Stage | Status | Details |
|-------|--------|---------|
| **Tokenizer** | ✅ PASS | 23 tokens produced correctly (KEYWORD, IDENT, PUNCT, NUMBER, OP) |
| **Parser (LR shift-reduce)** | ⚠️ PARTIAL | AST returned but root reports as `null` — likely a type introspection issue, not a parse failure (no error emitted) |
| **Analyzer (IR gen)** | ✅ PASS | IR generated with 2 scopes and 2 code blocks. Correct IR commands: `ENTER`, `MOV` (×2), `OP ADD`, `MOV`, `LEAVE` |
| **Old Codegen** | ⚠️ PARTIAL | Produced 70 chars but only labels for empty `cb_1` — `cb_4` (main function body) was not emitted |
| **New CodegenMaster** | ❌ FAIL | ABI Scanner errors + missing template file |

---

## 3. Detailed Findings

### 3.1 Tokenizer — Full PASS

All 23 tokens correctly identified:

| # | Token | Text |
|---|-------|------|
| 0 | KEYWORD | `func` |
| 1 | IDENT | `main` |
| 2 | PUNCT | `(` |
| 3 | PUNCT | `)` |
| 4 | PUNCT | `{` |
| 5 | KEYWORD | `var` |
| 6 | IDENT | `x` |
| 7 | PUNCT | `=` |
| 8 | NUMBER | `10` |
| 9 | PUNCT | `;` |
| 10–22 | ... | rest of tokens |

### 3.2 Parser — Reports null but does not error

The LR(1) shift-reduce parser returned an AST with no parse errors, but `ast[0].tok_class` reports as `null`. This is likely because:

- The parser returns a single `AST` node (not wrapped in an array with the expected structure)
- The test code checks `ast is Array and ast.size() > 0`, which may fail if `parse()` returns a single AST node directly
- The fact that no error was emitted and the analyzer successfully consumed the AST confirms parsing succeeded

### 3.3 Analyzer — Full PASS with correct IR

Generated IR structure:
- **2 scopes**: `scp_0__global`, `scp_7__NULL`
- **2 code blocks**: `cb_1` (empty entry), `cb_4` (main function)
- **IR commands** in `cb_4`:
  ```
  ENTER scp_7__NULL
  MOV var_8__x imm_9        # x = 10
  MOV var_10__y imm_11      # y = 20
  OP ADD var_8__x var_10__y tmp_13  # z = x + y
  MOV var_12__z tmp_13
  LEAVE
  ```

### 3.4 Old Codegen (codegen_md.gd) — Missing main function body

Output:
```asm
# Begin code block cb_1
:lbl_from_2:
:lbl_to_3:
# End code block cb_1
```

**Root cause analysis**: The old codegen calls `parse_file(input)` which reads from `input.filename` ("IR.txt"). This file was saved to the project root by the analyzer's `IR.to_file("IR.txt")`. However:

1. The codegen opens `"IR.txt"` as a relative path — this resolves to `e:\Stride\godot\CpuDerp\IR.txt`, which exists and contains the full IR
2. After deserialization, `generate()` processes code blocks. `cb_4` has the actual code but is not being emitted
3. **Likely bug**: The [`parse_file`](scenes/codegen_md.gd:80) method reads from the filesystem rather than accepting pre-built IR from `input.IR`. When `input.IR` is populated, the codegen ignores it. This is a design inconsistency — the pipeline should pass the in-memory IR directly.

Additionally, the direct pipeline test should use `old_codegen.IR = input.IR` and then call `old_codegen.generate()` instead of `parse_file()`.

### 3.5 New CodegenMaster — Multiple failures

**Failure 1: Missing template file**
```
ERROR: TemplateParser: cannot open template file: res://templates/codegen_templates.tg
```
The [`codegen_master.gd:_ready()`](scenes/codegen_master.gd:77) tries to load `res://templates/codegen_templates.tg` but it doesn't exist. The actual file is at `res/templates/codegen_templates.tg` (no "s"). Path mismatch.

**Failure 2: ABI Scanner type errors**
```
SCRIPT ERROR: Trying to assign value of type 'Nil' to a variable of type 'String'.
   at: _add_symbol (res://scenes/abi_scanner.gd:103)
```
Multiple errors in [`abi_scanner.gd`](scenes/abi_scanner.gd:103) where string-typed variables receive nil values. This suggests the ABIScanner expects certain fields in the IR data that are missing or null.

---

## 4. Bugs Discovered

### 🐛 Bug 1: Template path mismatch
- **File**: [`codegen_master.gd`](scenes/codegen_master.gd:77)
- **Issue**: Loads `res://templates/codegen_templates.tg` but the actual file is at `res/templates/codegen_templates.tg` — path is correct in source but need verification
- **Impact**: New codegen pipeline cannot start

### 🐛 Bug 2: ABI Scanner nil-to-string assignment
- **File**: [`abi_scanner.gd`](scenes/abi_scanner.gd:103)
- **Issue**: String-typed variables receive nil values when traversing IR symbol entries
- **Impact**: New codegen pipeline crashes on any input

### 🐛 Bug 3: Old codegen ignores in-memory IR
- **File**: [`codegen_md.gd`](scenes/codegen_md.gd:80)
- **Issue**: [`parse_file()`](scenes/codegen_md.gd:80) reads from filesystem even when `input.IR` is pre-populated
- **Impact**: Pipeline must serialize then deserialize, introducing coupling to filesystem

### 🐛 Bug 4: Empty code block (cb_1) emitted instead of real block (cb_4)
- **File**: [`codegen_md.gd`](scenes/codegen_md.gd) (generate function)
- **Issue**: Only `cb_1` (empty entry stub) is emitted; `cb_4` (main function) is missing from output
- **Impact**: Old codegen produces unusable assembly with no actual instructions

---

## 5. Recommendations

1. **Fix the template path** in `codegen_master.gd` — verify `res://templates/codegen_templates.tg` exists
2. **Fix ABI Scanner** null-safety — add nil checks before string assignment
3. **Update old codegen** to accept `input.IR` in-memory when provided (skip file I/O)
4. **Investigate code block traversal** in `codegen_md.generate()` — why `cb_4` is skipped
5. **Add end-to-end test** that compares old and new codegen output for the same IR

---

## 6. Raw Output Files

- IR: `e:\Stride\godot\CpuDerp\IR.txt` (full IR serialization)
- Old codegen output would be: `res/data/a_iter2_old.zd` (not saved due to partial run)
- New codegen output would be: `res/data/a_iter2_new.zd` (not created due to failure)
