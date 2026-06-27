# Functional Purity Codegen Plan

**Persona**: Functional Purity Advocate  
**Date**: 2026-06-27  
**Context**: Replace the ad-hoc [`codegen_md.gd`](../scenes/codegen_md.gd) (833 lines) with a purely functional, data-driven codegen for the CpuDerp IR-to-assembly stage.

---

## 1. Diagnosis of the Current Codegen

The existing [`codegen_md.gd`](../scenes/codegen_md.gd) suffers from numerous functional-purity violations:

| Violation | Location | Description |
|-----------|----------|-------------|
| Mutable global state | [`var IR = {}`](../scenes/codegen_md.gd:27) | Module-level mutable dictionary |
| Mutable symbol table | [`var all_syms = {}`](../scenes/codegen_md.gd:28) | Global accumulation of all IR symbols |
| Mutable block stack | [`var assy_block_stack:Array[AssyBlock]`](../scenes/codegen_md.gd:29) | Side-effectful push/pop across calls |
| Mutable register allocator | [`var regs_in_use = {}`](../scenes/codegen_md.gd:32) | Global register allocation state mutated by [`free_val`](../scenes/codegen_md.gd:628) and [`alloc_register`](../scenes/codegen_md.gd:634) |
| Side-effectful emit functions | [`emit_raw`](../scenes/codegen_md.gd:606) | Directly mutates `cur_assy_block.code` string |
| Hidden scope mutation | [`enter_scope`](../scenes/codegen_md.gd:234) | Mutates `entered_scopes` stack and `cur_scope` |
| Impure `new_lbl` / `new_imm` | [`new_lbl`](../scenes/codegen_md.gd:327) | Mutates `all_syms` as side effect |
| Sequential coupling | [`generate`](../scenes/codegen_md.gd:143) | Nondeterministic due to traversal order of dictionary keys |
| Scattered template literals | [`op_map`](../scenes/codegen_md.gd:12) | Hardcoded string templates embedded in code rather than declared as data |

**Consequences**: Untestable without mocking global state, non-reentrant, impossible to reason about locally, fragile ordering dependencies.

---

## 2. Philosophical Foundation

### Core Principles

1. **Pure Functions**: Every function maps input → output with **zero side effects**. Same input always produces same output.
2. **Immutable Data**: No variable is ever mutated. Transformations produce **new values** from old ones.
3. **Referential Transparency**: Any expression can be replaced by its value without changing program behavior.
4. **Explicit State Threading**: State (write position, register assignments, label counters) flows **through** functions via parameters and return values, never through mutable globals.
5. **Algebraic Data Types**: All data is modeled as sum types (tagged unions/variants) and product types (records/structs). Pattern matching replaces conditionals.
6. **Composition over Dispatch**: Instead of a giant match statement with side-effectful branches, compose small template functions via a template table.

### Algebraic Type Philosophy Applied to Codegen

The codegen is modeled as a **pure function** from the **IR program** (a value) to the **assembly result** (a value):

```
Codegen : IR_Program → AssemblyResult
```

No intermediate state is stored; every intermediate value is threaded explicitly. The template engine is a **higher-order pure function**:

```
TemplateEngine : Template × Environment → AssemblyResult
```

Where `Template` is a data structure (not code), `Environment` is the current mapping state, and `AssemblyResult` is the output.

---

## 3. Architecture Overview

### Layer Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                      Layer 3: Codegen Driver                     │
│  compile_program(ir_program) → assembly_result                   │
│  orchestrates templates, resolves references, produces output    │
├─────────────────────────────────────────────────────────────────┤
│                      Layer 2: Template Engine                    │
│  expand_template(template, env) → assembly_result                │
│  slot binding, label generation, register allocation             │
├─────────────────────────────────────────────────────────────────┤
│                      Layer 1: IR Model                            │
│  IR_Program, IR_Block, IR_Cmd, IR_Value (immutable data)         │
│  from ir_md.gd, class_IR_cmd.gd, class_IR_value.gd              │
├─────────────────────────────────────────────────────────────────┤
│                      Layer 0: Assembly Model                      │
│  AssemblyText, LocationMap, WritePosition (immutable data)       │
│  from class_AssyBlock.gd, class_LocationMap.gd                   │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
IR_Program
    │
    ▼
