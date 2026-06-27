# Data-Oriented Codegen Plan

**Persona**: Data-Oriented Design Advocate  
**Date**: 2026-06-27  
**Context**: Replace the ad-hoc [`codegen_md.gd`](../scenes/codegen_md.gd) (833 lines) with a data-driven, cache-friendly, structure-of-arrays codegen for the CpuDerp IR-to-assembly stage.

---

## 1. Diagnosis of the Current Codegen (DOD View)

The existing codegen is riddled with **pointer chasing, hash map scattering, object indirection, and unpredictable memory access patterns**. Every IR instruction processed causes a cascade of cache misses.

| Violation | Location | DOD Critique |
|-----------|----------|-------------|
| Dictionary-of-objects symbol table | [`var all_syms = {}`](../scenes/codegen_md.gd:28) | Hash map with scattered memory; each lookup is O(1)-amortized but cache-oblivious. Every IR value is a separate Dictionary allocation. |
| Array-of-objects code blocks | [`cb.code: Array[IR_Cmd]`](../class_CodeBlock.gd:4) | Each `IR_Cmd` is a `RefCounted` object — pointer indirection per command. Iterating `cb.code` is a linked-list-style traversal through heap objects. |
| String-based template parsing | [`find_reference`](../scenes/codegen_md.gd:542) | Scans template strings character-by-character at emit time. Hot path does naive search for `$`, `@`, `^` markers. |
| Register allocator as Dictionary | [`regs_in_use = {}`](../scenes/codegen_md.gd:32) | 4-register state expressed as hash map — absurdly heavyweight for 4 bools. |
| Location maps as nested Dictionaries | [`LocationMap.begin`](../class_LocationMap.gd:5) | Dictionary keyed by IP → Array[LocationRange]. Two levels of heap indirection per debug location. |
| Ad-hoc scope stack | [`entered_scopes = []`](../scenes/codegen_md.gd:36) | Dynamic Array of Dictionary references — pointer chasing through scope chain. |
| String accumulation | [`cur_assy_block.code += text`](../scenes/codegen_md.gd:608) | Repeated string allocation + copy. GDScript strings are copy-on-write but repeated concatenation still fragments. |
| Conditional tracing at emit time | [`ADD_DEBUG_TRACE`](../scenes/codegen_md.gd:7) | Debug trace branches on every emit call — pollutes I-cache even when disabled. |

**Consequence**: The codegen is dominated by allocation, hashing, string scanning, and pointer chasing — not by actual code generation logic.

---

## 2. Philosophical Foundation

### Core Principles

1. **Data Before Code**: The IR program is a **blob of flat arrays**, not a graph of objects. Code is secondary to data layout.

2. **Structure of Arrays (SoA)**: Instead of an array of `IR_Cmd` objects (each with a `words` array and a `loc`), use parallel typed arrays — one array for command heads, one for operands, one for locations. Processing iterates cache-friendly sequential memory.

3. **Hot/Cold Splitting**: The hot path (command dispatch, operand resolution, emit) operates on dense, sequential data. The cold path (label generation, scope analysis, fixup) is separated into its own pass.

4. **No Pointer Chasing**: Flat indices replace object references. Instead of `cmd.words[i]`, use `cmd_operands[cmd_operand_offset[cmd_index] + i]`. No `RefCounted` dereferences.

5. **Data-Driven Templates**: Templates are pre-compiled into a **flat bytecode** that the emit engine interprets. No string scanning at emit time.

6. **Batch Processing**: Process the IR in bulk passes — allocate all labels in one pass, resolve all operands in one pass, emit all assembly in one pass.

7. **The Data Model Determines What's Possible**: If the data layout makes a transformation O(n) with good locality, you design around it. If it would be O(n log n) with bad locality, you restructure the data.

---

## 3. Architecture Overview

### Layer Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                  Layer 3: Codegen Driver                       │
│  Flat IR → Flat Assembly (batch-oriented, three-pass)         │
├──────────────────────────────────────────────────────────────┤
│                  Layer 2: Template Engine (Flat)               │
│  Pre-compiled template bytecode → linear emit                  │
│  register allocator = 4-bit bitmask (hot), fallback (cold)    │
├──────────────────────────────────────────────────────────────┤
│                  Layer 1: Flat IR Representation               │
│  Parallel arrays: cmd_heads[], cmd_operands[], cmd_locs[]      │
│  Symbol table: ir_name[] packed as enum + flat index           │
├──────────────────────────────────────────────────────────────┤
│                  Layer 0: Flat Assembly Buffer                 │
│  PackedByteArray for assembly text (or pre-sized String)       │
│  Location map: flat arrays of {ip, loc_begin, loc_end}[]      │
└──────────────────────────────────────────────────────────────┘
```

### Three-Pass Pipeline

```
┌──────────┐    ┌──────────────────┐    ┌──────────────┐
│  Pass 1  │───►│     Pass 2      │───►│   Pass 3     │
│ Analyze  │    │   Template       │    │   Fixup      │
│ & Alloc  │    │   Expansion      │    │   & Link     │
└──────────┘    └──────────────────┘    └──────────────┘

