# A Literate Codegen Plan

> *"Let us change our traditional attitude to the construction of programs: Instead of imagining that our main task is to instruct a computer what to do, let us concentrate rather on explaining to human beings what we want a computer to do."* — Donald Knuth

**Author**: Literate Programming Advocate  
**Philosophy**: Programs are written for humans first. Code embedded in documentation, not the other way around. Tangling extracts code; weaving formats documentation.

---

## 1. Orientation: What We Have and What We Need

The project CpuDerp is a custom CPU emulator in Godot. Its compilation pipeline passes through several stages:

```
Source text  →  [parser_md.gd]  →  AST  →  [ir_md.gd]  →  IR (YAML)  →  [codegen_md.gd]  →  Assembly text  →  [comp_asm_zd.gd]  →  Machine code
```

The stage we care about is **IR → Assembly**, currently implemented in [`scenes/codegen_md.gd`](scenes/codegen_md.gd). This file has grown to 833 lines through accretion rather than design. It works, but it is difficult to extend, test, or reason about.

This document is itself an example of literate programming: I will explain the design in human-readable prose, with code sections embedded where they illuminate the discussion. The actual implementation would be **tangled** (extracted) from this document by a literate programming tool, producing the final source files.

### 1.1 The Tangling Contract

Throughout this document, code blocks are marked with a **tangle target** — the file they should be extracted into. For example, a section marked `→ codegen_engine.gd` would be extracted into `scenes/codegen_engine.gd`. A section marked `→ template_defs.gd` would become a data file.

The **weaving** process assembles this markdown into the document you are reading now. The **tangling** process extracts the code, discarding the prose, to produce compilable source files.

---

## 2. Architecture Overview

Before diving into code, let me describe the architecture at a high level. The existing codegen [`scenes/codegen_md.gd`](scenes/codegen_md.gd) treats every IR command type as a special case — a `match` statement on [`line 268`](scenes/codegen_md.gd:268) dispatches to fifteen distinct `generate_cmd_*` methods. Each of those methods manually:

1. Extracts operands from the IR command's word array
2. Allocates registers or temporaries
3. Constructs assembly text via string formatting
4. Emits the text with size accounting and location tracking

This is ad-hoc. The knowledge of *how an IR instruction maps to assembly* is scattered across fifteen functions, interleaved with register management, label generation, and location bookkeeping.

**The central insight of a data-driven design**: the mapping from IR to assembly *is data*, not code. It is a table of patterns. If we can describe each IR instruction's assembly expansion as a declarative template, then we can reduce the entire codegen to a single engine that interprets those templates.

Here is the architecture in schematic form:

```text
 ┌─────────────────────────────────────────────────────────┐
 │                    Template Table                        │
 │  (a data structure: IR opcode → assembly template)      │
 └──────────────────────┬──────────────────────────────────┘
                        │ consulted by
                        ▼
 ┌─────────────────────────────────────────────────────────┐
 │                   Pattern Matcher                        │
 │  (matches IR_Cmd words against template patterns,       │
 │   binds operands to slot names)                         │
 └──────────────────────┬──────────────────────────────────┘
                        │ produces
                        ▼
 ┌─────────────────────────────────────────────────────────┐
 │                    Slot Resolver                         │
 │  (replaces {slot} references with concrete assembly     │
 │   text: register names, memory operands, labels)        │
 └──────────────────────┬──────────────────────────────────┘
                        │ produces
                        ▼
 ┌─────────────────────────────────────────────────────────┐
 │                      Emitter                             │
 │  (assembles final text, tracks write position,          │
 │   records location map for debug)                       │
 └─────────────────────────────────────────────────────────┘
```

Each stage is a separate pass. This is the classic **pipeline** pattern: data flows from one stage to the next, and each stage has a single responsibility.

### 2.1 Why a Pipeline?

The existing code interleaves all these concerns. Look at [`emit()`](scenes/codegen_md.gd:474):

```gdscript
# This is lines 474-532 of the existing codegen.
# It handles: operand lookup, dereference, register allocation,
# promotion, address resolution, store-back, AND text emission.
# Five concerns, one function.
func emit(text:String, wp_diff:int, dbg_trace:String)->void:
    var imm_flag = false;
    var allocs = [];
    while true:
        var ref_load = find_reference(text, "$");
        if not ref_load: break;
        var res = load_value(ref_load.val);
        ...
```

A pipeline separates these concerns so that:

- Each pass is testable in isolation
- A pass can be replaced without touching the others
- The overall flow is visible in a single `generate()` function

---

## 3. The Template Data Structure

The core of the design is the **template table**. This is pure data — a Dictionary that maps IR instruction patterns to their assembly expansions.

Let me define the data structure first, then show how it is used.