[Template Table] ──pattern match──► Template  ──►  expand_template(template, env)
    │                                                   │
    │                                                   ▼
    │                                           AssemblyResult
    │                                           ├── text: String
    │                                           ├── write_pos: int
    │                                           ├── loc_map: LocationMap
    │                                           ├── labels: Dict[String, int]
    │                                           └── reg_alloc: RegAllocState
    │
    └──► compose(assemby_results) ──► AssemblyResult (final)
                                           │
                                           ▼
                                    comp_asm_zd.gd assembler
```

---

## 4. Core Data Types (Algebraic)

### 4.1 IR Model (Immutable Records)

These already exist but are used mutably. We treat them as **immutable value types** — no fields are modified after construction.

```gdscript
# IR_Cmd: from class_IR_cmd.gd — treated immutably
# .words: Array[String]  — the command tokens
# .loc: LocationRange     — source location

# IR_Value: from class_IR_value.gd — treated immutably
# .ir_name: String
# .val_type: String  — "variable", "immediate", "func", "code", "label", "temporary", etc.
```

### 4.2 Codegen-Specific Types (New)

```gdscript
# === Sum Types (tagged with "type" key) ===

# Template: a declarative description of how to expand an IR pattern into assembly
# Variant: "raw" | "direct" | "branch" | "call" | "alloc" | "scope"
struct Template = Dictionary({
    "type": String,           # variant tag
    "pattern": Array[String], # IR command prefix to match (e.g. ["MOV", :dest, :src])
    "body": String,           # template string with slot markers (e.g. "mov ^{dest}, ${src};\n")
    "slots": Dictionary,      # slot_name → SlotSpec
    "constraints": Array,     # additional codegen constraints
})

# SlotSpec: how to bind an IR operand position to a slot in the template
struct SlotSpec = Dictionary({
    "index": int,             # position in cmd.words (1-based, 0 is command head)
    "binding": String,        # "$" = load_value, "@" = address_value, "^" = store_val, "" = raw
    "type_filter": String,    # optional: restrict to certain IR value types
})

# AssemblyResult: the pure output of template expansion
struct AssemblyResult = Dictionary({
    "text": String,           # emitted assembly text fragment
    "write_pos": int,         # accumulated byte write position
    "loc_map": LocationMap,   # location map for debugging
    "labels": Dictionary,     # label_name → resolved_address (int)
    "reg_alloc": RegAllocState,  # current register allocation state
    "new_syms": Dictionary,   # new symbols created during expansion (immutables, labels, temps)
})

# RegAllocState: pure register allocation state (threaded, never mutated in place)
struct RegAllocState = Dictionary({
    "regs_in_use": Dictionary,  # reg_name → bool (immutable copy on each transition)
    "max_used": int,            # count of registers currently allocated
})

# SymTable: immutable symbol table snapshot
struct SymTable = Dictionary({
    "syms": Dictionary,  # ir_name → IR_Value
    "scopes": Dictionary, # scope_name → Scope
})

# Scope: immutable scope data
struct Scope = Dictionary({
    "ir_name": String,
    "user_name": String,
    "parent": String,
    "vars": Array,
    "funcs": Array,
    "local_vars_write_pos": int,
    "args_write_pos": int,
})
```

---

## 5. Template Engine: Pure Function Design

### 5.1 Top-Level Driver

```gdscript
# compile_program : SymTable × IR_Program → AssemblyResult
# The entry point. Pure function: takes IR program and symbol table, returns assembly.
static func compile_program(sym_table: Dictionary, ir_program: Dictionary) -> Dictionary:
    # 1. Thread initial empty state through all code blocks
    var initial_env = _make_initial_env(sym_table)
    var result = _compile_blocks(ir_program.code_blocks, ir_program.scopes, initial_env)
    result.text += _emit_globals(sym_table, result.new_syms)
    return result