Pass 1 (Cold Path):
  - Walk IR once to count everything
  - Allocate label slots, temporary slots, register plan
  - Build flat symbol index
  - Determine which code blocks to emit
  - Result: flat allocation table

Pass 2 (Hot Path):
  - Iterate flat command arrays sequentially
  - For each command: lookup pre-compiled template, emit flat assembly
  - Register allocation via 4-bit bitmask (hot), stack spill (cold)
  - Result: flat assembly buffer + fixup list

Pass 3 (Warm Path):
  - Apply fixups (enter/leave → sub/add)
  - Patch label references
  - Flatten location map
  - Result: final assembly string + final location map
```

---

## 4. Flat IR Data Model (SoA)

### 4.1 IR Command Table (Structure of Arrays)

Instead of `Array[IR_Cmd]` where each `IR_Cmd` is a `RefCounted` with an `Array[String] words`:

```gdscript
# === Flat IR Command Table (SoA) ===
# All arrays are parallel: index i accesses the i-th command.

# Command head opcode (enum encoded as int for cache-friendly dispatch)
# 0=INVALID, 1=MOV, 2=OP, 3=IF, 4=ELSE_IF, 5=ELSE,
# 6=WHILE, 7=CALL, 8=CALL_INDIRECT, 9=RETURN,
# 10=ENTER, 11=LEAVE, 12=ALLOC, 13=MOV_ARR
static var cmd_heads: PackedInt32Array    # [N]  — command opcode enum
static var cmd_operand_offset: PackedInt32Array  # [N]  — index into cmd_operands flat array
static var cmd_operand_count: PackedInt32Array   # [N]  — number of operands
static var cmd_loc_begin: PackedInt32Array  # [N]  — serialized location ID (or index into loc array)
static var cmd_loc_end: PackedInt32Array    # [N]  — serialized location ID

# Flat operand pool (all operands for all commands, concatenated)
static var cmd_operands: PackedStringArray  # [total_operands]

# Location pool
static var cmd_locs: Array[LocationRange]   # [total_locs] — cold path only, accessed on demand
```

**Why this is cache-friendly**: Iterating `cmd_heads` gives a sequential memory access pattern. Each command head is a 4-byte integer, so 8 commands fit in a single 64-byte cache line. Compare with the current code where each `IR_Cmd` is a separate heap object.

### 4.2 Flat Symbol Table

Instead of `all_syms: Dictionary` (hash map of ir_name → Dictionary):

```gdscript
# === Flat Symbol Table ===
# Symbols are stored in parallel arrays with a fast lookup structure.

# Primary symbol arrays (SoA, sorted by ir_name for binary search)
static var sym_ir_name: PackedStringArray    # [M]  — sorted
static var sym_val_type: PackedInt32Array    # [M]  — enum: 0=var, 1=imm, 2=func, 3=code, 4=lbl, 5=tmp
static var sym_storage_type: PackedInt32Array  # [M]  — enum: 0=global, 1=stack, 2=extern, 3=code
static var sym_storage_pos: PackedInt32Array   # [M]  — stack offset or global label index
static var sym_value: PackedStringArray     # [M]  — for immediates
static var sym_data_type: PackedInt32Array  # [M]  — enum: 0=int, 1=string, 2=char
static var sym_needs_deref: PackedByteArray  # [M]  — bool packed as byte
static var sym_is_array: PackedByteArray     # [M]  — bool packed as byte
static var sym_array_size: PackedInt32Array  # [M]  — array element count

