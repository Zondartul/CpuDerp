# CpuDerp Codegen Refactor — Master Synthesis Plan

**Generated**: 2026-06-27  
**Purpose**: Merge the cross-persona consensus architecture from [`synthesis_report.md`](./synthesis_report.md) with concrete implementation details grounded in the actual [`codegen_md.gd`](../scenes/codegen_md.gd) codebase. This is the actionable, step-by-step master plan for replacing the 833-line monolithic codegen with a data-driven pipeline.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Repository Structure — Target State](#2-repository-structure--target-state)
3. [Phase 0: Foundation (Sprint 0)](#3-phase-0-foundation-sprint-0)
4. [Phase 1: Template Engine + MOV (Sprint 1)](#4-phase-1-template-engine--mov-sprint-1)
5. [Phase 2: Storage Allocation + OP (Sprint 2)](#5-phase-2-storage-allocation--op-sprint-2)
6. [Phase 3: Register Resolution + Branching (Sprint 3)](#6-phase-3-register-resolution--branching-sprint-3)
7. [Phase 4: Complex Commands — CALL/RETURN/ARRAY (Sprint 4)](#7-phase-4-complex-commands--callreturnarray-sprint-4)
8. [Phase 5: Hardening & Cleanup (Sprint 5)](#8-phase-5-hardening--cleanup-sprint-5)
9. [Appendices](#9-appendices)

---

## 1. Project Overview

### 1.1 What We're Building

A **data-driven codegen pipeline** to replace `scenes/codegen_md.gd` (833 lines). The IR→assembly mapping moves from imperative `generate_cmd_*` functions to a **declarative YAML template file** processed by **5 pure-function pipeline stages**.

### 1.2 Current Architecture (Pain Points)

```
┌─────────────────────────────────────────────────────────────┐
│                 Current: codegen_md.gd (833 lines)           │
├─────────────────────────────────────────────────────────────┤
│  11 mutable module-level global variables                    │
│  13 generate_cmd_* functions (giant match statement)         │
│  op_map: 12 string-replace templates                         │
│  emit(): 60-line function mixing scanning, reg alloc, text   │
│  find_reference(): char-by-char scanning of $/@/^ markers    │
│  No tests. No isolation. No testability.                     │
└─────────────────────────────────────────────────────────────┘
```

**Key commands emitted** (from `generate_cmd` match, line 266):
- `MOV` — move dest, src
- `OP` — arithmetic op (ADD, SUB, etc.) via `op_map` string templates
- `IF` / `ELSE_IF` / `ELSE` — conditional branching
- `WHILE` — while loop
- `CALL` / `CALL_INDIRECT` — function call
- `RETURN` — return with optional value
- `ENTER` / `LEAVE` — scope entry/exit
- `ALLOC` — array allocation
- `MOV_ARR` — array element write

### 1.3 Target Architecture

```
┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
│ FlatIR   │──▶│ Storage  │──▶│ Template │──▶│ Register │──▶│ Assembly │
│ Builder  │   │ Allocate │   │ Expand   │   │ Resolve  │   │ Emit     │
└──────────┘   └──────────┘   └──────────┘   └──────────┘   └──────────┘
     │              │              │              │              │
  IR_Prog →     FlatIR →       FlatIR →       Buffer →        String →
  FlatIR        FlatIR(alloc)  Buffer          Buffer(res)     (final)
     (flat)       (+storage)     (+text)        (+resolved)
```

### 1.4 Guiding Principles

1. **Zero global mutable state.** Every stage function is `static func(input) -> Result`.
2. **Incremental migration.** One IR command at a time. Old + new codegen coexist.
3. **Golden file regression.** Every output change is validated against saved output.
4. **Data-driven templates.** YAML template file, not code.
5. **Test-first.** Write the test, make it pass, refactor.

---

## 2. Repository Structure — Target State

### 2.1 New Files

```
scenes/
├── codegen_md.gd              # UNCHANGED during migration (or gradually stripped)
├── flatir_build.gd             # [NEW] Stage 1: IR → FlatIR
├── stor_alloc.gd               # [NEW] Stage 2: storage allocation
├── tmpl_expand.gd              # [NEW] Stage 3: template expansion
├── reg_resolve.gd              # [NEW] Stage 4: register resolution
├── asm_emit.gd                 # [NEW] Stage 5: final assembly emit
├── codegen_master.gd           # [NEW] Pipeline orchestrator + dispatcher
└── codegen_result.gd           # [NEW] Result type shared by all stages

res/
├── templates/
│   └── templates.yaml          # [NEW] Template definitions (data, not code)
└── golden/
    ├── hello.asm               # [NEW] Golden file: expected output for hello.md
    ├── test_arr_if.asm
    ├── test_not_eq.asm
    └── ... (one per test program)

tests/
├── test_flatir_build.gd
├── test_stor_alloc.gd
├── test_tmpl_expand.gd
├── test_reg_resolve.gd
├── test_asm_emit.gd
├── test_codegen_integration.gd
└── test_golden_regression.gd
```

### 2.2 Shared Data Types (in `codegen_result.gd`)

```gdscript
# codegen_result.gd
class_name CodegenResult
extends RefCounted

enum ErrorType {
    OK,
    UNKNOWN_OP,
    TEMPLATE_NOT_FOUND,
    REGISTER_EXHAUSTED,
    STORAGE_OVERFLOW,
    INVALID_SLOT,
    LABEL_MISMATCH,
}

var ok: bool
var value: Variant        # FlatIR | Buffer | String | null
var error: ErrorType
var message: String
var loc: LocationRange

static func success(v) -> CodegenResult:
    var r = CodegenResult.new()
    r.ok = true; r.value = v; r.error = ErrorType.OK
    return r

static func failure(err: ErrorType, msg: String, loc: LocationRange = null) -> CodegenResult:
    var r = CodegenResult.new()
    r.ok = false; r.error = err; r.message = msg; r.loc = loc
    return r
```

### 2.3 FlatIR Data Structure

```gdscript
# The intermediate representation between Stage 1 and Stage 3.
# NOT the same as the YAML IR — this is a flattened processing-friendly version.
class_name FlatIR
extends RefCounted

# SoA-style symbol table (parallel arrays for hot-path cache friendliness)
# In GDScript we keep a Dictionary index for lookup, but the actual data
# lives in the parallel arrays.
var sym_names: PackedStringArray       # e.g. ["var_1", "var_2", "func_1"]
var sym_val_types: PackedStringArray   # e.g. ["variable", "temporary", "func"]
var sym_storage_types: PackedStringArray  # ["global", "stack", "immediate", "code", "extern"]
var sym_storage_pos: PackedInt32Array     # stack offset or 0 for non-stack
var sym_data_types: PackedStringArray     # ["int", "string", "func_ptr"]
var sym_is_array: PackedByteArray         # 0 or 1
var sym_array_size: PackedInt32Array      # element count
var sym_needs_deref: PackedByteArray      # 0 or 1 (for INDEX op)

# Name → index lookup (thin index over flat arrays)
var sym_index: Dictionary = {}            # "var_1" → 0, "var_2" → 1, ...

# Flat command array
var commands: Array[FlatCmd] = []         # sequence of commands in emit order

# Code block metadata
var code_blocks: Dictionary = {}          # cb_name → { lbl_from, lbl_to, cmd_start, cmd_len }
var scope_stack_sizes: Dictionary = {}    # scope_name → bytes needed for local vars
```

### 2.4 FlatCmd Structure

```gdscript
class_name FlatCmd
extends RefCounted

var op: String               # "MOV", "OP", "IF", etc.
var words: PackedStringArray  # e.g. ["MOV", "var_dest", "imm_42"]
var loc: LocationRange        # source location for debug
var cb_name: String           # which code block this belongs to
```

### 2.5 Buffer Structure (Stage 3 → Stage 4 → Stage 5)

```gdscript
# Buffer accumulates assembly text during Stages 3-4.
# Unlike the current AssyBlock which uses string concatenation,
# we use PackedStringArray and join once at the end.
class_name EmitBuffer
extends RefCounted

var lines: PackedStringArray = []
var write_pos: int = 0
var loc_map_begin: Dictionary = {}  # write_pos → Array[LocationRange]
var loc_map_end: Dictionary = {}    # write_pos → Array[LocationRange]

func append(text: String, size: int = 8, loc: LocationRange = null) -> void:
    if loc:
        if write_pos not in loc_map_begin: loc_map_begin[write_pos] = []
        loc_map_begin[write_pos].append(loc)
    lines.append(text)
    write_pos += size
    if loc:
        if write_pos not in loc_map_end: loc_map_end[write_pos] = []
        loc_map_end[write_pos].append(loc)

func to_text() -> String:
    return "\n".join(lines) + "\n"
```

---

## 3. Phase 0: Foundation (Sprint 0)

**Goal**: Characterize current behavior, write golden files, define template schema, build test infrastructure.

### 3.1 Task 0.1: Capture Golden Files

For each test program in `res/data/`:

| Test Program | Expected Assembly File |
|---|---|
| `res/data/hello.md` | `res/golden/hello.asm` |
| `res/data/array_test.md` | `res/golden/array_test.asm` |
| `res/data/test_arr_if.md` | `res/golden/test_arr_if.asm` |
| `res/data/test_arr2.md` | `res/golden/test_arr2.asm` |
| `res/data/test_not_eq.md` | `res/golden/test_not_eq.asm` |
| `res/data/elif_test.md` | `res/golden/elif_test.asm` |
| `res/data/printf_test.md` | `res/golden/printf_test.asm` |
| `res/data/return_test.md` | `res/golden/return_test.asm` |

**Implementation**:

```gdscript
# Run current codegen on all test programs, capture output
func capture_goldens():
    var test_files = [
        "res://res/data/hello.md",
        "res://res/data/test_arr_if.md",
        ...
    ]
    for f in test_files:
        var input = {"filename": f}
        var output = codegen_md.parse_file(input)
        var golden_path = f.replace("res/data/", "res/golden/").replace(".md", ".asm")
        var fp = FileAccess.open(golden_path, FileAccess.WRITE)
        fp.store_string(output)
        fp.close()
```

**Acceptance Criteria**: Every test program produces a committed golden file. The golden file is the **ground truth** for all future changes.

### 3.2 Task 0.2: Build `codegen_result.gd`

Create the shared result type (see §2.2). All pipeline stages will use this.

**Test**:
```gdscript
func test_codegen_result_success():
    var r = CodegenResult.success("hello")
    assert_true(r.ok)
    assert_eq(r.value, "hello")
    assert_eq(r.error, CodegenResult.ErrorType.OK)

func test_codegen_result_failure():
    var r = CodegenResult.failure(CodegenResult.ErrorType.UNKNOWN_OP, "unknown op MOVX", null)
    assert_false(r.ok)
    assert_eq(r.message, "unknown op MOVX")
```

### 3.3 Task 0.3: Define YAML Template Schema

Create `res/templates/templates.yaml` with initial template entries. The schema maps IR command patterns to assembly lines.

**Initial entries** (MOV only — we'll expand sprint by sprint):

```yaml
# templates/templates.yaml — Template schema v1
# Format:
#   entry_name:
#     pattern: [opcode, slot1, slot2, ...]
#     slots: { name: { type: "load"|"store"|"addr"|"label" }, ... }
#     assembly: [line1, line2, ...]   # lines with {slot_name} references
#     size: int   # total bytes (8 per instruction × N instructions)

MOV:
  description: "Move src value into dest register/location"
  pattern: ["MOV", "dest", "src"]
  slots:
    dest: { type: store }
    src:  { type: load }
  assembly:
    - "mov ^dest, $src;"
  size: 8
```

**Sigil convention** (preserved from current codegen for backward compatibility):

| Sigil | Meaning | Example |
|-------|---------|---------|
| `^name` | Store to `name` | `^dest` → `*dest` (global) or `EBP[-4]` (stack) |
| `$name` | Load from `name` | `$src` → `*src` or `EBP[8]` or `42` |
| `@name` | Address of `name` | `@arr` → `arr` (global) or `EBP+4` (stack) |

### 3.4 Task 0.4: Build Golden File Test Oracle

```gdscript
# test_golden_regression.gd
func test_golden_hello():
    var input = {"filename": "res://res/data/hello.md"}
    var output = codegen_md.parse_file(input)  # OLD codegen
    var golden = FileAccess.get_file_as_string("res://res/golden/hello.asm")
    assert_eq(output, golden, "hello.md output must match golden file")

func test_all_goldens_match():
    for golden_file in list_golden_files():
        var test_file = golden_file.replace(".asm", ".md").replace("res/golden/", "res/data/")
        var input = {"filename": "res://res/data/" + test_file}
        var output = codegen_md.parse_file(input)
        var golden = FileAccess.get_file_as_string("res://res/golden/" + golden_file)
        assert_eq(output, golden, "%s output must match golden" % test_file)
```

---

## 4. Phase 1: Template Engine + MOV (Sprint 1)

**Goal**: Build Stage 3 (TemplateExpander) and Stage 5 (AssemblyEmitter). Migrate only the `MOV` command. Old codegen handles everything else.

### 4.1 Task 1.1: Build Stage 5 — `asm_emit.gd`

The simplest stage — joins the buffer into a final string.

```gdscript
# asm_emit.gd
static func emit(buf: EmitBuffer) -> CodegenResult:
    var text = buf.to_text()
    return CodegenResult.success(text)

# Also: handle fixup_enter_leave here (or as a substage)
static func fixup_enter_leave(buf: EmitBuffer, scopes: Dictionary) -> EmitBuffer:
    # Replace __ENTER_scope / __LEAVE_scope with sub/add ESP
    # Same logic as current codegen_md.gd:754-762
    var text = buf.to_text()
    for scp_name in scopes:
        var stack_bytes = scopes[scp_name].local_vars_write_pos
        text = text.replace("__ENTER_%s;" % scp_name, "sub ESP, %d;" % (-stack_bytes))
        text = text.replace("__LEAVE_%s;" % scp_name, "add ESP, %d;" % stack_bytes)
    # Rebuild buffer from fixed-up text
    ...
```

**Tests**:
```gdscript
func test_emit_simple():
    var buf = EmitBuffer.new()
    buf.append("mov EAX, 5;\n", 8)
    var result = AsmEmitter.emit(buf)
    assert_true(result.ok)
    assert_eq(result.value, "mov EAX, 5;\n")
```

### 4.2 Task 1.2: Build Stage 3 — `tmpl_expand.gd`

Core template matching engine. Takes a FlatIR + template table, produces an EmitBuffer.

```gdscript
# tmpl_expand.gd
static func expand(ir: FlatIR, templates: Dictionary) -> CodegenResult:
    var buf = EmitBuffer.new()
    for cmd in ir.commands:
        var tmpl = find_template(cmd.op, templates)
        if tmpl == null:
            return CodegenResult.failure(
                CodegenResult.ErrorType.TEMPLATE_NOT_FOUND,
                "No template for op [%s]" % cmd.op, cmd.loc)
        var resolved = resolve_slots(cmd, tmpl, ir)
        if not resolved.ok:
            return resolved
        for line in resolved.value:
            buf.append(line + "\n", tmpl.size / tmpl.assembly.size())
    return CodegenResult.success(buf)
```

**Key sub-functions**:
- `find_template(op, templates)`: Look up by op name. Fallback pattern: try `OP:SUFFIX` → `OP`.
- `resolve_slots(cmd, tmpl, ir)`: For each named slot in template:
  - `type: "load"` → prefix with `$`, look up storage type
  - `type: "store"` → prefix with `^`, look up storage type
  - `type: "addr"` → prefix with `@`
  - `type: "label"` → use the literal label name
  - `type: "register"` → use the literal register name

**Tests**:
```gdscript
func test_expand_mov_immediate_to_global():
    var ir = make_flat_ir_with_sym("var_x", "variable", "global", 0, null)
    ir.commands.append(FlatCmd.new("MOV", ["MOV", "var_x", "42"], loc))
    var templates = { "MOV": MOV_TEMPLATE, ... }
    var result = TemplateExpander.expand(ir, templates)
    assert_true(result.ok)
    var text = result.value.to_text()
    assert_true(text.contains("mov *var_x, 42;"))
```

### 4.3 Task 1.3: Parallel Pipeline Dispatcher

Create `codegen_master.gd` — the orchestrator that decides old vs new codegen per command.

```gdscript
# codegen_master.gd
# Orchestrates pipeline and dispatches between old and new codegen.

var old_codegen: Node   # reference to existing codegen_md.gd
var migrated_ops: Dictionary = {}   # { "MOV": true, ... }
var templates: Dictionary = load_templates()

func generate(input: Dictionary) -> String:
    # 1. Deserialize IR (still using old deserialization for now)
    old_codegen.deserialize(input.text)  # populates old_codegen.IR, old_codegen.all_syms
    
    # 2. Build FlatIR from deserialized IR
    var flat_ir = FlatIRBuilder.build(old_codegen.IR, old_codegen.all_syms)
    
    # 3. Allocate storage
    var alloc_result = StorageAllocator.allocate(flat_ir)
    if not alloc_result.ok: return error_handler(alloc_result)
    
    # 4. Determine which commands are migrated
    var migrated: Array[FlatCmd] = []
    var unmigrated: Array[FlatCmd] = []
    for cmd in alloc_result.value.commands:
        if cmd.op in migrated_ops:
            migrated.append(cmd)
        else:
            unmigrated.append(cmd)
    
    # 5. Run migrated commands through new pipeline
    var new_result = TemplateExpander.expand(alloc_result.value, templates)
    if not new_result.ok: return error_handler(new_result)
    var resolved = RegisterResolver.resolve(new_result.value)
    var emitted = AssemblyEmitter.emit(resolved)
    
    # 6. Run unmigrated commands through old codegen
    var old_assy = old_codegen.generate_unmigrated(unmigrated)
    
    # 7. Combine and fixup
    var combined = emitted.value + old_assy
    return combined
```

**The key insight**: The old codegen's `generate_cmd` function dispatches by `cmd.words[0]`. We modify the old codegen to *skip* migrated commands and run them through the new pipeline. This way we can migrate one command at a time.

### 4.4 Task 1.4: Migrate MOV

Add `"MOV"` to `migrated_ops`. Verify:
- `res/data/hello.md` output matches golden (MOV is in hello.md's assembly)
- All other commands still handled by old codegen
- Integration test passes: `assert_eq(full_pipeline("hello.md"), golden["hello.md"])`

### 4.5 Task 1.5: YAML Template Loader

```gdscript
static func load_templates(path: String = "res://templates/templates.yaml") -> Dictionary:
    var fp = FileAccess.open(path, FileAccess.READ)
    var text = fp.get_as_text()
    fp.close()
    var yaml_data = uYaml.deserialize(text)
    # Convert from YAML format to internal lookup structure
    var templates = {}
    for entry_name in yaml_data:
        var entry = yaml_data[entry_name]
        templates[entry_name] = {
            "pattern": entry.pattern,
            "slots": entry.slots,
            "assembly": entry.assembly,
            "size": entry.size,
        }
    return templates
```

---

## 5. Phase 2: Storage Allocation + OP (Sprint 2)

**Goal**: Build Stage 1 (FlatIRBuilder) and Stage 2 (StorageAllocator). Migrate `OP` commands.

### 5.1 Task 2.1: Build Stage 1 — `flatir_build.gd`

Converts the existing IR/Dictionary structure into the FlatIR representation.

```gdscript
# flatir_build.gd
static func build(IR: Dictionary, all_syms: Dictionary) -> CodegenResult:
    var flat = FlatIR.new()
    
    # 1. Build symbol table index
    for sym_name in all_syms:
        var sym = all_syms[sym_name]
        var idx = flat.sym_names.size()
        flat.sym_names.append(sym_name)
        flat.sym_val_types.append(sym.get("val_type", ""))
        flat.sym_storage_types.append(sym.get("storage", {}).get("type", "") if sym.get("storage") is Dictionary else "")
        flat.sym_storage_pos.append(sym.get("storage", {}).get("pos", 0) if sym.get("storage") is Dictionary else 0)
        flat.sym_data_types.append(sym.get("data_type", ""))
        flat.sym_is_array.append(int(sym.get("is_array", 0)))
        flat.sym_array_size.append(int(sym.get("array_size", 0)))
        flat.sym_needs_deref.append(int(sym.get("needs_deref", false)))
        flat.sym_index[sym_name] = idx
    
    # 2. Build flat command list (traverse code blocks in order)
    for cb_name in IR.code_blocks:
        var cb = IR.code_blocks[cb_name]
        var cmd_start = flat.commands.size()
        for cmd in cb.code:
            var fc = FlatCmd.new()
            fc.cb_name = cb_name
            fc.op = cmd.words[0] if cmd.words.size() > 0 else ""
            fc.words = PackedStringArray(cmd.words)
            fc.loc = cmd.loc
            flat.commands.append(fc)
        flat.code_blocks[cb_name] = {
            "lbl_from": cb.lbl_from,
            "lbl_to": cb.lbl_to,
            "cmd_start": cmd_start,
            "cmd_len": len(cb.code),
        }
    
    # 3. Calculate per-scope stack sizes
    for scp_name in IR.scopes:
        var scope = IR.scopes[scp_name]
        flat.scope_stack_sizes[scp_name] = scope.get("local_vars_write_pos", 0)
    
    return CodegenResult.success(flat)
```

**Tests**:
```gdscript
func test_flatir_build_has_all_symbols():
    var ir = make_sample_IR()  # creates IR with var_x, func_main
    var result = FlatIRBuilder.build(ir.IR, ir.all_syms)
    assert_true(result.ok)
    var flat = result.value
    assert_true(flat.sym_index.has("var_x"))
    assert_true(flat.sym_index.has("func_main"))
```

### 5.2 Task 2.2: Build Stage 2 — `stor_alloc.gd`

Storage allocation currently happens in `allocate_vars()` (line 642) and `allocate_value()` (line 667) of the old codegen. Extract this logic.

```gdscript
# stor_alloc.gd
static func allocate(ir: FlatIR) -> CodegenResult:
    # Walk all symbols and assign storage positions
    # Same logic as allocate_vars + allocate_value but operating on FlatIR arrays
    
    # For each scope: determine which vars are local vs global
    # For global scope: storage_type = "global", pos = 0
    # For local scopes: storage_type = "stack", pos = descending from -3
    # For "arg" storage: storage_type = "stack", pos = ascending from 9
    # For "immediate": no storage needed
    
    return CodegenResult.success(ir)
```

**Tests**:
```gdscript
func test_global_var_gets_global_storage():
    var ir = make_flat_ir_with_scope("global", "none")
    # ... add var_x in global scope
    var result = StorageAllocator.allocate(ir)
    assert_true(result.ok)
    assert_eq(get_storage_type(result.value, "var_x"), "global")
```

### 5.3 Task 2.3: Add OP Templates to templates.yaml

```yaml
OP:ADD:
  description: "Add a + b → res"
  pattern: ["OP", "op", "a", "b", "res"]
  slots:
    a:   { type: load }
    b:   { type: load }
    res: { type: store }
  assembly:
    - "mov EAX, $a;"
    - "add EAX, $b;"
    - "mov ^res, EAX;"
  size: 24

OP:SUB:
  pattern: ["OP", "op", "a", "b", "res"]
  slots: ...
  assembly: ["mov EAX, $a;", "sub EAX, $b;", "mov ^res, EAX;"]
  size: 24

# ... similar for MUL, DIV, MOD, INC, DEC

OP:EQUAL:
  pattern: ["OP", "op", "a", "b", "res"]
  slots: ...
  assembly:
    - "cmp $a, $b;"
    - "mov ^res, CTRL;"
    - "band ^res, CMP_Z;"
    - "bnot ^res;"
    - "bnot ^res;"
  size: 40

OP:GREATER:
  pattern: ["OP", "op", "a", "b", "res"]
  slots: ...
  assembly:
    - "cmp $a, $b;"
    - "mov ^res, CTRL;"
    - "band ^res, CMP_G;"
    - "bnot ^res;"
    - "bnot ^res;"
  size: 40

# OP:INDEX uses the INDEX pattern
OP:INDEX:
  pattern: ["OP", "op", "a", "b", "res"]
  slots: ...
  assembly: ["add $a, $b;"]
  size: 8
  post_process:
    - set_needs_deref(res)
```

### 5.4 Task 2.4: Migrate OP

Add `"OP"` to `migrated_ops`. Verify:
- All 12 `op_map` entries (ADD, SUB, MUL, DIV, MOD, GREATER, LESS, INDEX, DEC, INC, EQUAL, NOT_EQUAL) have template entries
- Golden files still match for all test programs
- Old `op_map` and `generate_cmd_op()` no longer called for migrated programs

---

## 6. Phase 3: Register Resolution + Branching (Sprint 3)

**Goal**: Build Stage 4 (RegisterResolver). Migrate IF, ELSE_IF, ELSE, WHILE control flow.

### 6.1 Task 3.1: Build Stage 4 — `reg_resolve.gd`

The current codegen's `emit()` function (line 474) interleaves register allocation with template expansion. Our design separates them:

```gdscript
# reg_resolve.gd
static func resolve(buf: EmitBuffer, ir: FlatIR) -> CodegenResult:
    var resolved = EmitBuffer.new()
    
    # Register allocator: pure state machine
    var regs = RegAllocState.new()
    
    # Walk through each line in the buffer
    for line in buf.lines:
        # Find $, @, ^ references and replace with concrete assembly
        var processed = resolve_references(line, regs, ir)
        if not processed.ok:
            return processed
        resolved.append(processed.value + "\n", 8)
    
    return CodegenResult.success(resolved)

# Pure register state machine (same design as TDD plan's RegAllocState)
class RegAllocState:
    var _in_use: Array[bool] = [false, false, false, false]  # EAX, EBX, ECX, EDX
    
    func alloc() -> Dictionary:
        for i in range(4):
            if not _in_use[i]:
                var new_state = RegAllocState.new()
                new_state._in_use = _in_use.duplicate()
                new_state._in_use[i] = true
                return {"reg": regs[i], "state": new_state}
        return {"reg": null, "state": self}  # no free register
    
    func free(reg_name: String) -> RegAllocState:
        var idx = regs.find(reg_name)
        if idx == -1: return self
        var new_state = RegAllocState.new()
        new_state._in_use = _in_use.duplicate()
        new_state._in_use[idx] = false
        return new_state
```

**Tests**:
```gdscript
func test_alloc_register_returns_eax_first():
    var ra = RegAllocState.new()
    var r = ra.alloc()
    assert_eq(r.reg, "EAX")
    assert_false(r.state._in_use[0])  # old state unchanged
    assert_true(r.state._in_use[0])  # whoops, check docs

func test_free_register_returns_new_state():
    var r1 = RegAllocState.new().alloc()
    var r2 = r1.state.free("EAX")
    assert_false(r2._in_use[0])
```

### 6.2 Task 3.2: Add IF/ELSE/WHILE Templates

```yaml
IF:
  description: "Conditional branch: if cond == 0 goto else_label"
  pattern: ["IF", "cb_cond", "res", "cb_block"]
  slots:
    res: { type: load }
  assembly:
    - "cmp $res, 0;"
    - "jz {lbl_else};"
  size: 16
  # lbl_else and lbl_end are generated dynamically

ELSE_IF:
  description: "Else-if chain"
  pattern: ["ELSE_IF", "cb_cond", "res", "cb_block"]
  slots:
    res: { type: load }
  assembly:
    - "cmp $res, 0;"
    - "jz {lbl_else};"
  size: 16

WHILE:
  description: "While loop"
  pattern: ["WHILE", "cb_cond", "res", "cb_block", "lbl_next", "lbl_end"]
  slots:
    res: { type: load }
  assembly:
    - ":{lbl_next}:"
    - "cmp $res, 0;"
    - "jz {lbl_end};"
  size: 16
```

Key challenge for control flow: **labels must be generated dynamically**. The current codegen creates labels via `new_lbl()` which mutates `all_syms`. In our pipeline:
- Labels are pre-allocated during Stage 1 (FlatIRBuilder already knows all label names from `cb.lbl_from`, `cb.lbl_to`)
- Control flow commands reference labels by name; the template just outputs them
- `{lbl_else}`, `{lbl_end}`, `{lbl_next}` are resolved to the actual label names from the IR

### 6.3 Task 3.3: Migrate IF/ELSE_IF/ELSE/WHILE

Add to `migrated_ops`. Verify:
- `test_arr_if.md` golden matches
- `elif_test.md` golden matches
- Complex nested control flow produces identical assembly

---

## 7. Phase 4: Complex Commands — CALL/RETURN/ARRAY (Sprint 4)

**Goal**: Migrate CALL, CALL_INDIRECT, RETURN, ENTER, LEAVE, ALLOC, MOV_ARR.

### 7.1 Task 4.1: CALL/RETURN Templates

```yaml
CALL:
  description: "Function call with args"
  pattern: ["CALL", "fun", "[", "arg1", "arg2", "...", "]", "res"]
  slots:
    fun: { type: addr }
    arg*: { type: load }
    res: { type: store }
  assembly:
    - "push $arg*;"
    - "call @fun;"
    - "add ESP, {n_args * 4};"
    - "mov ^res, eax;"
  size: 32  # approximate, depends on arg count

RETURN:
  description: "Return with optional value"
  pattern: ["RETURN"]
  slots: {}
  assembly:
    - "__LEAVE_{scope};"
    - "ret;"
  size: 16

RETURN_VAL:
  description: "Return with value"
  pattern: ["RETURN", "res"]
  slots:
    res: { type: load }
  assembly:
    - "mov EAX, $res;"
    - "__LEAVE_{scope};"
    - "ret;"
  size: 24

ENTER:
  description: "Enter scope"
  pattern: ["ENTER", "scp_name"]
  slots: {}
  assembly:
    - "__ENTER_{scp_name};"
  size: 8

LEAVE:
  description: "Leave scope"
  pattern: ["LEAVE"]
  slots: {}
  assembly:
    - "__LEAVE_{scope};"
  size: 8
```

**Key challenge — variable-length templates**: CALL has variable-length argument pushes. Our template engine needs to support:
- `{n_args * 4}` — computed value
- `push $arg*;` — repeated for each argument
- `{scope}` — resolved from FlatIR's scope tracking

This requires the `resolve_slots` function to handle **iterators** and **arithmetic expressions**, not just simple name lookups.

### 7.2 Task 4.2: ALLOC/MOV_ARR Templates

```yaml
ALLOC:
  description: "Array allocation"
  pattern: ["ALLOC", "size", "arr_name"]
  slots:
    size: { type: load }
    arr_name: { type: store }
  assembly:
    - "mov ^arr_name, @arr_name;"
  size: 8

MOV_ARR:
  description: "Array element write"
  pattern: ["MOV_ARR", "dest", "[", "val_list", "...", "]"]
  slots:
    dest: { type: load }
    val*: { type: load }
  assembly:
    - "mov {tmp}, $dest;"
    - "*"
    - "mov *{tmp}, $val*;"
    - "add {tmp}, 4;"
    - "*"
    - "mov ^dest, {tmp};"
  size: 24  # variable
```

### 7.3 Task 4.3: Full Migration

All commands migrated to new pipeline. Old `generate_cmd_*` functions are no longer called. `migrated_ops` contains all 13 command types.

**Verification**: All golden files match. Full regression suite passes.

---

## 8. Phase 5: Hardening & Cleanup (Sprint 5)

**Goal**: Remove old codegen, performance testing, edge case coverage, documentation.

### 8.1 Task 5.1: Remove Dead Code

Delete (or comment out) from `codegen_md.gd`:
- `generate_cmd()` — the giant `match` statement
- All `generate_cmd_*` functions (mov, op, if, else_if, else, while, call, call_indirect, return, enter, leave, alloc, mov_arr)
- `emit()` — the 60-line string-scanning function
- `find_reference()`
- `alloc_register()` / `free_val()` / `alloc_temporary()`
- `load_value()` / `store_val()` / `address_value()`
- `mark_loc_begin()` / `mark_loc_end()` / `mark_loc()`
- `fixup_enter_leave()`
- `allocate_vars()` / `allocate_value()`

The old codegen is now a thin wrapper that calls the pipeline.

### 8.2 Task 5.2: Edge Case Coverage

Add tests for:
- Empty code blocks
- Deeply nested IF chains
- Maximum register pressure (all 4 registers in use)
- Strings with special characters
- Mixed global/stack storage
- Zero-argument function calls
- `CALL_INDIRECT` via variable

### 8.3 Task 5.3: Performance Regression

Benchmark the old codegen vs new pipeline on `hello.md`:
- Wall clock time
- Memory allocations
- Output byte equality

**Target**: New pipeline is not slower than old codegen. If slower, investigate:
- Template loading (parse YAML once, cache result)
- Buffer allocation (pre-size `PackedStringArray`)
- Register allocation (use bitmask, not Array[bool] copies)

### 8.4 Task 5.4: Documentation

Update:
- `docs/miniderp_syntax.md` — note that codegen pipeline changed
- `res/templates/templates.yaml` — complete template catalog with descriptions
- New developer guide: "How to add a new IR command"

---

## 9. Appendices

### Appendix A: Current IR Command Summary

| Command | Words | Old Codegen Function | Template Needed |
|---------|-------|---------------------|-----------------|
| MOV | `MOV dest src` | `generate_cmd_mov` | MOV |
| OP | `OP op a b res` | `generate_cmd_op` | OP:{op} (12 variants) |
| IF | `IF cb_cond res cb_block` | `generate_cmd_if` | IF |
| ELSE_IF | `ELSE_IF cb_cond res cb_block` | `generate_cmd_else_if` | ELSE_IF |
| ELSE | `ELSE cb_block` | `generate_cmd_else` | ELSE |
| WHILE | `WHILE cb_cond res cb_block lbl_next lbl_end` | `generate_cmd_while` | WHILE |
| CALL | `CALL fun [args...] res` | `generate_cmd_call` | CALL |
| CALL_INDIRECT | `CALL_INDIRECT funvar [args...] res` | `generate_cmd_call_indirect` | CALL_INDIRECT |
| RETURN | `RETURN [val]` | `generate_cmd_return` | RETURN |
| ENTER | `ENTER scp_name` | `generate_cmd_enter` | ENTER |
| LEAVE | `LEAVE` | `generate_cmd_leave` | LEAVE |
| ALLOC | `ALLOC size res` | `generate_cmd_alloc` | ALLOC |
| MOV_ARR | `MOV_ARR dest [vals...]` | `generate_cmd_mov_arr` | MOV_ARR |

### Appendix B: Assembly Sigil Reference

From `find_reference()` (line 542) and `emit()` (line 474):

| Input Sigil | `emit()` Logic | Resolves To |
|-------------|---------------|-------------|
| `$name` | `load_value(name)` | `*name` (global), `EBP[N]` (stack), `N` (immediate) |
| `@name` | `address_value(name)` | `name` (global), `EBP+N` (stack) |
| `^name` | `store_val(name)` | `*name` (global), `EBP[N]` (stack) |
| `$name` with `needs_deref` | 2x load: `mov reg, $name; mov reg, *reg;` | register holding dereferenced value |

### Appendix C: Golden File Format

Golden files contain the exact text output of the codegen: ZVM assembly. Example (from hello.md):

```asm
# Begin code block cb_0
:lbl_from_0:
# IR: CALL func_main
mov EAX, 0;
mov *var_imm_1, 5;
add ESP, 4;
call func_main;
...
```

### Appendix D: Migration Sprint Dependency Map

```
Sprint 0: Foundation
  ├── Golden files captured
  ├── codegen_result.gd built
  ├── Template schema defined
  └── Test oracle built
       │
       ▼
Sprint 1: MOV
  ├── asm_emit.gd (Stage 5)
  ├── tmpl_expand.gd (Stage 3)
  ├── codegen_master.gd (dispatcher)
  ├── YAML loader
  └── MOV migrated ✓
       │
       ▼
Sprint 2: OP + Storage
  ├── flatir_build.gd (Stage 1) — needed for storage allocation
  ├── stor_alloc.gd (Stage 2)
  ├── 12 OP templates added
  └── OP migrated ✓
       │
       ▼
Sprint 3: Control Flow
  ├── reg_resolve.gd (Stage 4) — needed for register allocation
  ├── IF/ELSE/WHILE templates
  └── Control flow migrated ✓
       │
       ▼
Sprint 4: Complex Commands
  ├── CALL/RETURN/ENTER/LEAVE templates
  ├── ALLOC/MOV_ARR templates
  └── All commands migrated ✓
       │
       ▼
Sprint 5: Hardening
  ├── Dead code removal
  ├── Edge case tests
  ├── Performance benchmark
  └── Documentation ✓
```

### Appendix E: Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Golden files drift during migration | High | Medium | Each sprint re-captures goldens. CI enforces match. |
| Template YAML schema changes mid-project | Medium | Low | Schema defined in Sprint 0. Changes require test updates. |
| Performance regression due to extra indirection | Low | Medium | Benchmark in Sprint 5. Hot path can be optimized with pre-compiled templates. |
| Registers exhausted in migrated control flow | Medium | Low | `RegAllocState` falls back to stack spill (same as current codegen's `alloc_temporary`). |
| Variable-length CALL templates too complex for simple slot resolver | Medium | Medium | Implement as special-case in template expander (not in YAML). Fall back to code for CALL only. |
| Pipeline dispatcher overhead | Low | Medium | Dispatcher removed in Sprint 5 after full migration. |
