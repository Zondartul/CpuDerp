# TDD-Driven Codegen Plan

**Persona**: Test-Driven Development (TDD) Advocate  
**Date**: 2026-06-27  
**Context**: Replace the ad-hoc [`codegen_md.gd`](../scenes/codegen_md.gd) (767 lines) with a data-driven, test-first codegen for the CpuDerp IR-to-assembly stage.

---

## 1. Diagnosis of the Current Codegen (TDD View)

The existing [`codegen_md.gd`](../scenes/codegen_md.gd) is **untestable by design**. Every obstacle below makes writing a unit test impossible without mocking the entire Godot runtime.

| TDD Violation | Location | Why It Blocks Testing |
|---------------|----------|----------------------|
| Mutable module-level globals | [`var IR = {}`](../scenes/codegen_md.gd:27), [`var all_syms = {}`](../scenes/codegen_md.gd:28), [`var regs_in_use = {}`](../scenes/codegen_md.gd:32) | Tests cannot run in isolation — state leaks between test cases. Must call [`reset()`](../scenes/codegen_md.gd:40) before every test, but `reset()` itself is a 12-field mutation that can get out of sync. |
| Side-effectful emit that reaches into global state | [`emit_raw`](../scenes/codegen_md.gd:606) mutates `cur_assy_block.code` and `cur_assy_block.write_pos` | Can't assert on return value — there is none. Must inspect global after call. If test forgets to set up `cur_assy_block`, it crashes. |
| Template logic mixed with operand resolution | [`emit`](../scenes/codegen_md.gd:474) does string scanning (`find_reference`), register allocation, deref handling, and text emission in one 60-line function | Every test for any command must set up the entire emit infrastructure — registers, symbol table, assembly block, location tracking. |
| Hash map symbol table with stringly-typed lookups | [`all_syms[ir_name]`](../scenes/codegen_md.gd:551) | No type safety. A test that misspells an `ir_name` gets a silent `null` and crashes downstream. No way to mock or stub symbol lookups. |
| `match` statement as command dispatch | [`generate_cmd`](../scenes/codegen_md.gd:266) hardcodes all 13 command types in a `match` | Adding a new command means modifying this function AND adding a `generate_cmd_*` function. Cannot test dispatch logic independently. |
| YAML deserialization coupled to codegen logic | [`parse_file`](../scenes/codegen_md.gd:55) reads a file AND deserializes AND inflates objects AND builds symbol table | Testing any codegen path requires a real YAML file on disk. Cannot construct a test IR program programmatically. |
| String concatenation for assembly output | [`cur_assy_block.code += text`](../scenes/codegen_md.gd:608) | Hard to assert on partial results. Must generate entire assembly string and regex-match for expected fragments. |
| Register allocator as global dictionary | [`regs_in_use`](../scenes/codegen_md.gd:32) with [`alloc_register`](../scenes/codegen_md.gd:634) / [`free_val`](../scenes/codegen_md.gd:628) | Tests must manually manage register state. A test that forgets to `free_val` leaks register allocations to subsequent tests. |
| Location tracking entangled with emit | [`mark_loc_begin`](../scenes/codegen_md.gd:790) / [`mark_loc_end`](../scenes/codegen_md.gd:795) called inside `generate_cmd_mov` etc. | Cannot test location tracking separately from command generation. |
| No interfaces, no dependency injection | Everything is `self.*` globals | Cannot substitute test doubles. Cannot verify interactions. Cannot test boundary conditions without triggering the full pipeline. |

**The consequence**: The current codegen has **zero tests**. Every bug fix risks regressions. Every new feature requires manual testing with the full compiler pipeline.

---

## 2. Philosophical Foundation

### Core Principles

1. **Red-Green-Refactor**: Write the test first (it fails — Red), write the minimal code to pass (it passes — Green), then improve the design (Refactor). Each cycle is 2–10 minutes.

2. **Testable Design Emerges from Test-First**: If a function is hard to test, the design is wrong. Restructure until the test is trivial. This means:
   - **Pure functions** where possible (same input → same output, no side effects)
   - **Dependency injection** where side effects are unavoidable
   - **Small, focused units** with single responsibilities
   - **Value types** over mutable objects

3. **Test the Behaviour, Not the Implementation**: Tests assert on observable outputs (strings, counts, presence/absence of labels). Tests do NOT assert on internal state (which register was allocated, which index was used).

4. **Incremental Complexity**: Start with the simplest possible codegen case (`MOV` immediate → register), get it tested and green, then add `OP`, then branching, then calls, then scopes. Each increment adds a test first.

5. **100% Code Coverage is the Goal**: Every branch, every error path, every edge case has a test. Coverage is measured per-script. Untested code is deleted.

6. **Tests Are the Specification**: A passing test suite IS the specification of what the codegen does. The test file is more important than the implementation file.

### The TDD Pipeline

```
                     ┌────────────────────┐
                     │  RED: Write test   │
                     │  that fails        │
                     └────────┬───────────┘
                              │
                              ▼
                     ┌────────────────────┐
                     │  GREEN: Write      │
                     │  minimal code      │
                     │  to pass test      │
                     └────────┬───────────┘
                              │
                              ▼
                     ┌────────────────────┐
                     │  REFACTOR: Improve │
                     │  design while      │
                     │  keeping tests     │
                     │  green             │
                     └────────┬───────────┘
                              │
                              ▼
                     ┌────────────────────┐
                     │  Next test:        │
                     │  add complexity    │
                     │  or coverage       │
                     └────────────────────┘
```

---

## 3. Architecture Overview

### Layer Diagram

```
┌────────────────────────────────────────────────────────────────────┐
│                    Layer 5: Codegen Orchestrator                     │
│  [codegen_driver.gd] — pure pipeline, no state, no side effects     │
│  Injects: sym_table, templates, scope_info → returns assembly text  │
├────────────────────────────────────────────────────────────────────┤
│                    Layer 4: Template Engine (Data-Driven)            │
│  [codegen_templates.gd] — template data + pattern matching           │
│  [codegen_expand.gd] — expand template with resolved operands       │
├────────────────────────────────────────────────────────────────────┤
│                    Layer 3: Operand Resolution                        │
│  [codegen_load_store.gd] — $/@/^ resolution + deref + addressing    │
│  [codegen_register.gd] — register allocator (pure state machine)    │
├────────────────────────────────────────────────────────────────────┤
│                    Layer 2: Assembly Text Assembly                    │
│  [codegen_text.gd] — assembly text building, label generation,      │
│                      location tracking, write position accounting   │
├────────────────────────────────────────────────────────────────────┤
│                    Layer 1: Symbol Table & Scope                      │
│  [codegen_symtable.gd] — immutable symbol queries, storage lookup   │
│  [codegen_scope.gd] — scope traversal, variable allocation          │
├────────────────────────────────────────────────────────────────────┤
│                    Layer 0: IR Input                                  │
│  [scenes/ir_md.gd] + [class_IR_cmd.gd] + [class_CodeBlock.gd]       │
│  Deserialized IR as input to the codegen pipeline                    │
└────────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
IR (Dictionary)                    ← from ir_md.gd serialization
    │
    ▼
SymbolTableBuilder                 ← codegen_symtable.gd
    │  Builds typed symbol table from IR scopes
    │  Allocates storage (global/stack)
    ▼
TemplateMatcher                    ← codegen_templates.gd
    │  Matches IR command head → Template record
    │  Produces emit plan with slot bindings
    ▼
TemplateExpander                   ← codegen_expand.gd
    │  For each template emit-op:
    │    TEXT   → append literal
    │    LOAD   → resolve $ref via codegen_load_store
    │    STORE  → resolve ^ref via codegen_load_store
    │    ADDR   → resolve @ref via codegen_load_store
    │    REG    → allocate/free via codegen_register
    │    LABEL  → define/reference via codegen_text
    │    SCOPE  → emit placeholder via codegen_text
    ▼
AssemblyBuffer                     ← codegen_text.gd
    │  Accumulates text, tracks write_pos, location_map
    ▼
FixupPass                          ← codegen_driver.gd
    │  Replace __ENTER_/__LEAVE_ placeholders
    │  Translate location maps
    ▼
Final Assembly String              → comp_asm_zd.gd
```

---

## 4. Test Plan: The Red-Green-Refactor Cycle Sequence

The implementation proceeds in **12 increments**, each starting with a failing test. Tests are ordered from simplest to most complex, so each increment builds on tested foundations.

### Increment 0: Test Infrastructure

**Before any codegen code**, set up the test harness.