# Fast lookup: ir_name_hash → index (open addressing, power-of-2 size)
# This is a minimal perfect hash for the hot path.
# Cold path uses binary search on the sorted sym_ir_name array.
static var sym_lookup: PackedInt32Array     # [lookup_size]  — -1 = empty, else index into sym arrays
```

**String interning**: All `ir_name` strings are **interned** — identical strings share the same storage. The template engine works with intern IDs, not strings.

### 4.3 Flat Scope Table

```gdscript
# === Flat Scope Table (SoA) ===
static var scp_ir_name: PackedStringArray
static var scp_user_name: PackedStringArray
static var scp_parent_idx: PackedInt32Array  # -1 = no parent
static var scp_var_start: PackedInt32Array   # index into sym arrays for first var
static var scp_var_count: PackedInt32Array
static var scp_func_start: PackedInt32Array
static var scp_func_count: PackedInt32Array
static var scp_local_vars_wp: PackedInt32Array  # local vars write position
static var scp_args_wp: PackedInt32Array     # args write position
```

---

## 5. Template Engine: Pre-Compiled Bytecode

### 5.1 Template Definition Format (Data, Not Code)

Templates are **pure data** — never code. Each template is a record that maps an IR command pattern to a sequence of emit operations.

```gdscript
# === Template Table ===
# Array of template records. Each record is a flat Dictionary (data-only, no methods).
# This is the COMPLETE mapping from IR commands to assembly.
const TEMPLATE_TABLE: Array[Dictionary] = [
    # Each template is a data record:
    {
        "pattern": ["MOV"],        # IR command head to match
        "size": 8,                 # instruction size in bytes (or "dynamic")
        "emit_ops": [              # pre-compiled emit operations (see 5.2)
            {"op": "TEXT", "text": "mov "},
            {"op": "STORE", "slot": 2},      # ^dest  (store_val)
            {"op": "TEXT", "text": ", "},
            {"op": "LOAD", "slot": 1},       # $src   (load_value)
            {"op": "TEXT", "text": ";\n"},
        ]
    },
    {
        "pattern": ["OP"],
        "size": "dynamic",
        # OP is special — it expands via the op_data table
        "op_gen": "OP_DISPATCH",   # references a named generator
        "emit_ops": [              # emit_ops are generated at compile time
            {"op": "TEXT", "text": "mov "},
            {"op": "TEMP_REG"},
            {"op": "TEXT", "text": ", "},
            {"op": "LOAD", "slot": 2},       # arg1
            {"op": "TEXT", "text": ";\n"},
            {"op": "OP_BODY", "slot": 1},    # op-specific body from op_data
            {"op": "TEXT", "text": "mov "},
            {"op": "STORE", "slot": 4},      # res
            {"op": "TEXT", "text": ", "},
            {"op": "TEMP_REG"},
            {"op": "TEXT", "text": ";\n"},
        ]
    },
]
```

### 5.2 Emit Opcode Bytecode

The template's `emit_ops` is a **flat array of emit opcodes** — no string scanning, no `find_reference`, no runtime pattern matching. Just a linear sequence of micro-operations:

```gdscript
# === Emit Opcode Enum ===
enum EmitOp {
    TEXT,        # append literal text
    LOAD,        # resolve $symbol → CPU-addressable text
    STORE,       # resolve ^symbol → store location text
    ADDR,        # resolve @symbol → address text
    TEMP_REG,    # allocate temp register (or stack spill)
    LABEL_DEF,   # emit label definition
    LABEL_REF,   # emit label reference (to be fixed up)
    OP_BODY,     # expand OP-specific body from op_data table
    BLOCK_REF,   # emit referenced code block (recursive compile)
    SCOPE_ENTER, # emit __ENTER_ placeholder
    SCOPE_LEAVE, # emit __LEAVE_ placeholder
    COMMIT_LOC,  # commit location range for current command
    CALL_ARGS,   # emit call argument push sequence
}
```

**Why this is faster**: Instead of scanning a template string character-by-character looking for `$`, `@`, `^` markers, the emitter iterates a `PackedInt32Array` of opcodes. Each opcode is a 4-byte integer — 16 opcodes fit in a cache line.

### 5.3 Op Data Table (SoA for Arithmetic Operations)

The current [`op_map`](../scenes/codegen_md.gd:12) is a Dictionary. The DOD version is a flat array:

```gdscript
# === OP Data Table (SoA) ===
# Indexed by opcode enum (ADD=0, SUB=1, MUL=2, etc.)
# Pre-compiled emit operations for each arithmetic op.

static var op_emit_ops: Array[PackedInt32Array]  # [n_ops]  — each is an EmitOp sequence + inline data
static var op_text_data: Array[PackedStringArray]  # [n_ops]  — TEXT data for each op
static var op_mono: PackedByteArray               # [n_ops]  — 1 if monadic (INC, DEC)

# Example: op_emit_ops[OP_ADD] =
#   [TEXT, TEXT_INDEX(0), TEMP_REG, TEXT_INDEX(1), LOAD, slot=2,
#    TEXT_INDEX(2), OP_ADD_BODY, TEMP_REG, TEXT_INDEX(3), STORE, slot=4]
# with op_text_data[OP_ADD] = ["mov ", ", ", ";\n", "mov ", ", ", ";\n"]
```

### 5.4 Template Bytecode Compilation (One-Time Cost)

At initialization, the template table is **compiled** from the human-readable format into the flat emit-op format:

```gdscript
static func compile_templates() -> void:
    # For each template in TEMPLATE_TABLE:
    #   1. Parse the body string once
    #   2. Convert markers ($, ^, @, {}, etc.) into EmitOp opcodes
    #   3. Extract literal text segments into a flat text pool
    #   4. Store the result as a PackedInt32Array
    # Result: template_bytecode[n] = compiled emit sequence for template n
    pass