```gdscript
# → template_defs.gd
# Template definitions for IR → Assembly code generation.
#
# Each entry maps an IR opcode (or opcode pattern) to a template.
# A template has:
#   - `pattern`:   the IR command words with named slots
#   - `assembly`:  one or more assembly lines with {slot} references
#   - `size`:      the total byte size of the emitted instructions
#   - `slots`:     the named operands that will be resolved
#   - `guard`:     optional condition for parametric selection

const template_table = {
    # --- Simple 1:1 mapping ---
    "MOV": {
        "pattern":   ["MOV", "dest", "src"],
        "assembly":  ["mov {dest}, {src};"],
        "size":      8,
        "slots":     ["dest", "src"],
    },
    
    # --- ALU operations with opcode dispatch ---
    # The key format "OP:{alu_op}" allows parametric lookup
    "OP:ADD": {
        "pattern":   ["OP", "ADD", "a", "b", "res"],
        "assembly":  ["add {a}, {b};"],
        "size":      8,
        "slots":     ["a", "b", "res"],
    },
    "OP:SUB": {
        "pattern":   ["OP", "SUB", "a", "b", "res"],
        "assembly":  ["sub {a}, {b};"],
        "size":      8,
        "slots":     ["a", "b", "res"],
    },
    "OP:MUL": {
        "pattern":   ["OP", "MUL", "a", "b", "res"],
        "assembly":  ["mul {a}, {b};"],
        "size":      8,
        "slots":     ["a", "b", "res"],
    },
    "OP:DIV": {
        "pattern":   ["OP", "DIV", "a", "b", "res"],
        "assembly":  ["div {a}, {b};"],
        "size":      8,
        "slots":     ["a", "b", "res"],
    },
    "OP:MOD": {
        "pattern":   ["OP", "MOD", "a", "b", "res"],
        "assembly":  ["mod {a}, {b};"],
        "size":      8,
        "slots":     ["a", "b", "res"],
    },
    
    # --- Comparison operations: multi-instruction expansions ---
    "OP:EQUAL": {
        "pattern":   ["OP", "EQUAL", "a", "b", "res"],
        "assembly":  [
            "cmp {a}, {b};",
            "mov {res}, CTRL;",
            "band {res}, CMP_Z;",
            "bnot {res};",
            "bnot {res};",
        ],
        "size":      40,   # 5 instructions × 8 bytes
        "slots":     ["a", "b", "res"],
    },
    "OP:NOT_EQUAL": {
        "pattern":   ["OP", "NOT_EQUAL", "a", "b", "res"],
        "assembly":  [
            "cmp {a}, {b};",
            "mov {res}, CTRL;",
            "band {res}, CMP_NZ;",
            "bnot {res};",
            "bnot {res};",
        ],
        "size":      40,
        "slots":     ["a", "b", "res"],
    },
    "OP:GREATER": {
        "pattern":   ["OP", "GREATER", "a", "b", "res"],
        "assembly":  [
            "cmp {a}, {b};",
            "mov {res}, CTRL;",
            "band {res}, CMP_G;",
            "bnot {res};",
            "bnot {res};",
        ],
        "size":      40,
        "slots":     ["a", "b", "res"],
    },
    "OP:LESS": {
        "pattern":   ["OP", "LESS", "a", "b", "res"],
        "assembly":  [
            "cmp {a}, {b};",
            "mov {res}, CTRL;",
            "band {res}, CMP_L;",
            "bnot {res};",
            "bnot {res};",
        ],
        "size":      40,
        "slots":     ["a", "b", "res"],
    },
    
    # --- Unary operations ---
    "OP:INC": {
        "pattern":   ["OP", "INC", "a", "NONE", "res"],
        "assembly":  ["inc {a};"],
        "size":      8,
        "slots":     ["a", "res"],
    },
    "OP:DEC": {
        "pattern":   ["OP", "DEC", "a", "NONE", "res"],
        "assembly":  ["dec {a};"],
        "size":      8,
        "slots":     ["a", "res"],
    },
    
    # --- Stack operations ---
    "ENTER": {
        "pattern":   ["ENTER", "scope"],
        "assembly":  ["__ENTER_{scope};"],
        "size":      8,
        "slots":     ["scope"],
    },
    "LEAVE": {
        "pattern":   ["LEAVE"],
        "assembly":  ["__LEAVE_{scope};"],
        "size":      8,
        "slots":     ["scope"],
    },
    "RETURN": {
        "pattern":   ["RETURN"],
        "assembly":  [
            "__LEAVE_{scope};",
            "ret;",
        ],
        "size":      16,
        "slots":     ["scope"],
    },
    "RETURN:val": {
        "pattern":   ["RETURN", "res"],
        "assembly":  [
            "mov EAX, {res};",
            "__LEAVE_{scope};",
            "ret;",
        ],
        "size":      24,
        "slots":     ["res", "scope"],
    },
}
```

**Why is this better than the existing `op_map` on line 12 of `codegen_md.gd`?**

Compare:

```gdscript
# OLD: line 12-25 of codegen_md.gd
const op_map = {
    "EQUAL": "cmp %a, %b; mov %a, CTRL; band %a, CMP_Z; bnot %a; bnot %a;\n",
    ...
};
```

The old version uses positional placeholders (`%a`, `%b`) — a custom mini-language embedded in a string. The new version uses named slots (`{a}`, `{b}`, `{res}`) in an explicit data structure. This matters because:

1. **Named slots are self-documenting** — `{res}` tells you what it is.
2. **The slot list is explicit** — the engine knows which operands to resolve.
3. **Multi-line expansions are natural arrays** — no need for string concatenation.
4. **Metadata (size) is adjacent to the template** — no separate calculation.

### 3.1 Immediate and INDEX Handling

Some operations need special treatment. The `INDEX` operation in the current code (line 20 of `codegen_md.gd`) just emits `add %a, %b;` and sets a `needs_deref` flag. This is because indexing is address calculation, and the dereference happens when the value is *used*, not when it is *computed*.

