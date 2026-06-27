# XP-Driven Data Codegen Plan

> **Author**: Extreme Programming Advocate  
> **Philosophy**: YAGNI. Simplest thing that works. Refactor mercilessly. Collective ownership. Continuous feedback. Evolutionary design.

---

## 1. The Current Pain

[`scenes/codegen_md.gd`](scenes/codegen_md.gd) (833 lines) suffers from:

| Smell | XP Diagnosis |
|---|---|
| One giant file with ~15 `generate_cmd_*` methods | Duplication — each method re-invents the same emit/location/register logic |
| `op_map` dictionary (line 12-25) is a template system **inside** strings | The domain (IR→assembly mapping) is trapped in string-replace; not data |
| Register allocation (`alloc_register`, line 634) is intertwined with template expansion (`emit`, line 474) | Single Responsibility Principle violated; cannot test allocation independently |
| `__ENTER_`/`__LEAVE_` placeholders + `fixup_enter_leave` (line 754) | A fixup pass for stack frames — should be a **slot resolver** in a pipeline |
| `all_syms` is a flat Dictionary mixing codeblocks, variables, temporaries, immediates, labels | No type safety; all lookups are string-based `assert(val in all_syms)` |
| Adding a new IR instruction means writing a new `generate_cmd_*` function | **High friction** — violates Open/Closed Principle |

---

## 2. The XP Goal

> **Replace the ad-hoc dispatch with a data-driven template engine — one small iteration at a time, always keeping the system green.**

No big-bang rewrite. We evolve the existing codegen into a pipeline of composable passes, where the IR→assembly mapping is **declared as data**, not as imperative `generate_cmd_*` functions.

---

## 3. Architecture: A Pipeline of Simple Passes

```
 IR (Dictionary of CodeBlocks)
     │
     ▼
 ┌─────────────┐
 │  1. Slot    │  Maps each IR_Value to a concrete storage slot
 │   Allocator │  (register, stack offset, global label, immediate)
 └──────┬──────┘
        │
        ▼
 ┌─────────────┐
 │  2. Pattern │  Matches each IR_Cmd against a table of templates
 │   Matcher   │  Binds operands → produces a "Fragment" tree
 └──────┬──────┘
        │
 ┌─────────────┐
 │  3. Slot    │  Replaces symbolic operand references ($, @, ^)
 │   Resolver  │  with concrete assembly strings (register names, labels)
 └──────┬──────┘
        │
        ▼
 ┌─────────────┐
 │  4. Emitter │  Concatenates fragments → text (with debug trace & location map)
 └─────────────┘
        │
        ▼
 Assembly text → [comp_asm_zd.gd](scenes/comp_asm_zd.gd) → Machine code
```

### Why this pipeline?

- **Each pass is testable in isolation** (feedback).
- **Passes can be added/removed/reordered** (evolutionary design).
- **No pass knows about passes beyond its immediate neighbor** (simplicity).
- **Replace one `generate_cmd_*` at a time** (courage).

---

## 4. The Template Data Structure (the Core Innovation)

Currently, an IR→assembly mapping lives in `op_map`:

```gdscript
# OLD: fragile string-replace
"EQUAL": "cmp %a, %b; mov %a, CTRL; band %a, CMP_Z; bnot %a; bnot %a;\n",
```

**NEW**: A **declarative template table** — pure data, no logic:

```gdscript
# NEW: data-driven pattern table
const template_table = {
	"MOV": {
		"out": "mov {dest}, {src};",
		"slots": ["dest", "src"],
		"size": 8,
	},
	"OP:EQUAL": {
		"out": [
			"cmp {a}, {b};",
			"mov {res}, CTRL;",
			"band {res}, CMP_Z;",
			"bnot {res};",
			"bnot {res};",
		],
		"slots": ["a", "b", "res"],
		"size": 40,  # 5 instructions × 8 bytes
	},
	"OP:ADD": {
		"out": "add {a}, {b};",  # simple: can be single-line
		"slots": ["a", "b", "res"],
		"size": 8,
	},
	"IF": {
		"out": [
			"# cond -> {cond_cb}",
			"cmp {cond_result}, 0;",
			"jz {else_lbl};",
			"# then -> {then_cb}",
			"jmp {end_lbl};",
			"{else_lbl}:",
		],
		"slots": ["cond_cb", "cond_result", "then_cb"],
		"generated_slots": ["else_lbl", "end_lbl"],
		"size": "auto",  # computed from generated labels + sub-blocks
	},
}
```