```

---

## 6. The Emit Engine (Hot Path)

### 6.1 Flat Assembly Buffer

Instead of `cur_assy_block.code += text` (string concatenation), use a pre-allocated buffer:

```gdscript
# === Flat Assembly Buffer ===
# Pre-allocated to the estimated size (estimate from IR command count × avg instruction size).
# Filled sequentially — cache-friendly write pattern.
static var asm_buffer: PackedByteArray
static var asm_write_pos: int

# Parallel fixup list (for things that need post-processing)
static var fixup_entries: Array[FixupEntry]
struct FixupEntry:
    var asm_offset: int        # position in asm_buffer to patch
    var fixup_type: int        # enum: LABEL_REF, SCOPE_ENTER, SCOPE_LEAVE
    var fixup_key: String      # label name or scope name
```

### 6.2 Register Allocator (4-Bit Bitmask)

The register allocator is a **4-bit bitmask** on the hot path — not a Dictionary:

```gdscript
# === Hot Register Allocator ===
# 4 registers = 4 bits. Bit i = 1 means register i is in use.
static var reg_bitmask: int = 0  # bits 0-3 for EAX, EBX, ECX, EDX

# Constants
const REG_EAX_BIT = 0b0001
const REG_EBX_BIT = 0b0010
const REG_ECX_BIT = 0b0100
const REG_EDX_BIT = 0b1000
const REG_ALL_BITS = 0b1111

# Hot path — no heap allocation
static func alloc_register_hot() -> int:
    if not (reg_bitmask & REG_EAX_BIT):
        reg_bitmask |= REG_EAX_BIT
        return REG_EAX
    if not (reg_bitmask & REG_EBX_BIT):
        reg_bitmask |= REG_EBX_BIT
        return REG_EBX
    if not (reg_bitmask & REG_ECX_BIT):
        reg_bitmask |= REG_ECX_BIT
        return REG_ECX
    if not (reg_bitmask & REG_EDX_BIT):
        reg_bitmask |= REG_EDX_BIT
        return REG_EDX
    return REG_NONE  # spill to stack (cold path)

static func free_register_hot(reg: int) -> void:
    match reg:
        REG_EAX: reg_bitmask &= ~REG_EAX_BIT
        REG_EBX: reg_bitmask &= ~REG_EBX_BIT
        REG_ECX: reg_bitmask &= ~REG_ECX_BIT
        REG_EDX: reg_bitmask &= ~REG_EDX_BIT
```

**Why a bitmask**: 4 registers × 1 bit each = a single 32-bit integer. The entire register allocator state fits in a CPU register. Compare with the current `regs_in_use: Dictionary` which requires hash computation, memory allocation, and cache line fill for every access.

### 6.3 Location Map (Flat Arrays)

Instead of nested Dictionaries:

```gdscript
# === Flat Location Map ===
# Parallel arrays: for each (ip, location) pair, store the mapping.
# Scanned linearly when building the final location map.
static var loc_ips: PackedInt32Array          # [K] — sorted IPs
static var loc_ranges: Array[LocationRange]   # [K] — parallel array
static var loc_kind: PackedByteArray          # [K] — 0=begin, 1=end

