# Functional Purity Advocate — Critique of All 9 Codegen Plans

**Author**: Functional Purity Advocate  
**Date**: 2026-06-27  
**Evaluated against**: Referential transparency, absence of mutable state, pure function composition, immutable data, separation of effects from computations.

---

## Executive Summary

Of the nine plans evaluated, only the **Unix Philosophy** and **Lisp/Macro-Driven** plans approach a genuinely pure design. The rest — including the technically impressive Data-Oriented Design — rely on pervasive mutable state and side-effectful procedures. The **GoF Design Patterns** plan is the single worst offender: it celebrates side-effectful patterns as virtues.

Below, each plan is critiqued in order from **closest to functional purity** to **furthest**.

---

## 1. Unix Philosophy Plan — Closest to Purity

### What it gets right

The Unix plan is the only one whose **interface contract enforces purity**. Every stage is `func transform(input: String) -> String`. This is a pure function signature — same input always yields same output, with no observable side effects.

From the plan itself:

```gdscript
# Each stage is a Node with a single transform function:
func transform(input: String) -> String:
    # Read input (text lines)
    # Process (one well-defined transformation)
    # Write output (text lines)
    pass
```

The plan explicitly declares:
> *"No globals. No mutable state. No side effects. Input is a string, output is a string."*

The pipeline becomes **function composition**:

```gdscript
func generate(ir_yaml: String) -> String:
    var flat      = stage_ir2flat.transform(ir_yaml)
    var allocated = stage_sym_alloc.transform(flat)
    var expanded  = stage_templ_expand.transform(allocated)
    var resolved  = stage_reg_resolve.transform(expanded)
    var assembly  = stage_line_asm.transform(resolved)
    return assembly
```

This is the only plan that explicitly prohibits mutable globals, enforces a `String → String` contract, and composes stages as pure function calls. **Text streams are immutable data** — each stage receives a string, produces a new string, and discards the input. No aliasing, no mutation, no hidden state.

### Where it falls short

The plan says stages are "pure" but doesn't mandate that **internal** processing be pure. The [`sym_alloc`](./plans/unix_philosophy_codegen_plan.md) stage, for example, builds an in-memory symbol table with flat arrays — still mutable, but scoped to the function. The register allocator uses a 4-element `Array[bool]` which is mutated locally rather than threaded as a persistent value.