In the data-driven design, this becomes an **operand flag** rather than a template concern:

```gdscript
# → template_defs.gd (continued)

const template_table = merge_tables(template_table, {
    "OP:INDEX": {
        "pattern":   ["OP", "INDEX", "a", "b", "res"],
        "assembly":  ["add {a}, {b};"],
        "size":      8,
        "slots":     ["a", "b", "res"],
        "flags":     {"res": {"needs_deref": true}},
    },
})
```

The `flags` field annotates individual slots with metadata. The Slot Resolver pass checks these flags when constructing the final assembly operand — if `needs_deref` is true, it wraps the operand in an extra dereference.

---

## 4. The Pattern Matcher

Given an [`IR_Cmd`](class_IR_cmd.gd) (which has a `words: Array[String]`), the Pattern Matcher finds the matching template and binds the operands.

```gdscript
# → codegen_engine.gd

class_name PatternMatcher
extends RefCounted

## Matches IR commands against the template table and produces
## a Binding: a dictionary of slot-name → IR-value-name.

var _templates: Dictionary  # initialized from template_defs.gd

func _init(templates: Dictionary) -> void:
    _templates = templates

## Match an IR_Cmd against the template table.
## Returns a Binding (slot_name → IR value handle), or null if no match.
func match(cmd: IR_Cmd) -> Dictionary:
    var op = cmd.words[0]
    var op2 = "" if cmd.words.size() < 2 else cmd.words[1]
    
    # Try specific key first: "OP:EQUAL", then fall back to "OP"
    var key = op if op2.is_empty() else "%s:%s" % [op, op2]
    var template = _templates.get(key)
    if template == null:
        template = _templates.get(op)
    if template == null:
        push_error("PatternMatcher: no template for [%s]" % key)
        return {}
    
    # Bind pattern slots to actual command words
    var binding = {}
    var pattern: Array = template.pattern
    for i in range(1, pattern.size()):
        var slot_name: String = pattern[i]
        if slot_name.begins_with("{"):
            # Positional binding: skip positional markers like [dest, src]
            continue
        if i < cmd.words.size():
            binding[slot_name] = cmd.words[i]
        else:
            # Slot is missing from command — maybe a default?
            binding[slot_name] = "NONE"
    
    binding["_template"] = template
    binding["_template_key"] = key
    return binding
```

The matcher implements a **two-level lookup**: it first tries a compound key like `"OP:EQUAL"`, then falls back to a simple key like `"OP"`. This allows parametric templates where the expansion depends on an operand value.

### 4.1 Parametric Templates

Consider the existing [`generate_cmd_op()`](scenes/codegen_md.gd:294). It currently uses `op_map` for the core expansion, then manually handles the `res` copy and temporary allocation. In the data-driven design, the templates for ADD, SUB, MUL, DIV, MOD, EQUAL, etc. are all separate entries keyed by `"OP:{op}"`.

This is **data-driven dispatch**: instead of a `match` statement with fifteen arms, we have a Dictionary lookup. Adding a new ALU operation means adding a new entry to the template table — no code changes, no new functions.

---

## 5. The Slot Resolver

Once we have a Binding (slot names → IR value handles), we need to resolve each operand to its concrete assembly representation. This is where the complexity of memory addressing, register allocation, and dereference lives.

```gdscript
# → codegen_engine.gd (continued)

class_name SlotResolver
extends RefCounted

## Resolves symbolic operand references like {dest} or {src}
## into concrete assembly text (register names, memory operands, labels).

var _all_syms: Dictionary   # the all_syms table from the IR
var _reg_alloc: RegisterAllocator

func _init(all_syms: Dictionary) -> void:
    _all_syms = all_syms
    _reg_alloc = RegisterAllocator.new()

## Given a binding and a scope, resolve each slot to an assembly fragment.
## Returns a Dictionary: slot_name → resolved_assembly_string.
func resolve(binding: Dictionary, scope: Dictionary) -> Dictionary:
    var template: Dictionary = binding["_template"]
    var resolved = {}
    
    for slot_name in template.slots:
        var ir_name: String = binding.get(slot_name, "")
        if ir_name.is_empty() or ir_name == "NONE":
            resolved[slot_name] = ""
            continue
        
        var handle = _all_syms.get(ir_name)
        if handle == null:
            push_error("SlotResolver: unknown symbol [%s]" % ir_name)
            continue
        
        var slot_flags = template.get("flags", {}).get(slot_name, {})
        var resolved_str = _resolve_operand(handle, slot_flags)
        resolved[slot_name] = resolved_str
    
    return resolved

func _resolve_operand(handle: Dictionary, flags: Dictionary) -> String:
    # Dispatch based on the value's type and storage
    match handle.val_type:
        "immediate":
            if handle.data_type == "string":
                return handle.ir_name  # label reference to string data
            else:
                return handle.value    # literal integer
        "code":
            # Code blocks are labels in assembly
            return handle.ir_name
        "label":
            return handle.ir_name
        _:
            # Variables, temporaries, params, etc. — need storage resolution
            return _resolve_storage(handle, flags)

func _resolve_storage(handle: Dictionary, flags: Dictionary) -> String:
    var storage = handle.get("storage", {})
    match storage.get("type"):
        "global":
            return "*%s" % handle.ir_name
        "stack":
            return "EBP[%d]" % storage.pos
        "extern":
            return "*%s" % handle.ir_name
        _:
            push_error("SlotResolver: unknown storage type [%s]" % storage.get("type"))
            return "ERROR"
```