# During codegen, we append to these arrays (sequential write).
# After codegen, we sort by IP and build the final Dictionary for the assembler.
```

### 6.4 Hot Path: Expand Template

```gdscript
static func expand_template(tmpl_idx: int, cmd_idx: int) -> void:
    var bytecode = template_bytecode[tmpl_idx]
    var text_data = template_text_data[tmpl_idx]
    var bc_pos = 0
    
    while bc_pos < len(bytecode):
        var opcode = bytecode[bc_pos]
        bc_pos += 1
        
        match opcode:
            EmitOp.TEXT:
                var text_idx = bytecode[bc_pos]
                bc_pos += 1
                append_text(text_data[text_idx])
            
            EmitOp.LOAD:
                var slot = bytecode[bc_pos]
                bc_pos += 1
                var operand = get_cmd_operand(cmd_idx, slot)
                var resolved = resolve_load(operand)
                append_text(resolved)
            
            EmitOp.STORE:
                var slot = bytecode[bc_pos]
                bc_pos += 1
                var operand = get_cmd_operand(cmd_idx, slot)
                var resolved = resolve_store(operand)
                append_text(resolved)
            
            EmitOp.TEMP_REG:
                var reg = alloc_register_hot()
                if reg == REG_NONE:
                    reg = spill_to_stack()  # cold path
                append_register_text(reg)
                temp_reg_stack.push_back(reg)
            
            EmitOp.OP_BODY:
                var op_slot = bytecode[bc_pos]
                bc_pos += 1
                var op_name = get_cmd_operand(cmd_idx, op_slot)
                var op_idx = op_name_to_index(op_name)
                expand_op_body(op_idx, cmd_idx)  # inline op-specific expansion
            
            EmitOp.BLOCK_REF:
                var slot = bytecode[bc_pos]
                bc_pos += 1
                var cb_name = get_cmd_operand(cmd_idx, slot)
                compile_code_block(cb_name)  # recursive, but tracked to avoid cycles
            
            EmitOp.LABEL_DEF:
                var slot = bytecode[bc_pos]
                bc_pos += 1
                var label_name = get_cmd_operand(cmd_idx, slot)
                emit_label_definition(label_name)
            
            EmitOp.LABEL_REF:
                var slot = bytecode[bc_pos]
                bc_pos += 1
                var label_name = get_cmd_operand(cmd_idx, slot)
                emit_label_reference(label_name)
            
            EmitOp.SCOPE_ENTER:
                var slot = bytecode[bc_pos]
                bc_pos += 1
                var scp_name = get_cmd_operand(cmd_idx, slot)
                append_text("__ENTER_%s;\n" % scp_name)
                record_fixup(asm_write_pos - len("__ENTER_..."), "SCOPE_ENTER", scp_name)
            
            EmitOp.SCOPE_LEAVE:
                var slot = bytecode[bc_pos]
                bc_pos += 1
                var scp_name = get_cmd_operand(cmd_idx, slot)
                append_text("__LEAVE_%s;\n" % scp_name)
                record_fixup(asm_write_pos - len("__LEAVE_..."), "SCOPE_LEAVE", scp_name)
            
            EmitOp.COMMIT_LOC:
                loc_ips.append(asm_write_pos)
                loc_ranges.append(cmd_locs[cmd_idx])
                loc_kind.append(0)  # begin
                loc_ips.append(asm_write_pos + cmd_size)
                loc_ranges.append(cmd_locs[cmd_idx])
                loc_kind.append(1)  # end
    
    # Free any temporary registers allocated during this expansion
    while not temp_reg_stack.is_empty():
        free_register_hot(temp_reg_stack.pop_back())
```

### 6.5 Operand Resolution (Table-Driven)

```gdscript
static func resolve_load(ir_name: String) -> String:
    var sym_idx = lookup_symbol(ir_name)  # O(1) via hash table, or binary search
    
    match sym_val_type[sym_idx]:
        VAL_IMMEDIATE:
            if sym_data_type[sym_idx] == DATA_INT:
                return sym_value[sym_idx]
            else:
                return sym_ir_name[sym_idx]  # label reference for string
        VAL_VARIABLE, VAL_TEMPORARY:
            match sym_storage_type[sym_idx]:
                STORAGE_GLOBAL: return "*%s" % sym_ir_name[sym_idx]
                STORAGE_STACK:  return "EBP[%d]" % sym_storage_pos[sym_idx]
                STORAGE_EXTERN: return "*%s" % sym_ir_name[sym_idx]
        VAL_CODE:
            return sym_ir_name[sym_idx]  # label reference
    
    return "<ERROR>"

static func resolve_store(ir_name: String) -> String:
    var sym_idx = lookup_symbol(ir_name)
    
    match sym_storage_type[sym_idx]:
        STORAGE_GLOBAL: return "*%s" % sym_ir_name[sym_idx]
        STORAGE_STACK:  return "EBP[%d]" % sym_storage_pos[sym_idx]
    
    return "<ERROR>"
```

---

## 7. Cold Path: Analysis Pass (Pass 1)

Pass 1 walks the IR once to **count and allocate** everything. No assembly output.

```gdscript
static func analyze(ir_data: Dictionary) -> void:
    # Step 1: Count everything
    var n_cmds = 0
    var n_operands = 0
    var n_syms = 0
    var n_scopes = 0
    var n_locs = 0
    
    for cb_key in ir_data.code_blocks:
        var cb = ir_data.code_blocks[cb_key]
        n_cmds += len(cb.code) if "code" in cb else 0
        for cmd in cb.code:
            n_operands += len(cmd.words)
            n_locs += 1
    
    for scp_key in ir_data.scopes:
        n_scopes += 1
        var scope = ir_data.scopes[scp_key]
        n_syms += len(scope.vars) + len(scope.funcs)
    
    # Step 2: Pre-allocate all flat arrays
    cmd_heads.resize(n_cmds)
    cmd_operand_offset.resize(n_cmds + 1)  # +1 for sentinel
    cmd_operand_count.resize(n_cmds)
    cmd_operands.resize(n_operands)
    cmd_locs.resize(n_locs)
    
    sym_ir_name.resize(n_syms)
    sym_val_type.resize(n_syms)
    sym_storage_type.resize(n_syms)
    sym_storage_pos.resize(n_syms)
    sym_value.resize(n_syms)
    sym_data_type.resize(n_syms)
    sym_needs_deref.resize(n_syms)
    sym_is_array.resize(n_syms)
    sym_array_size.resize(n_syms)
    
    scp_ir_name.resize(n_scopes)
    # ... etc
    
    # Step 3: Populate from IR data (single linear pass)
    # ...
    
    # Step 4: Build lookup table
    build_symbol_lookup()
