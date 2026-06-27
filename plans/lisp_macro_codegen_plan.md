# Lisp / Macro-Driven Codegen Plan

**Persona**: Lisp / Macro-Driven Advocate  
**Date**: 2026-06-27  
**Context**: Replace the ad-hoc [`codegen_md.gd`](../scenes/codegen_md.gd) (833 lines) with a data-driven, macro-expansion-based codegen for the CpuDerp IR-to-assembly stage, following Lisp principles of homoiconicity, code-as-data, and bottom-up programming.

---

## 1. Diagnosis of the Current Codegen

The existing [`codegen_md.gd`](../scenes/codegen_md.gd) is structured as a **procedural interpreter over IR data**, not as a **compiler that transforms data into data**. Every Lisp principle is violated:

| Violation | Location | Description |
|-----------|----------|-------------|
| No homoiconicity | [`op_map`](../scenes/codegen_md.gd:12) | Templates are *strings* with `%a`/`%b` placeholders, not data structures |
| String-based template substitution | [`emit`](../scenes/codegen_md.gd:474) | Finds `$`/`@`/`^` markers via `find_reference` and does string surgery — fragile, non-composable |
| Giant match as pseudo-dispatch | [`generate_cmd`](../scenes/codegen_md.gd:266) | `match cmd.words[0]` — a poor man's `funcall`; no generic dispatch mechanism |
| Side-effectful generators | [`generate_cmd_mov`](../scenes/codegen_md.gd:284) | Each generator calls `emit()` which mutates `cur_assy_block.code` |
| No macro pipeline | [`generate`](../scenes/codegen_md.gd:143) | Single monolithic pass; no separation of concerns |
| Templates not first-class | [`op_map`](../scenes/codegen_md.gd:12) | Templates cannot be combined, parametrized, or abstracted |
| Code mixed with data | [all of `codegen_md.gd`] | Assembly instruction patterns are embedded inside function bodies |

**Consequences**: Adding a new IR instruction requires modifying a function body. There is no way to reason about patterns generically. Extending the ISA means writing new GDScript, not declaring new templates.

---

## 2. Philosophical Foundation

### 2.1 Homoiconicity

> *Code is data, data is code.*

**IR commands** and **assembly instructions** should both be represented as **S-expression-like nested arrays** (homoiconic data). A template is **both data (a list structure) and code (a transformation rule)**. The template engine is a **macro expander** — it takes IR S-expressions and rewrites them into assembly S-expressions.

### 2.2 Macros as Template Expansion

A macro is a **function that transforms code before evaluation**. In codegen terms:

```
IR_Sexpr  ──[macro-expand]──>  Assembly_Sexpr  ──[serialize]──>  Assembly_Text
```

Each IR command is a **macro invocation**. The template for that command is a **macro definition**: a pattern + a rewrite rule. Macros are first-class data — they live in a table, can be combined, wrapped, and parametrized.

### 2.3 Bottom-Up Programming

> *Build the language up to your problem, then solve the problem.*

1. **Layer 0**: Define the core S-expression primitives (IR sexpr, assembly sexpr).
2. **Layer 1**: Build the macro expansion engine (pattern matcher, rewriter, environment).
3. **Layer 2**: Define the instruction templates as macro definitions (pure data).
4. **Layer 3**: Build macro passes (register allocation, label resolution, location tracking).
5. **Layer 4**: The driver composes passes into a pipeline.

Each layer is expressed in terms of the layers below it. The final codegen is a **composition of macro transforms**.

### 2.4 DSL Embedding

GDScript lacks native macros, but we can embed a **small DSL** for instruction templates using GDScript data literals (arrays and dictionaries). This DSL is itself defined using the same macro principles — a **meta-circular** definition.

---