### 5.1 Register Allocation as a Separate Concern

In the existing code, register allocation is interleaved with template expansion in [`emit()`](scenes/codegen_md.gd:474). In the new design, it becomes a separate pass that runs *before* the Slot Resolver:

```gdscript
# → codegen_engine.gd (continued)

class_name RegisterAllocator
extends RefCounted

## Manages the four general-purpose registers: EAX, EBX, ECX, EDX.
## This is a simple allocator that reserves and frees registers.

const REGS = ["EAX", "EBX", "ECX", "EDX"]

var _in_use = {}

func reset() -> void:
    _in_use = {}

func alloc() -> String:
    for reg in REGS:
        if not _in_use.get(reg, false):
            _in_use[reg] = true
            return reg
    return ""  # no free registers — caller must spill to stack

func free(reg: String) -> void:
    _in_use[reg] = false

func is_free(reg: String) -> bool:
    return not _in_use.get(reg, false)
```

This separation means we can test register allocation without invoking the full codegen pipeline. If we later want a better algorithm (e.g., graph coloring), we replace only this class.

### 5.2 Dereference Handling

The existing code handles `needs_deref` by injecting extra `mov` instructions during emission (see [`emit()`](scenes/codegen_md.gd:482-488)). In the new design, the Slot Resolver checks the slot flags and produces a multi-part operand:

```gdscript
# Within _resolve_operand, after resolving storage:
func _resolve_with_deref(handle: Dictionary, flags: Dictionary) -> Dictionary:
    # Returns a "fragment" that may have pre/post instructions
    var base = _resolve_storage(handle, flags)
    var needs_deref = flags.get("needs_deref", false)
    
    if needs_deref:
        # Emit: mov tmp, base; mov tmp, *tmp
        var tmp = _reg_alloc.alloc()
        return {
            "prologue": [
                "mov %s, %s;" % [tmp, base],
                "mov %s, *%s;" % [tmp, tmp],
            ],
            "operand": tmp,
            "epilogue": [
                # free tmp after use
            ],
            "_tmp": tmp,
        }
    else:
        return {
            "prologue": [],
            "operand": base,
            "epilogue": [],
        }
```

The prologue and epilogue instructions are assembled into the final output by the Emitter. This is much cleaner than the loop-based approach in the current code, where instruction injection happens mid-string-replacement.

---

## 6. The Emitter

The final stage concatenates resolved fragments into the assembly output, tracking write position and location information.

```gdscript
# → codegen_engine.gd (continued)

class_name Emitter
extends RefCounted

## Emits final assembly text with location tracking.

var _assy_block: AssyBlock
var _trace_enabled: bool = false

func begin(trace: bool = false) -> void:
    _assy_block = AssyBlock.new()
    _trace_enabled = trace

func get_result() -> AssyBlock:
    return _assy_block

## Emit a resolved template: substitute slot references with resolved operands.
func emit_template(template: Dictionary, resolved: Dictionary, 
                   loc: LocationRange, ir_trace: String = "") -> void:
    if _trace_enabled and not ir_trace.is_empty():
        _emit_raw("# IR: %s\n" % ir_trace, 0)
    
    var assembly_lines: Array = template.assembly
    var total_size: int = template.size
    var line_size: int = total_size / max(assembly_lines.size(), 1)
    
    for line in assembly_lines:
        var expanded = _substitute_slots(line, resolved)
        _mark_loc_begin(loc)
        _emit_raw(expanded, line_size)
        _mark_loc_end(loc)

func _substitute_slots(text: String, resolved: Dictionary) -> String:
    # Replace {slot_name} with resolved operand text
    var result = text
    for slot_name in resolved:
        var operand_text = resolved[slot_name]
        result = result.replace("{%s}" % slot_name, operand_text)
    return result

func _emit_raw(text: String, size: int) -> void:
    _assy_block.code += text
    _assy_block.write_pos += size

func _mark_loc_begin(loc: LocationRange) -> void:
    var wp = _assy_block.write_pos
    if not _assy_block.loc_map.begin.has(wp):
        _assy_block.loc_map.begin[wp] = []
    _assy_block.loc_map.begin[wp].append(loc)

func _mark_loc_end(loc: LocationRange) -> void:
    var wp = _assy_block.write_pos
    if not _assy_block.loc_map.end.has(wp):
        _assy_block.loc_map.end[wp] = []
    _assy_block.loc_map.end[wp].append(loc)
```

The Emitter is intentionally simple. It takes a template, a resolved binding, and emits text. It does not know about registers, memory operands, or IR values — those concerns have been handled by earlier passes. This is the **Single Responsibility Principle** in action.

---

## 7. Assembling the Pipeline

The [`generate()`](scenes/codegen_md.gd:143) function in the current code orchestrates the whole process. In the new design, it becomes a simple pipeline:

```gdscript
# → codegen_engine.gd (continued)

class_name CodegenPipeline
extends RefCounted

## The top-level pipeline that orchestrates IR → Assembly code generation.

var _templates: Dictionary = template_table
var _matcher: PatternMatcher
var _slot_resolver: SlotResolver
var _emitter: Emitter
var _reg_alloc: RegisterAllocator

var _all_syms: Dictionary
var _ir: Dictionary

func _init() -> void:
    _matcher = PatternMatcher.new(_templates)
    _emitter = Emitter.new()
    _reg_alloc = RegisterAllocator.new()

func reset() -> void:
    _all_syms = {}
    _ir = {}
    _reg_alloc.reset()

## Generate assembly from IR data.
func generate(ir: Dictionary) -> AssyBlock:
    reset()
    _ir = ir
    _build_sym_table()
    
    _emitter.begin(ADD_IR_TRACE)
    
    var referenced_cbs = _collect_referenced_codeblocks()
    var emitted_cbs = []
    
    while not referenced_cbs.is_empty():
        var cb = referenced_cbs.pop_front()
        if cb in emitted_cbs:
            continue
        emitted_cbs.append(cb)
        _emit_codeblock(cb, referenced_cbs)
    
    _fixup_enter_leave()
    
    var globals_text = _generate_globals()
    _emitter.get_result().code += globals_text
    
    return _emitter.get_result()
```

### 7.1 Emitting a Code Block

The core of the pipeline is [`_emit_codeblock()`](scenes/codegen_md.gd:179), which replaces the current `generate_code_block()`:

```gdscript
# → codegen_engine.gd (continued)

func _emit_codeblock(cb: CodeBlock, referenced_cbs: Array) -> void:
    var scope = _find_scope_for_codeblock(cb.ir_name)
    
    _emitter.emit_template(
        _make_label_template(cb.lbl_from),
        {}, null, ""
    )
    
    if cb.code.is_empty():
        return
    
    var i = 0
    while i < cb.code.size():
        var cmd: IR_Cmd = cb.code[i]
        var binding = _matcher.match(cmd)
        if binding.is_empty():
            i += 1
            continue
        
        var cur_scope = _get_current_scope()
        var resolved = _slot_resolver.resolve(binding, cur_scope)
        
        _emitter.emit_template(
            binding["_template"],
            resolved,
            cmd.loc,
            " ".join(PackedStringArray(cmd.words))
        )
        
        i += 1
    
    _emitter.emit_template(
        _make_label_template(cb.lbl_to),
        {}, null, ""
    )

func _make_label_template(label: String) -> Dictionary:
    return {
        "assembly": [":%s:\n" % label],
        "size": 0,
        "slots": [],
    }
```

Notice that there is no `match` statement dispatching to fifteen different functions. Every IR command — whether `MOV`, `OP:EQUAL`, `CALL`, `IF`, `WHILE`, `ENTER`, or `RETURN` — flows through the same path: **match → resolve → emit**.

### 7.2 Control Flow Templates

Control flow instructions like `IF`, `ELSE`, and `WHILE` need labels and conditional jumps. These are still templates, but they require the Pattern Matcher to generate fresh labels as part of binding:

```gdscript
# → template_defs.gd (continued)

const template_table = merge_tables(template_table, {
    "IF": {
        "pattern":   ["IF", "cb_cond", "res", "cb_block"],
        "assembly":  [
            "{cb_cond}",                        # inline the condition code block
            "cmp {res}, {_imm0};",              # compare result to 0
            "jz {_lbl_else};",                  # jump to else if zero
            "{cb_block}",                       # inline the then-block
            "jmp {_lbl_end};",                  # jump past else
            ":{_lbl_else}:",                    # else label
            ":{_lbl_end}:",                     # end label
        ],
        "size":      0,   # dynamic: depends on inlined blocks
        "slots":     ["cb_cond", "res", "cb_block"],
        "auto_labels": ["_lbl_else", "_lbl_end"],
        "auto_imm": {"_imm0": 0},
    },
    
    "WHILE": {
        "pattern":   ["WHILE", "cb_cond", "res", "cb_block", "lbl_next", "lbl_end"],
        "assembly":  [
            ":{lbl_next}:",
            "{cb_cond}",
            "cmp {res}, {_imm0};",
            "jz {lbl_end};",
            "{cb_block}",
            "jmp {lbl_next};",
            ":{lbl_end}:",
        ],
        "size":      0,
        "slots":     ["cb_cond", "res", "cb_block", "lbl_next", "lbl_end"],
        "auto_imm": {"_imm0": 0},
    },
    
    "CALL": {
        "pattern":   ["CALL", "fun", "[", "...args", "]", "res"],
        "assembly":  [
            # args are pushed in reverse order (handled by Slot Resolver)
            "{_push_args}",
            "call @{fun};",
            "add ESP, {_args_size};",
            "mov {res}, eax;",
        ],
        "size":      24,  # minimum; args add more
        "slots":     ["fun", "res"],
        "virtual_slots": ["_push_args", "_args_size"],
    },
})
```

The `auto_labels` mechanism tells the Pattern Matcher to generate fresh labels automatically. The `auto_imm` mechanism creates immediate values (like the integer `0` for comparison). The `virtual_slots` mechanism invokes a resolver callback to generate the push instructions for function arguments.

These are **parametrized templates** — the template is not just a string, but a structure that can generate new symbols, create immediates, and invoke subroutines. Yet the template remains *data*, not code.

---

## 8. The Fixup Pass