```

**Why pre-allocate**: Prevents the GDScript array resize cascade. Each `append()` to a dynamic array can trigger a reallocation + copy. Pre-allocating to the exact size means all memory is allocated once, in a single contiguous chunk.

---

## 8. Hot Path: Template Expansion (Pass 2)

```gdscript
static func generate(ir_data: Dictionary) -> Dictionary:
    # ---- Pass 1: Analyze ----
    analyze(ir_data)
    
    # ---- Pass 2: Emit ----
    # Pre-allocate assembly buffer (estimate: n_cmds × 64 bytes per cmd)
    asm_buffer = PackedByteArray()
    asm_buffer.resize(len(cmd_heads) * 64)
    asm_write_pos = 0
    
    # Process code blocks in traversal order
    var cb_queue: PackedStringArray = [get_global_cb_name(ir_data)]
    var cb_emitted: Dictionary = {}  # bit set, could be PackedByteArray
    var cb_order: PackedStringArray = []
    
    while len(cb_queue) > 0:
        var cb_name = cb_queue.pop_front()
        if cb_name in cb_emitted:
            continue
        cb_emitted[cb_name] = true
        cb_order.append(cb_name)
        
        # Queue referenced code blocks
        var cb_cmds = get_cmds_for_block(cb_name)
        for cmd_idx in cb_cmds:
            var head = cmd_heads[cmd_idx]
            if head == CMD_CALL:
                var fun_name = get_cmd_operand(cmd_idx, 1)
                var cb_ref = get_func_code_block(fun_name)
                if cb_ref and cb_ref not in cb_queue:
                    cb_queue.append(cb_ref)
            # ... similar for IF, WHILE, etc.
    
    # Emit code blocks in order
    for cb_name in cb_order:
        emit_code_block(cb_name)
    
    # ---- Pass 3: Fixup ----
    apply_fixups()
    
    # Build final result
    var result_text = asm_buffer.get_string_from_ascii()
    result_text += generate_globals_text()
    
    return {
        "code": result_text,
        "loc_map": build_final_loc_map(),
        "write_pos": asm_write_pos,
    }
```

### 8.1 Code Block Emission

```gdstatic
static func emit_code_block(cb_name: String) -> void:
    var cb_cmds = get_cmds_for_block(cb_name)
    
    # Emit block header
    append_text(":%s:\n" % get_block_label_from(cb_name))
    
    # Emit each command (linear scan, cache-friendly)
    for cmd_idx in cb_cmds:
        var head = cmd_heads[cmd_idx]
        var tmpl_idx = cmd_head_to_template[head]  # O(1) lookup table
        expand_template(tmpl_idx, cmd_idx)
    
    # Maybe emit return
    if is_func_code_block(cb_name):
        append_text("__LEAVE_%s;\n" % get_scope_for_block(cb_name))
        append_text("ret;\n")
        record_fixup(asm_write_pos - len("__LEAVE_..."), "SCOPE_LEAVE", get_scope_for_block(cb_name))
    
    # Emit block footer
    append_text(":%s:\n" % get_block_label_to(cb_name))
```

---

## 9. Fixup Pass (Pass 3, Warm Path)

### 9.1 Enter/Leave Expansion

The `__ENTER_` and `__LEAVE_` placeholders are replaced in a **single string scan** — not per-scope string replacement:

```gdscript
static func apply_fixups() -> void:
    var text = asm_buffer.get_string_from_ascii()
    
    # Single pass: find all __ENTER_ and __LEAVE_ markers and replace
    # This is O(n) with good locality since we scan once.
    for fixup in fixup_entries:
        match fixup.fixup_type:
            FIXUP_SCOPE_ENTER:
                var scp_idx = lookup_scope(fixup.fixup_key)
                var stack_bytes = scp_local_vars_wp[scp_idx]
                var replacement = "sub ESP, %d" % (-stack_bytes)
                # Replace at the recorded offset
                text = text.substr(0, fixup.asm_offset) + replacement + text.substr(fixup.asm_offset + len(replacement))
            
            FIXUP_SCOPE_LEAVE:
                var scp_idx = lookup_scope(fixup.fixup_key)
                var stack_bytes = scp_local_vars_wp[scp_idx]
                var replacement = "add ESP, %d" % (-stack_bytes)
                text = text.substr(0, fixup.asm_offset) + replacement + text.substr(fixup.asm_offset + len(replacement))