```

### 5.2 Template Table (The Heart of Data-Driven Design)

The template table is a **pure data structure** — a list of template records. The entire IR→assembly mapping is **declared as data**, not encoded in control flow.

```gdscript
# template_table : Array[Template]
# The master template table. Each IR command head maps to a template.
# This is the ONLY place that defines the IR→assembly mapping.
const TEMPLATE_TABLE = [
    # ---- Data movement ----
    Template.new({
        "type": "direct",
        "pattern": ["MOV"],
        "body": "mov ^{2}, ${1};\n",
        "slots": {"1": {index=1, binding="$"}, "2": {index=2, binding="^"}},
        "size": 8,  # cmd_size in bytes
    }),
    
    # ---- Arithmetic / Logic (delegates to op_map which is also data) ----
    Template.new({
        "type": "direct",
        "pattern": ["OP"],
        "body": _expand_op_template,
        "slots": {"1": {index=2}, "2": {index=3}, "3": {index=4}, "op": {index=1}},
        "size": "dynamic",  # computed from body
    }),
    
    # ---- Control flow: IF ---- 
    Template.new({
        "type": "branch",
        "pattern": ["IF"],
        "body": """
            ${cb_cond}
            cmp ${res}, ${imm0};
            jz ${lbl_else};
            ${cb_block}
            jmp ${lbl_end};
        ${lbl_else}:
        """,
        "slots": {
            "cb_cond": {index=1, binding="block"},
            "res": {index=2, binding="$"},
            "cb_block": {index=3, binding="block"},
        },
        "labels": [{"name": "lbl_else", "prefix": "if_else"}, {"name": "lbl_end", "prefix": "if_end"}],
    }),
    
    # ---- Control flow: WHILE ----
    Template.new({
        "type": "branch",
        "pattern": ["WHILE"],
        "body": """
        ${lbl_next}:
            ${cb_cond}
            cmp ${res}, ${imm0};
            jz ${lbl_end};
            ${cb_block}
            jmp ${lbl_next};
        ${lbl_end}:
        """,
        "slots": {
            "cb_cond": {index=1, binding="block"},
            "res": {index=2, binding="$"},
            "cb_block": {index=3, binding="block"},
            "lbl_next": {index=4},
            "lbl_end": {index=5},
        },
    }),
    
    # ---- Function calls ----
    Template.new({
        "type": "call",
        "pattern": ["CALL"],
        "body_template": _build_call_template,
    }),
    
    # ---- Scope enter/leave ----
    Template.new({
        "type": "scope",
        "pattern": ["ENTER"],
        "body": "__ENTER_{scp_name};\n",
        "slots": {"scp_name": {index=1}}
    }),
    
    Template.new({
        "type": "scope",
        "pattern": ["LEAVE"],
        "body": "__LEAVE_{scp_name};\n",
        "slots": {"scp_name": {index=1, binding="current_scope"}}
    }),
    
    # ---- Array allocation ----
    Template.new({
        "type": "alloc",
        "pattern": ["ALLOC"],
        "body": "mov ^{2}, @{arr_storage};\n",
        "slots": {"2": {index=2, binding="^"}, "size": {index=1}},
    }),
    
    # ---- Array element move ----
    Template.new({
        "type": "direct",
        "pattern": ["MOV_ARR"],
        "handler": _handle_mov_arr,  # special case for variable-length
    }),
    
    # ---- Return ----
    Template.new({
        "type": "direct",
        "pattern": ["RETURN"],
        "body": _build_return_body,
    }),
]
```

### 5.3 Core Template Expansion Function

```gdscript
# expand_template : Template × Environment → AssemblyResult
# PURE: takes a template and environment, returns AssemblyResult
# No mutations. State is threaded through.
static func expand_template(tmpl: Dictionary, env: Dictionary) -> Dictionary:
    match tmpl.type:
        "direct":
            return _expand_direct(tmpl, env)
        "branch":
            return _expand_branch(tmpl, env)
        "call":
            return _expand_call(tmpl, env)
        "alloc":
            return _expand_alloc(tmpl, env)
        "scope":
            return _expand_scope(tmpl, env)