The existing code uses a string-replace fixup for `__ENTER_`/`__LEAVE_` placeholders (see [`fixup_enter_leave()`](scenes/codegen_md.gd:754)). In the new design, the fixup is a **post-processing pass**:

```gdscript
# → codegen_engine.gd (continued)

class_name FixupPass
extends RefCounted

## Post-processing pass that replaces __ENTER_scope and __LEAVE_scope
## placeholders with actual stack adjustment instructions.

func run(assy_block: AssyBlock, ir: Dictionary) -> void:
    var code = assy_block.code
    
    for key in ir.scopes:
        var scope = ir.scopes[key]
        var scp_name = scope.ir_name
        var stack_bytes = scope.local_vars_write_pos
        
        code = code.replace(
            "__ENTER_%s;" % scp_name,
            "sub ESP, %d;" % (-stack_bytes)
        )
        code = code.replace(
            "__LEAVE_%s;" % scp_name,
            "sub ESP, %d;" % stack_bytes
        )
    
    assy_block.code = code
```

This is a pure transformation: it takes an `AssyBlock`, applies string replacements, and returns it. It has no side effects and does not interact with the operand resolver or register allocator.

### 8.1 Are String Replacements "Bad"?

A strict data-driven purist might argue that the fixup should use a structured representation rather than string replacement. But the literate programmer asks: *what is clearest for the human reader?*

The template `"__ENTER_{scope};"` is immediately understandable as a placeholder. The fixup function that replaces it with `"sub ESP, N;"` is a simple, linear transformation. This is not a compromise — it is a deliberate choice that prioritizes clarity over architectural purity. As Knuth would say, we are explaining to humans what we want the computer to do.

---

## 9. Tangling: What the Extracted Files Look Like

When we **tangle** this document, the code blocks marked with `→ codegen_engine.gd` would be extracted into `scenes/codegen_engine.gd`. The blocks marked with `→ template_defs.gd` would become `scenes/template_defs.gd`.

The resulting file structure would be:

```
scenes/
  template_defs.gd       # Pure data: the template table (≈200 lines)
  codegen_engine.gd       # The pipeline engine: matcher, resolver, emitter (≈300 lines)
  codegen_md.gd           # Refactored to delegate to codegen_engine (≈100 lines)
```

Compare this to the current 833-line `codegen_md.gd`. The separation makes each part independently testable and understandable.

### 9.1 The Refactored codegen_md.gd

After tangling, the original [`codegen_md.gd`](scenes/codegen_md.gd) becomes a thin wrapper:

```gdscript
# → scenes/codegen_md.gd (refactored)
extends Node

signal locations_ready(loc_map: Dictionary)

const ADD_DEBUG_TRACE = false
const ADD_IR_TRACE = true

var _pipeline: CodegenPipeline

func _ready() -> void:
    _pipeline = CodegenPipeline.new()

func reset() -> void:
    _pipeline.reset()

func parse_file(input: Dictionary) -> String:
    reset()
    var filename = input.filename
    var fp = FileAccess.open(filename, FileAccess.READ)
    var text = fp.get_as_text()
    fp.close()
    return generate_from_text(text)

func generate_from_text(text: String) -> String:
    var ir = uYaml.deserialize(text)
    return generate_from_ir(ir)

func generate_from_ir(ir: Dictionary) -> String:
    var assy_block = _pipeline.generate(ir)
    locations_ready.emit(assy_block.loc_map)
    return assy_block.code
```

The deserialization logic (parsing YAML, inflating values, building `all_syms`) remains in the wrapper because it is an I/O concern, not a code generation concern.

---

## 10. Weaving: How This Document Is Formatted

The literate programming toolchain works as follows:

1. **Weaving**: This markdown document is rendered with a custom stylesheet. Code blocks are displayed against a tinted background, with the tangle target shown as a file header. Prose flows around and between code blocks, explaining their purpose.

2. **Tangling**: The same markdown is parsed by a script that extracts code blocks, grouping them by their `→ filename` annotations. The output is a set of `.gd` files ready to be loaded by Godot.

The tangling script is itself a simple literate program:

```python
# → tools/tangle.py
# A literate programming tangler for GDScript.
# Extracts code blocks from markdown and writes them to files.

import re
import sys
from pathlib import Path

BLOCK_PATTERN = re.compile(
    r'```gdscript\n# → (.+?)\n(.+?)```',
    re.DOTALL
)

def tangle(markdown_path: str, output_dir: str) -> None:
    text = Path(markdown_path).read_text(encoding='utf-8')
    files = {}
    
    for match in BLOCK_PATTERN.finditer(text):
        filename = match.group(1).strip()
        code = match.group(2).rstrip() + '\n'
        files.setdefault(filename, []).append(code)
    
    for filename, blocks in files.items():
        out_path = Path(output_dir) / filename
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(''.join(blocks), encoding='utf-8')
        print(f"Tangled: {out_path}")

if __name__ == '__main__':
    tangle(sys.argv[1], sys.argv[2])
