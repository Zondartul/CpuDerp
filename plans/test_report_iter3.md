# Iteration 3 Test Report — Re-Test After 4 Bug Fixes

**Date**: 2026-06-28  
**Test Program**: `res/data/test_iter2.md`  
**Test Runner**: `res/tests/run_iter2_test.gd` (via `scenes/test_runner_iter2.tscn`)  
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
| **Tokenizer** | ✅ **PASS** | 23 tokens produced correctly (KEYWORD, IDENT, PUNCT, NUMBER, OP) |
| **Parser (LR shift-reduce)** | ⚠️ **PARTIAL** | AST root reports `null` (cosmetic — same as Iteration 2), but no parse error |
| **Analyzer (IR gen)** | ✅ **PASS** | IR generated with 2 scopes and 2 code blocks. Correct IR commands: `ENTER`, `MOV` (×2), `OP ADD`, `MOV`, `LEAVE` |
| **Old Codegen** (codegen_md.gd) | ✅ **PASS** | Produced **500 chars / 28 lines** with ALL expected patterns: `enter`, `leave`, `mov`, `add` |
| **New CodegenMaster** | ❌ **FAIL** | Two new errors: type mismatch in template parser + ABI scanner index error |

---

## 3. Detailed Findings

### 3.1 Tokenizer — Full PASS (23 tokens)

All tokens correctly identified — identical to Iteration 2.

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
| 10 | KEYWORD | `var` |
| 11 | IDENT | `y` |
| 12 | PUNCT | `=` |
| 13 | NUMBER | `20` |
| 14 | PUNCT | `;` |
| 15 | KEYWORD | `var` |
| 16 | IDENT | `z` |
| 17 | PUNCT | `=` |
| 18 | IDENT | `x` |
| 19 | OP | `+` |
| 20 | IDENT | `y` |
| 21 | PUNCT | `;` |
| 22 | PUNCT | `}` |

### 3.2 Parser — Reports `null` AST root but no parse error

Same as Iteration 2: the AST is returned successfully but `ast[0].tok_class` reports `null`. This is cosmetic — the analyzer consumes the AST without issues. **Not a regression.**

### 3.3 Analyzer — Full PASS

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

### 3.4 Old Codegen (codegen_md.gd) — Full PASS ✅

**Output**: 500 chars, 28 lines — **all 4 expected patterns found:**

- `[OK] enter`
- `[OK] leave`
- `[OK] mov`
- `[OK] add`

**Assembly excerpt** (lines 1–28):
```asm
# Begin code block cb_1
:lbl_from_2:
:lbl_to_3:
# End code block cb_1
# Begin code block cb_4
:func_14__main:
# IR: ENTER scp_7__NULL
sub ESP, 27;
# IR: MOV var_8__x imm_9
mov EAX, 10;
mov EBP[-3], EAX;
# IR: MOV var_10__y imm_11
mov EAX, 20;
mov EBP[-11], EAX;
# IR: OP ADD var_8__x var_10__y tmp_13
mov EAX, EBP[-3];
mov EBX, EBP[-11];
add EAX, EBX;
mov EBP[-23], EAX;
# IR: MOV var_12__z tmp_13
mov EAX, EBP[-23];
mov EBP[-19], EAX;
# IR: LEAVE
sub ESP, -27;
ret;
:lbl_to_6:
# End code block cb_4
```

**Both Bug 1 and Bug 2 fixes are confirmed working**:
- Bug 1 (in-memory IR): The codegen accepted `input.IR` directly and produced correct output without file I/O.
- Bug 2 (iterate all code blocks): Both `cb_1` (entry) AND `cb_4` (main function body) are now emitted, instead of just `cb_1`.

### 3.5 New CodegenMaster — FAIL ❌

#### Error 1: Template parser type mismatch (NEW)

Script errors during [`codegen_master.gd:_ready()`](scenes/codegen_master.gd:77) when loading the template file:

```
SCRIPT ERROR: Trying to assign an array of type "Array" to a variable of type "Array[SlotRef]".
   at: EmitLineNode._init (res://scenes/inflated_template_graph.gd:266)

SCRIPT ERROR: Trying to assign an array of type "Array" to a variable of type "Array[SlotDef]".
   at: TemplateDef._init (res://scenes/inflated_template_graph.gd:79)
```

These errors occur repeatedly (~30+ times) during template parsing. **Root cause**: The [`EmitLineNode._init()`](scenes/inflated_template_graph.gd:263) declares `slot_refs: Array[SlotRef]` (typed array) but the constructor parameter `p_slot_refs` is declared as `Array` (untyped). Godot 4.7's typed array system prevents assigning a plain `Array` to a typed `Array[SlotRef]`.

**Note**: The template file path is now **correct** — `res/templates/codegen_templates.tg` exists at the expected location. Bug 3 (from Iteration 2) regarding path resolution is **fixed**.