### Design decisions (XP rationale):

1. **`out` is an array of lines, not one big string** — Each line maps to one assembly instruction. The emitter can count lines × `cmd_size` for simple cases. No more `op_str.count(";") * cmd_size`.

2. **`slots` declares which IR operands bind where** — Explicit binding means the resolver knows exactly which operands need `$`/`@`/`^` treatment without scanning the string for sigils. (YAGNI: we start simple; sigil scanning stays in the resolver for now.)

3. **`generated_slots` declares slots created by the codegen** (labels, temporaries) — The pattern matcher allocates these automatically before emitting. No more scattered `new_lbl()` calls.

4. **`size` can be `"auto"`** — For templates that contain sub-codeblocks (IF, WHILE, CALL), the size is computed by summing the sub-block sizes. For fixed templates, it's a constant.

---

## 5. The Passes — Detailed Design

### 5.1 Slot Allocator (≈ existing [`allocate_vars`](scenes/codegen_md.gd:642) + [`alloc_register`](scenes/codegen_md.gd:634))

**Input**: `IR` Dictionary (CodeBlocks + Scopes with Values)  
**Output**: Same IR, but every `IR_Value` has a `.storage` populated.

```gdscript
class SlotAllocator:
	# Pure: given IR → returns IR with .storage filled
	# No emit logic, no template knowledge.
	func allocate(ir: Dictionary) -> Dictionary:
		for scope in ir.scopes.values():
			for val in scope.vars:    _alloc_value(val, scope)
			for val in scope.funcs:   _alloc_value(val, scope)
		for cb in ir.code_blocks.values():
			cb.storage = {"type": "code"}
		return ir
```

**XP tests** (before writing the pass):
- `test_alloc_global_var_stores_as_global`
- `test_alloc_local_var_stores_on_stack`
- `test_alloc_arg_stores_at_positive_ebp_offset`
- `test_alloc_temporary_falls_back_to_stack_when_no_registers`

### 5.2 Pattern Matcher (new — replaces the `match` dispatch)

**Input**: `IR_Cmd` + `template_table`  
**Output**: `Fragment` — a tree of resolved assembly lines + metadata.

```gdscript
class PatternMatcher:
	func match(cmd: IR_Cmd, table: Dictionary) -> Fragment:
		var key = _build_key(cmd)    # "MOV", "OP:ADD", "IF", etc.
		var pattern = table.get(key)
		if not pattern:
			push_error("No template for IR command: ", key)
			return Fragment.empty()
		
		var frag = Fragment.new()
		frag.template = pattern
		frag.bindings = _bind_slots(cmd.words, pattern.slots)
		
		# Allocate generated slots (labels, temporaries)
		for slot_name in pattern.generated_slots:
			frag.generated[slot_name] = _alloc_label(slot_name)
		
		return frag
```

**XP tests**:
- `test_match_mov_binds_dest_and_src`
- `test_match_op_add_binds_a_b_res`
- `test_match_if_allocates_else_lbl_and_end_lbl`
- `test_unknown_cmd_raises_error`

### 5.3 Slot Resolver (≈ core of existing [`emit`](scenes/codegen_md.gd:474))

**Input**: `Fragment` + resolved `IR_Value.storage` from Slot Allocator  
**Output**: `Fragment` with all symbolic references replaced with assembly strings.

```gdscript
class SlotResolver:
	func resolve(frag: Fragment, all_syms: Dictionary) -> Fragment:
		for i in range(frag.template.out.size()):
			var line = frag.template.out[i]
			for slot_name in frag.bindings.keys():
				var ir_val = frag.bindings[slot_name]
				var storage = _storage_of(ir_val, all_syms)
				var replacement = _format_storage(storage)
				line = line.replace("{" + slot_name + "}", replacement)
			frag.resolved_lines.append(line)
		return frag
```

**XP tests**:
- `test_resolve_global_var_becomes_label_ref`
- `test_resolve_stack_var_becomes_EBP_offset`
- `test_resolve_immediate_becomes_literal`
- `test_resolve_label_becomes_label_name`