```

**Optimization**: Instead of string slicing (which creates new strings), we could use a `PackedByteArray` and patch bytes in-place. But GDScript's string immutability makes this tricky. If performance demands it, we use `PackedByteArray` throughout.

### 9.2 Location Map Finalization

```gdscript
static func build_final_loc_map() -> LocationMap:
    var result = LocationMap.new()
    
    # Sort by IP (the loc_ips may not be in order due to recursive code block emission)
    # Use a simple linear build since IPs are mostly sequential
    for i in len(loc_ips):
        var ip = loc_ips[i]
        var range = loc_ranges[i]
        
        if loc_kind[i] == 0:  # begin
            if ip not in result.begin:
                result.begin[ip] = []
            result.begin[ip].append(range)
        else:  # end
            if ip not in result.end:
                result.end[ip] = []
            result.end[ip].append(range)
    
    return result
```

---

## 10. Memory Layout Summary

### Hot Data (Fits in L1/L2 Cache)

```
┌──────────────────────────────────────────┐
│ cmd_heads: PackedInt32Array    [4B × N]  │ ← sequential read
│ cmd_operand_offset: PackedInt32Array      │ ← sequential read
│ cmd_operand_count: PackedInt32Array       │ ← sequential read
│ reg_bitmask: int                [4B]       │ ← CPU register
│ asm_buffer: PackedByteArray    [1B × M]   │ ← sequential write
│ template_bytecode: PackedInt32Array[4B×K] │ ← sequential read
└──────────────────────────────────────────┘
```

### Cold Data (L3 Cache / RAM)

```
┌──────────────────────────────────────────┐
│ sym_*: parallel arrays           [large]   │ ← random access by symbol index
│ scp_*: parallel arrays           [small]   │ ← accessed per scope boundary
│ loc_*: parallel arrays           [small]   │ ← accessed at fixup time
│ fixup_entries: Array             [small]   │ ← accessed at fixup time
│ cmd_operands: PackedStringArray  [large]   │ ← random access by operand index
│ cmd_locs: Array[LocationRange]   [medium]  │ ← accessed at location commit
└──────────────────────────────────────────┘
```

---

## 11. Comparison: Current vs. DOD Codegen

| Aspect | Current [`codegen_md.gd`](../scenes/codegen_md.gd) | Data-Oriented Codegen |
|--------|-------|----------------------|
| **Memory for 1000 commands** | 1000 `IR_Cmd` objects × ~128 bytes = ~128KB, scattered across heap | 1 `PackedInt32Array` × 4KB for heads + operands = ~8KB, contiguous |
| **Symbol lookup** | `all_syms[name]` → hash computation → cache miss | `sym_lookup[hash % size]` → direct array index, or binary search on sorted array |
| **Register allocator** | `Dictionary` with hash lookups | 4-bit integer bitmask (CPU register) |
| **Template resolution** | `find_reference` string scan per `$`/`@`/`^` | Pre-compiled emit opcode sequence (integer array) |
| **Assembly output** | String concatenation (`+=`) | Pre-allocated `PackedByteArray` fill |
| **Location map** | Nested `Dictionary` of `Dictionary` of `Array` | Flat parallel arrays, sorted at end |
| **Code block traversal** | Recursive with stack of `RefCounted` references | Flat array iteration with integer indices |
| **Scope stack** | Array of Dictionary references | Integer index into flat scope arrays |
| **Memory allocation** | Ad-hoc, per-object allocation | Bulk pre-allocation in analyze pass |
| **Cache misses per command** | 10-20 (object dereferences, hash lookups, string scans) | 2-4 (sequential array reads, direct index lookups) |
| **Debug tracing** | Runtime `if ADD_DEBUG_TRACE` branch on every emit | Removed from hot path; separate tool for trace |

---

## 12. Implementation Strategy

### Phase 1: Data Structures (Module: `codegen_data.gd`)

1. Implement flat SoA arrays for IR commands (migration from `IR_Cmd` objects)
2. Implement flat symbol table with lookup
3. Implement flat scope table
4. Implement template compilation (body string → emit opcode bytecode)
5. Implement op data table

### Phase 2: Emit Engine (Module: `codegen_emit.gd`)

1. Implement assembly buffer (pre-allocated `PackedByteArray`)
2. Implement bitmask register allocator
3. Implement template expander (opcode interpreter)
4. Implement operand resolvers (load/store/address)
5. Implement location tracker (flat arrays)

### Phase 3: Codegen Driver (Module: `codegen_md_dod.gd`)

1. Implement 3-pass pipeline (Analyze → Expand → Fixup)
2. Implement code block traversal (reachability + topological order)
3. Implement fixup pass (enter/leave → sub/add, label resolution)
4. Implement global data emission
5. Wire into [`comp_compile_md.gd`](../scenes/comp_compile_md.gd) as a drop-in replacement

### Phase 4: Testing & Validation

1. Bit-exact output comparison with current codegen on all test programs
2. Profile: measure cache misses, allocation counts, wall-clock time
3. Test edge cases: nested scopes, indirect calls, array operations, string literals

---

## 13. Key Design Decisions

### Decision 1: Why SoA over AoS?

**Structure-of-Arrays** for the hot path because:
- Iterating over `cmd_heads` reads 4 bytes per command × 8 commands per cache line
- AoS would read: object pointer (8B) → dispatch → read object fields → each field may be in different cache lines
- SoA gives **predictable, linear memory access** — the prefetcher can keep up

### Decision 2: Why Pre-Compiled Template Bytecode?

The current approach of scanning template strings at emit time for `$`, `@`, `^` markers means every emit call does O(body_length) string operations. With pre-compiled bytecode:
- Template body is parsed **once** at init
- Emit time is a tight loop over `PackedInt32Array` — no string allocation, no character scanning
- Template bytecode can be **shared** across all commands of the same type

### Decision 3: Why Bitmask Register Allocator?

For 4 registers, a hash map is absurd. A 4-bit bitmask:
- Lives in a CPU register (no memory access)
- Allocation = bit test + set (2 ALU ops)
- Free = bit clear (1 ALU op)
- Zero heap allocation

### Decision 4: Why Pre-Allocated Assembly Buffer?

String concatenation in a loop is O(n²) due to repeated copying. Pre-allocating a `PackedByteArray`:
- Single contiguous allocation
- Sequential fill — cache-friendly write pattern
- Convert to string once at the end

### Decision 5: Why Three-Pass Design?

- **Pass 1 (Analyze)**: Counts and allocates. Must happen before any emit because we need to know symbol sizes, label counts, etc. This is **cold path** — runs once, can tolerate some cache misses.
- **Pass 2 (Expand)**: The hot path. Pure sequential processing of flat arrays. Must be maximally cache-friendly.
- **Pass 3 (Fixup)**: Warm path. Post-processes the assembly buffer. Runs once, tolerates random access.

---

## 14. Edge Cases and Their Data-Oriented Solutions

### Indirect Calls
The current codegen handles `CALL_INDIRECT` as a special case. In the DOD design, indirect calls use the same `CALL` template but with a different slot binding — the function operand is resolved via `LOAD` instead of `ADDR`.

### Array Operations (MOV_ARR)
Current codegen has a special [`generate_cmd_mov_arr`](../scenes/codegen_md.gd:734). In the DOD design, `MOV_ARR` is a **multi-instruction template** — the emit bytecode includes a loop that expands N `mov *ptr, $val; add ptr, 4;` sequences. Since the array size is known at compile time, the bytecode is fully unrolled.

### Nested Scopes
Current codegen uses [`enter_scope`](../scenes/codegen_md.gd:234) / [`leave_scope`](../scenes/codegen_md.gd:238) with a stack. In the DOD design, scope is tracked as **an integer index** — the current scope index is part of the hot path state (a single integer, not a stack). The ENTER/LEAVE templates emit placeholders that are fixed up in Pass 3.

### String Constants
String constants (immediates with `data_type == "string"`) are allocated in the global data section during Pass 1. Their storage is known before Pass 2 begins, so the `LOAD` opcode can resolve them to label references.

---

## 15. File Structure

```
plans/
├── data_oriented_codegen_plan.md     ← this file
scenes/
├── codegen_md_dod.gd                 ← new DOD codegen (replaces codegen_md.gd)
├── codegen_data.gd                   ← flat data structures & template compilation
├── codegen_emit.gd                   ← emit engine & template interpreter
```

The existing [`codegen_md.gd`](../scenes/codegen_md.gd) is preserved during development for A/B comparison. Once the DOD codegen passes all tests, the old file is removed.

---

## 16. Summary

This data-oriented design replaces **object indirection, hash map scattering, string scanning, and ad-hoc allocation** with:

- **Flat arrays** (PackedInt32Array, PackedByteArray) for all hot-path data
- **Pre-compiled template bytecode** for zero-scan emit
- **4-bit bitmask** for register allocation
- **Pre-allocated assembly buffer** for linear write
- **Three-pass pipeline** to separate cold counting from hot emitting
- **Structure-of-arrays** layout for cache-friendly iteration

The result is a codegen that respects the CPU's memory hierarchy — the hot path operates on contiguous memory, the critical data structures fit in L1 cache, and the cold paths are cleanly separated.