```

Of course, this tangler itself is a program that *should* be explained to humans. But that is a task for another document.

---

## 11. Migration Strategy (Tangling the Existing Code)

We cannot replace 833 lines of working code in one commit. The migration follows an **inside-out** strategy: we build the new pipeline alongside the old code, then migrate one instruction type at a time.

### Iteration 1: Template Table

Introduce [`template_defs.gd`](template_defs.gd) as a new file. Populate it with templates for **one** instruction family (say, `MOV` and the simple ALU ops). No code changes yet.

### Iteration 2: Pattern Matcher

Introduce [`PatternMatcher`](#4-the-pattern-matcher) class. Write unit tests that verify it produces correct bindings for `MOV`, `ADD`, `SUB`, etc. The old codegen still runs in production.

### Iteration 3: Slot Resolver + Emitter

Introduce [`SlotResolver`](#5-the-slot-resolver) and [`Emitter`](#6-the-emitter) classes. Add a `generate_from_ir()` method to the pipeline. Now we can generate assembly for simple operations using the new pipeline *in parallel* with the old one.

### Iteration 4: Parallel Execution

Modify the existing `generate_cmd_mov()` to delegate to the pipeline, then compare output. Run the test suite; if results match, the delegation is correct. Repeat for `generate_cmd_op()`, `generate_cmd_if()`, etc.

### Iteration 5: Complete Replacement

Once all `generate_cmd_*` functions delegate to the pipeline, delete them. The old `generate()` function becomes the thin wrapper shown in section 9.1.

### Iteration 6: Parametric Templates

With the pipeline established, introduce `auto_labels`, `auto_imm`, and `virtual_slots` mechanisms. Migrate `IF`, `ELSE`, `WHILE`, and `CALL` to use these features.

---

## 12. Summary: What Literate Programming Gives Us

This document is not a design doc that will be written and then ignored. It is **the source of truth**. The code is extracted from it. The explanation is not separate from the code — they are the same artifact.

The virtues of this approach for the CpuDerp codegen:

1. **The template table is data, not code.** Adding a new IR instruction means adding a row to a table, not writing a new function.
2. **The pipeline is explicit.** Each pass has a name, a purpose, and a clear boundary.
3. **The design is explained to humans.** Anyone reading this document understands not just *what* the code does, but *why* it does it that way.
4. **Tangling produces the actual source files.** There is no gap between documentation and implementation.

Or, as Knuth might say: we have concentrated on explaining to human beings what we want the computer to do, and the computer has been listening.

---

## Appendix: Complete Template Table Reference

For reference, here is the complete template table as it would appear after the migration. This is the "data" part of the data-driven design — the part that would grow as new IR instructions are added.

```gdscript
# → template_defs.gd (complete)

# Full template table for the CpuDerp IR → ZVM assembly codegen.
# Each entry is a template describing how an IR instruction is expanded.

