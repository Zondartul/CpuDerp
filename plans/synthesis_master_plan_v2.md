# CpuDerp Codegen Refactor — Master Synthesis Plan v2

**Date**: 2026-06-27  
**Supersedes**: `synthesis_master_plan.md` (v1)  
**Key innovation**: A human-readable **macro assembly template format** (`.tg`) that replaces both the YAML schema AND the 13 `generate_cmd_*` GDScript functions. Templates are compiled once at pre-build time into an **Inflated Template Graph** (ITG), cached, and consumed by a two-pass codegen pipeline.

---

## Table of Contents

1. [What Changed from v1](#1-what-changed-from-v1)
2. [Architecture Overview](#2-architecture-overview)
3. [The Template Format](#3-the-template-format)
4. [Template Parser & Pre-build Step](#4-template-parser--pre-build-step)
5. [Inflated Template Graph (Data Model)](#5-inflated-template-graph-data-model)
6. [Two-Pass Codegen Pipeline](#6-two-pass-codegen-pipeline)
7. [Migration Strategy](#7-migration-strategy)
8. [Repository Structure](#8-repository-structure)
9. [Appendices](#9-appendices)

---

## 1. What Changed from v1

| Aspect | v1 (YAML) | v2 (Macro Assembly) |
|--------|-----------|---------------------|
| Template format | YAML with named slots | `.tg` file — assembly-like language with `@directives` |
| Template parser | YAML deserializer | Custom `.tg` parser in GDScript |
| Pipelines stages | 5 sequential stages | 2 passes (declarative + imperative) over an inflated graph |
| String operations | Resolved during template expansion | Delayed — typed `AssemblyPart` nodes until final stringification |
| Variable-length ops | Fallback to special-case GDScript | Native `for arg in args:` in the template language |
| Temporaries | Allocated lazily during emit | Discovered in Pass 1, allocated before Pass 2 |
| Template location | Separate `.yaml` file | Single `codegen_templates.tg` file in `res://templates/` |
| Build step | Parsed at runtime | Pre-build step → cached inflated graph (`.tres`) |

---

## 2. Architecture Overview

### 2.1 The Big Picture

```
                    PRE-BUILD STEP
                    (once per edit)
┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐
│ codegen_     │────▶│ template_parser  │────▶│ Inflated Graph   │
│ templates.tg │     │ .gd              │     │ .tres (cached)   │
└──────────────┘     └──────────────────┘     └──────────────────┘
                          │                         │
                          │    On subsequent         │
                          │    launches: load cache   │
                          ▼                         ▼
                    [template_cache.tres]     (same graph format)


                        CODEGEN PIPELINE
                    (every compilation)

┌─────────────────────────────────────────────────────────────┐
│                        IR Program                              │
│              (from analyzer via ir_md.gd)                      │
└─────────────────────┬─────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  PASS 1 — Declarative Pass (Discover + Allocate)             │
│                                                               │
│  flatir_build.gd + stor_alloc.gd + abi_scanner.gd            │
│                                                               │
│  Input:  IR program (Dictionary from ir_md.gd)                │
│  Input:  Inflated Template Graph                              │
│                                                               │
│  Steps:                                                       │
│  1. Walk all IR scopes → collect symbol declarations          │
│  2. Walk all IR commands → match to templates                  │
│  3. For each matched template, walk the ITG:                  │
│     - Collect all {slot} references → register symbols        │
│     - Collect all @temp → add to temp list                   │
│     - Collect all @label → generate unique label names        │
│     - Collect all @ref_cb → mark code blocks reachable        │
│     - Collect all @new_imm → create immediate values          │
│  4. Allocate storage for ALL symbols and temps                │
│     (global→label, stack→EBP offset, temps→register or stack) │
│                                                               │
│  Output: ABIManifest (all symbols allocated)                  │
└─────────────────────┬─────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  PASS 2 — Imperative Pass (Resolve + Emit)                   │
│                                                               │
│  tmpl_expand.gd + reg_resolve.gd + asm_emit.gd               │
│                                                               │
│  Input:  IR command list (flat)                               │
│  Input:  Inflated Template Graph (same one)                   │
│  Input:  ABIManifest (from Pass 1)                            │
│                                                               │
│  Steps:                                                       │
│  1. For each IR command, look up its template in ITG          │
│  2. Walk the ITG body for that template:                     │
│     - @bind → bind slot names to actual word values           │
│     - EMIT_LINE → resolve {slot} to concrete string           │
│     - @temp → allocate from pre-planned temp pool             │
│     - @label → emit label with pre-generated name            │
│     - for arg in args: → iterate and emit per element         │
│     - @emit_cb → recursively Pass 2 on referenced code block  │
│     - @variant → switch on slot value                        │
│  3. Store results in EmitBuffer (typed parts)                 │
│  4. Fix up ENTER/LEAVE (now that stack sizes are known)       │
│  5. Stringify EmitBuffer → final assembly text               │
│                                                               │
│  Output: Assembly text (String)                               │
└─────────────────────┬─────────────────────────────────────────┘
                      │
                      ▼
              Final Assembly Text
              (fed to comp_asm_zd.gd)
```

### 2.2 Data Lifetime

```
                          PRE-BUILD TIME
template.tg ──→ template_parser ──→ InflatedGraph ──→ cached .tres
                                                     (never changes
                                                      during runtime)

                          COMPILE TIME (each compilation)
IR Program ──→ Pass 1 ──→ ABIManifest ──→ Pass 2 ──→ Assembly
                                                  ↑
                                           InflatedGraph
                                           (loaded from cache)
```

---

## 3. The Template Format

### 3.1 Philosophy

The `.tg` format is designed to be:
- **Human-readable** — looks like ZVM assembly with annotations
- **Expressive** — covers all 8 primitive operations (LOAD, STORE, ALLOC_TEMP, NEW_IMM, NEW_LABEL, EMIT_CB, EMIT_LINE, MARK_REACHABLE)
- **Self-contained** — one file replaces 13 `generate_cmd_*` functions + `op_map`
- **Parser-friendly** — simple enough to parse with a line-based scanner

### 3.2 Complete Template File

````
# res://templates/codegen_templates.tg
# CpuDerp Codegen Templates — IR Command → Assembly Mapping
#
# Format:
#   @template NAME(param_slot:type, ...):
#       @bind local_name = $cmd.words[N]
#       ...emitted lines with {local_name} references...
#   @end
#
# Slot types:
#   load    — value to be loaded from storage ($name)
#   store   — value to be stored to (^name)
#   addr    — address of value (@name)
#   variadic — slurps 0+ words from array
#   codeblock — name of a code block to emit inline
#   label   — label name from the IR
#   optional — may not exist in words


# ═══════════════════════════════════════════════════════════════
# MOV: Move src into dest
# ═══════════════════════════════════════════════════════════════

@template MOV(dest:store, src:load):
    @bind dest = $cmd.words[1]
    @bind src  = $cmd.words[2]

    mov {dest}, {src};
@end


# ═══════════════════════════════════════════════════════════════
# OP: Arithmetic/logic operation
# ═══════════════════════════════════════════════════════════════
# Patterns: OP op a b res

@template OP(op:immediate, a:load, b:load, res:store):
    @bind op  = $cmd.words[1]
    @bind a   = $cmd.words[2]
    @bind b   = $cmd.words[3]
    @bind res = $cmd.words[4]

    # --- Mono-operand ops (INC, DEC) ---
    @variant INC:
        mov {res}, {a};
        inc {res};
    @variant DEC:
        mov {res}, {a};
        dec {res};

    # --- Standard binary ops (need temporaries) ---
    @variant ADD, SUB, MUL, DIV, MOD:
        @temp tmp_a, tmp_b
        mov {tmp_a}, {a};
        mov {tmp_b}, {b};
        {op} {tmp_a}, {tmp_b};
        mov {res}, {tmp_a};

    # --- Comparison ops (use CTRL register) ---
    @variant GREATER:
        cmp {a}, {b};
        mov {res}, CTRL;
        band {res}, CMP_G;
        bnot {res};
        bnot {res};
    @variant LESS:
        cmp {a}, {b};
        mov {res}, CTRL;
        band {res}, CMP_L;
        bnot {res};
        bnot {res};
    @variant EQUAL:
        cmp {a}, {b};
        mov {res}, CTRL;
        band {res}, CMP_Z;
        bnot {res};
        bnot {res};
    @variant NOT_EQUAL:
        cmp {a}, {b};
        mov {res}, CTRL;
        band {res}, CMP_NZ;
        bnot {res};
        bnot {res};

    # --- INDEX: array offset computation ---
    @variant INDEX:
        add {a}, {b};
        @needs_deref(res)
@end


# ═══════════════════════════════════════════════════════════════
# IF: Conditional branch
# ═══════════════════════════════════════════════════════════════
# Patterns: IF cb_cond res cb_block

@template IF(cb_cond:codeblock, res:load, cb_block:codeblock):
    @bind cb_cond  = $cmd.words[1]
    @bind res      = $cmd.words[2]
    @bind cb_block = $cmd.words[3]

    @label lbl_else, lbl_end
    @new_imm(0) → imm_0

    @emit_cb(cb_cond)
    cmp {res}, {imm_0};
    jz  {lbl_else};
    @emit_cb(cb_block)
    jmp {lbl_end};
    :{lbl_else}:
    :{lbl_end}:
@end


# ═══════════════════════════════════════════════════════════════
# ELSE_IF: Else-if chain
# ═══════════════════════════════════════════════════════════════

@template ELSE_IF(cb_cond:codeblock, res:load, cb_block:codeblock):
    @bind cb_cond  = $cmd.words[1]
    @bind res      = $cmd.words[2]
    @bind cb_block = $cmd.words[3]

    @label lbl_else
    @new_imm(0) → imm_0

    @emit_cb(cb_cond)
    cmp {res}, {imm_0};
    jz  {lbl_else};
    @emit_cb(cb_block)
    jmp {%if_block_lbl_end};
    :{lbl_else}:
@end


# ═══════════════════════════════════════════════════════════════
# ELSE: Else block
# ═══════════════════════════════════════════════════════════════

@template ELSE(cb_block:codeblock):
    @bind cb_block = $cmd.words[1]

    @emit_cb(cb_block)
    :{%if_block_lbl_end}:
@end


# ═══════════════════════════════════════════════════════════════
# WHILE: While loop
# ═══════════════════════════════════════════════════════════════
# Patterns: WHILE cb_cond res cb_block lbl_next lbl_end

@template WHILE(cb_cond:codeblock, res:load, cb_block:codeblock, lbl_next:label, lbl_end:label):
    @bind cb_cond  = $cmd.words[1]
    @bind res      = $cmd.words[2]
    @bind cb_block = $cmd.words[3]
    @bind lbl_next = $cmd.words[4]
    @bind lbl_end  = $cmd.words[5]

    @new_imm(0) → imm_0

    :{lbl_next}:
    @emit_cb(cb_cond)
    cmp {res}, {imm_0};
    jz  {lbl_end};
    @emit_cb(cb_block)
    jmp {lbl_next};
    :{lbl_end}:
@end


# ═══════════════════════════════════════════════════════════════
# CALL: Function call
# ═══════════════════════════════════════════════════════════════
# Patterns: CALL fun [args...] res
# Note: args are in brackets, res is after

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


# ═══════════════════════════════════════════════════════════════
# CALL_INDIRECT: Call via variable (function pointer)
# ═══════════════════════════════════════════════════════════════

@template CALL_INDIRECT(funvar:load, args:variadic, res:store):
    @bind funvar = $cmd.words[1]
    @bind args   = $cmd.words[2..-2]
    @bind res    = $cmd.words[-1]

    @reverse(args)

    for arg in args:
        push {arg};
    endfor
    call {funvar};
    add  ESP, {len(args) * 4};
    mov  {res}, EAX;
@end


# ═══════════════════════════════════════════════════════════════
# RETURN: Return with optional value
# ═══════════════════════════════════════════════════════════════

@template RETURN(val:optional):
    @bind val = $cmd.words[1]?

    if {val}:
        mov EAX, {val};
    endif
    __LEAVE_{scope};
    ret;
@end


# ═══════════════════════════════════════════════════════════════
# ENTER: Enter scope (push stack frame)
# ═══════════════════════════════════════════════════════════════

@template ENTER(scp:immediate):
    @bind scp = $cmd.words[1]
    __ENTER_{scp};
@end


# ═══════════════════════════════════════════════════════════════
# LEAVE: Leave scope (pop stack frame)
# ═══════════════════════════════════════════════════════════════

@template LEAVE():
    __LEAVE_{scope};
@end


# ═══════════════════════════════════════════════════════════════
# ALLOC: Allocate array
# ═══════════════════════════════════════════════════════════════

@template ALLOC(size:load, res:store):
    @bind size = $cmd.words[1]
    @bind res  = $cmd.words[2]
    mov {res}, @{res};
@end


# ═══════════════════════════════════════════════════════════════
# MOV_ARR: Array element write (multiple values into array)
# ═══════════════════════════════════════════════════════════════

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
````

### 3.3 Template Grammar Reference

```
Directive:
    @template NAME(slot_defs) → marks start of template
    @end                        → marks end of template
    @variant LABEL1, LABEL2:    → switch case (for OP sub-types)
    @bind name = expr           → bind slot to IR word
    @temp name1, name2          → declare temporary value
    @label name1, name2         → declare generated label
    @new_imm(value) → name      → create immediate constant
    @emit_cb(slot)              → recursively emit a code block inline
    @ref_cb(slot)               → mark code block as reachable
    @needs_deref(slot)          → set needs_deref flag on a value
    @reverse(name)              → reverse a variadic list
    for name in list:           → iterate over variadic list
    endfor                      → end iteration block
    if {slot}:                  → conditional emission
    endif                       → end conditional

Slot Reference (inside emitted lines):
    {name}       → resolves to concrete assembly text depending on slot type
    {%context}   → resolves to context-specific value (e.g., %if_block_lbl_end)
    :{name}:     → label definition (emitted as :label_name:)
    {op}         → verbatim slot value (used for OP → ADD/SUB/etc.)

Slot Types (in @template signature):
    load         → value loaded from storage (was $name)
    store        → value stored to (was ^name)
    addr         → address of value (was @name)
    codeblock    → reference to a code block for inline emit
    label        → label name
    variadic     → slurps multiple words
    immediate    → verbatim word value from IR
    optional     → may be absent

Binding Expressions:
    $cmd.words[N]        → single word by index
    $cmd.words[N..-1]    → slice to end
    $cmd.words[2..-2]    → slice excluding first and last
    $cmd.words[-1]       → last word
    $cmd.words[1]?       → optional (may not exist)
```

---

## 4. Template Parser & Pre-build Step

### 4.1 Design

The `.tg` file parser is a separate GDScript resource (`template_parser.gd`). It is invoked:

1. **During pre-build** (when blueprints/configs are compiled):
   - Reads `res://templates/codegen_templates.tg`
   - Parses it into the Inflated Template Graph (ITG)
   - Serializes the ITG to a cached resource file (`.tres`)

2. **On subsequent launches**:
   - Loads the cached `.tres` directly (no parsing needed)
   - If the `.tg` file has been edited, re-parses (timestamp check)

### 4.2 Parser Logic

```gdscript
# template_parser.gd
class_name TemplateParser
extends RefCounted

# Parse a .tg file → returns InflatedGraph
static func parse(text: String) -> InflatedGraph:
    var graph = InflatedGraph.new()
    var lines = text.split("\n")
    var i = 0
    while i < lines.size():
        var line = lines[i].strip_edges()
        if line.begins_with("@template"):
            var (def, consumed) = parse_template(lines, i)
            graph.templates[def.name] = def
            i += consumed
        elif line.begins_with("#") or line.is_empty():
            i += 1
        else:
            i += 1  # skip unknown (comments, blank lines)
    return graph

static func parse_template(lines: Array, start: int) -> Array:
    # Parse @template NAME(slot_defs):
    var header = lines[start]
    var name = extract_name(header)
    var slots = extract_slots(header)
    var body: Array[ITGNode] = []
    var i = start + 1
    
    while i < lines.size():
        var line = lines[i].strip_edges()
        if line == "@end":
            break
        var node = parse_body_line(line, slots)
        if node != null:
            body.append(node)
        i += 1
    
    var def = TemplateDef.new(name, slots, body)
    return [def, i - start + 1]

static func parse_body_line(line: String, slots: Array) -> ITGNode:
    if line.begins_with("@bind"):
        return parse_bind(line)
    elif line.begins_with("@temp"):
        return parse_temp_allocation(line)
    elif line.begins_with("@label"):
        return parse_label_def(line)
    elif line.begins_with("@new_imm"):
        return parse_imm_def(line)
    elif line.begins_with("@emit_cb"):
        return parse_callback("emit_cb", line)
    elif line.begins_with("@ref_cb"):
        return parse_callback("ref_cb", line)
    elif line.begins_with("@needs_deref"):
        return parse_callback("needs_deref", line)
    elif line.begins_with("@reverse"):
        return parse_callback("reverse", line)
    elif line.begins_with("@variant"):
        return parse_variant_start(line, lines, i)
    elif line.begins_with("for "):
        return parse_for_each(line, lines, i)
    elif line.begins_with("if "):
        return parse_if_conditional(line, lines, i)
    elif line.begins_with("endfor") or line.begins_with("endif"):
        return null  # end marker, handled by parent parser
    else:
        # It's an emit line
        return parse_emit_line(line)
```

### 4.3 Caching

```gdscript
# In pre-build step:
var parser = TemplateParser.new()
var graph = parser.parse(tg_file_text)
ResourceSaver.save(graph, "res://templates/codegen_templates_cache.tres")

# In codegen:
var graph = load("res://templates/codegen_templates_cache.tres")
# graph is an InflatedGraph ready to use
```

---

## 5. Inflated Template Graph (Data Model)

```gdscript
# inflated_template_graph.gd
class_name InflatedGraph
extends Resource  # serializable as .tres

var templates: Dictionary = {}  # String name → TemplateDef
var version: int = 1


# inflated_template_types.gd
# Shared types used by both the ITG and codegen pipeline.

class_name TemplateDef
extends RefCounted

var name: String
var param_variants: Array[String]     # ["op"] — empty if no variants
var slots: Array[SlotDef]
var body: Array[ITGNode]

func _init(p_name: String, p_slots: Array, p_body: Array):
    name = p_name; slots = p_slots; body = p_body


class_name SlotDef
extends RefCounted

enum SlotType {
    LOAD,       # $name — load value from storage
    STORE,      # ^name — store value to storage
    ADDR,       # @name — address of value
    VARIADIC,   # slurps 0+ words
    CODEBLOCK,  # name of code block for inline emit
    LABEL,      # label name
    OPTIONAL,   # may not exist
    IMMEDIATE,  # verbatim word value
}

var name: String
var type: SlotType
var binding: String  # "$cmd.words[1]" — stored as parse info


class_name ITGNode:
    enum NodeType {
        EMIT_LINE,
        FOREACH,
        IF_CONDITIONAL,
        VARIANT_SWITCH,
        CALLBACK,
        TEMP_ALLOC,
        LABEL_DEF,
        IMM_DEF,
        BINDING,
    }
    var type: NodeType


class_name EmitLineNode
extends ITGNode

var text_pattern: String            # "mov {dest}, {src};"
var slot_refs: Array[SlotRef]       # extracted from {} during parse


class_name SlotRef
extends RefCounted

enum Role {
    LOAD_REF,       # {dest} with dest:store → using ^ sigil
    STORE_REF,      # {dest} with dest:load → using $ sigil
    ADDR_REF,       # {fun} with fun:addr → using @ sigil
    LABEL_REF,      # {lbl_else} — plain label string
    VALUE_REF,      # {op} — verbatim word value
    TEMP_REF,       # {tmp_a} — reference to a temporary
    IMM_REF,        # {imm_0} — reference to immediate constant
    CONTEXT_REF,    # {%if_block_lbl_end} — context variable
    COMPUTED_REF,   # {len(args)} — computed value
}

var slot_name: String
var role: Role


class_name ForEachNode
extends ITGNode

var list_name: String       # "args"
var element_name: String    # "arg"
var body: Array[ITGNode]


class_name VariantSwitchNode
extends ITGNode

var slot_name: String        # "op"
var variants: Dictionary     # "ADD" → Array[ITGNode], "SUB" → Array[ITGNode]


class_name CallbackNode
extends ITGNode

var callback_name: String    # "ref_cb", "needs_deref", "reverse"
var arg_names: Array[String]  # ["fun"]


class_name TempAllocNode
extends ITGNode

var temp_names: Array[String]  # ["tmp_a", "tmp_b"]


class_name LabelDefNode
extends ITGNode

var label_names: Array[String]  # ["lbl_else", "lbl_end"]


class_name ImmDefNode
extends ITGNode

var imm_name: String     # "imm_0"
var value: int           # 0
```

### 5.2 ABIManifest (created by Pass 1, consumed by Pass 2)

```gdscript
# abi_manifest.gd
class_name ABIManifest
extends RefCounted

# All known symbols (variables, functions, temporaries, immediates)
var symbols: Dictionary = {}    # ir_name → SymbolInfo

# Pre-generated label names for @label declarations
var labels: Dictionary = {}     # meta_name → generated_label_string

# All temps discovered during template scan
var temps: Array[TempSlot] = []  # pre-allocated in Pass 1

# Code blocks reachable through @ref_cb or in IR
var reachable_cbs: Array[String] = []

# Per-scope stack data
var scope_stack_sizes: Dictionary = {}  # scp_name → bytes needed

# Template-to-slot-ref mapping (for discovery iteration)
var template_slot_refs: Dictionary = {}  # template_name → Array[SlotRef]


class SymbolInfo:
    var ir_name: String
    var val_type: String           # "variable", "temporary", "immediate", "func", "code", "label"
    var storage_type: String       # "global", "stack", "register", "immediate", "code", "extern"
    var storage_pos: int           # stack offset or register index
    var data_type: String          # "int", "string", "func_ptr"
    var is_array: bool
    var array_size: int
    var needs_deref: bool
    var scope: String              # which scope this belongs to


class TempSlot:
    var name: String               # "tmp_a"
    var preferred_register: String # "EAX" or null (stack spill)
    var stack_pos: int             # EBP offset if spilled
```

---

## 6. Two-Pass Codegen Pipeline

### 6.1 Pass 1: Declarative Pass (ABI Discovery + Storage Allocation)

```
Purpose: Walk the IR program AND the inflated template graph together.
         Discover every symbol, temp, label, and code block reference.
         Allocate storage for all of them BEFORE any emit begins.

Input:
  - IR program (from ir_md.gd via deserialize)
  - InflatedGraph (from cache, loaded once at startup)
  - Template-to-IR-command mapping (what template handles MOV, OP, etc.)

Output:
  - ABIManifest (all symbols allocated, all temps planned, all labels generated)
```

```gdscript
# abi_scanner.gd (NEW)
# Scans IR commands through the lens of the ITG to discover symbols.

static func discover(IR: Dictionary, graph: InflatedGraph) -> ABIManifest:
    var manifest = ABIManifest.new()
    
    # Step 1: Collect all declared symbols from IR scopes
    for scp_name in IR.scopes:
        var scope = IR.scopes[scp_name]
        for var_handle in scope.get("vars", []):
            add_symbol(manifest, var_handle, scp_name)
        for func_handle in scope.get("funcs", []):
            add_symbol(manifest, func_handle, scp_name)
    
    # Step 2: Walk all code blocks, match each command to its template
    for cb_name in IR.code_blocks:
        var cb = IR.code_blocks[cb_name]
        manifest.reachable_cbs.append(cb_name)
        for cmd in cb.get("code", []):
            var tmpl_name = cmd.words[0]
            var tmpl = graph.templates.get(tmpl_name)
            if tmpl == null:
                push_error("No template for [%s]" % tmpl_name)
                continue
            # Walk the template's ITG body
            scan_template_node(tmpl.body, cmd, manifest)
    
    # Step 3: Allocate storage for all discovered symbols
    StorageAllocator.allocate(manifest, IR)
    
    return manifest

static func scan_template_node(nodes: Array, cmd: IR_Cmd, manifest: ABIManifest):
    for node in nodes:
        match node.type:
            ITGNode.NodeType.CALLBACK:
                handle_callback(node, cmd, manifest)
            ITGNode.NodeType.TEMP_ALLOC:
                for t_name in node.temp_names:
                    manifest.temps.append(TempSlot.new(t_name))
            ITGNode.NodeType.LABEL_DEF:
                for lbl_name in node.label_names:
                    manifest.labels[lbl_name] = generate_unique_label(lbl_name)
            ITGNode.NodeType.IMM_DEF:
                var imm_ir_name = create_immediate(node.value)
                manifest.symbols[imm_ir_name] = SymbolInfo.new(...)
            ITGNode.NodeType.VARIANT_SWITCH:
                # Scan all variants' bodies
                for variant_name in node.variants:
                    scan_template_node(node.variants[variant_name], cmd, manifest)
            ITGNode.NodeType.FOREACH:
                scan_template_node(node.body, cmd, manifest)

static func handle_callback(node: CallbackNode, cmd: IR_Cmd, manifest: ABIManifest):
    match node.callback_name:
        "ref_cb":
            var cb_name = resolve_word(cmd, node.arg_names[0])
            if cb_name not in manifest.reachable_cbs:
                manifest.reachable_cbs.append(cb_name)
        "needs_deref":
            var sym_name = resolve_word(cmd, node.arg_names[0])
            var sym = manifest.symbols.get(sym_name)
            if sym: sym.needs_deref = true
        # "reverse" is a Pass 2 operation only
```

### 6.2 StorageAllocator (separate from old allocate_vars)

```gdscript
# stor_alloc.gd (UPDATED for v2)
# Allocates storage for all symbols discovered in Pass 1.

static func allocate(manifest: ABIManifest, IR: Dictionary) -> void:
    # Same logic as current codegen_md.gd allocate_vars + allocate_value
    # but operating on manifest.symbols instead of all_syms + IR.scopes.
    
    # Step 1: Walk scopes, assign stack positions
    for scp_name in IR.scopes:
        var scope = IR.scopes[scp_name]
        scope.local_vars_write_pos = to_local_pos(0)
        scope.args_write_pos = to_arg_pos(0)
        
        for sym_name in scope.get("vars", []):
            var sym = manifest.symbols[sym_name.ir_name]
            if scope.user_name == "global":
                sym.storage_type = "global"
                sym.storage_pos = 0
            else:
                sym.storage_type = "stack"
                sym.storage_pos = scope.local_vars_write_pos
                scope.local_vars_write_pos -= get_data_size(sym)
    
    # Step 2: Allocate temporaries
    # Try to assign registers first, then fall back to stack
    var reg_assignments = ["EAX", "EBX", "ECX", "EDX"]
    var next_reg = 0
    for temp in manifest.temps:
        if next_reg < 4:
            temp.preferred_register = reg_assignments[next_reg]
            temp.stack_pos = 0
            next_reg += 1
        else:
            # Spill to stack in the current scope
            temp.preferred_register = ""
            temp.stack_pos = allocate_stack_spill(...)
    
    # Step 3: Store back to manifest
    manifest.scope_stack_sizes = extract_stack_sizes(IR.scopes)
```

### 6.3 Pass 2: Imperative Pass (Resolve + Emit)

```
Purpose: Walk each IR command, apply its template, resolve slots against
         the ABIManifest, and produce assembly text.

Input:
  - IR command list (flattened code blocks in emit order)
  - InflatedGraph (loaded from cache)
  - ABIManifest (from Pass 1)

Output:
  - Assembly text (String)
```

```gdscript
# tmpl_expand.gd (UPDATED for v2)
# The imperative template expander.

static func expand(
    commands: Array,        # flat IR command list in emit order
    graph: InflatedGraph,
    manifest: ABIManifest
) -> CodegenResult:
    var buf = EmitBuffer.new()
    
    for cmd in commands:
        var tmpl = graph.templates.get(cmd.words[0])
        if tmpl == null:
            return CodegenResult.failure(...)
        
        # Resolve slot bindings for this command
        var bindings = resolve_bindings(tmpl.slots, cmd.words)
        
        # Walk the template body
        emit_node_list(tmpl.body, cmd, bindings, manifest, buf)
    
    # Fix up ENTER/LEAVE placeholders
    fixup_enter_leave(buf, manifest)
    
    return CodegenResult.success(buf.to_text())

static func emit_node_list(
    nodes: Array, cmd: IR_Cmd, bindings: Dictionary,
    manifest: ABIManifest, buf: EmitBuffer
):
    for node in nodes:
        match node.type:
            ITGNode.NodeType.EMIT_LINE:
                emit_line(node.text_pattern, node.slot_refs, bindings, manifest, buf)
            ITGNode.NodeType.FOREACH:
                var list = bindings[node.list_name]
                for elem in list:
                    bindings[node.element_name] = elem
                    emit_node_list(node.body, cmd, bindings, manifest, buf)
            ITGNode.NodeType.VARIANT_SWITCH:
                var variant_value = bindings[node.slot_name]
                var variant_body = node.variants.get(variant_value)
                if variant_body != null:
                    emit_node_list(variant_body, cmd, bindings, manifest, buf)
            ITGNode.NodeType.CALLBACK:
                handle_emit_callback(node, cmd, bindings, manifest, buf)
            ITGNode.NodeType.LABEL_DEF:
                for lbl_name in node.label_names:
                    var actual = manifest.labels[lbl_name]
                    buf.append(":%s:\n" % actual, 0)
            ITGNode.NodeType.TEMP_ALLOC:
                # Temporaries are pre-allocated in manifest.
                # Here we just resolve them to register/stack refs.
                pass  # handled at resolve-slot time
            ITGNode.NodeType.IMM_DEF:
                pass  # already created in Pass 1

static func emit_line(
    pattern: String, slot_refs: Array, bindings: Dictionary,
    manifest: ABIManifest, buf: EmitBuffer
):
    var resolved = pattern
    
    # Replace each {slot_name} with its resolved assembly text
    for ref in slot_refs:
        var replacement = resolve_slot(ref, bindings, manifest)
        resolved = resolved.replace("{%s}" % ref.slot_name, replacement)
    
    buf.append(resolved + "\n", ...)
    # Also handle location marking (mark_loc_begin/end)

static func resolve_slot(ref: SlotRef, bindings: Dictionary, manifest: ABIManifest) -> String:
    match ref.role:
        SlotRef.Role.LOAD_REF:
            var sym = manifest.symbols[bindings[ref.slot_name]]
            return load_value_text(sym)
        SlotRef.Role.STORE_REF:
            var sym = manifest.symbols[bindings[ref.slot_name]]
            return store_value_text(sym)
        SlotRef.Role.ADDR_REF:
            var sym = manifest.symbols[bindings[ref.slot_name]]
            return address_value_text(sym)
        SlotRef.Role.LABEL_REF:
            return manifest.labels[ref.slot_name]
        SlotRef.Role.VALUE_REF:
            return bindings[ref.slot_name]
        SlotRef.Role.TEMP_REF:
            var temp = find_temp(ref.slot_name, manifest)
            if temp.preferred_register:
                return temp.preferred_register
            else:
                return "EBP[%d]" % temp.stack_pos
        SlotRef.Role.IMM_REF:
            var sym = manifest.symbols[ref.slot_name]
            return sym.ir_name  # label reference to data section
        SlotRef.Role.COMPUTED_REF:
            return compute_value(ref, bindings)
        SlotRef.Role.CONTEXT_REF:
            return get_context_value(ref.slot_name, manifest)
```

### 6.4 The 8 Primitive Operations — Where They Live

| Operation | Where it happens | How |
|-----------|-----------------|-----|
| **LOAD**(name) → value | `resolve_slot()` with `LOAD_REF` | Returns `*var_x` or `EBP[-4]` or `42` |
| **STORE**(name, value) | `resolve_slot()` with `STORE_REF` | Returns `*var_x` or `EBP[-4]` |
| **ALLOC_TEMP**() → reg_or_stack | Pre-planned in Pass 1, resolved at emit time | Returns `EAX` or `EBP[-12]` |
| **NEW_IMM**(value) → const | Pass 1 `ImmDefNode` handler | Creates symbol with storage_type=immediate |
| **NEW_LABEL**(hint) → string | Pass 1 `LabelDefNode` handler | Generates unique name, stored in manifest |
| **EMIT_CB**(name) | Pass 2 `@emit_cb` handler | Recursive call to expand() on named code block |
| **EMIT_LINE**(text) | `emit_line()` in Pass 2 | Resolves all slot refs → appends to buffer |
| **MARK_REACHABLE**(cb) | Pass 1 `@ref_cb` handler | Adds cb to manifest.reachable_cbs |

---

## 7. Migration Strategy

The migration is still incremental — one IR command at a time — but now the template format replaces `generate_cmd_*` functions directly, rather than going through a YAML intermediary.

### Sprint Plan

```
Sprint 0: Foundation
  ├── Build template_parser.gd (parses .tg → InflatedGraph)
  ├── Build codegen_result.gd
  ├── Build abi_scanner.gd (Pass 1: symbol discovery)
  ├── Build stor_alloc.gd (storage allocation from manifest)
  ├── Capture golden files from current codegen
  ├── Write codegen_templates.tg with ONE template: MOV
  └── Test: template parser produces correct ITG for MOV

Sprint 1: MOV + Infrastructure
  ├── Build tmpl_expand.gd (Pass 2: imperative emit)
  ├── Build EmitBuffer with AssemblyPart delay
  ├── Build codegen_master.gd (dispatcher: old codegen ↔ new pipeline)
  ├── Wire Pass 1 + Pass 2 together for MOV
  ├── Verify: hello.md golden matches
  └── MOV removed from old generate_cmd_mov()

Sprint 2: OP + Storage
  ├── Add ALL 12 OP variants to codegen_templates.tg
  ├── Verify @variant switch works in Pass 2
  ├── Verify @temp allocation works (tmp_a, tmp_b)
  ├── Verify golden files match for all OP-using programs
  └── OP removed from old generate_cmd_op() + op_map

Sprint 3: Control Flow
  ├── Add IF, ELSE_IF, ELSE, WHILE to templates.tg
  ├── Build @label generation (unique names in Pass 1)
  ├── Build @new_imm(0) for zero constant
  ├── Build @emit_cb for recursive code block emission
  ├── Verify if/while golden files match
  └── Old if/while functions removed

Sprint 4: Complex Commands
  ├── Add CALL, CALL_INDIRECT, RETURN, ENTER, LEAVE to templates.tg
  ├── Build variadic iteration (for arg in args:)
  ├── Build @ref_cb for reachability
  ├── Build __ENTER_/__LEAVE_ fixup
  ├── Verify all golden files match
  └── Old generate_cmd_call/return/enter/leave removed

Sprint 5: Arrays + Hardening
  ├── Add ALLOC, MOV_ARR to templates.tg
  ├── Build @needs_deref handling
  ├── Full integration test — all 13 commands migrated
  ├── Remove ALL old generate_cmd_* functions
  ├── Edge case tests
  ├── Performance benchmark (old vs new)
  └── Documentation
```

### Parallel Pipeline Dispatcher

```gdscript
# codegen_master.gd (same concept as v1, but dispatches through ITG)
var migrated_ops: Dictionary = {}
var graph: InflatedGraph = load("res://templates/codegen_templates_cache.tres")

func generate(input: Dictionary) -> String:
    # Step 1: Deserialize IR (using existing codegen_md.deserialize for now)
    old_codegen.deserialize(input.text)
    
    # Step 2: Pass 1 — ABI Discovery
    var manifest = ABIScanner.discover(old_codegen.IR, graph)
    
    # Step 3: Separate migrated from unmigrated commands
    var migrated_cmds = []
    var unmigrated_cmds = []
    for cmd in flatten_commands(old_codegen.IR):
        if cmd.words[0] in migrated_ops:
            migrated_cmds.append(cmd)
        else:
            unmigrated_cmds.append(cmd)
    
    # Step 4: Pass 2 for migrated commands
    var new_result = TemplateExpander.expand(migrated_cmds, graph, manifest)
    
    # Step 5: Old codegen for unmigrated commands
    var old_text = old_codegen.generate_remaining(unmigrated_cmds)
    
    # Step 6: Combine
    return new_result + old_text
```

---

## 8. Repository Structure — Target State

```
res/
├── templates/
│   ├── codegen_templates.tg           # [NEW] Human-readable template file
│   └── codegen_templates_cache.tres    # [NEW] Cached Inflated Graph (auto-generated)
│
├── golden/
│   ├── hello.asm                       # [NEW] Golden files
│   ├── array_test.asm
│   ├── test_arr_if.asm
│   ├── test_not_eq.asm
│   ├── elif_test.asm
│   ├── printf_test.asm
│   └── return_test.asm
│
└── data/                               # Test programs (unchanged)

scenes/
├── codegen_md.gd                       # UNCHANGED during migration
├── template_parser.gd                  # [NEW] .tg → InflatedGraph parser
├── inflated_template_graph.gd          # [NEW] Data model types (Resource)
├── abi_manifest.gd                     # [NEW] Data model: Pass 1 output
├── abi_scanner.gd                      # [NEW] Pass 1: Symbol discovery
├── stor_alloc.gd                       # [NEW] Pass 1: Storage allocation
├── tmpl_expand.gd                      # [NEW] Pass 2: Imperative emit
├── reg_resolve.gd                      # [NEW] Register state machine
├── asm_emit.gd                         # [NEW] Stringification + fixups
├── codegen_master.gd                   # [NEW] Pipeline orchestrator
└── codegen_result.gd                   # [NEW] Result type

tests/
├── test_template_parser.gd
├── test_abi_scanner.gd
├── test_stor_alloc.gd
├── test_tmpl_expand.gd
├── test_reg_resolve.gd
├── test_asm_emit.gd
├── test_codegen_integration.gd
└── test_golden_regression.gd
```

---

## 9. Appendices

### Appendix A: All 13 IR Commands and Their Template Patterns

| Command | Words Pattern | Template | Key Features |
|---------|--------------|----------|--------------|
| MOV | `MOV dest src` | MOV | LOAD + STORE |
| OP | `OP op a b res` | OP[op] | @variant (12), @temp, op→mask lookup |
| IF | `IF cb_cond res cb_block` | IF | @label, @new_imm, @emit_cb |
| ELSE_IF | `ELSE_IF cb_cond res cb_block` | ELSE_IF | @label, @new_imm, @emit_cb |
| ELSE | `ELSE cb_block` | ELSE | @emit_cb |
| WHILE | `WHILE cb_cond res cb_block lbl_next lbl_end` | WHILE | @label, @new_imm, @emit_cb |
| CALL | `CALL fun [args...] res` | CALL | variadic, @ref_cb, @reverse, for loop |
| CALL_INDIRECT | `CALL_INDIRECT funvar [args...] res` | CALL_INDIRECT | variadic, for loop |
| RETURN | `RETURN [val]` | RETURN | @val:optional |
| ENTER | `ENTER scp_name` | ENTER | scope placeholder |
| LEAVE | `LEAVE` | LEAVE | scope placeholder |
| ALLOC | `ALLOC size res` | ALLOC | ADDR_REF |
| MOV_ARR | `MOV_ARR dest [vals...]` | MOV_ARR | @temp, variadic, for loop |

### Appendix B: Primitive Ops Summary

| # | Operation | Pass | Description |
|---|-----------|------|-------------|
| 1 | LOAD(name) → value | 2 | Resolve name to `*label`, `EBP[offset]`, or `value` |
| 2 | STORE(name) → target | 2 | Resolve name to `*label` or `EBP[offset]` |
| 3 | ALLOC_TEMP() → reg_or_stack | 1/2 | Pre-planned in Pass 1, resolved in Pass 2 |
| 4 | NEW_IMM(n) → symbol | 1 | Create immediate constant in manifest |
| 5 | NEW_LABEL(hint) → string | 1 | Generate unique label name |
| 6 | EMIT_CB(name) | 2 | Recursively emit code block inline |
| 7 | EMIT_LINE(text) | 2 | Resolve slots → append to buffer |
| 8 | MARK_REACHABLE(cb) | 1 | Register code block for later emission |

### Appendix C: Key Differences from Current Codegen

| Current (`codegen_md.gd`) | New Pipeline |
|--------------------------|--------------|
| 11 mutable globals | Zero mutable state |
| 13 `generate_cmd_*` functions | One `.tg` file with 13 `@template` blocks |
| `op_map` string dictionary | `@variant` directives in OPTemplate |
| `emit()` — 60-line combined function | Separate Pass 1 (discover) + Pass 2 (emit) |
| `find_reference()` — char-by-char `$/@/^` scanning | Structured SlotRef role system |
| `alloc_register()` — mutable dictionary | Pre-planned temp allocation in Pass 1 |
| `new_lbl()` — mutates `all_syms` | `@label` → pre-generated in Pass 1 |
| `referenced_cbs` — discovered lazily during emit | `@ref_cb` → discovered eagerly in Pass 1 |
| String concatenation at every step | AssemblyPart typed nodes → stringify once |
| Must read entire 833-line file to understand | Read one `.tg` file — self-documenting |