This is **local mutation within a pure function** — acceptable in FP when the mutation is invisible to callers. But a stricter approach would thread state through return values (as the TDD plan's `RegAllocState` does).

### Verdict: **8/10** — The most pragmatically pure design. The `String → String` contract is a binding commitment to referential transparency at the composition boundary.

---

## 2. Lisp/Macro-Driven Plan — Homoiconic Purity

### What it gets right

This plan understands that **code generation is a sequence of pure transformations on data**. The macro expansion engine is fundamentally a pure function:

```
expand(sexpr: Array, env: Dictionary) -> Array
```

This is **referentially transparent**: the same IR S-expression always expands to the same assembly S-expression. No mutation, no side effects, no hidden state.

The pipeline of macro passes is composition of pure transformations:

```gdscript
var pipeline = [
    template_expansion_pass,
    storage_allocation_pass,
    register_allocation_pass,
    label_resolution_pass,
    serialization_pass,
]

func compile(ir_program) -> String:
    var asm_sexpr = into_sexpr(ir_program)
    for pass in pipeline:
        asm_sexpr = pass.process(asm_sexpr, env)
    return asm_sexpr
```

Each pass is a **macro**: a function that transforms one S-expression into another. This is the essence of functional programming — transforming immutable data through pure functions.

The plan's **homoiconicity** principle (code is data, data is code) aligns perfectly with functional purity. Templates are structured data (nested arrays), not strings with embedded markers. Quasiquotation is a pure mechanism for template expansion — it's essentially `map` over a data structure with substitution points.

**Metaprogramming without side effects**: The `define_alu_family` function is a pure function that returns a dictionary of macros. No mutation, no globals — just data in, data out.

```
func define_alu_family(ops: Dictionary) -> Dictionary:
    var result = {}
    for ir_name in ops:
        var asm_op = ops[ir_name]
        result[ir_name] = defmacro(...)
    return result
```

### Where it falls short

The `MacroEnvironment` (`env`) is **mutable**. It contains:
- `register_pool: Dictionary` — mutated by `alloc_register()`
- `label_counter: int` — mutated by `gensym()`
- `all_syms: Dictionary` — potentially mutated during passes

This is the plan's crucial compromise: the environment is an accumulator of mutable state that gets threaded through otherwise-pure transformations. A truly pure design would make `gensym` a function that returns `(new_symbol, new_env)` — threading the counter through return values.

However, this is a known tension in FP (see: Haskell's `State` monad). The plan's architecture **admits this imperative core** but isolates it in the environment object rather than scattering it through all components.

### Verdict: **7/10** — Architecturally aligned with functional purity. The mutable `env` is a necessary concession, but the overall transformation-oriented design is excellent.

---

## 3. TDD Plan — Pure State Machine, But Compromised by Mutable Buffers

### What it gets right

The TDD plan's [`RegAllocState`](./plans/tdd_codegen_plan.md) is a **genuinely pure state machine**:

```gdscript
func alloc() -> Dictionary:
    # Returns a NEW state with the register marked in-use
    var new_state = RegAllocState.new()
    new_state._in_use = _in_use.duplicate()
    new_state._in_use[i] = true
    return {"reg": REGS[i], "state": new_state}

func free(reg_name: String) -> RegAllocState:
    var new_state = RegAllocState.new()
    new_state._in_use = _in_use.duplicate()
    new_state._in_use[idx] = false
    return new_state
```

This is textbook functional state threading. `alloc()` does not mutate — it returns a new `RegAllocState` with the change applied. `free()` returns a new state. This is exactly how you'd write it in Haskell or Clojure.

The plan's philosophy emphasizes:
> *"Pure functions where possible (same input → same output, no side effects)"*
> *"Value types over mutable objects"*

The dependency injection architecture also supports purity — components receive their dependencies via constructors rather than pulling from global state.

### Where it falls short

The [`AssemblyBuffer`](./plans/tdd_codegen_plan.md) is a **purely imperative accumulator**:

```gdscript
var text: String = ""
func append(fragment: String) -> void:
    text += fragment    # MUTATION!
```

The `TemplateExpander` mutates its injected buffer:

```gdscript
func _expand_mov(cmd, tmpl):
    var src = _resolver.resolve_load(cmd.words[1])
    var dest = _resolver.resolve_store(cmd.words[2])
    _buf.append_with_size("mov %s, %s;\n" % [dest, src], tmpl.size)  # SIDE EFFECT
```

So while the *register allocator* is pure, the *emit pipeline* is entirely side-effectful. The expander returns `{"buf": _buf, "regs": _regs}` — acknowledging that the buffer was mutated. This is a hybrid: pure register management wrapped in an imperative emit shell.

A purely functional version would have `expand()` return `(new_buffer_text, new_reg_state)` rather than mutating an injected buffer.

### Verdict: **5/10** — Strong on theory (pure state machine, dependency injection, testability), but the actual implementation uses side-effectful mutation for the hot path.

---

## 4. Data-Oriented Design — Excellent Data Strategy, Catastrophic Purity Violation

### What it gets right

The DOD plan's data structures are **immutable-friendly**: `PackedInt32Array`, `PackedByteArray`, flat arrays. These are value-like — they *could* be used purely. The SoA layout is excellent for cache performance.

The pre-compiled template bytecode is pure data — a `PackedInt32Array` of emit opcodes, interpreted linearly. No string scanning, no runtime pattern matching.

### Where it falls short

**Everything is mutable global static state.** Every single array is declared `static var` at module level:

```gdscript
static var cmd_heads: PackedInt32Array
static var cmd_operand_offset: PackedInt32Array
static var cmd_operand_count: PackedInt32Array
static var cmd_operands: PackedStringArray
static var asm_buffer: PackedByteArray
static var asm_write_pos: int
static var reg_bitmask: int = 0
static var loc_ips: PackedInt32Array
```

The entire codegen is a **global state machine** — functions like `analyze()` mutate these arrays as side effects, returning `void`. The expander `expand_template()` mutates `asm_buffer`, `asm_write_pos`, `reg_bitmask`, `temp_reg_stack`, `loc_ips`, `loc_ranges`, `loc_kind` — all as side effects.

```gdscript
static func expand_template(tmpl_idx: int, cmd_idx: int) -> void:
    # Mutates: asm_buffer, asm_write_pos, reg_bitmask, loc_ips, ...
    # Returns: void
```

This is the **furthest possible from functional purity** while still being "data-oriented." The data is mutable, the functions are procedures, and there is zero referential transparency. Calling `expand_template(5, 12)` twice with the same arguments produces different results because the internal state has changed.

The register allocator uses a **mutable bitmask**:

```gdscript
static var reg_bitmask: int = 0

static func alloc_register_hot() -> int:
    if not (reg_bitmask & REG_EAX_BIT):
        reg_bitmask |= REG_EAX_BIT  # MUTATION!
        return REG_EAX
```

Compare this with the TDD plan's pure `RegAllocState` which returns a new state. The DOD version mutates a global integer — same semantics, but side-effectful.

### Verdict: **2/10** — Technically brilliant for performance, but architecturally the least pure. The `static var` approach is procedural programming dressed in flat arrays.

---

## 5. Literate Programming Plan — Simple but Impure

### What it gets right

The template table is **pure data**:

```gdscript
const template_table = {
    "MOV": {
        "pattern":  ["MOV", "dest", "src"],
        "assembly": ["mov {dest}, {src};"],
        "size": 8,
        "slots": ["dest", "src"],
    },
    ...
}
```

A const dictionary — immutable, referentially transparent, pure.

The pipeline pattern (`PatternMatcher → SlotResolver → Emitter`) separates concerns, though each stage is stateful.

### Where it falls short

Every component uses mutable state:

```gdscript
# RegisterAllocator — mutable dictionary
var _in_use = {}
func alloc() -> String:
    _in_use[reg] = true    # SIDE EFFECT
    return reg

# SlotResolver — mutable allocator
var _reg_alloc: RegisterAllocator
func resolve(binding, scope):
    # Calls _reg_alloc.alloc() — mutates internal state

# Emitter — mutable assembly block
var _assy_block: AssyBlock
func emit_template(template, resolved, loc, ir_trace):
    _assy_block.code += text   # MUTATION
    _assy_block.write_pos += size  # MUTATION

# CodegenPipeline — mutable IR state
var _all_syms: Dictionary
var _ir: Dictionary
func reset():  # EXISTS because the object is stateful
    _all_syms = {}
    _ir = {}
```

The plan explicitly uses a `reset()` method — a telltale sign of imperative state management. In a purely functional design, you'd just create a new pipeline for each compilation.

The fixup pass is a string-mutation operation:

```gdscript
func run(assy_block: AssyBlock, ir: Dictionary) -> void:
    var code = assy_block.code
    code = code.replace("__ENTER_%s;" % scp_name, "sub ESP, %d;" % (-stack_bytes))
    assy_block.code = code  # MUTATION
```

### Verdict: **4/10** — Well-structured, but entirely imperative. The `reset()` method and pervasive mutation make this a procedural design with good documentation.

---

## 6. XP Plan — Pragmatic Impurity

### What it gets right

The pipeline of four passes (`SlotAllocator → PatternMatcher → SlotResolver → Emitter`) has a clean data flow. The template table is pure data. The pipeline is simple and testable.

### Where it falls short

XP explicitly prioritizes simplicity over purity:

> *"No pass knows about passes beyond its immediate neighbor"*

This is good engineering but not functional purity. Every pass mutates its inputs or internal state:

```gdscript
class SlotAllocator:
    func allocate(ir: Dictionary) -> Dictionary:
        for scope in ir.scopes.values():
            for val in scope.vars: _alloc_value(val, scope)
        return ir  # Returns the SAME dictionary, MUTATED in place!
```

The `SlotAllocator` mutates the IR dictionary in place and returns it — a "destructive update" pattern. This breaks referential transparency: if you pass the same IR to `allocate()` twice, the second call sees already-allocated values.

The `Emitter` mutates `AssyBlock`:

```gdscript
class Emitter:
    func emit(fragments: Array[Fragment], debug_trace: bool) -> AssyBlock:
        var ab = AssyBlock.new()
        for frag in fragments:
            ab.code += line + "\n"  # MUTATION of local
            ab.write_pos += frag.template.size_per_line  # MUTATION
        return ab
```

The `Fragment` objects are also mutable:

```gdscript
class Fragment:
    var template: TemplateEntry
    var bindings: Dictionary
    var generated: Dictionary
    var resolved_lines: Array[String]
```

### Verdict: **3/10** — Pragmatic and clean, but entirely side-effectful. XP values simplicity, not purity.

---

## 7. Agile/Scrum Plan — Process, Not Architecture

### What it gets right

This plan is about **process**, not code architecture. It doesn't prescribe mutable state; it prescribes sprints and ceremonies. The technical section is deliberately vague ("just enough architecture").

### Where it falls short

Where it does specify architecture, it's imperative:

```gdscript
# Template.gd — compiled template object (mutable fields)
class_name Template
var name: String
var compiled: Array[TemplateOp]
var static_size: int
```

The `emit_interpreter` (Epic C, story C-3) is described as a "lightweight interpreter" — inherently a state machine with mutable program counters and output buffers.

The plan's focus on "velocity," "story points," and "sprint reviews" is orthogonal to functional purity. It neither helps nor hinders — it simply doesn't address purity as a concern.

### Verdict: **N/A** — This is a process plan, not an architecture plan. It has no meaningful stance on functional purity.

---

## 8. Waterfall/BDUF Plan — Mutable State Locked in by Specification

### What it gets right

Comprehensive documentation. The template data is separate from code. The pipeline has well-defined stages with explicit input/output contracts.

### Where it falls short

The "frozen" specification explicitly specifies mutable state:

```gdscript
# RegisterAllocator — specified with mutable Dictionary
class RegisterAllocator:
    var in_use: Dictionary = {}   # reg_name → bool
    
    func alloc() -> String or null
    func free(reg: String) -> void
```

This is a **mutable register allocator**, specified as a concrete class with mutation methods. The spec is so detailed that it locks in side-effectful patterns before any implementation begins.

The Allocation Pass is specified to **mutate the IR in place**:

```
Stage 2: Allocation Pass
  Input:  validated IR, AllocatorStrategy
  Output: IR with storage assigned to all values
  Algorithm:
    1. For each scope in ir.scopes: allocate storage
    2. Populate all_syms dictionary
```

The IR dictionary is mutated in place — the "output" is the same object with new fields added.

The plan also specifies a `CommandExpander` that calls `template_engine.expand()` which is inherently stateful (templates are loaded from files, cached, expanded with side effects).

### Verdict: **1/10** — The most rigid plan, and it rigidly specifies mutable state. The "measure twice, cut once" philosophy ensures that the wrong (impure) design is locked in early.

---

## 9. Design Patterns (GoF OOP) Plan — The Anti-Pattern to Functional Purity

### What it gets right

The template system is data-driven (pure data in YAML files). The Template Registry uses Prototype pattern with cloning (which *could* be used for immutable copies).

### Where it falls short

This plan is **textbook OOP — which is textbook impurity**. Every GoF pattern it uses is a **design for mutation**:

| Pattern | Impurity |
|---------|----------|
| **Visitor** | Visitor methods hit mutable state in the visited objects AND the visitor itself |
| **Command** | Every `IrCmd*` object is a mutable data holder (no immutability guarantee) |
| **Strategy** | Strategies are objects with mutable internal state (`regs: bool[4]`) |
| **Composite** | `AssyBlock.add(child)` — mutates children array |
| **Decorator** | Wraps mutable emitters; `emit()` is a side-effectful method |
| **Chain of Responsibility** | Handlers are objects that may maintain state |
| **Mediator** | Encapsulates mutable object interactions |
| **State** | **Explicitly designed to manage mutable state transitions** |
| **Prototype** | `duplicate()` is cloning, but the clones are mutable |

The State pattern is particularly galling from a functional perspective:

```gdscript
class CodegenContext:
    var state: CodegenState
    var ir_data: Dictionary
    var emitter: AssyEmitter
    var assy_block: AssyBlock
    var stor_alloc: StorageAllocator
    
    func change_state(new_state: CodegenState):
        if state: state.exit(self)
        state = new_state
        state.enter(self)
```

This is a **mutable context with mutable state transitions**. Every field is mutable. `change_state()` mutates `self.state`. The `State` pattern is the ultimate celebration of mutable state — it's designed to *manage* state by *mutating* it.

The plan brags about ~30 new files — each a new mutable object with methods. The Decorator pattern wraps side-effectful emitters with more side-effectful emitters. The Composite pattern builds tree structures that are recursively mutated.

From the plan's own file list:

```
Total: ~30 new files, each with a single focused responsibility. Compare to 1 file of 833 lines.
```

Yes, 30 files of mutable objects. Single responsibility means *each field can be mutated for a different reason*.

### Verdict: **0/10** — The furthest from functional purity. Every GoF pattern in this plan is a mutable object pattern. If functional purity is the goal, this plan is the antithesis.

---

## Ranking Summary

| Rank | Plan | Score | Why |
|------|------|-------|-----|
| 1 | **Unix Philosophy** | 8/10 | `String → String` pure function contract; pipeline is function composition; no globals |
| 2 | **Lisp/Macro-Driven** | 7/10 | Homoiconic transformations; pure macro expansion; pipeline of pure passes; mutable `env` is the only compromise |
| 3 | **TDD** | 5/10 | Genuinely pure `RegAllocState` state machine; dependency injection; but AssemblyBuffer and Expander are side-effectful |
| 4 | **Literate Programming** | 4/10 | Clean pipeline, but every component uses mutable state and `reset()` |
| 5 | **XP** | 3/10 | Pragmatic but entirely side-effectful; SlotAllocator mutates IR in place |
| 6 | **Data-Oriented Design** | 2/10 | `static var` mutable global arrays everywhere; zero referential transparency |
| 7 | **Waterfall/BDUF** | 1/10 | Locks in mutable state at the specification level; frozen errors |
| 8 | **Design Patterns (GoF OOP)** | 0/10 | Celebrity endorsement of every mutable pattern in the GoF catalog |
| — | **Agile/Scrum** | N/A | Process plan; no architectural stance on purity |

---

## Key Insights for a Pure Codegen Design

### What the best plans teach us

1. **The Unix plan's `String → String` contract is the gold standard.** Every stage is a pure function. Composition is function application. This is the simplest and most verifiably correct approach.

2. **The Lisp plan's homoiconic transformations are the most principled.** Representing both IR and assembly as structured data enables pure macro expansion. The only weakness is the mutable environment — which can be fixed by threading state through return values (as the TDD plan's `RegAllocState` demonstrates).

3. **The TDD plan's `RegAllocState` is the right pattern for state management.** Instead of mutating a global bitmask, return a new state. This is how you make state referentially transparent.

### A purely functional codegen would combine these ideas

```
Layer 1: All data is immutable (Strings, PackedByteArray, nested Arrays)
Layer 2: Every stage is a pure function: Stage(input) → (output, new_state)
Layer 3: Pipeline is function composition with state threading
Layer 4: The driver calls the pipeline once — no reset(), no mutation
```

Concretely:

```gdscript
# The pure codegen pipeline:
func generate(ir: Dictionary) -> AssemblyResult:
    var s0 = alloc_storage(ir)             # pure: (IR) → AssemblyState
    var t0 = match_templates(s0)            # pure: (AssemblyState) → AssemblyState
    var t1 = resolve_operands(t0)           # pure: (AssemblyState) → AssemblyState
    var t2 = allocate_registers(t1)         # pure: (AssemblyState) → AssemblyState
    var t3 = resolve_labels(t2)             # pure: (AssemblyState) → AssemblyState
    var result = serialize(t3)              # pure: (AssemblyState) → String
    return AssemblyResult.new(result.text, result.loc_map)
```

Each stage is a **pure function** that takes an immutable snapshot and returns a new one. No globals, no mutation, no side effects. The entire codegen is a single expression.