```
tests/
├── test_codegen_text.gd          # Assembly text builder tests
├── test_codegen_register.gd      # Register allocator tests
├── test_codegen_load_store.gd    # Operand resolver tests
├── test_codegen_templates.gd     # Template matcher tests
├── test_codegen_expand.gd        # Template expander tests
├── test_codegen_symtable.gd      # Symbol table tests
├── test_codegen_driver.gd        # Integration tests
├── fixtures/
│   ├── mov_only.ir.yaml          # Pre-baked IR fixtures
│   ├── arithmetic.ir.yaml
│   ├── if_else.ir.yaml
│   └── ...
└── test_runner.gd                # Shared test utilities
```

**Test runner pattern** (Godot's built-in test system or a lightweight custom runner):

```gdscript
# test_runner.gd — reusable test assertions
static func assert_str_eq(got: String, expected: String, msg: String = "") -> void:
    if got != expected:
        push_error("FAIL: %s\n  Expected: [%s]\n  Got:      [%s]" % [msg, expected, got])
    else:
        print("PASS: %s" % msg)

static func assert_int_eq(got: int, expected: int, msg: String) -> void:
    if got != expected:
        push_error("FAIL: %s\n  Expected: %d\n  Got:      %d" % [msg, expected, got])
    else:
        print("PASS: %s" % msg)

static func assert_true(cond: bool, msg: String) -> void:
    if not cond:
        push_error("FAIL: %s" % msg)
    else:
        print("PASS: %s" % msg)
```

---

### Increment 1: Assembly Text Builder [`codegen_text.gd`]

**Red** — Write tests first:

```gdscript
# test_codegen_text.gd
func test_append_text() -> void:
    var buf = AssemblyBuffer.new()
    buf.append("mov eax, 5;\n")
    buf.append("add eax, ebx;\n")
    Runner.assert_str_eq(buf.text, "mov eax, 5;\nadd eax, ebx;\n", "append_text concatenates")

func test_write_pos_increment() -> void:
    var buf = AssemblyBuffer.new()
    buf.append("mov eax, 5;\n")
    Runner.assert_int_eq(buf.write_pos, 0, "write_pos unchanged for non-byte text")

func test_write_pos_manual() -> void:
    var buf = AssemblyBuffer.new()
    buf.append_with_size("mov eax, 5;\n", 8)
    Runner.assert_int_eq(buf.write_pos, 8, "write_pos advances by declared size")

func test_label_definition() -> void:
    var buf = AssemblyBuffer.new()
    buf.define_label("my_label")
    Runner.assert_str_eq(buf.text, ":my_label:\n", "label definition emits :name:")

func test_label_reference() -> void:
    var buf = AssemblyBuffer.new()
    buf.reference_label("my_label")
    Runner.assert_str_eq(buf.text, "my_label", "label reference emits bare name")

func test_location_tracking() -> void:
    var buf = AssemblyBuffer.new()
    var loc = LocationRange.from_string("test.md:10:2")
    buf.mark_location(loc, 0)   # begin at wp=0
    buf.append_with_size("mov eax, 5;\n", 8)
    buf.mark_location(loc, 1)   # end at wp=8
    Runner.assert_true(0 in buf.loc_map.begin, "begin location recorded at wp=0")
    Runner.assert_true(8 in buf.loc_map.end, "end location recorded at wp=8")
```

**Green** — Implement:

```gdscript
# codegen_text.gd — AssemblyBuffer
class_name AssemblyBuffer
extends RefCounted

var text: String = ""
var write_pos: int = 0
var loc_map: LocationMap = LocationMap.new()

func append(fragment: String) -> void:
    text += fragment

func append_with_size(fragment: String, byte_size: int) -> void:
    text += fragment
    write_pos += byte_size

func define_label(name: String) -> void:
    text += ":%s:\n" % name

func reference_label(name: String) -> void:
    text += name

func mark_location(loc: LocationRange, kind: int) -> void:
    var map = loc_map.begin if kind == 0 else loc_map.end
    if write_pos not in map:
        map[write_pos] = []
    map[write_pos].append(loc)
```

**Refactor**: Keep simple. Single responsibility: building assembly text.

---

### Increment 2: Register Allocator [`codegen_register.gd`]

**Red** — Test the pure state machine:

```gdscript
# test_codegen_register.gd
func test_alloc_first_register() -> void:
    var state = RegAllocState.new()
    var result = state.alloc()
    Runner.assert_str_eq(result.reg, "EAX", "first alloc yields EAX")
    Runner.assert_true(result.state.is_used("EAX"), "EAX marked in-use")

func test_alloc_all_four() -> void:
    var state = RegAllocState.new()
    var regs = []
    for i in 4:
        var result = state.alloc()
        regs.append(result.reg)
        state = result.state
    Runner.assert_str_eq(regs, ["EAX", "EBX", "ECX", "EDX"], "allocs cycle through 4 regs")

func test_alloc_exhaustion() -> void:
    var state = RegAllocState.new()
    for i in 4:
        var r = state.alloc()
        state = r.state
    var result = state.alloc()
    Runner.assert_true(result.reg == null, "5th alloc returns null (spill needed)")

func test_free_and_reuse() -> void:
    var state = RegAllocState.new()
    var r1 = state.alloc(); state = r1.state
    var r2 = state.alloc(); state = r2.state
    state = state.free("EAX")
    var r3 = state.alloc()
    Runner.assert_str_eq(r3.reg, "EAX", "after free, EAX is reusable")

func test_free_unused_register_is_noop() -> void:
    var state = RegAllocState.new()
    var result = state.free("EAX")  # not allocated yet
    Runner.assert_true(result.is_used("EAX") == false, "free on unused reg is safe")
```

**Green** — Implement as a pure state machine (no mutation, state is threaded through return values):

```gdscript
# codegen_register.gd
class_name RegAllocState
extends RefCounted

const REGS = ["EAX", "EBX", "ECX", "EDX"]
var _in_use: Array[bool] = [false, false, false, false]

func alloc() -> Dictionary:
    for i in len(REGS):
        if not _in_use[i]:
            var new_state = RegAllocState.new()
            new_state._in_use = _in_use.duplicate()
            new_state._in_use[i] = true
            return {"reg": REGS[i], "state": new_state}
    return {"reg": null, "state": self}  # spill needed

func free(reg_name: String) -> RegAllocState:
    var idx = REGS.find(reg_name)
    if idx == -1 or not _in_use[idx]:
        return self  # noop
    var new_state = RegAllocState.new()
    new_state._in_use = _in_use.duplicate()
    new_state._in_use[idx] = false
    return new_state

func is_used(reg_name: String) -> bool:
    var idx = REGS.find(reg_name)
    return _in_use[idx] if idx != -1 else false
```

**Refactor**: The `_in_use` array could become a 4-bit bitmask for performance later, but keep it as `Array[bool]` for clarity first.

---

### Increment 3: Symbol Table & Storage Allocation [`codegen_symtable.gd`]

**Red** — Test symbol queries and storage allocation in isolation:

```gdscript
# test_codegen_symtable.gd
func test_lookup_variable() -> void:
    var st = SymTable.new()
    st.add_var("var_x", "variable", "int", {"type": "global", "pos": 0}, "my_var")
    var sym = st.lookup("var_x")
    Runner.assert_str_eq(sym.ir_name, "var_x", "lookup by ir_name")
    Runner.assert_str_eq(sym.val_type, "variable", "val_type preserved")
    Runner.assert_str_eq(sym.storage.type, "global", "storage type preserved")

func test_lookup_missing_returns_null() -> void:
    var st = SymTable.new()
    Runner.assert_true(st.lookup("nonexistent") == null, "missing lookup returns null")

func test_storage_allocation_global() -> void:
    var st = SymTable.new()
    var sym = st.allocate("var_g", "variable", "int", "global")
    Runner.assert_str_eq(sym.storage.type, "global", "global variables get global storage")
    Runner.assert_str_eq(sym.ir_name, "var_g", "storage uses ir_name as label")

func test_storage_allocation_stack() -> void:
    var st = SymTable.new()
    var sym1 = st.allocate("local_a", "variable", "int", "stack")
    Runner.assert_str_eq(sym1.storage.type, "stack", "local vars get stack storage")
    Runner.assert_int_eq(sym1.storage.pos, -3, "first stack var at EBP-3")
    var sym2 = st.allocate("local_b", "variable", "int", "stack")
    Runner.assert_int_eq(sym2.storage.pos, -7, "second stack var at EBP-7 (4 bytes each)")

func test_storage_allocation_arg() -> void:
    var st = SymTable.new()
    var sym = st.allocate("arg0", "variable", "int", "arg")
    Runner.assert_int_eq(sym.storage.pos, 9, "first arg at EBP+9")

func test_generate_globals_text() -> void:
    var st = SymTable.new()
    st.add_var("var_x", "variable", "int", {"type": "global", "pos": 0}, "my_var")
    st.add_imm("str_hello", "immediate", "string", "hello")
    var text = st.generate_globals()
    Runner.assert_str_contains(text, ":var_x: db 0;", "global var emits db 0")
    Runner.assert_str_contains(text, ":str_hello: db", "string imm emits db")
```

**Green** — Implement:

```gdscript
# codegen_symtable.gd
class_name SymTable
extends RefCounted

var _syms: Dictionary = {}  # ir_name → Dictionary

func lookup(ir_name: String) -> Dictionary:
    return _syms.get(ir_name, {})

func add_var(ir_name: String, val_type: String, data_type: String, storage: Dictionary, user_name: String) -> void:
    _syms[ir_name] = {
        "ir_name": ir_name,
        "val_type": val_type,
        "data_type": data_type,
        "storage": storage,
        "user_name": user_name,
        "needs_deref": false,
    }

func add_imm(ir_name: String, val_type: String, data_type: String, value: String) -> void:
    _syms[ir_name] = {
        "ir_name": ir_name,
        "val_type": val_type,
        "data_type": data_type,
        "value": value,
        "storage": {"type": "NULL", "pos": 0},
    }

func allocate(ir_name: String, val_type: String, data_type: String, storage_kind: String) -> Dictionary:
    var pos = 0
    var storage = {}
    match storage_kind:
        "global":
            storage = {"type": "global", "pos": 0}
        "stack":
            _next_stack_pos -= 4
            pos = _next_stack_pos
            storage = {"type": "stack", "pos": pos}
        "arg":
            pos = _next_arg_pos
            _next_arg_pos += 4
            storage = {"type": "stack", "pos": pos}
    var sym = {"ir_name": ir_name, "val_type": val_type, "data_type": data_type, "storage": storage, "needs_deref": false}
    _syms[ir_name] = sym
    return sym

func generate_globals() -> String:
    var text = ""
    for ir_name in _syms:
        var sym = _syms[ir_name]
        if sym.storage.type == "global":
            if sym.data_type == "string":
                text += ":%s: db \"%s\", 0;\n" % [ir_name, sym.value]
            else:
                text += ":%s: db 0;\n" % ir_name
    return text
```

---

### Increment 4: Operand Resolution [`codegen_load_store.gd`]

**Red** — Test `$` (load), `^` (store), `@` (address) resolution:

```gdscript
# test_codegen_load_store.gd
func test_load_immediate_int() -> void:
    var st = SymTable.new()
    st.add_imm("imm_5", "immediate", "int", "5")
    var resolver = OperandResolver.new(st)
    var result = resolver.resolve_load("imm_5")
    Runner.assert_str_eq(result, "5", "int immediate resolves to literal")

func test_load_immediate_string() -> void:
    var st = SymTable.new()
    st.add_imm("str_hello", "immediate", "string", "Hello")
    var resolver = OperandResolver.new(st)
    var result = resolver.resolve_load("str_hello")
    Runner.assert_str_eq(result, "str_hello", "string immediate resolves to label ref")

func test_load_global_var() -> void:
    var st = SymTable.new()
    st.add_var("var_x", "variable", "int", {"type": "global", "pos": 0}, "x")
    var resolver = OperandResolver.new(st)
    var result = resolver.resolve_load("var_x")
    Runner.assert_str_eq(result, "*var_x", "global var loads as *label")

func test_load_stack_var() -> void:
    var st = SymTable.new()
    st.add_var("local_a", "variable", "int", {"type": "stack", "pos": -3}, "a")
    var resolver = OperandResolver.new(st)
    var result = resolver.resolve_load("local_a")
    Runner.assert_str_eq(result, "EBP[-3]", "stack var loads as EBP[pos]")

func test_store_global_var() -> void:
    var st = SymTable.new()
    st.add_var("var_x", "variable", "int", {"type": "global", "pos": 0}, "x")
    var resolver = OperandResolver.new(st)
    var result = resolver.resolve_store("var_x")
    Runner.assert_str_eq(result, "*var_x", "global var stores as *label")

func test_store_stack_var() -> void:
    var st = SymTable.new()
    st.add_var("local_a", "variable", "int", {"type": "stack", "pos": -3}, "a")
    var resolver = OperandResolver.new(st)
    var result = resolver.resolve_store("local_a")
    Runner.assert_str_eq(result, "EBP[-3]", "stack var stores as EBP[pos]")

func test_address_global() -> void:
    var st = SymTable.new()
    st.add_var("var_x", "variable", "int", {"type": "global", "pos": 0}, "x")
    var resolver = OperandResolver.new(st)
    var result = resolver.resolve_address("var_x")
    Runner.assert_str_eq(result, "var_x", "global address is bare label")

func test_address_stack() -> void:
    var st = SymTable.new()
    st.add_var("local_a", "variable", "int", {"type": "stack", "pos": -3}, "a")
    var resolver = OperandResolver.new(st)
    var result = resolver.resolve_address("local_a")
    Runner.assert_str_eq(result, "EBP+-3", "stack address is EBP+-3")

func test_deref_handling() -> void:
    var st = SymTable.new()
    st.add_var("arr_ptr", "variable", "int", {"type": "stack", "pos": -3}, "p")
    var resolver = OperandResolver.new(st)
    var result = resolver.resolve_store("arr_ptr", true)  # needs_deref
    Runner.assert_str_eq(result, "*EBP[-3]", "deref wraps in *")
```

**Green** — Implement as a dependency-injected resolver:

```gdscript
# codegen_load_store.gd
class_name OperandResolver
extends RefCounted

var _sym_table: SymTable

func _init(sym_table: SymTable) -> void:
    _sym_table = sym_table

func resolve_load(ir_name: String) -> String:
    var sym = _sym_table.lookup(ir_name)
    if sym.is_empty(): return "<ERROR:%s>" % ir_name
    match sym.val_type:
        "immediate":
            return sym.value if sym.data_type == "int" else sym.ir_name
        _:
            match sym.storage.type:
                "global": return "*%s" % sym.ir_name
                "stack":  return "EBP[%d]" % sym.storage.pos
                "extern": return "*%s" % sym.ir_name
                "code":   return sym.ir_name
    return "<ERROR:unknown_storage>"

func resolve_store(ir_name: String, needs_deref: bool = false) -> String:
    var sym = _sym_table.lookup(ir_name)
    if sym.is_empty(): return "<ERROR:%s>" % ir_name
    var base = ""
    match sym.storage.type:
        "global": base = "*%s" % sym.ir_name
        "stack":  base = "EBP[%d]" % sym.storage.pos
        _:        base = "<ERROR>"
    return "*%s" % base if needs_deref else base

func resolve_address(ir_name: String) -> String:
    var sym = _sym_table.lookup(ir_name)
    if sym.is_empty(): return "<ERROR:%s>" % ir_name
    match sym.storage.type:
        "global": return sym.ir_name
        "stack":  return "EBP+%d" % sym.storage.pos
        "code":   return sym.ir_name
        "extern": return sym.ir_name
    return "<ERROR:unknown_storage>"
```

**Key test design point**: The `OperandResolver` receives its symbol table via constructor injection. This means tests can pass a minimal `SymTable` with only the symbols needed for that test. No global state.

---

### Increment 5: Template Data & Pattern Matching [`codegen_templates.gd`]

**Red** — Test that the template table is pure data and pattern matching works:

```gdscript
# test_codegen_templates.gd
func test_template_table_has_mov() -> void:
    var tmpl = TemplateTable.match(["MOV", "dest", "src"])
    Runner.assert_true(tmpl != null, "MOV pattern matched")
    Runner.assert_str_eq(tmpl.pattern[0], "MOV", "pattern head is MOV")

func test_template_table_has_op() -> void:
    var tmpl = TemplateTable.match(["OP", "ADD", "a", "b", "r"])
    Runner.assert_true(tmpl != null, "OP pattern matched")

func test_template_table_has_if() -> void:
    var tmpl = TemplateTable.match(["IF", "cb_cond", "res", "cb_block"])
    Runner.assert_true(tmpl != null, "IF pattern matched")

func test_template_table_unknown_returns_null() -> void:
    var tmpl = TemplateTable.match(["NONEXISTENT"])
    Runner.assert_true(tmpl == null, "unknown op returns null")

func test_template_body_has_slot_markers() -> void:
    var tmpl = TemplateTable.match(["MOV", "dest", "src"])
    Runner.assert_str_contains(tmpl.body, "$1", "MOV template references slot 1 (src)")
    Runner.assert_str_contains(tmpl.body, "^2", "MOV template references slot 2 (dest)")

func test_op_subtemplate_exists() -> void:
    Runner.assert_true("ADD" in OpTemplateTable, "ADD op subtemplate exists")
    Runner.assert_true("EQUAL" in OpTemplateTable, "EQUAL op subtemplate exists")

func test_op_subtemplate_body_has_slots() -> void:
    var body = OpTemplateTable["ADD"]
    Runner.assert_str_contains(body, "$2", "ADD template refs arg1 (slot 2)")
    Runner.assert_str_contains(body, "$3", "ADD template refs arg2 (slot 3)")
    Runner.assert_str_contains(body, "^4", "ADD template refs result (slot 4)")
```

**Green** — Template table as pure data constants:

```gdscript
# codegen_templates.gd
class_name TemplateTable
extends RefCounted

# Template record: {pattern: Array[String], body: String, slots: Dictionary, size: String|int, handler: String}
const TEMPLATES: Array[Dictionary] = [
    # MOV dest src
    {"pattern": ["MOV"], "body": "mov ^2, $1;\n", "size": 8},
    # OP op arg1 arg2 res
    {"pattern": ["OP"], "body": "__OP_BODY__", "size": "dynamic", "handler": "op_dispatch"},
    # IF cb_cond res cb_block
    {"pattern": ["IF"], "body": "__IF_COMPOUND__", "size": "compound", "handler": "if_compound"},
    # ELSE_IF cb_cond res cb_block
    {"pattern": ["ELSE_IF"], "body": "__ELSE_IF_COMPOUND__", "size": "compound", "handler": "else_if_compound"},
    # ELSE cb_block
    {"pattern": ["ELSE"], "body": "__ELSE_COMPOUND__", "size": "compound", "handler": "else_compound"},
    # WHILE cb_cond res cb_block lbl_next lbl_end
    {"pattern": ["WHILE"], "body": "__WHILE_COMPOUND__", "size": "compound", "handler": "while_compound"},
    # CALL fun [args...] res
    {"pattern": ["CALL"], "body": "__CALL_COMPOUND__", "size": "compound", "handler": "call_compound"},
    # CALL_INDIRECT funvar [args...] res
    {"pattern": ["CALL_INDIRECT"], "body": "__CALL_INDIRECT_COMPOUND__", "size": "compound", "handler": "call_indirect_compound"},
    # RETURN [res]
    {"pattern": ["RETURN"], "body": "__RETURN__", "size": "compound", "handler": "return_compound"},
    # ENTER scope
    {"pattern": ["ENTER"], "body": "__ENTER_$1;\n", "size": "placeholder"},
    # LEAVE
    {"pattern": ["LEAVE"], "body": "__LEAVE_%s;\n", "size": "placeholder"},
    # ALLOC size res
    {"pattern": ["ALLOC"], "body": "mov ^2, @__arr_$1;\n", "size": 8, "handler": "alloc_compound"},
    # MOV_ARR dest [src1 src2 ...]
    {"pattern": ["MOV_ARR"], "body": "__MOV_ARR_COMPOUND__", "size": "compound", "handler": "mov_arr_compound"},
]

# Op subtemplates — used by OP dispatch
const OP_TEMPLATES: Dictionary = {
    "ADD": "add $tmpA, $tmpB;\n",
    "SUB": "sub $tmpA, $tmpB;\n",
    "MUL": "mul $tmpA, $tmpB;\n",
    "DIV": "div $tmpA, $tmpB;\n",
    "MOD": "mod $tmpA, $tmpB;\n",
    "INC": "inc ^4;\n",
    "DEC": "dec ^4;\n",
    "GREATER": "cmp $tmpA, $tmpB; mov $tmpA, CTRL; band $tmpA, CMP_G; bnot $tmpA; bnot $tmpA;\n",
    "LESS":    "cmp $tmpA, $tmpB; mov $tmpA, CTRL; band $tmpA, CMP_L; bnot $tmpA; bnot $tmpA;\n",
    "EQUAL":   "cmp $tmpA, $tmpB; mov $tmpA, CTRL; band $tmpA, CMP_Z; bnot $tmpA; bnot $tmpA;\n",
    "NOT_EQUAL": "cmp $tmpA, $tmpB; mov $tmpA, CTRL; band $tmpA, CMP_NZ; bnot $tmpA; bnot $tmpA;\n",
    "INDEX": "add $tmpA, $tmpB;\n",
}

static func match(cmd_words: Array) -> Dictionary:
    var cmd_head = cmd_words[0]
    for tmpl in TEMPLATES:
        if tmpl.pattern[0] == cmd_head:
            return tmpl
    return {}

static func match_op(op_name: String) -> String:
    return OP_TEMPLATES.get(op_name, "")
```

**Key test design point**: `TemplateTable.match()` is a pure function — no state, no side effects, trivially testable. The template table is a constant, so it's verified at load time.

---

### Increment 6: MOV Command Expansion (The First Real Codegen)

**Red** — Test end-to-end expansion of the simplest command:

```gdscript
# test_codegen_expand.gd
func test_expand_mov_imm_to_global() -> void:
    # Setup: IR command MOV var_x imm_5
    var cmd = IR_Cmd.new({"words": ["MOV", "var_x", "imm_5"]})
    var st = SymTable.new()
    st.add_var("var_x", "variable", "int", {"type": "global", "pos": 0}, "x")
    st.add_imm("imm_5", "immediate", "int", "5")
    var resolver = OperandResolver.new(st)
    var buf = AssemblyBuffer.new()
    var regs = RegAllocState.new()

    var expander = TemplateExpander.new(resolver, buf, regs)
    var result = expander.expand(cmd)

    Runner.assert_str_eq(buf.text, "mov *var_x, 5;\n", "MOV immediate to global")
    Runner.assert_int_eq(buf.write_pos, 8, "write_pos advanced by 8")
```

**Green** — Implement the expander for the MOV case:

```gdscript
# codegen_expand.gd — initial version, just MOV
class_name TemplateExpander
extends RefCounted

var _resolver: OperandResolver
var _buf: AssemblyBuffer
var _regs: RegAllocState

func _init(resolver: OperandResolver, buf: AssemblyBuffer, regs: RegAllocState) -> void:
    _resolver = resolver
    _buf = buf
    _regs = regs

func expand(cmd: IR_Cmd) -> Dictionary:
    var tmpl = TemplateTable.match(cmd.words)
    if tmpl.is_empty():
        push_error("No template for: %s" % cmd.words[0])
        return {"buf": _buf, "regs": _regs}

    match tmpl.pattern[0]:
        "MOV":
            _expand_mov(cmd, tmpl)
        _:
            push_error("Not yet implemented: %s" % cmd.words[0])

    return {"buf": _buf, "regs": _regs}

func _expand_mov(cmd: IR_Cmd, tmpl: Dictionary) -> void:
    # MOV body: "mov ^2, $1;\n"
    var src = _resolver.resolve_load(cmd.words[1])  # slot 1 = src
    var dest = _resolver.resolve_store(cmd.words[2])  # slot 2 = dest
    _buf.append_with_size("mov %s, %s;\n" % [dest, src], tmpl.size)
```

**Refactor**: The slot mapping (which word index maps to which slot in the template) is currently hardcoded. Extract it to the template record so the expander can be generic.

```gdscript
# Refactored _expand_mov to be generic
func _expand_simple(cmd: IR_Cmd, tmpl: Dictionary) -> void:
    var body = tmpl.body
    # Replace $N with load_value(cmd.words[N])
    # Replace ^N with store_val(cmd.words[N])
    # Replace @N with address_value(cmd.words[N])
    body = _resolve_slots(body, cmd.words)
    _buf.append_with_size(body, tmpl.size)

func _resolve_slots(body: String, words: Array) -> String:
    var result = body
    # Find all $N markers and resolve
    result = _resolve_marker(result, "$", words, funcref(_resolver, "resolve_load"))
    # Find all ^N markers and resolve
    result = _resolve_marker(result, "^", words, funcref(_resolver, "resolve_store"))
    # Find all @N markers and resolve
    result = _resolve_marker(result, "@", words, funcref(_resolver, "resolve_address"))
    return result

func _resolve_marker(body: String, marker: String, words: Array, resolve_fn: FuncRef) -> String:
    var result = body
    while true:
        var pos = result.find(marker)
        if pos == -1: break
        # Extract the slot number after the marker
        var end_pos = pos + 1
        while end_pos < len(result) and result[end_pos].is_valid_int():
            end_pos += 1
        var slot_str = result.substr(pos + 1, end_pos - pos - 1)
        var slot = int(slot_str)
        var ir_name = words[slot] if slot < len(words) else ""
        var resolved = resolve_fn.call_func(ir_name)
        result = result.substr(0, pos) + resolved + result.substr(end_pos)
    return result
```

---

### Increment 7: OP Command Expansion (Arithmetic with Temp Registers)

**Red** — Test OP expansion with register allocation:

```gdscript
func test_expand_op_add() -> void:
    var cmd = IR_Cmd.new({"words": ["OP", "ADD", "var_a", "var_b", "var_r"]})
    var st = SymTable.new()
    st.add_var("var_a", "variable", "int", {"type": "global", "pos": 0}, "a")
    st.add_var("var_b", "variable", "int", {"type": "global", "pos": 0}, "b")
    st.add_var("var_r", "variable", "int", {"type": "global", "pos": 0}, "r")
    var resolver = OperandResolver.new(st)
    var buf = AssemblyBuffer.new()
    var regs = RegAllocState.new()
    var expander = TemplateExpander.new(resolver, buf, regs, st)

    var result = expander.expand(cmd)

    # Expected: mov EAX, *var_a; add EAX, *var_b; mov *var_r, EAX;
    Runner.assert_str_contains(buf.text, "mov EAX, *var_a;", "OP loads arg1 into temp reg")
    Runner.assert_str_contains(buf.text, "add EAX, *var_b;", "OP performs operation")
    Runner.assert_str_contains(buf.text, "mov *var_r, EAX;", "OP stores result")
    Runner.assert_int_eq(buf.write_pos, 24, "3 instructions × 8 bytes = 24")

func test_expand_op_inc_monadic() -> void:
    var cmd = IR_Cmd.new({"words": ["OP", "INC", "var_x", "", "var_x"]})
    var st = SymTable.new()
    st.add_var("var_x", "variable", "int", {"type": "global", "pos": 0}, "x")
    var resolver = OperandResolver.new(st)
    var buf = AssemblyBuffer.new()
    var regs = RegAllocState.new()
    var expander = TemplateExpander.new(resolver, buf, regs, st)

    var result = expander.expand(cmd)

    Runner.assert_str_contains(buf.text, "mov *var_x, *var_x;", "INC copies to result first")
    Runner.assert_str_contains(buf.text, "inc *var_x;", "INC performs increment")

func test_op_temp_registers_are_freed() -> void:
    var cmd = IR_Cmd.new({"words": ["OP", "ADD", "var_a", "var_b", "var_r"]})
    var st = SymTable.new()
    st.add_var("var_a", "variable", "int", {"type": "global", "pos": 0}, "a")
    st.add_var("var_b", "variable", "int", {"type": "global", "pos": 0}, "b")
    st.add_var("var_r", "variable", "int", {"type": "global", "pos": 0}, "r")
    var resolver = OperandResolver.new(st)
    var buf = AssemblyBuffer.new()
    var regs = RegAllocState.new()
    var expander = TemplateExpander.new(resolver, buf, regs, st)

    var result = expander.expand(cmd)
    # After expansion, temp registers should be freed
    var final_regs = result.regs
    Runner.assert_true(not final_regs.is_used("EAX"), "EAX freed after OP")
```

**Green** — Implement OP expansion with temp register management:

```gdscript
func _expand_op(cmd: IR_Cmd, tmpl: Dictionary) -> void:
    var op_name = cmd.words[1]
    var arg1 = cmd.words[2]
    var arg2 = cmd.words[3]
    var res = cmd.words[4]
    var op_body = TemplateTable.match_op(op_name)
    var is_mono = op_name in ["INC", "DEC"]

    if is_mono:
        # Mono ops: mov ^res, $arg1; inc ^res;
        var dest = _resolver.resolve_store(res)
        var src = _resolver.resolve_load(arg1)
        _buf.append_with_size("mov %s, %s;\n" % [dest, src], 8)
        _buf.append_with_size(str(op_body), 8)
        return

    # Binary ops: alloc temp reg, load args, execute, store result
    var alloc_result = _regs.alloc()
    var tmp_reg = alloc_result.reg
    _regs = alloc_result.state

    var r1 = _resolver.resolve_load(arg1)
    _buf.append_with_size("mov %s, %s;\n" % [tmp_reg, r1], 8)

    var alloc_result2 = _regs.alloc()
    var tmp_reg2 = alloc_result2.reg
    _regs = alloc_result2.state
    var r2 = _resolver.resolve_load(arg2)
    _buf.append_with_size("mov %s, %s;\n" % [tmp_reg2, r2], 8)

    # Replace $tmpA, $tmpB in op body with actual register names
    var body = op_body.replace("$tmpA", tmp_reg).replace("$tmpB", tmp_reg2)
    var op_size = 8 * op_body.count(";")
    _buf.append_with_size(body, op_size)

    var dest = _resolver.resolve_store(res)
    _buf.append_with_size("mov %s, %s;\n" % [dest, tmp_reg], 8)

    # Free temp registers
    _regs = _regs.free(tmp_reg)
    _regs = _regs.free(tmp_reg2)
```

---

### Increment 8: Label Generation & Branching (IF/WHILE)

**Red** — Test label generation and IF expansion:

```gdscript
func test_new_label_generates_unique_name() -> void:
    var label_gen = LabelGenerator.new()
    var lbl1 = label_gen.fresh("if_else")
    var lbl2 = label_gen.fresh("if_else")
    Runner.assert_str_contains(lbl1, "lbl_1__if_else", "first label has id 1")
    Runner.assert_str_contains(lbl2, "lbl_2__if_else", "second label has id 2")

func test_expand_if_simple() -> void:
    # IF cb_cond res cb_block
    var cmd = IR_Cmd.new({"words": ["IF", "cb_cond", "tmp_res", "cb_body"]})
    var st = SymTable.new()
    st.add_var("tmp_res", "variable", "int", {"type": "stack", "pos": -3}, "")
    st.add_imm("imm_0", "immediate", "int", "0")
    # Code blocks as symbols
    st.add_code_block("cb_cond", "code")
    st.add_code_block("cb_body", "code")

    var resolver = OperandResolver.new(st)
    var buf = AssemblyBuffer.new()
    var regs = RegAllocState.new()
    var expander = TemplateExpander.new(resolver, buf, regs, st)

    # We need a CodeBlockRefProvider so the expander can call back to emit code blocks
    # For now, we'll test with a mock that records the call
    var mock_block_provider = MockCodeBlockProvider.new()
    expander.block_provider = mock_block_provider

    var result = expander.expand(cmd)

    # Assert structural elements
    Runner.assert_str_contains(buf.text, "cmp EBP[-3], 0;", "IF compares result with 0")
    Runner.assert_str_contains(buf.text, "jz lbl_", "IF jumps to else label on zero")
    Runner.assert_str_contains(buf.text, "jmp lbl_", "IF has end jump")
    Runner.assert_str_contains(buf.text, ":lbl_", "IF has label definitions")
    Runner.assert_true(mock_block_provider.called_with("cb_cond"), "IF emitted cb_cond code block")
    Runner.assert_true(mock_block_provider.called_with("cb_body"), "IF emitted cb_body code block")
```

**Green** — Implement IF expansion:

```gdscript
func _expand_if(cmd: IR_Cmd, tmpl: Dictionary) -> void:
    var cb_cond = cmd.words[1]
    var res = cmd.words[2]
    var cb_block = cmd.words[3]

    var lbl_else = _label_gen.fresh("if_else")
    var lbl_end = _label_gen.fresh("if_end")

    # Emit condition code block
    _emit_code_block(cb_cond)

    # cmp res, 0
    var res_ref = _resolver.resolve_load(res)
    _buf.append_with_size("cmp %s, 0;\n" % res_ref, 8)

    # jz lbl_else
    _buf.append_with_size("jz %s;\n" % lbl_else, 8)

    # Emit body code block
    _emit_code_block(cb_block)

    # jmp lbl_end
    _buf.append_with_size("jmp %s;\n" % lbl_end, 8)

    # lbl_else:
    _buf.define_label(lbl_else)

    # If not continued (no ELSE_IF/ELSE following), emit lbl_end:
    # (This will be handled by the driver, not the template expander)

func _emit_code_block(cb_name: String) -> void:
    if _block_provider == null:
        _buf.append_with_size("$%s\n" % cb_name, 0)  # placeholder for now
        return
    var ab = _block_provider.get_block_assembly(cb_name)
    if ab != null:
        _buf.append_with_size(ab.code, ab.write_pos)
```

**Key test design point**: The `_block_provider` is a dependency injected into `TemplateExpander`. Tests inject a `MockCodeBlockProvider` that records which blocks were requested and returns controlled assembly text. This makes the IF expansion testable without needing the full recursive code block compilation.

---

### Increment 9: CALL/RETURN Expansion

**Red** — Test function call expansion:

```gdscript
func test_expand_call_with_args() -> void:
    # CALL fun [arg1 arg2] res
    var cmd = IR_Cmd.new({"words": ["CALL", "func_add", "[", "var_a", "var_b", "]", "var_r"]})
    var st = SymTable.new()
    st.add_var("var_a", "variable", "int", {"type": "global", "pos": 0}, "a")
    st.add_var("var_b", "variable", "int", {"type": "global", "pos": 0}, "b")
    st.add_var("var_r", "variable", "int", {"type": "global", "pos": 0}, "r")
    st.add_func("func_add", "func", {"type": "code", "pos": 0}, "add", "cb_add")
    st.add_code_block("cb_add", "code")

    var resolver = OperandResolver.new(st)
    var buf = AssemblyBuffer.new()
    var regs = RegAllocState.new()
    var expander = TemplateExpander.new(resolver, buf, regs, st)

    var result = expander.expand(cmd)

    # Expected: push *var_b; push *var_a; call @func_add; add ESP, 8; mov *var_r, EAX;
    Runner.assert_str_contains(buf.text, "push *var_b;", "CALL pushes args in reverse")
    Runner.assert_str_contains(buf.text, "push *var_a;", "CALL pushes first arg second (stack order)")
    Runner.assert_str_contains(buf.text, "call @func_add;", "CALL emits call instruction")
    Runner.assert_str_contains(buf.text, "add ESP, 8;", "CALL cleans up 8 bytes (2 args × 4)")
    Runner.assert_str_contains(buf.text, "mov *var_r, EAX;", "CALL stores return value")

func test_expand_return_with_value() -> void:
    var cmd = IR_Cmd.new({"words": ["RETURN", "var_result"]})
    var st = SymTable.new()
    st.add_var("var_result", "variable", "int", {"type": "global", "pos": 0}, "result")

    var resolver = OperandResolver.new(st)
    var buf = AssemblyBuffer.new()
    var regs = RegAllocState.new()
    var expander = TemplateExpander.new(resolver, buf, regs, st)
    expander.current_scope_name = "scp_func"

    var result = expander.expand(cmd)

    Runner.assert_str_contains(buf.text, "mov EAX, *var_result;", "RETURN moves value to EAX")
    Runner.assert_str_contains(buf.text, "__LEAVE_scp_func;", "RETURN emits scope leave placeholder")
    Runner.assert_str_contains(buf.text, "ret;\n", "RETURN emits ret instruction")

func test_expand_return_no_value() -> void:
    var cmd = IR_Cmd.new({"words": ["RETURN"]})
    var resolver = OperandResolver.new(SymTable.new())
    var buf = AssemblyBuffer.new()
    var regs = RegAllocState.new()
    var expander = TemplateExpander.new(resolver, buf, regs, SymTable.new())
    expander.current_scope_name = "scp_func"

    var result = expander.expand(cmd)

    Runner.assert_not_contains(buf.text, "EAX", "RETURN without value does not touch EAX")
    Runner.assert_str_contains(buf.text, "__LEAVE_scp_func;", "RETURN emits scope leave")
    Runner.assert_str_contains(buf.text, "ret;\n", "RETURN emits ret")
```

**Green** — Implement CALL/RETURN expansion:

```gdscript
func _expand_call(cmd: IR_Cmd, tmpl: Dictionary, is_indirect: bool = false) -> void:
    var fun_ref = cmd.words[1]
    var args = _extract_args(cmd.words, 2)  # extract args between [ and ]
    var res = cmd.words[-1]

    # Push args in reverse order (last arg pushed first = top of stack = first arg)
    for i in range(len(args) - 1, -1, -1):
        var arg_ref = _resolver.resolve_load(args[i])
        _buf.append_with_size("push %s;\n" % arg_ref, 8)

    var n_args = len(args)
    var pushed_size = 4 * n_args

    # Call instruction
    if is_indirect:
        var fun_load = _resolver.resolve_load(fun_ref)
        _buf.append_with_size("call %s;\n" % fun_load, 8)
    else:
        var fun_addr = _resolver.resolve_address(fun_ref)
        _buf.append_with_size("call @%s;\n" % fun_addr, 8)

    # Clean up stack
    if pushed_size > 0:
        _buf.append_with_size("add ESP, %s;\n" % pushed_size, 8)

    # Store return value
    var dest = _resolver.resolve_store(res)
    _buf.append_with_size("mov %s, EAX;\n" % [dest], 8)

    # Queue referenced code block for emission (handled by driver)
    if not is_indirect:
        var fun_sym = _sym_table.lookup(fun_ref)
        if fun_sym.get("code", "") != "":
            _block_provider.queue_block(fun_sym.code)

func _extract_args(words: Array, start_idx: int) -> Array:
    var args = []
    var i = start_idx
    if i < len(words) and words[i] == "[":
        i += 1
        while i < len(words) and words[i] != "]":
            args.append(words[i])
            i += 1
    else:
        if i < len(words):
            args.append(words[i])
    return args

func _expand_return(cmd: IR_Cmd, tmpl: Dictionary) -> void:
    if len(cmd.words) >= 2:
        var val = _resolver.resolve_load(cmd.words[1])
        _buf.append_with_size("mov EAX, %s;\n" % val, 8)

    _buf.append_with_size("__LEAVE_%s;\n" % _current_scope_name, 8)
    _buf.append_with_size("ret;\n", 8)
```

---

### Increment 10: Scope Enter/Leave & Fixup

**Red** — Test scope placeholder generation and fixup:

```gdscript
func test_expand_enter_emits_placeholder() -> void:
    var cmd = IR_Cmd.new({"words": ["ENTER", "scp_func"]})
    var st = SymTable.new()
    var resolver = OperandResolver.new(st)
    var buf = AssemblyBuffer.new()
    var regs = RegAllocState.new()
    var expander = TemplateExpander.new(resolver, buf, regs, st)

    expander.expand(cmd)
    Runner.assert_str_contains(buf.text, "__ENTER_scp_func;", "ENTER emits __ENTER_ placeholder")

func test_fixup_replaces_enter_leave() -> void:
    var fixupper = FixupPass.new()
    var text = "some code\n__ENTER_scp_myfunc;\nmore code\n__LEAVE_scp_myfunc;\n"
    var scopes = {
        "scp_myfunc": {"local_vars_write_pos": -12}
    }
    var result = fixupper.apply(text, scopes)
    Runner.assert_contains(result, "sub ESP, 12", "__ENTER_ replaced with sub")
    Runner.assert_contains(result, "add ESP, 12", "__LEAVE_ replaced with add")
    Runner.assert_not_contains(result, "__ENTER_", "no __ENTER_ placeholders remain")
    Runner.assert_not_contains(result, "__LEAVE_", "no __LEAVE_ placeholders remain")
```

**Green** — Implement fixup pass:

```gdscript
# codegen_fixup.gd
class_name FixupPass
extends RefCounted

func apply(assembly_text: String, scopes: Dictionary) -> String:
    var result = assembly_text
    for scp_key in scopes:
        var scope = scopes[scp_key]
        var scp_name = scope.ir_name if "ir_name" in scope else scp_key
        var stack_bytes = scope.local_vars_write_pos
        result = result.replace(
            "__ENTER_%s" % scp_name,
            "sub ESP, %d" % (-stack_bytes if stack_bytes < 0 else stack_bytes)
        )
        result = result.replace(
            "__LEAVE_%s" % scp_name,
            "add ESP, %d" % (stack_bytes if stack_bytes < 0 else -stack_bytes)
        )
    return result
```

---

### Increment 11: ALLOC & MOV_ARR (Array Operations)

**Red** — Test array allocation and element copy:

```gdscript
func test_expand_alloc() -> void:
    var cmd = IR_Cmd.new({"words": ["ALLOC", "5", "arr_ptr"]})
    var st = SymTable.new()
    var resolver = OperandResolver.new(st)
    var buf = AssemblyBuffer.new()
    var regs = RegAllocState.new()
    var expander = TemplateExpander.new(resolver, buf, regs, st)

    expander.expand(cmd)

    # ALLOC should create a new array symbol and emit mov arr_ptr, @arr_storage
    Runner.assert_str_contains(buf.text, "mov *arr_ptr,", "ALLOC stores array address")
    Runner.assert_true(st.lookup("arr_ptr") != {}, "arr_ptr added to symbol table")
    # The array storage should be in the symbol table too
    Runner.assert_true(len(st.syms) > 1, "array storage symbol created")

func test_expand_mov_arr() -> void:
    var cmd = IR_Cmd.new({"words": ["MOV_ARR", "arr_dest", "[", "val_1", "val_2", "val_3", "]"]})
    var st = SymTable.new()
    st.add_var("arr_dest", "variable", "int", {"type": "stack", "pos": -3}, "arr")
    st.add_imm("val_1", "immediate", "int", "10")
    st.add_imm("val_2", "immediate", "int", "20")
    st.add_imm("val_3", "immediate", "int", "30")
    var resolver = OperandResolver.new(st)
    var buf = AssemblyBuffer.new()
    var regs = RegAllocState.new()
    var expander = TemplateExpander.new(resolver, buf, regs, st)

    expander.expand(cmd)

    Runner.assert_str_contains(buf.text, "mov EAX, EBP[-3];", "MOV_ARR loads array base address")
    Runner.assert_str_contains(buf.text, "mov *EAX, 10;", "MOV_ARR stores first element")
    Runner.assert_str_contains(buf.text, "add EAX, 4;", "MOV_ARR increments pointer")
    Runner.assert_str_contains(buf.text, "mov *EAX, 30;", "MOV_ARR stores last element")
```

---

### Increment 12: Integration Test — Full Pipeline

**Red** — Test the complete driver end-to-end with real IR:

```gdscript
# test_codegen_driver.gd
func test_compile_simple_mov_program() -> void:
    var ir_data = _load_fixture("mov_only.ir.yaml")
    var driver = CodegenDriver.new()

    var result = driver.generate(ir_data)

    Runner.assert_str_contains(result.code, ":lbl_f_0:", "has entry label")
    Runner.assert_str_contains(result.code, "mov *var_x, 42;", "has MOV instruction")
    Runner.assert_true(result.loc_map.begin.size() > 0, "has location mappings")

func test_compile_arithmetic_program() -> void:
    var ir_data = _load_fixture("arithmetic.ir.yaml")
    var driver = CodegenDriver.new()

    var result = driver.generate(ir_data)

    Runner.assert_str_contains(result.code, "mov EAX,", "uses temp register")
    Runner.assert_str_contains(result.code, "add EAX,", "has addition")
    Runner.assert_str_contains(result.code, "sub EAX,", "has subtraction")

func test_compile_if_else_program() -> void:
    var ir_data = _load_fixture("if_else.ir.yaml")
    var driver = CodegenDriver.new()

    var result = driver.generate(ir_data)

    Runner.assert_str_contains(result.code, "jz lbl_", "has conditional jump")
    Runner.assert_str_contains(result.code, "jmp lbl_", "has unconditional jump")
    Runner.assert_str_contains(result.code, ":lbl_2__if_else:", "has else label")  # or whatever the counter would be

func test_compile_fibonacci_program() -> void:
    var ir_data = _load_fixture("fibonacci.ir.yaml")
    var driver = CodegenDriver.new()

    var result = driver.generate(ir_data)

    # The assembled code should be parseable by comp_asm_zd.gd
    var assembler = preload("res://scenes/comp_asm_zd.gd").new()
    var chunk = assembler.assemble(result.code)
    Runner.assert_true(chunk.code.size() > 0, "assembler produces valid machine code")
    Runner.assert_int_eq(chunk.refs.size(), 0, "all label references resolved")

func test_output_bit_exact_with_old_codegen() -> void:
    # For each fixture, compare output of new codegen with old codegen
    var ir_yaml = _read_fixture("fibonacci.ir.yaml")
    var old_codegen = preload("res://scenes/codegen_md.gd").new()
    var old_result = old_codegen.parse_file(_fixture_path("fibonacci.ir.yaml"))

    var ir_data = _deserialize_yaml(ir_yaml)
    var driver = CodegenDriver.new()
    var new_result = driver.generate(ir_data)

    Runner.assert_str_eq(new_result.code, old_result, "new codegen matches old codegen output")
```

**Green** — Implement the driver that orchestrates the entire pipeline:

```gdscript
# codegen_driver.gd
class_name CodegenDriver
extends RefCounted

func generate(ir_data: Dictionary) -> Dictionary:
    # Stage 1: Build symbol table with storage allocation
    var symtable = _build_symtable(ir_data)

    # Stage 2: Create the assembly buffer and expander
    var resolver = OperandResolver.new(symtable)
    var buf = AssemblyBuffer.new()
    var regs = RegAllocState.new()
    var block_provider = CodeBlockProvider.new(resolver, symtable)
    var label_gen = LabelGenerator.new()

    var expander = TemplateExpander.new(resolver, buf, regs, symtable)
    expander.block_provider = block_provider
    expander.label_gen = label_gen

    # Stage 3: Emit code blocks in reachability order
    var cb_queue = _get_initial_code_blocks(ir_data)
    var emitted = {}

    while cb_queue.size() > 0:
        var cb_name = cb_queue.pop_front()
        if cb_name in emitted: continue
        emitted[cb_name] = true

        var cb = ir_data.code_blocks[cb_name]
        _emit_code_block(cb, expander, ir_data, symtable)

    # Stage 4: Fixup enter/leave placeholders
    var fixup_pass = FixupPass.new()
    buf.text = fixup_pass.apply(buf.text, ir_data.scopes)

    # Stage 5: Append global data section
    buf.text += symtable.generate_globals()

    return {"code": buf.text, "loc_map": buf.loc_map, "write_pos": buf.write_pos}

func _emit_code_block(cb: Dictionary, expander: TemplateExpander, ir_data: Dictionary, symtable: SymTable) -> void:
    expander.buf.define_label(cb.lbl_from)
    if "code" in cb:
        for cmd in cb.code:
            expander.expand(cmd)
    # Check if this is a function code block, emit return
    var func_name = _find_func_for_block(cb.ir_name, ir_data)
    if func_name != null:
        var scope_name = symtable.lookup(func_name).get("scope", "")
        expander.buf.append_with_size("__LEAVE_%s;\n" % scope_name, 8)
        expander.buf.append_with_size("ret;\n", 8)
    expander.buf.define_label(cb.lbl_to)
```

---

## 5. Template Engine: Data-Driven Design

### Template Record Schema

Each template is a **data record** — no code, no methods, just fields:

```gdscript
# Template record schema
{
    "pattern": Array[String],    # IR command head to match (e.g., ["MOV"])
    "body": String,              # Template body with $N, ^N, @N slot markers
    "size": Variant,             # 8 (fixed), "dynamic" (count ;), "compound" (multi-step handler)
    "handler": String,           # Optional: name of handler function for compound templates
}
```

### Slot Marker Convention

| Marker | Resolution | Example Output |
|--------|-----------|----------------|
| `$1`   | `resolve_load(words[1])` | `5`, `*var_x`, `EBP[-3]` |
| `^2`   | `resolve_store(words[2])` | `*var_x`, `EBP[-3]` |
| `@3`   | `resolve_address(words[3])` | `var_x`, `EBP+-3` |
| `$tmpA`| Allocated register name | `EAX`, `EBX` |

### Template Table (Complete)

The full template table covers all 13 IR command types:

| Pattern | Body/Handler | Size |
|---------|-------------|------|
| `MOV` | `mov ^2, $1;\n` | 8 |
| `OP` | `__OP_DISPATCH__` | dynamic |
| `IF` | `__IF_COMPOUND__` | compound |
| `ELSE_IF` | `__ELSE_IF_COMPOUND__` | compound |
| `ELSE` | `__ELSE_COMPOUND__` | compound |
| `WHILE` | `__WHILE_COMPOUND__` | compound |
| `CALL` | `__CALL_COMPOUND__` | compound |
| `CALL_INDIRECT` | `__CALL_INDIRECT_COMPOUND__` | compound |
| `RETURN` | `__RETURN__` | compound |
| `ENTER` | `__ENTER_$1;\n` | placeholder |
| `LEAVE` | `__LEAVE_%s;\n` | placeholder |
| `ALLOC` | `__ALLOC_COMPOUND__` | compound |
| `MOV_ARR` | `__MOV_ARR_COMPOUND__` | compound |

### Op Template Table (for OP dispatch)

| Op Name | Template Body |
|---------|--------------|
| `ADD` | `add $tmpA, $tmpB;\n` |
| `SUB` | `sub $tmpA, $tmpB;\n` |
| `MUL` | `mul $tmpA, $tmpB;\n` |
| `DIV` | `div $tmpA, $tmpB;\n` |
| `MOD` | `mod $tmpA, $tmpB;\n` |
| `INC` | `inc ^4;\n` |
| `DEC` | `dec ^4;\n` |
| `GREATER` | `cmp $tmpA, $tmpB; mov $tmpA, CTRL; band $tmpA, CMP_G; bnot $tmpA; bnot $tmpA;\n` |
| `LESS` | `cmp $tmpA, $tmpB; mov $tmpA, CTRL; band $tmpA, CMP_L; bnot $tmpA; bnot $tmpA;\n` |
| `EQUAL` | `cmp $tmpA, $tmpB; mov $tmpA, CTRL; band $tmpA, CMP_Z; bnot $tmpA; bnot $tmpA;\n` |
| `NOT_EQUAL` | `cmp $tmpA, $tmpB; mov $tmpA, CTRL; band $tmpA, CMP_NZ; bnot $tmpA; bnot $tmpA;\n` |
| `INDEX` | `add $tmpA, $tmpB;\n` |

---

## 6. File Structure

```
scenes/
├── codegen_text.gd              # AssemblyBuffer: text accumulation, labels, locations
├── codegen_register.gd          # RegAllocState: pure register state machine
├── codegen_load_store.gd        # OperandResolver: $/^/@ resolution
├── codegen_symtable.gd          # SymTable: symbol queries, storage allocation, globals gen
├── codegen_templates.gd         # TemplateTable + OpTemplateTable (pure data constants)
├── codegen_expand.gd            # TemplateExpander: IR cmd → assembly via templates
├── codegen_fixup.gd             # FixupPass: __ENTER_/__LEAVE_ → sub/add
├── codegen_driver.gd            # CodegenDriver: orchestrates the full pipeline
tests/
├── test_runner.gd               # Shared test assertions
├── test_codegen_text.gd         # AssemblyBuffer tests
├── test_codegen_register.gd     # RegAllocState tests
├── test_codegen_load_store.gd   # OperandResolver tests
├── test_codegen_symtable.gd     # SymTable tests
├── test_codegen_templates.gd    # TemplateTable tests
├── test_codegen_expand.gd       # TemplateExpander tests (MOV, OP, IF, CALL, etc.)
├── test_codegen_fixup.gd        # FixupPass tests
├── test_codegen_driver.gd       # Integration tests
├── fixtures/
│   ├── mov_only.ir.yaml
│   ├── arithmetic.ir.yaml
│   ├── if_else.ir.yaml
│   ├── while_loop.ir.yaml
│   ├── function_call.ir.yaml
│   ├── arrays.ir.yaml
│   └── fibonacci.ir.yaml        # Full program test
```

---

## 7. Dependency Injection Architecture

The key to testability is **constructor injection**. Every component receives its dependencies explicitly:

```
TemplateExpander
    ├── OperandResolver (injected)
    │     └── SymTable (injected into OperandResolver)
    ├── AssemblyBuffer (injected — output collector)
    ├── RegAllocState (injected — threaded through, returned in result)
    ├── LabelGenerator (injected — pure label factory)
    ├── CodeBlockProvider (injected — provides assembly for nested code blocks)
    └── current_scope_name (set before compound expansions)
```

**Test doubles** for each dependency:

| Dependency | Test Double | Purpose |
|-----------|-------------|---------|
| `SymTable` | `SymTable` built inline in test | Add only the symbols needed for the test case |
| `AssemblyBuffer` | Real `AssemblyBuffer` | Assert on `buf.text` and `buf.write_pos` |
| `RegAllocState` | Real `RegAllocState` | Assert on register allocation pattern |
| `CodeBlockProvider` | `MockCodeBlockProvider` | Records block names; returns controlled assembly |
| `LabelGenerator` | Real `LabelGenerator` or reset each test | Assert on label name format |

---

## 8. Test Fixture Format

Test fixtures are **minimal IR YAML files** that exercise specific codegen features:

```yaml
# fixtures/mov_only.ir.yaml
scopes:
  scp_0:
    user_name: global
    parent: none
    vars:
      - [var_1, variable, x, int, NULL, NULL, NULL, NULL, NULL, 0, 0]
    funcs: []
code_blocks:
  cb_0:
    lbl_from: lbl_f_0
    lbl_to: lbl_t_0
    code:
      - [MOV, var_1, "imm_5", "test.md:1:1"]
```

Fixtures are loaded as YAML strings and deserialized using [`ir_md.gd`](../scenes/ir_md.gd) deserialization (or directly into the Dictionary format the codegen expects).

---

## 9. Edge Cases and Their Test Coverage

| Edge Case | Test | Expected Behaviour |
|-----------|------|-------------------|
| **Empty code block** | `test_empty_block` | No assembly emitted except labels |
| **Missing symbol** | `test_resolve_missing` | Returns `<ERROR:name>` or emits error |
| **Register spill** | `test_reg_spill` | When 4 regs used, 5th alloc → null, spills to stack temp |
| **Nested IF-ELSE** | `test_nested_if` | Labels are unique; jumps target correct labels |
| **Zero-arg CALL** | `test_call_no_args` | No push instructions; no stack cleanup |
| **String immediate** | `test_load_string_imm` | Resolves to label name, not literal value |
| **Stack variable alignment** | `test_stack_positions` | Vars at -3, -7, -11 (4-byte aligned) |
| **Multiple scopes** | `test_multiple_scopes` | Each scope has unique __ENTER_/__LEAVE_ placeholders |
| **Circular code block reference** | `test_circular_ref` | Detected and handled (or prevented) |
| **Very large program** | `test_large_program` | No stack overflow from recursion; reasonable performance |
| **Indirect call** | `test_call_indirect` | Uses `call $funvar;` instead of `call @fun;` |
| **ARRAY with INDEX operation** | `test_index_marks_deref` | Result symbol gets `needs_deref = true` |
| **Immediate zero comparison** | `test_if_uses_imm0` | `cmp res, 0` uses literal 0 (from `new_imm(0)`) |

---

## 10. Migration Strategy

### Phase 1: Test Infrastructure (Day 1)
1. Create `tests/` directory structure
2. Implement `test_runner.gd` with assertion helpers
3. Create test fixture YAML files from existing test programs
4. Verify test framework runs (all tests initially = RED)

### Phase 2: Core Components (Days 2–3)
Increment 1–4: Build and test the foundation components:
1. `AssemblyBuffer` (text, labels, locations)
2. `RegAllocState` (register state machine)
3. `OperandResolver` ($/^/@ resolution)
4. `SymTable` (symbol queries, storage allocation)

Each component is built **test-first** — write the test, see it fail (RED), implement the minimal code (GREEN), then improve (REFACTOR).

### Phase 3: Template Engine (Days 4–6)
Increment 5–11: Build template expansion incrementally:
1. Template data table (pure constants)
2. MOV expansion (simplest command)
3. OP expansion (temp register management)
4. IF/ELSE_IF/ELSE expansion (label generation, branching)
5. WHILE expansion (looping)
6. CALL/CALL_INDIRECT/RETURN expansion (argument handling)
7. ENTER/LEAVE/ALLOC/MOV_ARR expansion (scope, array)

### Phase 4: Integration (Days 7–8)
Increment 12: Build the driver:
1. `CodegenDriver` orchestrates the pipeline
2. Code block traversal in reachability order
3. Fixup pass (enter/leave → sub/add)
4. Global data section generation
5. Location map accumulation and translation

### Phase 5: Validation (Days 9–10)
1. Run all test programs through new codegen
2. Compare output bit-exact with old codegen
3. Fuzz testing: random IR programs, compare outputs
4. Profile: measure allocation counts, string operations
5. Replace old codegen in [`comp_compile_md.gd`](../scenes/comp_compile_md.gd)

---

## 11. Comparison: Current vs. TDD Codegen

| Aspect | Current [`codegen_md.gd`](../scenes/codegen_md.gd) | TDD-Driven Codegen |
|--------|-------|-------------------|
| **Test coverage** | 0% | 100% (target) |
| **Test count** | 0 | 50+ |
| **Module size** | 1 file × 767 lines | 7 files × ~100 lines each |
| **Global mutable state** | 12 variables | Zero — all state is injected |
| **Functions returning void** | ~15 | Zero — every function returns a value |
| **Template encoding** | String constants in code | Pure data records in a table |
| **Register allocator** | Global dictionary | Pure state machine |
| **String scanning at emit** | Yes (find_reference) | No — template slots are pre-defined |
| **Dependency injection** | None — all self.* globals | Constructor injection throughout |
| **Error handling** | ad-hoc `push_error` calls | Tested error paths |
| **Entry point** | `parse_file(filename)` — requires file I/O | `generate(ir_data)` — pure data in, data out |
| **Adding new IR command** | New `generate_cmd_*` + new `match` arm | New template record + handler (tested first) |
| **Re-entrant** | No | Yes — no global state |

---

## 12. Summary

This TDD-driven design replaces **untestable global state, ad-hoc string scanning, and monolithic control flow** with:

- **Tests first** — every function has a test written before the implementation
- **Dependency injection** — all components receive their dependencies explicitly via constructors
- **Pure state machines** — register allocator threads state through return values, never mutates
- **Data-driven templates** — the IR→assembly mapping is pure data, not control flow
- **Small composable units** — 7 small files instead of 1 monolithic file
- **Incremental complexity** — 12 Red-Green-Refactor increments from simplest MOV to full pipeline
- **Testable by construction** — no mocking framework needed; dependencies are real objects constructed in test setup

The design emerges from the discipline of writing the test first: if a component is hard to test, it gets redesigned until the test is trivial. The result is a codegen that is verifiably correct, easily extensible, and safe to refactor.