## 3. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Layer 4: Codegen Driver                         │
│  compile(ir_program) ──> assembly_text                                  │
│  orchestrates macro passes in order                                     │
├─────────────────────────────────────────────────────────────────────────┤
│                         Layer 3: Macro Passes                           │
│  ┌───────────────┐  ┌──────────────┐  ┌────────────────┐               │
│  │ register-alloc │  │ label-resolve│  │ location-track │  ...           │
│  └───────────────┘  └──────────────┘  └────────────────┘               │
│  Each pass is a macro: transform assembly sexpr → assembly sexpr        │
├─────────────────────────────────────────────────────────────────────────┤
│                      Layer 2: Template / Macro Table                    │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  macro_table = {                                                  │   │
│  │    "MOV":     macro( pattern( cmd[1] cmd[2] ),                    │   │
│  │                   → `(mov ,dest ,src) ),                          │   │
│  │    "ADD":     macro( pattern( cmd[1] cmd[2] cmd[3] ),             │   │
│  │                   → `(add ,a ,b  mov ,res ,a) ),                  │   │
│  │    "IF":      IF_MACRO,   ← macros can be generators too           │   │
│  │    ...                                                             │   │
│  │  }                                                                 │   │
│  └──────────────────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────────────┤
│                    Layer 1: Macro Expansion Engine                       │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  expand(sexpr, env) ──> sexpr                                     │   │
│  │  match(pattern, sexpr) ──> bindings | null                        │   │
│  │  rewrite(template, bindings) ──> sexpr                            │   │
│  │  quasiquote / unquote (backtick ,@ ,)                             │   │
│  └──────────────────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────────────┤
│                    Layer 0: S-Expression Primitives                      │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  IR_Sexpr    = Array  (e.g. ["MOV", "dest", "src"])              │   │
│  │  Asm_Sexpr   = Array  (e.g. ["mov", "^dest", "$src"])            │   │
│  │  Pattern     = Array with pattern-variables                      │   │
│  │  Env         = Dictionary (symbol → value, register state, ...)   │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

### Key Insight: Quasiquotation