### 5.4 Emitter (≈ existing [`emit_raw`](scenes/codegen_md.gd:606) + [`mark_loc`](scenes/codegen_md.gd:786))

**Input**: Array of resolved `Fragment`s  
**Output**: Final assembly text + `LocationMap`.

```gdscript
class Emitter:
	func emit(fragments: Array[Fragment], debug_trace: bool) -> AssyBlock:
		var ab = AssyBlock.new()
		for frag in fragments:
			for line in frag.resolved_lines:
				if debug_trace:
					ab.code += "# " + frag.debug_info + "\n"
				ab.code += line + "\n"
				ab.write_pos += frag.template.size_per_line
		return ab
```

---

## 6. Incremental Migration Strategy (the XP Way)

We do **not** flip a switch. We replace one IR command at a time.

### Sprint 1: Extract `PatternMatcher` and `template_table`

1. Write the `template_table` constant using **only the current `op_map` entries** (lines 12-25). This is a no-op refactor: the data is the same, just expressed as structured dicts.
2. Write `PatternMatcher` that reads the table and produces `Fragment` objects.
3. Wire `PatternMatcher` into `generate_cmd_op` — replace the string-replace with fragment resolution.
4. **Test**: all existing assembly output must be byte-identical.

### Sprint 2: Extract `SlotAllocator`

1. Extract lines 642-698 into a standalone `SlotAllocator` pass.
2. Call it once at the start of `generate()` (line 143) instead of inside `allocate_vars`.
3. **Test**: same output. Verify storage assignments via a test helper.

### Sprint 3: Extract `SlotResolver`

1. Move the `$`/`@`/`^` scanning logic (lines 474-540) into `SlotResolver`.
2. Replace the inline `emit()` function with a call to `SlotResolver.resolve()` + `Emitter.emit()`.
3. **Test**: same output.

### Sprint 4: Convert `generate_cmd_if` → template data

1. Move the IF/ELSE_IF/ELSE/WHILE patterns into the `template_table`.
2. Remove `generate_cmd_if`, `generate_cmd_else_if`, `generate_cmd_else`, `generate_cmd_while`.
3. **Test**: same output for all branching programs in `res/data/`.

### Sprint 5: Convert `generate_cmd_call` → template data

1. Add CALL/CALL_INDIRECT/RETURN patterns to the `template_table`.
2. Remove `generate_cmd_call`, `generate_cmd_call_indirect`, `generate_cmd_return`.
3. **Test**: same output for `res/data/lib/` test files.

### Sprint 6: Remove dead code

1. Delete all `generate_cmd_*` functions.
2. Delete `op_map`.
3. Delete `__ENTER_`/`__LEAVE_` fixup — replace with direct emit (the slot allocator already knows the stack frame size).
4. Rename `codegen_md.gd` → `codegen_pipeline.gd`. (Collective ownership: the old name was misleading.)

---

## 7. Template Format Specification

### 7.1 Template Entry Schema

```gdscript
class TemplateEntry:
	var key: String          # "MOV", "OP:ADD", "IF", "CALL", etc.
	var out: Array[String]   # Assembly lines with {slot} placeholders
	var slots: Array[String] # Slots bound from IR_Cmd.words[]
	var generated_slots: Array[String]  # Slots created by codegen (labels)
	var size_per_line: int = 8          # Bytes per assembly line
```

### 7.2 Slot Naming Convention

| Slot prefix | Meaning | Example resolution |
|---|---|---|
| `{foo}` | Load operand `foo` | `*var_5` (global), `EBP[-12]` (stack), `42` (immediate) |
| `{@foo}` | Address of operand `foo` | `var_5` (global label), `EBP+12` (stack address) |
| `{^foo}` | Store target `foo` | `*var_5` (global), `EBP[-12]` (stack) |

(This matches the existing `$`/`@`/`^` sigils, just expressed as template syntax.)

### 7.3 Fragment Data Structure

```gdscript
class Fragment:
	var template: TemplateEntry
	var bindings: Dictionary       # slot_name → IR_Value (or ir_name string)
	var generated: Dictionary      # generated_slot_name → allocated name
	var resolved_lines: Array[String]  # After SlotResolver runs
	var loc: LocationRange         # Source location for debug mapping
```

---

## 8. Collective Code Ownership