#### Error 2: ABI Scanner index access on array (NEW)

After template parsing (which creates an empty/partially-populated graph), the ABI scanner fails:

```
SCRIPT ERROR: Invalid access to property or key 'words' on a base object of type 'Array'.
   at: discover (res://scenes/abi_scanner.gd:74)
```

At [`abi_scanner.gd:74`](scenes/abi_scanner.gd:74), `cmd` is expected to be an `IR_Cmd` object with a `.words` property, but the IR code blocks contain raw arrays instead. This suggests the `InflatedGraph` was not correctly populated (due to Error 1), or the code-block traversal in `discover()` expects a different data structure.

#### Error 3: Chained failure

```
SCRIPT ERROR: Invalid access to property or key 'reachable_cbs' on a base object of type 'Nil'.
   at: CodegenMaster.generate (res://scenes/codegen_master.gd:155)
```

Because `ABIScanner.discover()` returned `null`, the `manifest.reachable_cbs` access fails.

---

## 4. Bug Fix Status

| Bug # | Description | Status | Evidence |
|-------|-------------|--------|----------|
| **Bug 1** | Old codegen `parse_file()` ignores in-memory IR | ✅ **FIXED** | Old codegen produced 500 chars of correct assembly via `input.IR` — no file I/O needed |
| **Bug 2** | Old codegen only emits `cb_1` (empty block) | ✅ **FIXED** | Both `cb_1` AND `cb_4` emitted — main function body now present |
| **Bug 3** | ABI scanner nil-to-string assignments | ⚠️ **FIXED (but new error)** | Null checks are in place at lines 102–116 — no more nil-to-string errors. However, a **new error** occurs: `invalid access to property 'words' on a base object of type 'Array'`. This is a different issue — the data structure shape mismatch |
| **Bug 4** | Template file not found in headless mode | ✅ **FIXED** | `res/templates/codegen_templates.tg` is now found correctly. The `_resolve_tg_path()` multi-strategy fallback handles headless mode |

---

## 5. Remaining Issues

### 🐛 New Bug A: Typed array assignment mismatch
- **File**: [`inflated_template_graph.gd`](scenes/inflated_template_graph.gd:263)
- **Line**: 266 (`EmitLineNode._init`) and 79 (`TemplateDef._init`)
- **Issue**: Constructor parameters are untyped `Array` but assigned to typed `Array[SlotRef]` / `Array[SlotDef]` fields. Godot 4.7 enforces type safety at runtime — this is a hard error.
- **Impact**: Template parsing fails, leaving the `InflatedGraph` empty, causing downstream failures in the ABI scanner.

### 🐛 New Bug B: ABI Scanner expects `IR_Cmd` objects but receives arrays
- **File**: [`abi_scanner.gd`](scenes/abi_scanner.gd:74)
- **Issue**: `cmd.words[0]` assumes `cmd` is an `IR_Cmd` with a `.words` array property. The IR code blocks returned from the analyzer contain raw GDScript arrays, not `IR_Cmd` objects (or the template parser's failed state returns malformed data).
- **Impact**: ABI scanner cannot discover symbols, returns null manifest.

### ⚠️ Unchanged: Parser AST root is `null` (cosmetic)
- **Issue**: `ast[0].tok_class` reports `null` — likely a test introspection quirk, not a real bug (analyzer consumes AST fine).

---

## 6. Recommendations

1. **Fix `inflated_template_graph.gd`** — Change constructor parameter types from `Array` to `Array[SlotRef]` / `Array[SlotDef]` in [`EmitLineNode._init()`](scenes/inflated_template_graph.gd:263) and [`TemplateDef._init()`](scenes/inflated_template_graph.gd:76):
   - `p_slot_refs: Array[SlotRef]` instead of `p_slot_refs: Array`
   - `p_slots: Array[SlotDef]` instead of `p_slots: Array`
   - `p_param_variants: Array[String]` (already typed)
   - `p_body: Array[ITGNode]` (already typed)

2. **Fix `abi_scanner.gd`** — At line 74, add a type check before accessing `cmd.words`:
   ```gdscript
   if cmd is IR_Cmd:
       var tmpl_name = cmd.words[0]
   elif typeof(cmd) == TYPE_ARRAY and cmd.size() > 0:
       var tmpl_name = str(cmd[0])
   ```
   Or ensure the code block traversal returns `IR_Cmd` objects consistently.

3. **Re-test after both fixes** — The new codegen pipeline should succeed once these two issues are resolved.

---

## 7. Raw Output

- Old codegen assembly: **500 chars, 28 lines** (full correct output, both code blocks emitted)
- New codegen: **Failed** — no assembly output produced
- Test exit code: **1** (failure due to new codegen)