In Lisp, the backtick (`` ` ``) introduces a **quasiquote**: a template that is mostly literal but allows **unquoting** (`,`) to splice in computed values. In GDScript, we represent this as nested arrays with a quasiquote marker:

```gdscript
# Lisp:    `(mov ,dest ,src)
# GDScript: ["quasiquote", ["mov", ["unquote", "dest"], ["unquote", "src"]]]
```

But we can be more ergonomic: use a **template DSL** that looks like:

```gdscript
var t_mov = qq(["mov", ^"dest", $"src"])  # `^` means store-address, `$` means load-value
```

---

## 4. The Macro Expansion Engine

### 4.1 Core: `expand(sexpr, env) → sexpr`

The fundamental operation. Given an S-expression and an environment, rewrite it:

```gdscript
func expand(sexpr:Array, env:Dictionary) -> Array:
    if sexpr.is_empty():
        return sexpr
    var head = sexpr[0]
    if head is String and head in macro_table:
        var macro_fn = macro_table[head]
        return expand(macro_fn.call(sexpr, env), env)
    # Default: recursively expand sub-expressions
    var result = []
    for s in sexpr:
        result.append(expand_element(s, env))
    return result

func expand_element(s, env):
    if s is Array:
        return expand(s, env)
    if s is PatternVar:
        return env[s.name]
    return s
```

### 4.2 Pattern Matching

A pattern is an S-expression where some positions are **pattern variables**:

```gdscript
class PatternVar:
    var name: String
    var constraint: Callable  # optional type/class constraint
    
class Pattern:
    var template: Array  # the pattern shape with PatternVars embedded
```

```gdscript
func match(pattern:Array, sexpr:Array) -> Dictionary:
    var bindings = {}
    _match_recursive(pattern, sexpr, bindings)
    return bindings

func _match_recursive(p, s, bindings):
    if p is PatternVar:
        if p.constraint and not p.constraint.call(s):
            return false  # constraint failed
        bindings[p.name] = s
        return true
    if p is Array and s is Array:
        if p.size() != s.size():
            return false
        for i in p.size():
            if not _match_recursive(p[i], s[i], bindings):
                return false
        return true
    return p == s
```

### 4.3 Template Rewriting (Quasiquote Expansion)

```gdscript
# `(mov ,dest ,src)  →  ["mov", env["dest"], env["src"]]
func expand_qq(template:Array, bindings:Dictionary) -> Array:
    var result = []
    for elem in template:
        if elem is QQUnquote:
            result.append(bindings[elem.name])
        elif elem is Array:
            result.append(expand_qq(elem, bindings))
        else:
            result.append(elem)
    return result
```

Where `QQUnquote` is a marker class:

```gdscript
class QQUnquote:
    var name: String
```

### 4.4 Convenience DSL: `qq()` and `pv()`

```gdscript
# Helper to build quasiquoted templates
static func qq(template) -> Array:
    return _qq_mark(template)

static func _qq_mark(sexpr):
    if sexpr is Array:
        return sexpr.map(_qq_mark)
    return sexpr  # literals pass through

# Pattern variable constructor
static func pv(name: String, constraint: Callable = Callable()) -> PatternVar:
    return PatternVar.new(name, constraint)
```

### 4.5 Macro Definition

A macro is any callable that takes an IR command S-expression and returns an assembly S-expression:

```gdscript
class Macro:
    var pattern: Pattern
    var template: Array        # quasiquoted assembly template
    var expander: Callable     # optional: full custom expander (for complex control flow)
    
    func apply(sexpr:Array, env:Dictionary) -> Array:
        if expander.is_valid():
            return expander.call(sexpr, env)
        var bindings = match(pattern.template, sexpr)
        if bindings.is_empty():
            push_error("pattern match failed for: ", sexpr)
            return []
        return expand_qq(template, bindings)
```

---

## 5. Template DSL Design

### 5.1 Simple Arithmetic Macros

Simple templates are **pure data declarations** — no functions to write:

```gdscript
# Template table: the heart of the codegen
const MACRO_TABLE = {
    "MOV":  Macro.new(pv(["MOV", pv("dest"), pv("src")]),
                qq(["mov", "^" + ^"dest", "$" + ^"src"])),
    
    "ADD":  Macro.new(pv(["OP", "ADD", pv("a"), pv("b"), pv("res")]),
                qq(["mov", $"t1", $"a",
                    "mov", $"t2", $"b",
                    "add", ^"t1", ^"t2",
                    "mov", ^"res", ^"t1"])),
    
    "SUB":  Macro.new(pv(["OP", "SUB", pv("a"), pv("b"), pv("res")]),
                qq(["mov", $"t1", $"a",
                    "mov", $"t2", $"b",
                    "sub", ^"t1", ^"t2",
                    "mov", ^"res", ^"t1"])),
                    
    "GREATER": Macro.new(pv(["OP", "GREATER", pv("a"), pv("b"), pv("res")]),
                qq(["cmp", $"a", $"b",
                    "mov", ^"res", "CTRL",
                    "band", ^"res", "CMP_G",
                    "bnot", ^"res",
                    "bnot", ^"res"])),
}
```

Each template is **data, not code**. Adding a new ALU op means adding one entry to the table.

### 5.2 Control Flow Macros (Generators)

Control flow like `IF` needs **computed labels** and **conditional branching**. These are **generator macros** — they have a custom expander that generates labels and wires blocks:

```gdscript
MACRO_TABLE["IF"] = Macro.new_with_expander(
    pv(["IF", pv("cb_cond"), pv("res"), pv("cb_block")]),
    # custom expander:
    func(sexpr, env):
        var bindings = match(Pattern(["IF", pv("cb_cond"), pv("res"), pv("cb_block")]), sexpr)
        var lbl_else = env.gensym("if_else")
        var lbl_end  = env.gensym("if_end")
        var imm0 = env.allocate_immediate(0)
        return [
            qq_ref(@$"cb_cond"),           # emit the condition codeblock
            ["cmp", $"res", imm0],
            ["jz", lbl_else],
            qq_ref(@$"cb_block"),          # emit the then-block
            ["jmp", lbl_end],
            [":", lbl_else],
            [":", lbl_end],
        ]
)
```

### 5.3 Macro-Composition: `defmacro` in GDScript

Since GDScript doesn't have `defmacro`, we define a factory:

```gdscript
static func defmacro(pattern_pattern:Array, template_or_expander):
    """Define a macro entry. If template_or_expander is an Array, treat as quasiquoted template.
       If it's a Callable, treat as a custom expander."""
    if template_or_expander is Array:
        return Macro.new(Pattern.new(pattern_pattern), template_or_expander)
    else:
        return Macro.new_with_expander(Pattern.new(pattern_pattern), template_or_expander)
```

Usage:

```gdscript
const alu_macros = {
    "ADD": defmacro(
        ["OP", "ADD", pv("a"), pv("b"), pv("res")],
        qq(["mov", $"t1", $"a", "mov", $"t2", $"b", "add", ^"t1", ^"t2", "mov", ^"res", ^"t1"])
    ),
    "DEC": defmacro(
        ["OP", "DEC", pv("a"), pv("b"), pv("res")],
        qq(["dec", ^"res", "mov", ^"res", $"a"])
    ),
}

# Merge with main table
MACRO_TABLE.merge(alu_macros)
```

---

## 6. Macro Passes

A key Lisp insight: **macros run in passes**. Each pass transforms the representation one step closer to the final output. This replaces the monolithic [`generate`](../scenes/codegen_md.gd:143) function.

### 6.1 Pass 0: Deserialization (IR Load)

```
Input:  YAML text
Output: IR Program (S-expressions in a dictionary)
```

Already handled by [`deserialize`](../scenes/codegen_md.gd:64) / [`uYaml`](../scenes/uYaml.gd). Keep this layer minimal.

### 6.2 Pass 1: Template Expansion (IR → Pseudo-Assembly)

```
Input:  IR_Program (sexpr tree: code_blocks + scopes)
Output: Pseudo-Assembly (sexpr tree with symbolic references)
```

- Each `IR_Cmd` is matched against `MACRO_TABLE` and expanded.
- `emit_cb` becomes macro expansion: `macro_expand(cb)` instead of `generate_code_block(cb)`.
- Labels, immediates, and temporaries are **gensyms** — symbols generated by the macro system.

### 6.3 Pass 2: Storage Allocation

```
Input:  Pseudo-Assembly (symbolic references to variables)
Output: Pseudo-Assembly (with stack offsets / global labels resolved)
```

A macro pass that rewrites variable references:

```gdscript
var storage_pass = MacroPass.new()
storage_pass.add_rule(
    pv("$" + pv("var")),
    func(sexpr, env):
        var handle = env.lookup(sexpr.var)
        match handle.storage.type:
            "global": return sexpr  # already a label reference
            "stack":  return ["EBP", handle.storage.pos]
            "register": return handle.storage.reg
)
```

### 6.4 Pass 3: Register Allocation

```
Input:  Pseudo-Assembly (with symbolic temporaries)
Output: Pseudo-Assembly (with physical registers or stack slots)
```

A constraint-based macro pass:

```gdscript
var reg_alloc_pass = MacroPass.new()
reg_alloc_pass.on_symbol("temporary", func(sym, env):
    var reg = env.alloc_register()
    if reg:
        return reg  # replace temp with register name
    else:
        return env.alloc_stack_slot(sym)  # spill to stack
)
```

### 6.5 Pass 4: Label Resolution

```
Input:  Pseudo-Assembly (with symbolic labels and cross-references)
Output: Linear Assembly (concrete byte offsets resolved)
```

```gdscript
var label_pass = MacroPass.new()
label_pass.on_enter(func(sexpr, env):
    # First pass: collect all label positions
    if sexpr[0] == ":":
        env.define_label(sexpr[1], env.current_offset())
)
label_pass.on_exit(func(sexpr, env):
    # Second pass: resolve label references
    if sexpr[0] in ["jmp", "jz", "call"] and env.is_label(sexpr[1]):
        sexpr[1] = env.resolve_label(sexpr[1])
)
```

### 6.6 Pass 5: Final Serialization

```
Input:  Linear Assembly (sexpr tree)
Output: Assembly Text (string)
```

The last pass flattens the sexpr tree into text:

```gdscript
func serialize(sexpr:Array) -> String:
    var text = ""
    for elem in sexpr:
        if elem is Array:
            text += serialize(elem)
        elif elem is String:
            text += elem + " "
        elif elem is int:
            text += str(elem) + " "
        # etc.
    return text
```

### 6.7 Pipeline Composition

```gdscript
var pipeline = [
    template_expansion_pass,   # Pass 1
    storage_allocation_pass,   # Pass 2
    register_allocation_pass,  # Pass 3 (may invoke Pass 2 for spills)
    label_resolution_pass,     # Pass 4
    serialization_pass,        # Pass 5
]

func compile(ir_program:Dictionary) -> String:
    var asm_sexpr = into_sexpr(ir_program)
    for pass in pipeline:
        asm_sexpr = pass.process(asm_sexpr, env)
    return asm_sexpr  # now a string
```

---

## 7. Comparison: Current vs. Macro-Driven

| Concern | Current (`codegen_md.gd`) | Macro-Driven |
|---------|--------------------------|--------------|
| ALU instructions | [`op_map`](../scenes/codegen_md.gd:12) string table + [`generate_cmd_op`](../scenes/codegen_md.gd:294) function | Declarative macro table entries |
| New IR instruction | Write a new `generate_cmd_*` function | Add one macro entry in data |
| Control flow | [`generate_cmd_if`](../scenes/codegen_md.gd:349) (41 lines) | Custom expander macro (~12 lines) |
| Register allocation | [`alloc_register`](../scenes/codegen_md.gd:634) + [`free_val`](../scenes/codegen_md.gd:628) | Dedicated macro pass |
| Label generation | [`new_lbl`](../scenes/codegen_md.gd:327) (ad-hoc) | `env.gensym()` (principled) |
| Template substitution | `$`/`@`/`^` string markers + [`find_reference`](../scenes/codegen_md.gd:542) | Quasiquote + unquote (structured) |
| Location tracking | [`mark_loc_begin`](../scenes/codegen_md.gd:790) / [`mark_loc_end`](../scenes/codegen_md.gd:795) | Macro pass over sexpr tree |
| Why testable? | Must mock global state | Pipe data through pure functions |
| Composability | None — functions call `emit()` | Any macro can wrap another |

---

## 8. Detailed Design: Classes and Modules

### 8.1 New Files

| File | Purpose |
|------|---------|
| [`macro_engine.gd`](macro_engine.gd) | Core expander, pattern matcher, quasiquote expander |
| [`macro_table.gd`](macro_table.gd) | All instruction templates as data |
| [`macro_passes.gd`](macro_passes.gd) | Register alloc, label resolve, storage allocate passes |
| [`macro_codegen.gd`](macro_codegen.gd) | Driver: composes passes, [`compile()`](macro_codegen.gd) entry point |
| [`macro_sexpr.gd`](macro_sexpr.gd) | S-expression primitives, value classes |

### 8.2 Class: [`MacroEngine`](macro_engine.gd)

```gdscript
# macro_engine.gd
class_name MacroEngine

var macro_table: Dictionary = {}
var env: MacroEnvironment

func expand(sexpr:Array) -> Array:
    # Recursively expand macros until fixpoint
    var prev = null
    var curr = sexpr
    while curr.hash() != (prev.hash() if prev else -1):
        prev = curr
        curr = _expand_once(curr)
    return curr

func _expand_once(sexpr:Array) -> Array:
    if sexpr.is_empty(): return sexpr
    var head = sexpr[0]
    if head is String and head in macro_table:
        var m = macro_table[head] as Macro
        return m.apply(sexpr.slice(1), env)
    # Default: recursively expand elements
    return sexpr.map(func(s): return s if not (s is Array) else _expand_once(s))

func define_macro(name:String, macro:Macro) -> void:
    macro_table[name] = macro
```

### 8.3 Class: [`MacroEnvironment`](macro_engine.gd)

```gdscript
# macro_engine.gd
class_name MacroEnvironment

var all_syms: Dictionary = {}
var label_counter: int = 0
var register_pool: Dictionary = {}
# Pass-specific state stored as tagged data

func gensym(prefix:String = "lbl") -> String:
    label_counter += 1
    return "%s_%d" % [prefix, label_counter]

func lookup(name:String) -> Dictionary:
    return all_syms.get(name, {})

func alloc_register() -> String:
    for reg_name in register_pool:
        if not register_pool[reg_name]:
            register_pool[reg_name] = true
            return reg_name
    return ""  # no free register

func free_register(reg_name:String) -> void:
    if reg_name in register_pool:
        register_pool[reg_name] = false
```

### 8.4 Class: [`MacroPass`](macro_passes.gd)

```gdproof
# macro_passes.gd
class_name MacroPass

var rules: Array[MacroPassRule] = []
var enter_hooks: Array[Callable] = []
var exit_hooks: Array[Callable] = []

func process(sexpr:Array, env:MacroEnvironment) -> Array:
    for hook in enter_hooks: hook.call(sexpr, env)
    var result = _walk(sexpr, env)
    for hook in exit_hooks: hook.call(result, env)
    return result

func _walk(sexpr:Array, env:MacroEnvironment) -> Array:
    var result = []
    for elem in sexpr:
        if elem is Array:
            var transformed = _apply_rules(elem, env)
            if transformed != elem:
                result.append_array(transformed if transformed is Array else [transformed])
            else:
                result.append(_walk(elem, env))
        else:
            result.append(elem)
    return result

func _apply_rules(sexpr:Array, env:MacroEnvironment) -> Array:
    for rule in rules:
        var bindings = match(rule.pattern, sexpr)
        if not bindings.is_empty():
            return rule.action.call(sexpr, bindings, env)
    return sexpr  # no rule matched
```

### 8.5 Template Table Example ([`macro_table.gd`](macro_table.gd))

```gdscript
# macro_table.gd — all instruction templates as PURE DATA

const T = preload("res://macro_engine.gd")

static func alu_macro(op_name:String, asm_template:Array) -> Macro:
    return T.defmacro(
        ["OP", op_name, pv("a"), pv("b"), pv("res")],
        asm_template
    )

static func build_table() -> Dictionary:
    var table = {}
    
    # Simple ALU ops: pure data declarations
    table["ADD"] = alu_macro("ADD", qq(
        ["mov", ^"t1", $"a",
         "mov", ^"t2", $"b",
         "add", ^"t1", ^"t2",
         "mov", ^"res", ^"t1"]
    ))
    table["SUB"] = alu_macro("SUB", qq(
        ["mov", ^"t1", $"a",
         "mov", ^"t2", $"b",
         "sub", ^"t1", ^"t2",
         "mov", ^"res", ^"t1"]
    ))
    table["GREATER"] = alu_macro("GREATER", qq(
        ["cmp", $"a", $"b",
         "mov", ^"res", "CTRL",
         "band", ^"res", "CMP_G",
         "bnot", ^"res",
         "bnot", ^"res"]
    ))
    
    # Control flow: custom expander macros
    table["IF"] = T.defmacro_with(
        ["IF", pv("cb_cond"), pv("res"), pv("cb_block")],
        func(sexpr, bindings, env):
            var lbl_else = env.gensym("if_else")
            var lbl_end  = env.gensym("if_end")
            var imm0 = env.allocate_immediate(0)
            return [
                qq_ref(bindings["cb_cond"]),   # emit condition
                ["cmp", bindings["res"], imm0],
                ["jz", lbl_else],
                qq_ref(bindings["cb_block"]),  # emit then-block
                ["jmp", lbl_end],
                [":", lbl_else],
                [":", lbl_end],
            ]
    )
    
    table["WHILE"] = T.defmacro_with(
        ["WHILE", pv("cb_cond"), pv("res"), pv("cb_block"), pv("lbl_next"), pv("lbl_end")],
        func(sexpr, bindings, env):
            var imm0 = env.allocate_immediate(0)
            return [
                [":", bindings["lbl_next"]],
                qq_ref(bindings["cb_cond"]),
                ["cmp", bindings["res"], imm0],
                ["jz", bindings["lbl_end"]],
                qq_ref(bindings["cb_block"]),
                ["jmp", bindings["lbl_next"]],
                [":", bindings["lbl_end"]],
            ]
    )
    
    table["CALL"] = T.defmacro_with(
        ["CALL", pv("fun"), pv("args", Constraint.is_array), pv("res")],
        func(sexpr, bindings, env):
            var n = bindings["args"].size()
            var result = []
            for arg in bindings["args"]:
                result.append(["push", "$" + arg])
            result.append(["call", "@" + bindings["fun"]])
            result.append(["add", "ESP", str(4 * n)])
            result.append(["mov", "^" + bindings["res"], "eax"])
            return result
    )
    
    return table
```

---

## 9. Migration Strategy

### Phase 1: Sexpr Foundation
- Implement [`macro_sexpr.gd`](macro_sexpr.gd) with `PatternVar`, `QQUnquote`, `Pattern` classes.
- Implement [`macro_engine.gd`](macro_engine.gd) with `expand`, `match`, `expand_qq`.
- **Test**: Verify that `match` and `expand_qq` work correctly for simple patterns.

### Phase 2: Port ALU Templates
- Build [`macro_table.gd`](macro_table.gd) with ALU op templates (migrated from [`op_map`](../scenes/codegen_md.gd:12)).
- Build [`macro_passes.gd`](macro_passes.gd) with the storage-allocation macro pass (replacing `load_value`/`store_val`/`address_value`).
- **Test**: Generate identical assembly for arithmetic-heavy test programs.

### Phase 3: Port Control Flow
- Implement `IF`, `ELSE_IF`, `ELSE`, `WHILE`, `CALL` as generator macros.
- Replace the [`generate_cmd_if`](../scenes/codegen_md.gd:349) family of functions.
- **Test**: Generate identical assembly for control-flow-heavy programs.

### Phase 4: Register Allocation Pass
- Build the register allocation macro pass (replacing [`alloc_register`](../scenes/codegen_md.gd:634) / [`free_val`](../scenes/codegen_md.gd:628)).
- **Test**: Verify register reuse and spilling behavior.

### Phase 5: Label Resolution & Serialization
- Build label resolution pass.
- Build final serialization pass.
- **Test**: Full end-to-end IR → Assembly text parity with current codegen.

### Phase 6: Replace `codegen_md.gd`
- Route [`compile()`](macro_codegen.gd) through macro pipeline.
- Remove deprecated `generate_cmd_*` functions.
- **Test**: All existing programs compile identically.

---

## 10. Homoiconicity in Practice

### 10.1 Debugging: Inspect Intermediate S-Expressions

Because every macro pass transforms one sexpr into another, you can **inspect the output of any pass**:

```gdscript
var after_pass2 = pipeline[2].process(after_pass1, env)
print(after_pass2)  # See what register allocation did
```

This is impossible with the current codegen — the output is written directly to a string.

### 10.2 Metaprogramming: Macros that Write Macros

A **macro-generating macro** can create families of templates:

```gdscript
func define_alu_family(ops:Dictionary) -> Dictionary:
    """ops = {"ADD":"add", "SUB":"sub", "MUL":"mul", ...}"""
    var result = {}
    for ir_name in ops:
        var asm_op = ops[ir_name]
        result[ir_name] = defmacro(
            ["OP", ir_name, pv("a"), pv("b"), pv("res")],
            qq(["mov", ^"t1", $"a",
                "mov", ^"t2", $"b",
                asm_op, ^"t1", ^"t2",
                "mov", ^"res", ^"t1"])
        )
    return result

# One call generates 10+ macros:
MACRO_TABLE.merge(define_alu_family({
    "ADD": "add", "SUB": "sub", "MUL": "mul",
    "DIV": "div", "MOD": "mod",
    "AND": "and", "OR": "or", "XOR": "xor",
}))
```

### 10.3 Pattern Matching as Code Analysis

Pattern matching can be used for **analysis passes** (optimization, validation):

```gdscript
# Dead-code elimination macro pass
func dead_code_elimination(sexpr, env):
    if match(["mov", pv("_"), pv("_")], sexpr) and _next_is_jmp(sexpr):
        return []  # eliminate dead code before unconditional jump
    return sexpr
```

---

## 11. Summary: The Lisp Way

| Principle | How It Manifests |
|-----------|-----------------|
| **Homoiconicity** | IR and assembly are both nested arrays (S-expressions). Templates are data, not strings. |
| **Macros** | Each IR command is a macro invocation. The template table is the macro definition set. |
| **Bottom-up** | Layer 0: sexpr primitives. Layer 1: macro expander. Layer 2: templates. Layer 3: passes. Layer 4: driver. |
| **DSL embedding** | Template definitions form a DSL for instruction encoding, embedded in GDScript data literals. |
| **Code as data** | `MACRO_TABLE` is pure data. Adding an instruction = adding one dictionary entry. |
| **Metaprogramming** | Macro-generating macros (`define_alu_family`) eliminate repetition. |
| **Multiple passes** | Each concern is a separate macro pass. Compose them in a pipeline. |
| **Extensible compiler** | New ISA → new template entries. New optimization → new macro pass. No core code changes. |

The result is a codegen that is **declarative, extensible, inspectable, and composable** — all properties that follow from treating code as data and using macros as the fundamental transformation primitive.