```

### 5.4 Direct Template Expansion (Example of Pure Implementation)

```gdscript
static func _expand_direct(tmpl: Dictionary, env: Dictionary) -> Dictionary:
    # Parse template body, replacing slot markers with resolved values
    var body = tmpl.body
    var reg_alloc = env.reg_alloc
    var new_syms = env.new_syms.duplicate()  # copy, since we're building new state
    var text = ""
    var size = 0
    
    # Step 1: Resolve all slots from left to right
    # (deterministic ordering ensures referential transparency)
    var slot_names = tmpl.slots.keys()
    slot_names.sort()  # deterministic order
    for slot_name in slot_names:
        var spec = tmpl.slots[slot_name]
        var ir_name = env.cmd.words[spec.index]
        var resolved = _resolve_slot(ir_name, spec, env, reg_alloc)
        body = body.replace("{%s}" % slot_name, resolved.text)
        reg_alloc = resolved.reg_alloc  # thread state
        if resolved.new_sym:
            new_syms[resolved.new_sym.ir_name] = resolved.new_sym
    
    # Step 2: Compute size
    size = body.count(";") * env.cmd_size if tmpl.size == "dynamic" else tmpl.size
    
    return AssemblyResult.new({
        "text": body,
        "write_pos": env.write_pos + size,
        "loc_map": _merge_loc_maps(env.loc_map, env.cmd.loc, env.write_pos, size),
        "labels": env.labels,
        "reg_alloc": reg_alloc,
        "new_syms": new_syms,
    })
```

### 5.5 Slot Resolution (Pure)

```gdscript
# Resolve a single IR operand to an assembly text fragment.
# Returns: { text: String, reg_alloc: RegAllocState, new_sym: IR_Value|null }
static func _resolve_slot(ir_name: String, spec: Dictionary, env: Dictionary, reg_alloc: Dictionary) -> Dictionary:
    match spec.binding:
        "$":  return _emit_load_value(ir_name, env.sym_table, env.scope, reg_alloc)
        "@":  return _emit_address_value(ir_name, env.sym_table, reg_alloc)
        "^":  return _emit_store_val(ir_name, env.sym_table, env.scope, reg_alloc)
        "block": return _emit_code_block(ir_name, env.sym_table, env.scopes, reg_alloc)
        _:    return {"text": ir_name, "reg_alloc": reg_alloc, "new_sym": null}
```

### 5.6 Load/Store Functions (Pure)

```gdscript
# load_value : String × SymTable × Scope × RegAllocState → ResolvedValue
# Returns the CPU-addressable representation of an IR value.
static func load_value(ir_name: String, sym_table: Dictionary, scope: Dictionary, reg_alloc: Dictionary) -> Dictionary:
    var handle = sym_table.syms[ir_name]
    var res = ""
    
    match handle.val_type:
        "immediate":
            res = handle.value if handle.data_type == "int" else handle.ir_name
        _:
            match handle.storage.type:
                "global":  res = "*%s" % handle.ir_name
                "stack":   res = "EBP[%d]" % handle.storage.pos
                "extern":  res = "*%s" % handle.ir_name
                "code":    res = handle.ir_name
    
    # Handle deref if needed
    if handle.get("needs_deref", false):
        var alloc_result = _alloc_register(reg_alloc)
        res = alloc_result.reg
        reg_alloc = alloc_result.reg_alloc
        # emit mov reg, [reg] — but this would split across template boundaries
        # Better: handle deref as a separate template expansion step
    
    return {"text": res, "reg_alloc": reg_alloc}
```

---

## 6. Register Allocation (Pure State Machine)

The register allocator is a **pure state machine** — input state → output state, no mutations.

```gdscript
static func _alloc_register(reg_alloc: Dictionary) -> Dictionary:
    const REGS = ["EAX", "EBX", "ECX", "EDX"]
    var in_use = reg_alloc.regs_in_use.duplicate()
    var reg = null
    
    for r in REGS:
        if not in_use.get(r, false):
            in_use[r] = true
            reg = r
            break
    
    return {
        "reg": reg,
        "reg_alloc": RegAllocState.new({
            "regs_in_use": in_use,
            "max_used": max(reg_alloc.max_used, REGS.find(reg) + 1) if reg else reg_alloc.max_used,
        })
    }

static func _free_register(reg_name: String, reg_alloc: Dictionary) -> Dictionary:
    var in_use = reg_alloc.regs_in_use.duplicate()
    if reg_name in reg_alloc.regs_in_use:
        in_use[reg_name] = false
    return RegAllocState.new({
        "regs_in_use": in_use,
        "max_used": reg_alloc.max_used,
    })