const TEMPLATES = {
    # ── Data Movement ──────────────────────────────────────────
    "MOV": {
        "pattern":  ["MOV", "dest", "src"],
        "assembly": ["mov {dest}, {src};"],
        "size": 8,
        "slots": ["dest", "src"],
    },
    "MOV_ARR": {
        "pattern":  ["MOV_ARR", "dest", "[", "...vals", "]", "END"],
        "assembly": [
            "mov {_tmp}, {dest};",
            "{_store_vals}",
        ],
        "size": 0,  # dynamic
        "slots": ["dest"],
        "virtual_slots": ["_tmp", "_store_vals"],
    },
    
    # ── ALU (binary) ───────────────────────────────────────────
    "OP:ADD": { "pattern": ["OP", "ADD", "a", "b", "res"], "assembly": ["add {a}, {b};"], "size": 8, "slots": ["a", "b", "res"] },
    "OP:SUB": { "pattern": ["OP", "SUB", "a", "b", "res"], "assembly": ["sub {a}, {b};"], "size": 8, "slots": ["a", "b", "res"] },
    "OP:MUL": { "pattern": ["OP", "MUL", "a", "b", "res"], "assembly": ["mul {a}, {b};"], "size": 8, "slots": ["a", "b", "res"] },
    "OP:DIV": { "pattern": ["OP", "DIV", "a", "b", "res"], "assembly": ["div {a}, {b};"], "size": 8, "slots": ["a", "b", "res"] },
    "OP:MOD": { "pattern": ["OP", "MOD", "a", "b", "res"], "assembly": ["mod {a}, {b};"], "size": 8, "slots": ["a", "b", "res"] },
    
    # ── ALU (unary) ────────────────────────────────────────────
    "OP:INC": { "pattern": ["OP", "INC", "a", "NONE", "res"], "assembly": ["inc {a};"], "size": 8, "slots": ["a", "res"] },
    "OP:DEC": { "pattern": ["OP", "DEC", "a", "NONE", "res"], "assembly": ["dec {a};"], "size": 8, "slots": ["a", "res"] },
    
    # ── Comparisons ────────────────────────────────────────────
    "OP:EQUAL":     { "pattern": ["OP", "EQUAL", "a", "b", "res"], "assembly": ["cmp {a}, {b};", "mov {res}, CTRL;", "band {res}, CMP_Z;", "bnot {res};", "bnot {res};"], "size": 40, "slots": ["a", "b", "res"] },
    "OP:NOT_EQUAL": { "pattern": ["OP", "NOT_EQUAL", "a", "b", "res"], "assembly": ["cmp {a}, {b};", "mov {res}, CTRL;", "band {res}, CMP_NZ;", "bnot {res};", "bnot {res};"], "size": 40, "slots": ["a", "b", "res"] },
    "OP:GREATER":   { "pattern": ["OP", "GREATER", "a", "b", "res"], "assembly": ["cmp {a}, {b};", "mov {res}, CTRL;", "band {res}, CMP_G;", "bnot {res};", "bnot {res};"], "size": 40, "slots": ["a", "b", "res"] },
    "OP:LESS":      { "pattern": ["OP", "LESS", "a", "b", "res"], "assembly": ["cmp {a}, {b};", "mov {res}, CTRL;", "band {res}, CMP_L;", "bnot {res};", "bnot {res};"], "size": 40, "slots": ["a", "b", "res"] },
    
    # ── Index ──────────────────────────────────────────────────
    "OP:INDEX": {
        "pattern":  ["OP", "INDEX", "a", "b", "res"],
        "assembly": ["add {a}, {b};"],
        "size": 8,
        "slots": ["a", "b", "res"],
        "flags": {"res": {"needs_deref": true}},
    },
    
    # ── Control Flow ───────────────────────────────────────────
    "IF": {
        "pattern":  ["IF", "cb_cond", "res", "cb_block"],
        "assembly": [
            "{cb_cond}",
            "cmp {res}, {_imm0};",
            "jz {_lbl_else};",
            "{cb_block}",
            "jmp {_lbl_end};",
            ":{_lbl_else}:",
            ":{_lbl_end}:",
        ],
        "size": 0,
        "slots": ["cb_cond", "res", "cb_block"],
        "auto_labels": ["_lbl_else", "_lbl_end"],
        "auto_imm": {"_imm0": 0},
    },
    "ELSE_IF": {
        "pattern":  ["ELSE_IF", "cb_cond", "res", "cb_block"],
        "assembly": [
            "{cb_cond}",
            "cmp {res}, {_imm0};",
            "jz {_lbl_else};",
            "{cb_block}",
            "jmp {_lbl_end};",
            ":{_lbl_else}:",
        ],
        "size": 0,
        "slots": ["cb_cond", "res", "cb_block"],
        "auto_labels": ["_lbl_else"],
        "auto_imm": {"_imm0": 0},
    },
    "ELSE": {
        "pattern":  ["ELSE", "cb_block"],
        "assembly": [
            "{cb_block}",
            ":{_lbl_end}:",
        ],
        "size": 0,
        "slots": ["cb_block"],
        "auto_labels": ["_lbl_end"],
    },
    "WHILE": {
        "pattern":  ["WHILE", "cb_cond", "res", "cb_block", "lbl_next", "lbl_end"],
        "assembly": [
            ":{lbl_next}:",
            "{cb_cond}",
            "cmp {res}, {_imm0};",
            "jz {lbl_end};",
            "{cb_block}",
            "jmp {lbl_next};",
            ":{lbl_end}:",
        ],
        "size": 0,
        "slots": ["cb_cond", "res", "cb_block", "lbl_next", "lbl_end"],
        "auto_imm": {"_imm0": 0},
    },
    
    # ── Function Calls ─────────────────────────────────────────
    "CALL": {
        "pattern":  ["CALL", "fun", "[", "...args", "]", "res"],
        "assembly": [
            "{_push_args}",
            "call @{fun};",
            "add ESP, {_args_size};",
            "mov {res}, eax;",
        ],
        "size": 24,
        "slots": ["fun", "res"],
        "virtual_slots": ["_push_args", "_args_size"],
    },
    "CALL_INDIRECT": {
        "pattern":  ["CALL_INDIRECT", "funvar", "[", "...args", "]", "res"],
        "assembly": [
            "{_push_args}",
            "call {funvar};",
            "add ESP, {_args_size};",
            "mov {res}, eax;",
        ],
        "size": 24,
        "slots": ["funvar", "res"],
        "virtual_slots": ["_push_args", "_args_size"],
    },
    
    # ── Stack Frame ────────────────────────────────────────────
    "ENTER": {
        "pattern":  ["ENTER", "scope"],
        "assembly": ["__ENTER_{scope};"],
        "size": 8,
        "slots": ["scope"],
    },
    "LEAVE": {
        "pattern":  ["LEAVE"],
        "assembly": ["__LEAVE_{scope};"],
        "size": 8,
        "slots": ["scope"],
        "scope_slot": "scope",
    },
    "RETURN": {
        "pattern":  ["RETURN"],
        "assembly": ["__LEAVE_{scope};", "ret;"],
        "size": 16,
        "slots": [],
        "scope_slot": "scope",
    },
    "RETURN:val": {
        "pattern":  ["RETURN", "res"],
        "assembly": ["mov EAX, {res};", "__LEAVE_{scope};", "ret;"],
        "size": 24,
        "slots": ["res"],
        "scope_slot": "scope",
    },
    
    # ── Allocation ─────────────────────────────────────────────
    "ALLOC": {
        "pattern":  ["ALLOC", "size", "res"],
        "assembly": ["mov {res}, {_arr_label};"],
        "size": 8,
        "slots": ["res"],
        "virtual_slots": ["_arr_label"],
    },
}
```

This table is the complete specification of the IR → Assembly mapping. Every IR instruction the compiler can produce has exactly one entry. Adding a new instruction means adding one entry to this table. No new functions. No new `match` arms. Just data.

---

*This document was itself written as a literate program. The code blocks, when tangled, produce the actual GDScript files for the CpuDerp codegen pipeline. The prose explains to human beings what we want the computer to do.*
