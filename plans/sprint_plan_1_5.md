# CpuDerp Codegen Refactor — Sprint Plans 1-5

**Supersedes**: Section 7 of `synthesis_master_plan_v2.md`  
**Prerequisite**: Sprint 0 complete — all foundation files exist and are verified  
**Status**: Active planning document

---

## Table of Contents

1. [How to Use This Document](#1-how-to-use-this-document)
2. [Integration Test Procedure](#2-integration-test-procedure)
3. [Test Runner Reference](#3-test-runner-reference)
4. [Definition of Done](#4-definition-of-done)
5. [Sprint 1 — MOV + Infrastructure](#5-sprint-1--mov--infrastructure)
6. [Sprint 2 — OP + Storage](#6-sprint-2--op--storage)
7. [Sprint 3 — Control Flow](#7-sprint-3--control-flow)
8. [Sprint 4 — Complex Commands](#8-sprint-4--complex-commands)
9. [Sprint 5 — Arrays + Hardening](#9-sprint-5--arrays--hardening)
10. [Appendix: Old-Codegen Function Retirement Map](#10-appendix-old-codegen-function-retirement-map)
11. [Appendix: Golden File IR Command Inventory](#11-appendix-golden-file-ir-command-inventory)

---

## 1. How to Use This Document

Each sprint section is self-contained and specifies:

- **Goal** — one-sentence objective
- **Files to modify** — exact file paths and what to change
- **Template changes** — which `@template` blocks are affected
- **Test criteria** — how to verify the sprint is complete
- **Risks** — what could go wrong and mitigation
- **Estimated effort** — rough lines of code
- **Rollback strategy** — how to undo

Read a sprint, implement its changes in [💻 Code] mode, run the tests, then verify. Do not move to the next sprint until the current sprint's Definition of Done is satisfied.

---

## 2. Integration Test Procedure

### 2.1 End-to-End Compilation in the Godot Editor

This procedure compiles a `.md` source file through the full pipeline (tokenizer → parser → analyzer → new codegen) and compares output against its golden `.asm` file.

**Prerequisites**: Godot editor with the CpuDerp project open.

**Steps**:

1. **Open the test program**: Navigate to `res://data/` and open any `.md` file (e.g., `hello.md`).

2. **Set the compile flag**: In `comp_compile_md.gd`, ensure `use_new_codegen = true` (line 34). This defaults to `true`.

3. **Register migrated ops**: In `codegen_master.gd`, add ops to `migrated_ops` dict for the sprint under test.  
   Example (Sprint 1): `migrated_ops = {"MOV": true}`

4. **Trigger compilation**: In the editor, run the project (F5). The compilation pipeline fires automatically on any `.md` file load or save.  
   Output is written to `a.zd` in the project root.

5. **Compare against golden**: Open `a.zd` and the corresponding golden file (`res://golden/hello.asm`). They must match byte-for-byte (ignoring any `# IR:` comment lines that are purely cosmetic).

6. **Verify all golden files**: Repeat for every golden file that uses the ops migrated in this sprint. The IR command inventory in Appendix 11 tells you which golden files depend on which ops.

### 2.2 Automated Regression Test

See Section 3 for the full test-runner reference.

```bash
# In Godot editor console:
RunTests.run_all()
```

Or for a single suite:

```bash
RunTests.run_suite("golden_regression")
```

### 2.3 Verifying Mixed Old+New Output

To verify that the hybrid pipeline (some ops migrated, some still on old codegen) produces identical output to the all-old pipeline:

1. Set `migrated_ops = {}` (all old) → compile → capture output as `reference.zd`.
2. Set `migrated_ops` to the sprint's target set → compile → compare against `reference.zd`.
3. The two outputs MUST be byte-identical.

This is what `test_golden_regression.gd` does with its `MIGRATION_STEPS` array.

---

## 3. Test Runner Reference

### 3.1 From Godot Editor Console

```gdscript
# Run ALL test suites:
RunTests.run_all()

# Run a specific suite by name (case-insensitive prefix match):
RunTests.run_suite("template_parser")
RunTests.run_suite("abi_scanner")
RunTests.run_suite("stor_alloc")
RunTests.run_suite("codegen_integration")
RunTests.run_suite("golden_regression")
```

### 3.2 Headless Syntax Check (Terminal)

```bash
# Project syntax check (no output = success):
godot --headless --check-only --path "e:\Stride\godot\CpuDerp"
```

This is already running as an active terminal. It validates that all `.gd` files parse correctly.

### 3.3 Test Suite Dependency Graph

```
template_parser ────────────────────┐
                                    ├──> codegen_integration ──> golden_regression
abi_scanner ────> stor_alloc ───────┘
                                    │
                                    └──> (Pass 2: tmpl_expand + asm_emit)
```

- **template_parser tests**: Must pass on their own; no other dependencies.
- **abi_scanner tests**: Depend on template_parser (need ITG).
- **stor_alloc tests**: Depend on abi_scanner (need ABIManifest).
- **codegen_integration tests**: Depend on all of the above.
- **golden_regression tests**: Depend on full compilation pipeline + all golden files.

### 3.4 Adding New Tests Per Sprint

For each sprint, add test cases to:

| Test file | What to add |
|-----------|-------------|
| `test_template_parser.gd` | If new `@template` directives are added |
| `test_abi_scanner.gd` | If new discovery patterns are needed |
| `test_stor_alloc.gd` | If new storage types are added |
| `test_codegen_integration.gd` | Add new `TEST_PROGRAMS` entries if needed |
| `test_golden_regression.gd` | Add new migration step configurations to `MIGRATION_STEPS` |

---

## 4. Definition of Done

A sprint is **Done** when ALL of the following are true:

1. **Code changes committed** — all files modified per the sprint spec.
2. **`@template` blocks updated** in `codegen_templates.tg` — no stale templates.
3. **Old `generate_cmd_*` function retired** — the corresponding function in `codegen_md.gd` is either deleted or bypassed (see Appendix 10).
4. **Template parser tests pass** — `RunTests.run_suite("template_parser")` outputs `[PASS]`.
5. **ABI scanner tests pass** — `RunTests.run_suite("abi_scanner")` outputs `[PASS]`.
6. **Storage allocator tests pass** — `RunTests.run_suite("stor_alloc")` outputs `[PASS]`.
7. **Golden regression tests pass** — `RunTests.run_suite("golden_regression")` with the sprint's `migrated_ops` set passes for all affected golden files.
8. **Old codegen still works** — Setting `migrated_ops = {}` and compiling produces identical output to the pre-migration baseline.
9. **Integration test passes** — Compiling each test `.md` file through the hybrid pipeline produces output identical to the golden file.
10. **No regressions** — `RunTests.run_all()` produces zero failures.

---

## 5. Sprint 1 — MOV + Infrastructure

### 5.1 Goal

Wire the two-pass pipeline end-to-end for the MOV command: Pass 1 discovers symbols through the MOV template, Pass 2 emits correct MOV assembly, and the pipeline dispatcher (`codegen_master.gd`) correctly separates migrated vs unmigrated commands.

### 5.2 Files to Modify

| File | Change |
|------|--------|
| [`scenes/codegen_master.gd`](scenes/codegen_master.gd:42) | Add `migrated_ops = {"MOV": true}` as default (line ~42). Wire `_flatten_commands()` into `generate()` so the flat command list includes label markers and code blocks in the correct order. Ensure `_separate_commands` preserves label-marker synthetic commands. |
| [`scenes/tmpl_expand.gd`](scenes/tmpl_expand.gd:50) | The `expand()` function must handle synthetic `__LBL_FROM__` / `__LBL_TO__` commands by emitting the label markers as comments/labels. Add a case for these synthetic commands in the main loop. |
| [`scenes/tmpl_expand.gd`](scenes/tmpl_expand.gd:170) | [`_build_bindings_from_body()`](scenes/tmpl_expand.gd:170) must handle the case where a MOV command's words array includes an immediate (e.g., `MOV var_8__x imm_9`). The binding `$cmd.words[1]` → `dest`, `$cmd.words[2]` → `src` — verify this works for both `var` and `imm` targets. |
| [`scenes/reg_resolve.gd`](scenes/reg_resolve.gd:71) | `_resolve_load()` for immediate symbols must return the literal value (e.g., `67536`) not the IR name. Currently line 79 returns `str(sym.storage_pos)` but the `imm_9` symbol has `storage_pos` = 0 (set by `allocate_imms`). **Fix**: store the immediate's actual value in `storage_pos` during `_add_imm` in `abi_scanner.gd`. |
| [`scenes/abi_scanner.gd`](scenes/abi_scanner.gd:220) | When creating an `ImmDefNode` symbol, store the actual immediate value (from `node.value`) in `storage_pos`. This is what `reg_resolve.gd` reads for integer immediates. |
| [`scenes/globals_emit.gd`](scenes/globals_emit.gd) | This file is referenced in `codegen_master.gd` but may not exist yet. **Create it** — it must emit the data section globals (`:var_N__x: db 0;\n:imm_N: db 0;\n`). The old codegen's `generate_globals()` does this. |
| [`scenes/codegen_result.gd`](scenes/codegen_result.gd:41) | The `EmitBuffer.append()` method appends `"\n"` in `asm_emit.gd` (line 51). But `emit_label` in `tmpl_expand.gd` already adds `"\n"`. Ensure no double-newlines. Verify with golden file comparison. |

### 5.3 Template Changes

None — the `MOV` template is already correct in `codegen_templates.tg` (lines 173-178):

```
@template MOV(dest:store, src:load):
    @bind dest = $cmd.words[1]
    @bind src  = $cmd.words[2]
    mov {dest}, {src};
@end
```

**Verification**: The template parser test `test_mov_template_slots()` must pass.

### 5.4 Test Criteria

1. `RunTests.run_suite("template_parser")` — all pass (including `test_mov_template_slots`).
2. `RunTests.run_suite("abi_scanner")` — `test_discover_with_simple_mov_ir` and `test_discover_symbols_from_scopes` pass.
3. `RunTests.run_suite("stor_alloc")` — all pass.
4. `RunTests.run_suite("codegen_integration")` — golden files exist and have correct structure.
5. **Full compilation test**: Compile `hello.md` (which uses MOV in the global scope) with `migrated_ops = {"MOV": true}`. The output must match `res://golden/hello.asm` exactly.
6. **Regression**: Compile `hello.md` with `migrated_ops = {}` — must match golden (all-old path still works).

### 5.5 Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| `reg_resolve.gd` returns wrong value for immediates | MOV lines like `mov EAX, 67536;` become `mov EAX, imm_9;` | Fix `storage_pos` in `abi_scanner.gd` `ImmDefNode` handler; verify against golden |
| `EmitBuffer` double-newlines | Output has blank lines, mismatch with golden | Remove `"\n"` from either `emit_line()` or `append()` |
| Label markers not emitted | Code blocks missing `:lbl_from_N:` / `:lbl_to_N:` markers | Verify `__LBL_FROM__` / `__LBL_TO__` handling in `tmpl_expand.gd` |
| Globals not emitted | Data section missing `:var_N__x: db 0;` lines | Create `globals_emit.gd` and wire into `codegen_master.gd` `generate()` line 162 |

### 5.6 Estimated Effort

- ~80-120 lines of new/modified GDScript across 4-5 files
- ~2-4 hours including testing and golden file comparison

### 5.7 Rollback Strategy

1. Revert `migrated_ops` to `{}` — old codegen takes over completely.
2. If core pipeline wiring is broken, revert specific commits touching `codegen_master.gd`, `tmpl_expand.gd`, or `reg_resolve.gd`.
3. The `.tg` file and `template_parser.gd` need no changes, so they are not a rollback risk.

---

## 6. Sprint 2 — OP + Storage

### 6.1 Goal

Migrate all 12 OP variants (INC, DEC, ADD, SUB, MUL, DIV, MOD, GREATER, LESS, EQUAL, NOT_EQUAL, INDEX) to the template system, verifying that `@variant` dispatch, `@temp` allocation, and opcode-specific emit work correctly.

### 6.2 Files to Modify

| File | Change |
|------|--------|
| [`scenes/codegen_master.gd`](scenes/codegen_master.gd:42) | Add `"OP"` to `migrated_ops`: `migrated_ops = {"MOV": true, "OP": true}` |
| [`scenes/tmpl_expand.gd`](scenes/tmpl_expand.gd:252) | [`_handle_variant_switch`] — verify it correctly dispatches on the `op` slot value. The variant value comes from `bindings.get("op")` which maps to `cmd.words[1]` (e.g., `"ADD"`). Ensure `bindings` is populated via the `OP` template's `@bind op = $cmd.words[1]` line. |
| [`scenes/tmpl_expand.gd`](scenes/tmpl_expand.gd:98) | [`emit_node_list`] — the `@variant` directive is parsed as a `VariantSwitchNode`. The `TEMP_ALLOC` case (line 132) is a no-op (temps pre-allocated in Pass 1). Verify that `TEMP_REF` resolution via `reg_resolve.gd` works: `{tmp_a}` resolves to `EAX`, `{tmp_b}` resolves to `EBX`. |
| [`scenes/reg_resolve.gd`](scenes/reg_resolve.gd:25) | `resolve_temp` — verify that temp names `tmp_a` / `tmp_b` are found in `manifest.temps`. The `manifest.temps` list is populated by `abi_scanner.gd` `_scan_template_nodes` when it encounters `TempAllocNode`. |
| [`scenes/abi_scanner.gd`](scenes/abi_scanner.gd:208) | `_add_temp` — verify it correctly registers temps from `OP` template's `@temp tmp_a, tmp_b` directive. The `OP` template has these inside the `@variant ADD, SUB, MUL, DIV, MOD:` block. Since `abi_scanner.gd` scans ALL variant bodies (line 241-242), temps from any variant are discovered. |
| [`res/templates/codegen_templates.tg`](res/templates/codegen_templates.tg:186) | Review the OP template. The `INDEX` variant (line 235) has `@needs_deref(res)` but no body — verify against golden: `array_test.asm` shows `OP INDEX` producing `mov eax, *var_5__arr; mov ebx, 4; mul eax, ebx; mov ecx, eax;`. This is the existing logic — the template may need a body for INDEX. |
| [`scenes/codegen_master.gd`](scenes/codegen_master.gd:147) | [`_separate_commands`] must handle OP commands correctly. OP has 5 words: `OP ADD var_a var_b var_res`. The `cmd.words[0]` is `"OP"`, matched against `migrated_ops`. |

### 6.3 Template Changes

The `OP` template (lines 186-238) has all 12 variants defined. **Critical review needed**:

- **INDEX variant** (line 234-238): Currently only has `@needs_deref(res)` with no body. Looking at `array_test.asm` lines 4-7, INDEX produces:
  ```
  mov EAX, *var_5__arr;
  mov EBX, 4;
  mul EAX, EBX;
  mov ECX, EAX;
  ```
  This is 4 instructions. The current template has no body for INDEX. **This is a gap from foundation** — the INDEX variant body must be added.

- **Mono-operand ops** (INC, DEC): Currently the template emits `mov {res}, {a}; inc {res};`. Golden shows for some cases like line 89-96 in `test_arr_if.asm` which uses `OP ADD` (binary). Need to verify INC/DEC appear in golden files.

- **Comparison ops** (GREATER, LESS, EQUAL, NOT_EQUAL): Templates match golden patterns (e.g., `test_not_eq.asm` lines 16-21 for NOT_EQUAL).

### 6.4 Test Criteria

1. `RunTests.run_suite("template_parser")` — `test_op_has_12_variants` passes.
2. `RunTests.run_suite("abi_scanner")` — `test_discover_temps` passes (OP ADD discovers tmp_a, tmp_b).
3. Compile a program with OP commands:
   - `hello.md` (uses OP: ADD, MUL, INDEX) with `migrated_ops = {"MOV": true, "OP": true}` must match `hello.asm`.
   - `array_test.md` (uses OP: INDEX) with same migrated_ops must match `array_test.asm`.
   - `test_not_eq.md` (uses OP: NOT_EQUAL, EQUAL) must match `test_not_eq.asm`.
4. All 7 golden files that use OP must be verified (see Appendix 11).

### 6.5 Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| **INDEX variant has no body** | OP INDEX will emit nothing, causing missing instructions in array code | Add INDEX body to `OP` template: `mov {tmp_a}, {a};\nmov {tmp_b}, {b};\nmul {tmp_a}, {tmp_b};\nmov {res}, {tmp_a};` — verify against golden |
| @temp not allocated in Pass 1 for all variant code paths | Temp references fail in Pass 2 | Confirm `abi_scanner.gd` scans ALL variant bodies (line 241-242) |
| Opcode lookup fails for case mismatch | e.g., `"ADD"` vs `"add"` | Verify template has `@variant ADD, SUB, ...` (uppercase) and IR emits uppercase |
| Temp register shortage (>4 temps across all OP uses) | Temp spilled to stack, changing output | Verify golden matches — if old codegen uses different register allocation, the `reg_resolve.gd` spill logic must match old behavior |

### 6.6 Estimated Effort

- ~50-80 lines of template changes (INDEX body)
- ~30-50 lines of GDScript changes
- ~2-4 hours including golden file comparison for all 12 variants

### 6.7 Rollback Strategy

1. Remove `"OP"` from `migrated_ops` — OP falls back to old codegen.
2. If template changes are wrong, revert `@template OP(...)` block in `.tg` file to its pre-sprint state.
3. Template parser needs no rollback.

---

## 7. Sprint 3 — Control Flow

### 7.1 Goal

Migrate IF, ELSE_IF, ELSE, and WHILE commands to the template system, implementing `@label` (unique label generation), `@new_imm` (zero constant), `@emit_cb` (recursive code block emission), and the `{%if_block_lbl_end}` context variable for ELSE_IF/ELSE chaining.

### 7.2 Files to Modify

| File | Change |
|------|--------|
| [`scenes/codegen_master.gd`](scenes/codegen_master.gd:42) | Add control-flow ops: `migrated_ops = {"MOV": true, "OP": true, "IF": true, "ELSE_IF": true, "ELSE": true, "WHILE": true}` |
| [`scenes/tmpl_expand.gd`](scenes/tmpl_expand.gd:275) | [`_handle_emit_cb`] must correctly look up the referenced code block in `code_blocks` and recursively expand its commands. The `visited` set prevents infinite loops. Verify that `@emit_cb(cb_cond)` inside IF emits the condition code block inline before the `cmp` instruction. |
| [`scenes/tmpl_expand.gd`](scenes/tmpl_expand.gd:381) | [`_handle_label_def`] — emit pre-generated labels. The label names are generated in Pass 1 by `abi_scanner.gd` (e.g., `lbl_else` → `lbl_else_4`). Verify the naming convention matches what golden expects. |
| [`scenes/tmpl_expand.gd`](scenes/tmpl_expand.gd:406) | [`_handle_if_conditional`] — the `if {val}:` / `endif` conditional in templates like RETURN. Must correctly check if the `val` binding is present and non-empty. |
| [`scenes/tmpl_expand.gd`](scenes/tmpl_expand.gd) | **Context variables**: The ELSE_IF template references `{%if_block_lbl_end}` and ELSE references `{%if_block_lbl_end}`. These are **context variables** set dynamically during emit. The `tmpl_expand.gd` must maintain a context stack or the parent IF/ELSE_IF must set `%if_block_lbl_end` in the bindings before recursing into ELSE_IF or ELSE. This is a **design gap** — the current `tmpl_expand.gd` has no mechanism for this. |
| [`scenes/tmpl_expand.gd`](scenes/tmpl_expand.gd) | **New method**: `_emit_with_context()` — when expanding IF, before expanding ELSE_IF/ELSE children, set `bindings["%if_block_lbl_end"]` to the IF's `lbl_end` label name. This allows ELSE_IF and ELSE to reference their parent IF's end label. |
| [`scenes/abi_scanner.gd`](scenes/abi_scanner.gd:216) | `_scan_template_nodes` for `LabelDefNode` — generates unique names like `lbl_1__lbl_else`. The `ctx.label_counter` increments per command. Verify this produces the correct label names matching golden (e.g., `lbl_else_4`, `lbl_end_4`, `lbl_23__while_next`, `lbl_24__while_end`). |
| [`scenes/asm_emit.gd`](scenes/asm_emit.gd:149) | [`_resolve_context_ref`] — must handle `{%if_block_lbl_end}`, `{%scope}`, and `{%scope_name}`. The `%scope` and `%scope_name` references appear in RETURN and LEAVE templates. These must be set by the expander based on the current code block's scope. |
| [`scenes/reg_resolve.gd`](scenes/reg_resolve.gd:47) | `resolve_value` for `CODEBLOCK` type — `@emit_cb(cb_block)` passes the code block name as a slot value. This needs no special resolution; it's used as a key to look up the code block. |

### 7.3 Template Changes

The following templates require careful review:

**IF** (lines 246-261):
```
@template IF(cb_cond:codeblock, res:load, cb_block:codeblock):
    @label lbl_else, lbl_end
    @new_imm(0) → imm_0
    @emit_cb(cb_cond)
    cmp {res}, {imm_0};
    jz  {lbl_else};
    @emit_cb(cb_block)
    jmp {%if_block_lbl_end};  # <-- NEEDS context variable
    :{lbl_else}:
    :{lbl_end}:
@end
```

**Issues**: 
1. The IF template currently has `jmp {lbl_end};` but golden (e.g., `elif_test.asm` line 18) shows `jmp lbl_end_4;`. This is correct since `{lbl_end}` resolves to the generated label name.
2. **Missing context set**: The IF template must set `{%if_block_lbl_end}` to the value of `lbl_end` so that ELSE_IF and ELSE can reference it. This is a **runtime concern** — the template can't set context variables directly. Instead, the `tmpl_expand.gd` code must do this when expanding IF.

**ELSE_IF** (lines 268-283):
```
@template ELSE_IF(cb_cond:codeblock, res:load, cb_block:codeblock):
    @label lbl_else
    @new_imm(0) → imm_0
    @emit_cb(cb_cond)
    cmp {res}, {imm_0};
    jz  {lbl_else};
    @emit_cb(cb_block)
    jmp {%if_block_lbl_end};   # <-- references parent IF's end label
    :{lbl_else}:
@end
```

**Issues**: 
1. The ELSE_IF template correctly references `{%if_block_lbl_end}` — this MUST be set by the parent IF's expansion.
2. The ELSE_IF needs to NOT emit `:{%if_block_lbl_end}:` at the end — that's done by the ELSE template or by the IF template's closing label. Verify against `elif_test.asm` which shows `:lbl_end_4:` appearing after the ELSE block.

**ELSE** (lines 289-295):
```
@template ELSE(cb_block:codeblock):
    @bind cb_block = $cmd.words[1]
    @emit_cb(cb_block)
    :{%if_block_lbl_end}:
@end
```

**Issues**:
1. ELSE references `{%if_block_lbl_end}` which must be set by the parent IF expander.
2. Golden shows `elif_test.asm` line 39: `:lbl_end_4:` — this comes from ELSE's `:{%if_block_lbl_end}:` template line.

**WHILE** (lines 302-318):
```
@template WHILE(cb_cond:codeblock, res:load, cb_block:codeblock, lbl_next:label, lbl_end:label):
    @new_imm(0) → imm_0
    :{lbl_next}:
    @emit_cb(cb_cond)
    cmp {res}, {imm_0};
    jz  {lbl_end};
    @emit_cb(cb_block)
    jmp {lbl_next};
    :{lbl_end}:
@end
```

**Issues**: WHILE directly takes `lbl_next` and `lbl_end` as LABEL-type parameters from the IR command. These are already-resolved label names (e.g., `lbl_23__while_next`, `lbl_24__while_end`). The template's `:{lbl_next}:` and `:{lbl_end}:` correctly emit them as label definitions. **Verify**: The label slot type `LABEL` vs `IMMEDIATE` — in the template signature, `lbl_next:label` and `lbl_end:label` use the `label` type. The role resolution for `{lbl_next}` in `asm_emit.gd` (line 106-111) returns the plain label name from `manifest.labels`, but these are already *concrete* label names from the IR, not *generated* by the WHILE template. **Design gap**: The WHILE template's label slot type should be `immediate` (verbatim word value), not `label`, because the labels are pre-determined by the IR analyzer, not generated by the template. **Fix**: Change `lbl_next:label` and `lbl_end:label` → immediate slots, or ensure `_resolve_slot_ref` handles `LABEL_REF` by returning the verbatim binding value.

### 7.4 Context Variable Mechanism (Design Detail)

The `{%if_block_lbl_end}` context variable is critical for IF/ELSE_IF/ELSE chaining. Here is the precise mechanism:

1. When `tmpl_expand.gd` encounters an IF command, it:
   a. Resolves the IF template's bindings (including `lbl_else`, `lbl_end`).
   b. Creates a **context frame** with `%if_block_lbl_end` = resolved `lbl_end` value.
   c. Passes this context to the `emit_node_list` call.

2. When the same template chain encounters ELSE_IF or ELSE:
   a. The `_resolve_context_ref` in `asm_emit.gd` looks up `%if_block_lbl_end` from the active context frame.
   b. It returns the label name set by the parent IF.

3. **Implementation approach**: Add a `context: Dictionary` parameter to `emit_node_list()` and all handlers. The expander passes context down the call chain. The IF expander sets `context["%if_block_lbl_end"] = resolved_label` before expanding the body.

**Alternative approach**: Store context in the `EmitBuffer` — less invasive but mixes concerns. Preferred: explicit context parameter.

### 7.5 Test Criteria

1. `RunTests.run_suite("template_parser")` — all pass.
2. `RunTests.run_suite("abi_scanner")` — `test_discover_labels`, `test_discover_imms` pass.
3. Compile and compare golden files:
   - `elif_test.md` (uses IF, ELSE_IF, ELSE) must match `elif_test.asm`.
   - `test_not_eq.md` (uses IF, ELSE) must match `test_not_eq.asm`.
   - `test_arr_if.md` (uses WHILE, IF) must match `test_arr_if.asm`.
   - `hello.md` (uses WHILE) must match `hello.asm`.
4. `@emit_cb` produces correct inline expansion — condition code blocks appear before `cmp` instructions.
5. `@label` generates unique, deterministic names matching golden.

### 7.6 Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Context variable design gap** | ELSE_IF/ELSE can't reference parent IF's end label, producing incorrect jumps | Implement context frame parameter in `emit_node_list()` and all handlers |
| **Label name mismatch** | Template generates `lbl_1__lbl_else` but golden expects `lbl_else_4` | Verify naming convention in `abi_scanner.gd` line 217: `"lbl_%d__%s" % [ctx.label_counter, lbl_name]` — may need to match old `new_lbl()` function |
| **@new_imm imm_0 naming conflict** | Multiple IFs create `imm_0` which already exists from previous commands | Use unique counter-based names instead of fixed `imm_0`. Change `ImmDefNode` to generate unique names per template instantiation |
| **@emit_cb infinite recursion** | Circular code block references hang the compiler | Visited set in `tmpl_expand.gd` line 330 prevents this |
| **WHILE label type mismatch** | LABEL_REF returns manifest label but WHILE labels come from IR directly | Change WHILE slots from `label` to `immediate` type, or fix `LABEL_REF` to fall back to verbatim binding value |

### 7.7 Estimated Effort

- ~80-120 lines of GDScript changes (context variable mechanism, label handling)
- ~30 lines of template adjustments (IF/ELSE_IF/ELSE tweaks)
- ~4-6 hours including debugging context variable chain and golden file comparison

### 7.8 Rollback Strategy

1. Remove control-flow ops from `migrated_ops` — IF/ELSE_IF/ELSE/WHILE fall back.
2. If context variable mechanism breaks the pipeline, revert changes to `tmpl_expand.gd` and `asm_emit.gd`.
3. Template changes to IF/ELSE_IF/ELSE/WHILE can be reverted independently.

---

## 8. Sprint 4 — Complex Commands

### 8.1 Goal

Migrate CALL, CALL_INDIRECT, RETURN, ENTER, and LEAVE to the template system, implementing variadic iteration (`for arg in args:`), `@ref_cb` for reachability marking, `@reverse` for argument order reversal, `@reverse` for argument stack push order, `__ENTER_` / `__LEAVE_` fixup for stack frame management, and the `{%scope}` / `{%scope_name}` context variables.

### 8.2 Files to Modify

| File | Change |
|------|--------|
| [`scenes/codegen_master.gd`](scenes/codegen_master.gd:42) | Add complex ops: `migrated_ops = {"MOV": true, "OP": true, "IF": true, "ELSE_IF": true, "ELSE": true, "WHILE": true, "CALL": true, "CALL_INDIRECT": true, "RETURN": true, "ENTER": true, "LEAVE": true}` |
| [`scenes/tmpl_expand.gd`](scenes/tmpl_expand.gd:231) | [`_handle_foreach`] — must correctly iterate over the variadic `args` list. The CALL template uses `for arg in args:` where `args` is bound to `$cmd.words[2..-2]` (a slice). Verify the slice binding produces an Array, and the foreach iterates each element. |
| [`scenes/tmpl_expand.gd`](scenes/tmpl_expand.gd:366) | [`_handle_reverse`] — the `@reverse(args)` directive reverses the args list in-place in the bindings dictionary. This must happen BEFORE the `for arg in args:` loop. **Verify ordering**: The template has `@reverse(args)` before the `for` loop; the expander must process nodes in order. |
| [`scenes/tmpl_expand.gd`](scenes/tmpl_expand.gd:76) | [`fixup_enter_leave`] — after all emit is done, `AsmEmitter.fixup_enter_leave()` replaces `__ENTER_{scp}` / `__LEAVE_{scp}` placeholders with actual `sub ESP, N` instructions. The `manifest.scope_stack_sizes` must have been populated by `stor_alloc.gd`. **Verify**: The ENTER template emits `__ENTER_{scp}` and LEAVE template emits `__LEAVE_{scope}` — but `{scope}` is a context variable, not a slot binding. |
| [`scenes/tmpl_expand.gd`](scenes/tmpl_expand.gd) | **Context propagation**: ENTER and LEAVE templates reference `{%scope}` (e.g., `__LEAVE_{scope}` — the template uses `{scope}`, which resolves to `{%scope}` context ref). The `codegen_master.gd` or the expander must set `%scope` to the current scope's IR name when expanding commands inside a code block. |
| [`scenes/codegen_master.gd`](scenes/codegen_master.gd) | **Scope tracking**: When iterating the flattened command list and encountering a `__LBL_FROM__` marker, the master should detect the associated scope (from the code block's scope) and set it as context for subsequent commands. This can be done by looking up the code block's scope from `IR.code_blocks`. |
| [`scenes/asm_emit.gd`](scenes/asm_emit.gd:149) | [`_resolve_context_ref`] — handle `{%scope}` return the current scope's IR name (e.g., `scp_8__NULL`). The RETURN template uses `__LEAVE_{scope}`; the LEAVE template uses `__LEAVE_{scope}`. |
| [`scenes/abi_scanner.gd`](scenes/abi_scanner.gd:280) | `_handle_callback` for `ref_cb` — when scanning CALL commands, the `@ref_cb(fun)` directive must mark the target code block as reachable. The `fun` binding resolves to the function name (e.g., `func_4__main`). The scanner must look up which code block corresponds to this function. |
| [`scenes/stor_alloc.gd`](scenes/stor_alloc.gd:56) | `allocate()` must correctly compute `scope_stack_sizes` — the ENTER `sub ESP, N` instructions depend on this. The `scope_stack_sizes` dict maps scope IR names to byte sizes for their stack frames. |
| [`scenes/evaluator_binding.gd`](scenes/evaluator_binding.gd) | **NEW FILE**: The `{len(args)}` computed reference in CALL template (`add ESP, {len(args) * 4};`) requires arithmetic evaluation. Create a simple expression evaluator or modify `_resolve_computed_ref` in `asm_emit.gd` to handle arithmetic. |

### 8.3 Template Changes

**CALL** (lines 327-341):
```
@template CALL(fun:addr, args:variadic, res:store):
    @bind fun  = $cmd.words[1]
    @bind args = $cmd.words[2..-2]   # from [ to just before res
    @bind res  = $cmd.words[-1]
    @ref_cb(fun)
    @reverse(args)
    for arg in args:
        push {arg};
    endfor
    call {fun};
    add  ESP, {len(args) * 4};
    mov  {res}, EAX;
@end
```

**Issues**:
1. `{len(args) * 4}` — the `{len(args)}` part resolves to the number of args. The `* 4` multiplication must be handled. **Gap**: `_resolve_computed_ref` currently only handles `len(X)` not `len(X) * 4`. Need arithmetic support.
2. `{fun}` with `fun:addr` type — resolves to the function label name. Golden shows `call func_4__main;` — correct.
3. `@ref_cb(fun)` — `fun` binds to the function name from `$cmd.words[1]`. The ABI scanner must look up the associated code block.
4. Push order: golden shows args pushed in reverse order (stack convention). `@reverse(args)` handles this.

**CALL_INDIRECT** (lines 348-361): Same as CALL but uses `funvar:load` instead of `fun:addr`, and no `@ref_cb`.

**RETURN** (lines 368-376):
```
@template RETURN(val:optional):
    @bind val = $cmd.words[1]?
    if {val}:
        mov EAX, {val};
    endif
    __LEAVE_{scope};
    ret;
@end
```

**Issues**:
1. `{scope}` must resolve to the current scope's IR name via context variable. Golden shows `__LEAVE_scp_8__NULL;` in `return_test.asm`.
2. The `val:optional` and `if {val}:` conditional correctly handles optional return values.

**ENTER** (lines 383-386):
```
@template ENTER(scp:immediate):
    @bind scp = $cmd.words[1]
    __ENTER_{scp};
@end
```

**Issues**: `__ENTER_{scp}` emits the placeholder. `{scp}` uses VALUE_REF role (since `scp:immediate` is IMMEDIATE type → resolves as VALUE_REF in `_resolve_slot_ref`). But `scp` is a scope name like `scp_14__NULL`, which should be emitted as a plain string. The `IMMEDIATE` slot type gets `VALUE_REF` role → returns verbatim binding. **Correct**.

**LEAVE** (lines 390-394):
```
@template LEAVE():
    __LEAVE_{scope};
@end
```

**Issues**: `{scope}` must be a context variable set by the scoping mechanism described above.

### 8.4 Computed Expression `{len(args) * 4}`

The CALL template uses `add ESP, {len(args) * 4};` to pop arguments after a call. The current `_resolve_computed_ref` in `asm_emit.gd` only handles `len(X)`. Extend it:

1. Parse `len(X)` → count = len(bindings["X"])
2. Parse arithmetic: `{len(args) * 4}` → split on `*`, multiply
3. Support at minimum: `len(X) * N` where N is a positive integer

**Alternative**: Pre-compute the expression during `@bind` processing and store the result. This is simpler: in `_evaluate_binding`, detect arithmetic and compute. But the template doesn't have a `@bind` for `len(args) * 4` — it's inline in the emit line.

### 8.5 Test Criteria

1. `RunTests.run_suite("template_parser")` — `test_call_template_variadic_args` passes.
2. `RunTests.run_suite("abi_scanner")` — `test_discover_reachable_cbs` passes.
3. Compile and compare golden files:
   - `hello.md` (uses CALL, ENTER, LEAVE, RETURN) must match `hello.asm`.
   - `return_test.md` (uses CALL, RETURN, ENTER, LEAVE) must match `return_test.asm`.
   - `printf_test.md` (uses CALL, ENTER, LEAVE) must match `printf_test.asm`.
4. **ENTER/LEAVE fixup**: After emit, `__ENTER_scp_14__NULL` is replaced with `sub ESP, 68` (or appropriate stack size). Verify against golden.
5. **Variadic args**: CALL with 3 args produces 3 `push` instructions and `add ESP, 12`.
6. **@reverse**: Args pushed in correct (reverse) order.
7. **Scope context**: RETURN `__LEAVE_{scope}` resolves to correct scope name.

### 8.6 Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Scope context not set for LEAVE** | `{scope}` resolves to empty string, producing `__LEAVE_` | Implement scope tracking in `codegen_master.gd` — associate each code block with its scope via `IR.scopes` information |
| **{len(args) * 4} not supported** | `add ESP, 0;` instead of `add ESP, 16;` | Extend `_resolve_computed_ref` or pre-compute in `_evaluate_binding` |
| **@ref_cb not finding code block** | Static analysis (abi_scanner) marks code blocks reachable but can't resolve function name → code block mapping | Add function-to-code-block lookup in `ABIScanner.discover()` using `IR.scopes[scp].funcs[N].code` field |
| **ENTER/LEAVE fixup order** | Fixup happens after template expansion, but template emits `__ENTER_{scp}` as text — the fixup replaces text. If the scope name doesn't match, no replacement occurs | Verify `scope_stack_sizes` keys match the scope names used in `__ENTER_{scp}` |
| **Variadic slice too greedy** | `$cmd.words[2..-2]` captures wrong words for CALL with no args vs 3 args | Verify binding produces correct slice for `CALL func [ ] tmp` (0 args = 2..-2 = empty) and `CALL func [ a b c ] tmp` (3 args = `[a, b, c]`) |

### 8.7 Estimated Effort

- ~100-150 lines of GDScript changes (scope tracking, computed refs, ref_cb lookup)
- ~20 lines of template tweaks
- ~4-8 hours including debugging ENTER/LEAVE fixup and variadic iteration

### 8.8 Rollback Strategy

1. Remove complex ops from `migrated_ops`.
2. If scope tracking mechanism is wrong, revert scope-related changes.
3. ENTER/LEAVE fixup reverts to old codegen path.

---

## 9. Sprint 5 — Arrays + Hardening

### 9.1 Goal

Migrate ALLOC and MOV_ARR to the template system, implement `@needs_deref` handling, remove ALL 13 old `generate_cmd_*` functions from `codegen_md.gd`, run full integration tests across all golden files, and produce documentation.

### 9.2 Files to Modify

| File | Change |
|------|--------|
| [`scenes/codegen_master.gd`](scenes/codegen_master.gd:42) | Add array ops: `migrated_ops = {"MOV": true, "OP": true, "IF": true, "ELSE_IF": true, "ELSE": true, "WHILE": true, "CALL": true, "CALL_INDIRECT": true, "RETURN": true, "ENTER": true, "LEAVE": true, "ALLOC": true, "MOV_ARR": true}` |
| [`scenes/codegen_master.gd`](scenes/codegen_master.gd) | **Final cleanup**: When all 13 ops are migrated, the `_generate_unmigrated()` path becomes dead code. Optionally remove it for cleanliness. The `_old_codegen` instance is still needed for `fixup_symtable` in `comp_compile_md.gd`. |
| [`scenes/codegen_md.gd`](scenes/codegen_md.gd) | **Retire all 13 `generate_cmd_*` functions** (see Appendix 10). After removing, the old codegen class still works for the fallback path but its function-specific emit is replaced by a generic template dispatcher stub. |
| [`scenes/abi_scanner.gd`](scenes/abi_scanner.gd:286) | `_handle_callback` for `needs_deref` — must set the `needs_deref` flag on the symbol referenced by the slot. The ALLOC template has `@needs_deref(res)` indicating the result needs an address-of resolution. |
| [`scenes/reg_resolve.gd`](scenes/reg_resolve.gd:47) | `resolve_value` must check `sym.needs_deref` and adjust the resolution. For `ALLOC`, the template does `mov {res}, @{res};` — the `{res}` in STORE_REF mode should return the *address* of the symbol (e.g., `var_5__arr` not `*var_5__arr`). **Alternative**: The ALLOC template uses `@{res}` syntax which is ADDR_REF. Verify `{res}` with `store` slot gets ADDR_REF role → returns address. |
| [`scenes/asm_emit.gd`](scenes/asm_emit.gd:83) | `_resolve_slot_ref` for `ADDR_REF` — must correctly return the address of a symbol. Golden `array_test.asm` shows `mov *var_5__arr, EAX;` for ALLOC — wait, that's a store. Let me check... `array_test.asm` line 4: `mov EAX, *var_5__arr;` — that's a load. Line 6: `mul EAX, EBX;` — arithmetic. ALLOC in golden? Actually `array_test.md` doesn't seem to use ALLOC. The golden file inventory in Appendix 11 should clarify. |
| [`res/templates/codegen_templates.tg`](res/templates/codegen_templates.tg:402) | **ALLOC template**: Review `mov {res}, @{res};` — this moves the *address* of `res` INTO `res`. Golden confirmation needed. |
| [`res/templates/codegen_templates.tg`](res/templates/codegen_templates.tg:413) | **MOV_ARR template**: Review `for val in vals:` — this iterates array values. The `@temp tmp` is used for the destination pointer. Golden confirmation needed. |
| [`docs/todo_implementation.md`](docs/todo_implementation.md) | **Documentation**: Update implementation status, mark all migrations complete. |
| [`docs/todo.md`](docs/todo.md) | Update project todo list — mark codegen refactor as complete. |

### 9.3 Template Changes

**ALLOC** (lines 402-406):
```
@template ALLOC(size:load, res:store):
    @bind size = $cmd.words[1]
    @bind res  = $cmd.words[2]
    mov {res}, @{res};
@end
```

**Issues**:
1. The template moves the address of `res` into `res` itself. This seems odd. Verify against golden: what does the old `generate_cmd_alloc()` produce? Looking at `codegen_md.gd` line 751-756.
2. `@{res}` — the `@` prefix triggers ADDR_REF role for the `res` slot. This returns the address (not the value) of the symbol. For a global var like `var_5__arr`, this returns `var_5__arr` (the label), not `*var_5__arr`.

**MOV_ARR** (lines 413-423):
```
@template MOV_ARR(dest:load, vals:variadic):
    @bind dest = $cmd.words[1]
    @bind vals = $cmd.words[3..-2]   # skip dest, [, ... , ]
    @temp tmp
    mov {tmp}, {dest};
    for val in vals:
        mov *{tmp}, {val};
        add {tmp}, 4;
    endfor
@end
```

**Issues**:
1. `{dest}` is typed `load` in the template signature but semantically it's an address. The template moves `{dest}` into `{tmp}`, then uses `*{tmp}` to dereference. **Verify**: `{dest}` resolves correctly as a load value.
2. `*{tmp}` — the `*` prefix in the template line is literal text, not a slot reference. The template emits `mov *EAX, {val};` — this is correct assembly syntax for indirect memory access.

### 9.4 @needs_deref Details

The `@needs_deref` directive marks a symbol as requiring dereference. It's used by:
- **OP INDEX** variant: `@needs_deref(res)` marks the result of an INDEX operation as needing dereference.
- **ALLOC**: `@needs_deref(res)` — wait, the ALLOC template doesn't have `@needs_deref`. It uses `@{res}` (ADDR_REF) instead.

Actually, looking at the `.tg` file, only the OP INDEX variant has `@needs_deref`. This marks the `res` slot as needing dereference, which means when the RESULT is later used as a LOAD, it should be dereferenced.

In `reg_resolve.gd`, when `_resolve_load` encounters a symbol with `needs_deref = true`, it should add an extra dereference. The current `_resolve_load` doesn't check `needs_deref` — this is a **gap**.

**Implementation**: In `_resolve_load`, after determining the storage text, if `sym.needs_deref` is true, wrap in an additional dereference. For example, a stack symbol `EBP[-27]` with `needs_deref` becomes `*EBP[-27]`.

### 9.5 Old Codegen Retirement

See Appendix 10 for the complete function retirement map. After Sprint 5, all 13 `generate_cmd_*` functions are removed. The old codegen class remains only for:
- IR deserialization (used in `codegen_master.gd` `generate()` step 1)
- The fallback `_generate_unmigrated()` path (which becomes a stub when all ops are migrated)

### 9.6 Test Criteria

1. All existing tests pass — `RunTests.run_all()` produces zero failures.
2. ALL golden files match with `migrated_ops = {all 13 ops}`.
3. `comp_compile_md.gd` compilation path works — full pipeline from `.md` to `.zd`.
4. Old codegen with `migrated_ops = {}` still produces identical output (proving retirement didn't break deserialization).
5. Edge cases:
   - Zero-length variadic lists (CALL with no args).
   - Nested IF/ELSE_IF/ELSE chains.
   - WHILE with empty body.
   - Return with and without value.
   - Array INDEX with immediate offset.
6. Performance benchmark: Compile `printf_test.md` with old codegen vs new pipeline. New pipeline should be comparable or faster.

### 9.7 Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| **@needs_deref not implemented in reg_resolve** | INDEX results not dereferenced, causing wrong array access | Add `needs_deref` check to `_resolve_load` |
| **ALLOC template produces wrong output** | Array allocation fails | Verify against golden and old `generate_cmd_alloc()` |
| **Old codegen removal breaks deserialization** | Full pipeline fails even with migrated_ops={} | Keep old codegen file but remove only the 13 function bodies; keep `deserialize()` |
| **All-ops-migrated golden regression fails** | Some edge case not handled | Debug the specific golden diff, compare old vs new output for that test program |

### 9.8 Estimated Effort

- ~80-120 lines of GDScript changes (needs_deref, cleanup, edge cases)
- ~30 lines of template tweaks
- ~4-6 hours including full regression testing and documentation

### 9.9 Rollback Strategy

1. Revert to pre-sprint-5 state. ALL old `generate_cmd_*` functions are restored.
2. If `@needs_deref` is wrong, revert `reg_resolve.gd` changes only.

---

## 10. Appendix: Old-Codegen Function Retirement Map

Each generate_cmd_* function is retired in the sprint that migrates its corresponding IR command.

| Old Function | File:Line | Sprint | Template | Status |
|------------|-----------|--------|----------|--------|
| `generate_cmd_mov()` | [`codegen_md.gd:309`](scenes/codegen_md.gd:309) | 1 | MOV | Active |
| `generate_cmd_op()` | [`codegen_md.gd:319`](scenes/codegen_md.gd:319) | 2 | OP | Active |
| `generate_cmd_if()` | [`codegen_md.gd:374`](scenes/codegen_md.gd:374) | 3 | IF | Active |
| `generate_cmd_else_if()` | [`codegen_md.gd:397`](scenes/codegen_md.gd:397) | 3 | ELSE_IF | Active |
| `generate_cmd_else()` | [`codegen_md.gd:418`](scenes/codegen_md.gd:418) | 3 | ELSE | Active |
| `generate_cmd_while()` | [`codegen_md.gd:426`](scenes/codegen_md.gd:426) | 3 | WHILE | Active |
| `generate_cmd_call()` | [`codegen_md.gd:446`](scenes/codegen_md.gd:446) | 4 | CALL | Active |
| `generate_cmd_call_indirect()` | [`codegen_md.gd:476`](scenes/codegen_md.gd:476) | 4 | CALL_INDIRECT | Active |
| `generate_cmd_return()` | [`codegen_md.gd:733`](scenes/codegen_md.gd:733) | 4 | RETURN | Active |
| `generate_cmd_enter()` | [`codegen_md.gd:741`](scenes/codegen_md.gd:741) | 4 | ENTER | Active |
| `generate_cmd_leave()` | [`codegen_md.gd:746`](scenes/codegen_md.gd:746) | 4 | LEAVE | Active |
| `generate_cmd_alloc()` | [`codegen_md.gd:751`](scenes/codegen_md.gd:751) | 5 | ALLOC | Active |
| `generate_cmd_mov_arr()` | [`codegen_md.gd:759`](scenes/codegen_md.gd:759) | 5 | MOV_ARR | Active |

**Retirement procedure per sprint**:

1. Verify the new template produces byte-identical output for ALL golden files that use the command(s).
2. In the old function's body, replace with a stub that pushes an error if called (since `_separate_commands` should have excluded it).
3. After all 13 are retired (Sprint 5), consider removing the entire `codegen_md.gd` file or keeping only `deserialize()`.

---

## 11. Appendix: Golden File IR Command Inventory

Each golden file uses a specific set of IR commands. When migrating a sprint, you must compile every golden file that uses the sprint's commands and verify byte-identical output.

| Golden File | MOV | OP | IF | ELSE_IF | ELSE | WHILE | CALL | CALL_IND | RET | ENTER | LEAVE | ALLOC | MOV_ARR |
|-------------|:--:|:--:|:--:|:-------:|:----:|:----:|:----:|:--------:|:---:|:-----:|:-----:|:-----:|:-------:|
| [`hello.asm`](res/golden/hello.asm) | ✅ | ✅ ADD,MUL,INDEX | | | | ✅ | ✅ | | ✅ | ✅ | ✅ | | |
| [`array_test.asm`](res/golden/array_test.asm) | ✅ | ✅ INDEX | | | | | ✅ | | | ✅ | ✅ | | |
| [`test_arr_if.asm`](res/golden/test_arr_if.asm) | ✅ | ✅ ADD,INDEX,EQUAL | ✅ | | ✅ | ✅ | | | ✅ | ✅ | ✅ | | |
| [`test_not_eq.asm`](res/golden/test_not_eq.asm) | ✅ | ✅ NOT_EQUAL,EQUAL | ✅ | | ✅ | | | | | | ✅ | | |
| [`elif_test.asm`](res/golden/elif_test.asm) | ✅ | | ✅ | ✅ | ✅ | | | | | | | | |
| [`printf_test.asm`](res/golden/printf_test.asm) | ✅ | | | | | | ✅ | | | ✅ | ✅ | | |
| [`return_test.asm`](res/golden/return_test.asm) | ✅ | | | | | | ✅ | | ✅ | ✅ | ✅ | | |

**Columns not represented in any golden file**:

- **CALL_INDIRECT** — No golden file uses indirect calls. Will need a new test `.md` file or manual verification.
- **ALLOC** — No golden file uses array allocation. Will need manual verification.
- **MOV_ARR** — No golden file uses array element writes. Will need manual verification.

**Test coverage gap**: For Sprint 5, we need to create test `.md` files for ALLOC and MOV_ARR, or verify through manual compilation.

**Migration progression by golden file**:

| Sprint | Commands migrated | Golden files that should match |
|--------|-------------------|-------------------------------|
| 1 | MOV | All 7 (all use MOV) |
| 2 | MOV, OP | All 7 (hello uses OP, array_test uses OP INDEX, test_arr_if uses OP, test_not_eq uses OP) |
| 3 | MOV, OP, IF, ELSE_IF, ELSE, WHILE | All 7 (elif_test uses IF/ELSE_IF/ELSE, test_arr_if uses WHILE/IF, test_not_eq uses IF/ELSE) |
| 4 | MOV, OP, IF, ELSE_IF, ELSE, WHILE, CALL, CALL_INDIRECT, RETURN, ENTER, LEAVE | All 7 (hello/return_test use CALL/RETURN/ENTER/LEAVE, printf_test uses CALL/ENTER/LEAVE, test_arr_if uses RETURN/ENTER/LEAVE) |
| 5 | All 13 | All 7 + manual ALLOC/MOV_ARR tests |

---

## Sprint Summary Table

| Aspect | Sprint 1 | Sprint 2 | Sprint 3 | Sprint 4 | Sprint 5 |
|--------|----------|----------|----------|----------|----------|
| **Ops migrated** | MOV | OP | IF, ELSE_IF, ELSE, WHILE | CALL, CALL_IND, RET, ENTER, LEAVE | ALLOC, MOV_ARR |
| **Template features** | @bind, EMIT_LINE | @variant, @temp | @label, @new_imm, @emit_cb, {%context} | variadic, for, @ref_cb, @reverse, fixup | @needs_deref |
| **Files to create** | `globals_emit.gd` | — | — | `evaluator_binding.gd` | — |
| **Files to modify** | 4-5 | 3-4 | 4-5 | 5-6 | 4-5 |
| **Old functions retired** | `generate_cmd_mov` | `generate_cmd_op` | `generate_cmd_if/else_if/else/while` | `generate_cmd_call/call_indirect/return/enter/leave` | `generate_cmd_alloc/mov_arr` |
| **Estimated effort** | 2-4 hrs | 2-4 hrs | 4-6 hrs | 4-8 hrs | 4-6 hrs |
| **Cumulative ops** | 1 | 2 | 6 | 11 | 13 |
| **Key risk** | Immediate value resolution | INDEX variant body missing | Context variable mechanism | Scope tracking, computed refs | @needs_deref in reg_resolve |