```

---

## 7. Code Block Generation (Pure Composition)

### 7.1 Block Compilation

```gdscript
# compile_block : CodeBlock × Environment → AssemblyResult
# Pure: compiles a single code block into assembly.
static func compile_block(cb: Dictionary, env: Dictionary) -> Dictionary:
    # Start with block header
    var result = _emit_raw(":%s:\n" % cb.lbl_from, 0, env)
    
    # Compile each IR command in order
    for cmd in cb.code:
        result = _append_result(result, _compile_cmd(cmd, env))
        # Thread environment through each compilation step
        env = _update_env(env, result)
    
    # Maybe emit function return
    if _is_func_code_block(cb.ir_name, env.sym_table):
        result = _append_result(result, _emit_func_return(env))
    
    # Block tail
    result = _append_result(result, _emit_raw(":%s:\n" % cb.lbl_to, 0, env))
    
    return result
```

### 7.2 Command Compilation via Template Lookup

```gdscript
# compile_cmd : IR_Cmd × Environment → AssemblyResult
# Pure: looks up the matching template and expands it.
static func _compile_cmd(cmd: Dictionary, env: Dictionary) -> Dictionary:
    var cmd_head = cmd.words[0]
    
    for tmpl in env.template_table:
        if tmpl.pattern[0] == cmd_head:
            var bound_env = env.duplicate()
            bound_env.cmd = cmd
            return expand_template(tmpl, bound_env)
    
    push_error("Unknown IR command: %s" % cmd_head)
    return AssemblyResult.new({"text": "", "write_pos": env.write_pos, ...})
```

---

## 8. Data-Driven Op Templates

The arithmetic op template is **itself data-driven**, using the existing [`op_map`](../scenes/codegen_md.gd:12) extended as pure data:

```gdscript
# OP_TEMPLATES : Dictionary[String, String]
# Pure data: maps IR operation names to assembly template bodies.
# Extracted from the ad-hoc op_map in codegen_md.gd.
const OP_TEMPLATES = {
    "ADD": "mov {tmpA}, ${arg1};\nadd {tmpA}, ${arg2};\nmov ^{res}, {tmpA};\n",
    "SUB": "mov {tmpA}, ${arg1};\nsub {tmpA}, ${arg2};\nmov ^{res}, {tmpA};\n",
    "MUL": "mov {tmpA}, ${arg1};\nmul {tmpA}, ${arg2};\nmov ^{res}, {tmpA};\n",
    "DIV": "mov {tmpA}, ${arg1};\ndiv {tmpA}, ${arg2};\nmov ^{res}, {tmpA};\n",
    "MOD": "mov {tmpA}, ${arg1};\nmod {tmpA}, ${arg2};\nmov ^{res}, {tmpA};\n",
    "INC": "mov ^{res}, ${arg1};\ninc ^{res};\n",
    "DEC": "mov ^{res}, ${arg1};\ndec ^{res};\n",
    "GREATER": "mov {tmpA}, ${arg1};\nmov {tmpB}, ${arg2};\ncmp {tmpA}, {tmpB};\nmov {tmpA}, CTRL;\nband {tmpA}, CMP_G;\nbnot {tmpA};\nbnot {tmpA};\nmov ^{res}, {tmpA};\n",
    "LESS":    "mov {tmpA}, ${arg1};\nmov {tmpB}, ${arg2};\ncmp {tmpA}, {tmpB};\nmov {tmpA}, CTRL;\nband {tmpA}, CMP_L;\nbnot {tmpA};\nbnot {tmpA};\nmov ^{res}, {tmpA};\n",
    "EQUAL":   "mov {tmpA}, ${arg1};\nmov {tmpB}, ${arg2};\ncmp {tmpA}, {tmpB};\nmov {tmpA}, CTRL;\nband {tmpA}, CMP_Z;\nbnot {tmpA};\nbnot {tmpA};\nmov ^{res}, {tmpA};\n",
    "NOT_EQUAL": "mov {tmpA}, ${arg1};\nmov {tmpB}, ${arg2};\ncmp {tmpA}, {tmpB};\nmov {tmpA}, CTRL;\nband {tmpA}, CMP_NZ;\nbnot {tmpA};\nbnot {tmpA};\nmov ^{res}, {tmpA};\n",
    "INDEX": "mov {tmpA}, ${arg1};\nadd {tmpA}, ${arg2};\nmov ^{res}, {tmpA};\n",
}
```

The OP template expansion is itself a **pure function composition**: it composes the OP-specific body with the general slot resolution machinery.

---

## 9. Fixup as a Pure Transformation

### 9.1 Enter/Leave Fixup

The current [`fixup_enter_leave`](../scenes/codegen_md.gd:754) mutates the assembly string in place. The pure version is a **string transformation**:

```gdscript
# fixup_enter_leave : String × Dictionary → String
# Pure: replaces __ENTER_/__LEAVE_ placeholders with actual SUB instructions.
static func fixup_enter_leave(assy_text: String, scopes: Dictionary) -> String:
    var result = assy_text
    for scope_key in scopes:
        var scope = scopes[scope_key]
        var scp_name = scope.ir_name
        var stack_bytes = scope.local_vars_write_pos
        result = result.replace(
            "__ENTER_%s" % scp_name,
            "sub ESP, %d" % (-stack_bytes if stack_bytes < 0 else stack_bytes)
        )
        result = result.replace(
            "__LEAVE_%s" % scp_name,
            "add ESP, %d" % (-stack_bytes if stack_bytes < 0 else stack_bytes)
        )
    return result