| File | Responsibility |
|---|---|
| [`template_table.gd`](plans/template_table.gd) (new) | The entire IR→assembly mapping as **data**. Anyone can add/edit entries. No code changes needed for new instructions. |
| [`slot_allocator.gd`](plans/slot_allocator.gd) (new) | Storage allocation pass. Pure function: IR → IR. |
| [`pattern_matcher.gd`](plans/pattern_matcher.gd) (new) | Matches IR_Cmd → template. Pure function. |
| [`slot_resolver.gd`](plans/slot_resolver.gd) (new) | Replaces symbolic references. Pure function. |
| [`emitter.gd`](plans/emitter.gd) (new) | Concatenates fragments → text + LocationMap. |
| [`codegen_md.gd`](scenes/codegen_md.gd) | Orchestrator: calls pipeline passes. Shrinks with each sprint. |

Each file is small (< 150 lines), testable in isolation, and can be understood by any team member.

---

## 9. YAGNI — What We Explicitly WON'T Do (Yet)

| Postponed feature | Reason (XP) |
|---|---|
| Register spilling | Current 4-register model works for MiniDerp. When it breaks, we'll add it. |
| Instruction scheduling / optimization | The CPU is emulated; no pipeline hazards. YAGNI. |
| Complex pattern matching (wildcards, optional slots) | Flat `key` match suffices for all current IR commands. |
| Template inheritance / composition | If two templates share output, we extract later (Once and Only Once). |
| Hot-reloadable templates | The table is `const`. If we need dynamic templates, we defer. |

---

## 10. Test Strategy (Continuous Feedback)

All tests live in `tests/` and run as Godot unit tests.

### Acceptance test (smoke — always green)

```gdscript
func test_all_example_programs_produce_same_assembly():
	for file in _example_files():
		var ir = load_ir(file)
		var old_asm = OLD_CODEGEN.generate(ir)
		var new_asm = PIPELINE_CODEGEN.generate(ir)
		assert_eq(new_asm, old_asm)
```

### Pass-level tests

```gdscript
func test_slot_allocator_assigns_globals_for_global_scope():
	var ir = make_single_var_ir("x")
	var allocator = SlotAllocator.new()
	allocator.allocate(ir)
	var var_x = ir.code_blocks["global"].code[0].bindings["dest"]
	assert_eq(var_x.storage.type, "global")

func test_pattern_matcher_returns_fragment_for_mov():
	var cmd = IR_Cmd.new({words: ["MOV", "dest", "src"]})
	var frag = PatternMatcher.new().match(cmd, template_table)
	assert_eq(frag.template.key, "MOV")
	assert_eq(frag.bindings["dest"], "dest")

func test_slot_resolver_resolves_register():
	var frag = make_fragment_with_slot("reg_slot", "EAX")
	SlotResolver.new().resolve(frag, all_syms)
	assert_eq(frag.resolved_lines[0], "mov EAX, src;")
```

### Mutation tests (courage)

```gdscript
func test_removing_template_entry_breaks_corresponding_test():
	# If someone deletes "MOV" from the table, this test fails.
	# Collective ownership safety net.
```

---

## 11. Risk Mitigation

| Risk | Mitigation (XP) |
|---|---|
| Breaking change during migration | Each sprint keeps the old `generate_cmd_*` as fallback. Bit-exact comparison test. |
| Template table doesn't express some pattern | Keep the old `generate_cmd_*` as fallback for that pattern. Migrate later. |
| Performance regression | The pipeline makes extra object allocations (Fragment). If it matters, optimize last — not first. |
| Too much new code | Each pass is < 150 lines. The template table replaces in aggregate more code than it adds. |

---

## 12. Success Criteria

- [ ] All IR commands in [`codegen_md.gd`](scenes/codegen_md.gd:268) are represented in `template_table`.
- [ ] All `generate_cmd_*` functions are deleted.
- [ ] The `op_map` dictionary is removed.
- [ ] The fixup passes (`fixup_enter_leave`, `fixup_symtable`) are replaced.
- [ ] Adding a new IR instruction requires: **one template entry + one test**. Zero new functions.
- [ ] All existing `res/data/*` example programs produce identical assembly output.
- [ ] Codebase shrinks by ≥40% (833 → ~500 lines total across all passes).