```

### 9.2 Location Map Translation (Pure)

```gdscript
# translate_loc_map : LocationMap × int → LocationMap
# Pure: offset all IPs in a location map by a write position delta.
static func translate_loc_map(loc_map: Dictionary, offset: int) -> Dictionary:
    var new_map = LocationMap.new()
    for ip in loc_map.begin:
        var ip_int = int(ip)
        new_map.begin[ip_int + offset] = loc_map.begin[ip]
    for ip in loc_map.end:
        var ip_int = int(ip)
        new_map.end[ip_int + offset] = loc_map.end[ip]
    return new_map
```

---

## 10. Environment Structure (Explicit State Threading)

The `Environment` is a pure value type that threads all state through the computation:

```gdscript
struct Environment = Dictionary({
    "sym_table": Dictionary,       # immutable symbol table snapshot
    "scopes": Dictionary,          # scope dictionary (from IR)
    "template_table": Array,       # the template table (constant)
    "write_pos": int,              # current byte write position
    "loc_map": LocationMap,        # accumulated location map
    "labels": Dictionary,          # label_name → resolved_address
    "reg_alloc": RegAllocState,    # register allocation state
    "new_syms": Dictionary,        # newly created symbols this pass
    "cmd_size": int,               # instruction size in bytes (constant = 8)
    "cmd": IR_Cmd,                 # current command being expanded (set per template expansion)
    "scope_stack": Array,          # scope stack (threaded, never mutated)
    "current_scope": String,       # current scope ir_name
})
```

**Key invariant**: Every function that takes an `Environment` returns a **new** `Environment` (or `AssemblyResult` containing one). The old environment is never modified.

---

## 11. File-by-File Comparison

| Aspect | Current [`codegen_md.gd`](../scenes/codegen_md.gd) | New Functional Codegen |
|--------|-------|----------------------|
| State | 11 mutable module-level variables | Zero — all state is parameter-threaded |
| Functions returning void | Many (`emit`, `alloc_register`, `free_val`, `enter_scope`) | None — every function returns a value |
| Template encoding | String constants in [op_map](../scenes/codegen_md.gd:12) | Full Template records in a data table |
| IR command dispatch | [`match cmd.words[0]`](../scenes/codegen_md.gd:268) (hardcoded match) | Template table lookup (data-driven, extendable without code changes) |
| Register allocation | Mutable [`regs_in_use`](../scenes/codegen_md.gd:32) dict | Pure state threading via `RegAllocState` |
| Label generation | Side-effectful [`new_lbl`](../scenes/codegen_md.gd:327) | Pure function: `_fresh_label(counter) → (label_name, new_counter)` |
| Location tracking | Side-effectful [`mark_loc_begin`](../scenes/codegen_md.gd:790) | Pure: `_merge_loc_maps(existing_map, loc, ip) → new_map` |
| Fixup | In-place string mutation [`fixup_enter_leave`](../scenes/codegen_md.gd:754) | Pure string transformation |
| Testability | Untestable without mocking all globals | Every function is independently testable with pure I/O |

---

## 12. Implementation Strategy

### Phase 1: Define Pure Data Types and Pure Functions (New File: `codegen_pure.gd`)

Create a new file `scenes/codegen_pure.gd` with:
- Pure `Template` builder functions
- Pure `AssemblyResult` builder
- Pure `RegAllocState` transition functions
- Pure `Environment` construction
- The `TEMPLATE_TABLE` constant data
- All pure helper functions (`_resolve_slot`, `_emit_load_value`, etc.)

**No state, no side effects, no signals. Pure functions only.**

### Phase 2: Build Template Engine

Implement:
- `expand_template(tmpl, env) → AssemblyResult` for each variant
- `compile_block(cb, env) → AssemblyResult`
- `compile_cmd(cmd, env) → AssemblyResult` via template table lookup

### Phase 3: Build the Driver

Implement the top-level driver that:
1. Accepts deserialized IR (from `ir_md.gd` serialization)
2. Threads initial Environment
3. Compiles all referenced code blocks
4. Applies fixups as pure transformations
5. Returns final `AssemblyResult`

### Phase 4: Integration

- Replace the `generate()` entry point in the existing codegen with a call to the new pure driver
- Keep the existing `deserialize` / YAML parsing for backwards compatibility
- Wire up the `locations_ready` signal from the pure result

### Phase 5: Testing Strategy (Pure Function Testing)

Every pure function can be tested independently:

```gdscript
# Example test pattern:
func test_expand_mov_template():
    var tmpl = TEMPLATE_TABLE[0]  # MOV template
    var env = _make_test_env()
    env.cmd = IR_Cmd.new({"words": ["MOV", "var_x", "imm_5"]})
    env.sym_table.syms = _make_test_syms()
    
    var result = expand_template(tmpl, env)
    
    assert_eq(result.text, "mov *var_x, 5;\n")
    assert_eq(result.write_pos, 8)
```

---

## 13. Summary of Benefits

1. **Referential transparency**: Every expression can be reasoned about locally.
2. **No hidden state**: All dependencies are explicit parameters.
3. **Data-driven**: Adding a new IR command = adding a new Template record, not a new function + case in a match.
4. **Testable by construction**: Pure functions need no mocks or test harnesses.
5. **Reentrant**: Multiple codegen passes can run simultaneously with no interference.
6. **Composable**: Templates can be composed from smaller templates. The regex-like slot resolution system is itself a pure function.
7. **Algebraic clarity**: Sum types (template variants) + product types (AssemblyResult, Environment) + pure functions = mathematical verifiability.
8. **Documentation through types**: The Template table IS the documentation of the IR→assembly mapping.

---

## 14. Appendix: Key Files Reference

| File | Role in New Design |
|------|-------------------|
| [`class_IR_cmd.gd`](../class_IR_cmd.gd) | Immutable IR command data — consumed by template engine |
| [`class_IR_value.gd`](../class_IR_value.gd) | Immutable IR value type — symbol table entries |
| [`class_CodeBlock.gd`](../class_CodeBlock.gd) | Immutable code block — input to `compile_block` |
| [`class_AssyBlock.gd`](../class_AssyBlock.gd) | Assembly output container — `AssemblyResult` supersedes this |
| [`class_Location.gd`](../class_Location.gd) | Location data — consumed by `_merge_loc_maps` |
| [`class_LocationRange.gd`](../class_LocationRange.gd) | Location range — consumed by `_merge_loc_maps` |
| [`class_LocationMap.gd`](../class_LocationMap.gd) | Location map — part of `AssemblyResult` |
| [`scenes/ir_md.gd`](../scenes/ir_md.gd) | IR generation — provides input to the new codegen |
| [`scenes/comp_asm_zd.gd`](../scenes/comp_asm_zd.gd) | Assembler — consumes the text output of the new codegen |
| [`lang_zvm.gd`](../lang_zvm.gd) | ZVM ISA definitions — used by slot resolver for register names and opcodes |
| [`scenes/lang_md.gd`](../scenes/lang_md.gd) | MiniDerp language — upstream of the codegen pipeline |
