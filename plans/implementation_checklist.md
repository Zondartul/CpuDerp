# Implementation Checklist — Codegen Refactor v2

**Derived from**: `plans/synthesis_master_plan_v2.md`
**Target**: Incrementally replace `scenes/codegen_md.gd` with a template-driven two-pass pipeline
**Source files analyzed**: `scenes/codegen_md.gd`, `scenes/ir_md.gd`, `scenes/comp_compile_md.gd`, `class_IR_cmd.gd`, `class_CodeBlock.gd`, `class_AssyBlock.gd`, `class_IR_value.gd`, `globals.gd`

---

## A. Architect Review Findings (Gaps & Issues to Address)

Before implementing, the following gaps in the v2 plan MUST be resolved. Each is annotated with its impact and a fix recommendation.

### A.1 CRITICAL: `InflatedGraph` inheritance for `.tres` serialization

| Issue | In `InflatedGraph` is `Resource`, but children (`TemplateDef`, `SlotDef`, `ITGNode`, etc.) are `RefCounted`. GDScript serialization via `ResourceSaver` requires all composed types to also be `Resource` subclasses or primitive types. |
|---|---|
| **Impact** | `ResourceSaver.save(graph, ...)` will fail or produce an incomplete `.tres` file. The entire caching strategy breaks. |
| **Fix** | Either: (a) Make all ITG node types extend `Resource`, OR (b) store the ITG as a plain `Dictionary` tree inside `InflatedGraph` and write a custom `_to_dict()` / `from_dict()` pair. Recommendation: option (b) — simpler, avoids bloating the Resource system. |

### A.2 CRITICAL: `%if_block_lbl_end` context variable — scoping undefined

| Issue | `ELSE_IF` and `ELSE` templates reference `{%if_block_lbl_end}` from the preceding `IF` template. This is equivalent to the current `cur_block.if_block_lbl_end` mutable state. The plan defines `CONTEXT_REF` in `SlotRef.Role` but does NOT specify how context variables are created, propagated, or scoped between templates. |
|---|---|
| **Impact** | `ELSE_IF` and `ELSE` will fail to resolve the end-label reference. Control flow if/else chains break. |
| **Fix** | Define a `ContextScope` object passed through Pass 2. `IF` template sets `context.if_block_lbl_end = generated_label`. `ELSE_IF`/`ELSE` reads it. Must be scoped per if-chain, not global. See file [`scenes/codegen_md.gd:367-369`](scenes/codegen_md.gd:367) for the current logic. |

### A.3 HIGH: Location map emission missing from new pipeline

| Issue | The current codegen produces `AssyBlock.loc_map` (via `mark_loc_begin`/`mark_loc_end`) which maps assembly write positions back to source locations. The new pipeline has no equivalent. The debugger will break. See [`scenes/codegen_md.gd:786-798`](scenes/codegen_md.gd:786). |
|---|---|
| **Impact** | No source-level debugging. The debug panel's "highlight line" feature stops working. |
| **Fix** | Each `EMIT_LINE` in Pass 2 must carry the original `cmd.loc` (a `LocationRange`). The `EmitBuffer` must track a parallel `LocationMap` dictionary (same structure as `class_LocationMap.gd`). The final `CodegenResult` must include a `loc_map: LocationMap` field. |

### A.4 HIGH: `reverse` callback not handled in Pass 2 `emit_node_list`

| Issue | The `CALL` template uses `@reverse(args)` but Pass 2's `emit_node_list` shows no `CALLBACK` handler for `"reverse"`. The Pass 1 handler comment says "reverse is a Pass 2 operation only". |
|---|---|
| **Impact** | CALL arguments won't be reversed; stack argument order will be wrong. |
| **Fix** | Add a `handle_reverse()` case in Pass 2's `emit_node_list` that reverses the bound list in-memory before subsequent nodes are processed. |

### A.5 HIGH: `flatten_commands()` function doesn't exist

| Issue | The `codegen_master.gd` dispatcher calls `flatten_commands(old_codegen.IR)` but the current IR has nested `CodeBlock` objects with `if_block_continued` state. See [`scenes/codegen_md.gd:148-173`](scenes/codegen_md.gd:148). |
|---|---|
| **Impact** | The pipeline won't have a flat command list to iterate over. |
| **Fix** | Implement `flatten_commands(IR, graph, manifest)` that walks `manifest.reachable_cbs` in emit order and extracts each `IR_Cmd` into a single flat list. Preserve the emit ordering from `codegen_md.gd:generate()`. |

### A.6 MEDIUM: Register allocator conflict during migration

| Issue | During migration, `codegen_master.gd` runs both old and new codegen on the same `codegen_md.gd` instance. The old codegen uses mutable `regs_in_use` (line 633-640). The new pipeline has its own allocator. If both run in the same `generate()` call, register state corrupts. |
|---|---|
| **Impact** | Intermittent register allocation failures during migration sprints. |
| **Fix** | `codegen_master.gd` must create a **fresh** `codegen_md.gd` instance (or call `reset()`) before delegating to old codegen for unmigrated commands. Never share state. |

### A.7 MEDIUM: `AND`, `OR`, `NOT`, `B_*` ops missing from template

| Issue | The OP template covers only 12 variants. The analyzer's `op_map` in [`scenes/analyzer_md.gd:18-43`](scenes/analyzer_md.gd:18) also includes `AND`, `OR`, `NOT`, `B_AND`, `B_OR`, `B_XOR`, `B_SHIFT_RIGHT`, `B_SHIFT_LEFT`, `B_NOT`. Whether these are actually emitted depends on test programs. |
|---|---|
| **Impact** | If a test program uses these ops, the new codegen will fail with "No template for [AND]". |
| **Fix** | (a) Add `# UNUSED` comment for missing variants in `.tg` template, OR (b) add them with correct assembly patterns. Verify by checking if any test data file uses these ops. |

### A.8 LOW: `generate_globals()` equivalent missing

| Issue | The current codegen emits global variable/array/string declarations at the end via `generate_globals()`. The new pipeline doesn't show where this happens. See [`scenes/codegen_md.gd:202-220`](scenes/codegen_md.gd:202). |
|---|---|
| **Impact** | Global data section missing from output. |
| **Fix** | Add a `globals_emit.gd` step at the end of Pass 2 (or in `codegen_master.gd`) that walks `manifest.symbols` and emits `:label: db 0;` / `:label: alloc N;` / `:label: db "str", 0;` lines. |

### A.9 LOW: Cache invalidation strategy unspecified

| Issue | The plan says "timestamp check" for re-parsing `.tg` files but doesn't specify how this works in the editor vs exported builds. |
|---|---|
| **Impact** | Stale cache may be used after template edits. Export builds may lack the parser entirely. |
| **Fix** | In editor, use `ResourceLoader.has_cached()` + file modification time check. In export, either pre-bake the `.tres` or include the parser. Document this decision. |

### A.10 LOW: No `add_IR_trace` / debug annotation equivalent

| Issue | The old codegen has `ADD_IR_TRACE` and `ADD_DEBUG_TRACE` flags that annotate assembly with `# IR: ...` and `# emit.xxx()` comments. See [`scenes/codegen_md.gd:8-9`](scenes/codegen_md.gd:8). |
|---|---|
| **Impact** | Debug builds lose traceability. Minor, but may break scripts that parse assembly output. |
| **Fix** | Add optional `trace_enabled: bool` parameter to Pass 2. When true, emit debug comment lines. |

---

## B. File Manifest — New Files to Create

All new files go in `scenes/` unless otherwise specified.

| # | File | Class(es) | Depends On | Description |
|---|------|-----------|------------|-------------|
| 1 | `inflated_template_types.gd` | `TemplateDef`, `SlotDef`, `ITGNode` (base), `EmitLineNode`, `SlotRef`, `ForEachNode`, `VariantSwitchNode`, `CallbackNode`, `TempAllocNode`, `LabelDefNode`, `ImmDefNode` | None (pure data) | All data types for the ITG. Must support `_to_dict()` / `from_dict()` for serialization (see A.1). |
| 2 | `inflated_template_graph.gd` | `InflatedGraph extends Resource` | #1 | Container: `templates: Dictionary`, `version: int`. Serializes to `.tres` via custom `_get_property_list()` + `_set()` + `_get()`. |
| 3 | `abi_manifest.gd` | `ABIManifest extends RefCounted`, `SymbolInfo`, `TempSlot` | None | Pass 1 output: symbols, labels, temps, reachable Cbs, scope stack sizes. |
| 4 | `codegen_result.gd` | `CodegenResult` | `LocationMap` (existing) | Return type: `.success(assembly_text, loc_map)` / `.failure(error_msg)`. |
| 5 | `template_parser.gd` | `TemplateParser` | #1, #2 | Parses `.tg` text → `InflatedGraph`. Line-based scanner with recursive descent for nested blocks. |
| 6 | `abi_scanner.gd` | `ABIScanner` | #2, #3, existing IR types | Pass 1: walks IR code blocks through ITG, discovers symbols/temps/labels/callbacks. |
| 7 | `stor_alloc.gd` | `StorageAllocator` | #3, #6 | Allocates storage (global/stack) for all symbols in manifest. |
| 8 | `tmpl_expand.gd` | `TemplateExpander` | #2, #3, #4 | Pass 2: walks IR commands, resolves slots against manifest, produces assembly text + loc_map. |
| 9 | `reg_resolve.gd` | `RegisterResolver` | #3 | Pre-planned register assignment for temporaries (called from `stor_alloc.gd`). |
| 10 | `asm_emit.gd` | `AsmEmitter` | #4 | Stringification of typed emit buffer + `__ENTER_`/`__LEAVE_` fixup + globals emission. |
| 11 | `globals_emit.gd` | `GlobalsEmitter` | #3 | Walks `manifest.symbols` for global variables/arrays/strings → emits data section. |
| 12 | `codegen_master.gd` | `CodegenMaster extends Node` | #6, #7, #8, #9, #10, #11, existing `codegen_md.gd` | Pipeline orchestrator: splits migrated/unmigrated commands, runs each half, combines output + location maps. |

---

## C. Files to Modify

| File | Changes | Sprint |
|------|---------|--------|
| `scenes/comp_compile_md.gd` | Replace `codegen.parse_file(input)` → `codegen_master.generate(input)`. Add `@export var codegen_master: Node`. | Sprint 1 |
| `scenes/codegen_md.gd` | Add `generate_remaining(unmigrated_cmds)` method. Add `reset_for_master()` that resets only non-IR state. NO structural changes to existing functions. | Sprint 1 |

---

## D. Directory Structure to Create

```
res/
└── templates/
    ├── codegen_templates.tg        # [NEW] Template file
    └── codegen_templates_cache.tres # [NEW] Auto-generated cache

scenes/
    ├── inflated_template_types.gd   # [NEW]
    ├── inflated_template_graph.gd   # [NEW]
    ├── abi_manifest.gd              # [NEW]
    ├── codegen_result.gd            # [NEW]
    ├── template_parser.gd           # [NEW]
    ├── abi_scanner.gd               # [NEW]
    ├── stor_alloc.gd                # [NEW]
    ├── tmpl_expand.gd               # [NEW]
    ├── reg_resolve.gd               # [NEW]
    ├── asm_emit.gd                  # [NEW]
    ├── globals_emit.gd              # [NEW]
    └── codegen_master.gd            # [NEW]

tests/
    ├── test_template_parser.gd      # [NEW]
    ├── test_abi_scanner.gd          # [NEW]
    ├── test_stor_alloc.gd           # [NEW]
    ├── test_tmpl_expand.gd          # [NEW]
    ├── test_reg_resolve.gd          # [NEW]
    ├── test_asm_emit.gd             # [NEW]
    ├── test_codegen_integration.gd  # [NEW] Full pipeline
    └── test_golden_regression.gd    # [NEW] Compare output to golden files
```

---

## E. Detailed Sprint Checklist

### Sprint 0 — Foundation

**Goal**: Data types, template parser, golden files, first template (MOV). No codegen pipeline yet.

| # | Task | File(s) | Dependencies | Acceptance Criteria |
|---|------|---------|--------------|-------------------|
| 0.1 | Create `res/templates/` directory | `res/templates/` | None | Directory exists |
| 0.2 | Write `inflated_template_types.gd` with all ITG node types | `scenes/inflated_template_types.gd` | None | All types have `_to_dict()` / `from_dict()` (see A.1). Can round-trip through JSON. |
| 0.3 | Write `inflated_template_graph.gd` as `Resource` | `scenes/inflated_template_graph.gd` | 0.2 | `ResourceSaver.save()` and `load()` work correctly. |
| 0.4 | Write `abi_manifest.gd` | `scenes/abi_manifest.gd` | None | Can create manifest, add symbols/temps/labels. |
| 0.5 | Write `codegen_result.gd` | `scenes/codegen_result.gd` | `class_LocationMap.gd` | `.success()` and `.failure()` paths work. |
| 0.6 | Write `template_parser.gd` — core scan logic | `scenes/template_parser.gd` | 0.2, 0.3 | Can parse `@template`, `@end`, `@bind`, `@temp`, `@label`, `@new_imm`, `@emit_cb`, `@ref_cb`, `@variant`, `@reverse`, `@needs_deref`, `for/endfor`, `if/endif`, emit lines |
| 0.7 | Write `template_parser.gd` — slot extraction and binding expression parsing | `scenes/template_parser.gd` | 0.6 | Correctly parses `$cmd.words[N]`, `$cmd.words[N..-1]`, `$cmd.words[-1]`, `$cmd.words[1]?` |
| 0.8 | Write `codegen_templates.tg` with MOV template only | `res/templates/codegen_templates.tg` | None | File is valid; parser (0.7) produces correct `TemplateDef` for MOV |
| 0.9 | Capture golden files from current codegen: run ALL `res/data/*.md` through current codegen, save outputs | Generated outputs in `res/golden/` | Running `codegen_md.gd` | Each `.md` → `.asm` file. See Sprint 0 in plan v2 section 7. |
| 0.10 | Write `test_template_parser.gd` | `tests/test_template_parser.gd` | 0.6, 0.7 | MOV template parsed correctly: 2 slots (dest:store, src:load), 2 binds, 1 emit line. |
| 0.11 | Write `test_golden_regression.gd` (runs current codegen against golden) | `tests/test_golden_regression.gd` | 0.9 | All golden files pass with current codegen. |

### Sprint 1 — MOV + Infrastructure

**Goal**: Full pipeline works for MOV instruction. Parallel pipeline dispatcher ready.

| # | Task | File(s) | Dependencies | Acceptance Criteria |
|---|------|---------|--------------|-------------------|
| 1.1 | Write `abi_scanner.gd` — Pass 1 discovery | `scenes/abi_scanner.gd` | 0.3, 0.4 | Can walk IR code blocks, match commands to templates, discover symbols/temps/labels for MOV |
| 1.2 | Write `reg_resolve.gd` — register pre-planning | `scenes/reg_resolve.gd` | 0.4 | Allocates EAX/EBX/ECX/EDX, falls back to stack spill |
| 1.3 | Write `stor_alloc.gd` — storage allocator | `scenes/stor_alloc.gd` | 1.2, existing `codegen_md.gd:allocate_vars()` | Produces same assignments as old codegen for global and stack variables. Matches old `allocate_value()` logic. |
| 1.4 | Write `tmpl_expand.gd` — Pass 2 imperative emit (MOV only) | `scenes/tmpl_expand.gd` | 0.3, 0.4, 0.5 | Can expand MOV template: resolves `{dest}` and `{src}` to correct assembly text, emits `mov ^dest, $src;\n` |
| 1.5 | Write `asm_emit.gd` — stringification + fixups | `scenes/asm_emit.gd` | 0.5, 1.4 | Can stringify emit buffer, handle `__ENTER_` / `__LEAVE_` fixup |
| 1.6 | Write `globals_emit.gd` | `scenes/globals_emit.gd` | 0.4 | Emits `:label: db 0;` / `:label: alloc N;` for global symbols. Matches `generate_globals()` exactly (A.8). |
| 1.7 | Write `codegen_master.gd` — orchestrator | `scenes/codegen_master.gd` | 1.1, 1.3, 1.4, 1.5, 1.6, existing `codegen_md.gd` | Splits migrated ops. Runs Pass 1 + Pass 2 for migrated. Delegates unmigrated to old codegen. **MUST call `codegen_md.reset()`** before using old codegen (see A.6). |
| 1.8 | Modify `codegen_md.gd` — add `generate_remaining()` | `scenes/codegen_md.gd` | None | New method accepts list of unmigrated `IR_Cmd` objects, runs old `generate()` logic on them only. Must preserve all existing behavior. |
| 1.9 | Wire `comp_compile_md.gd` to use `codegen_master.gd` | `scenes/comp_compile_md.gd` | 1.7 | Compilation uses new pipeline. `migrated_ops = {}` initially (all commands still go through old codegen). |
| 1.10 | Add MOV to `migrated_ops` in `codegen_master.gd` | `scenes/codegen_master.gd` | 1.7 | MOV runs through new pipeline. All other commands through old codegen. |
| 1.11 | Verify: `hello.md` golden matches | `res/golden/hello.asm` | 1.10 | `test_golden_regression.gd` passes with MOV migrated. |
| 1.12 | Write `test_codegen_integration.gd` | `tests/test_codegen_integration.gd` | 1.10 | Full pipeline on hello.md matches golden. |
| 1.13 | Remove MOV from `generate_cmd_mov()` | `scenes/codegen_md.gd:284-291` | 1.11 | MOV is no longer handled by old codegen. Remove the function body (keep stub for safety, or delete). |

### Sprint 2 — OP + Storage

**Goal**: All arithmetic/logic/bitwise operations migrated. `@variant`, `@temp`, register allocation working.

| # | Task | File(s) | Dependencies | Acceptance Criteria |
|---|------|---------|--------------|-------------------|
| 2.1 | Add ALL 12+ OP variants to `codegen_templates.tg` | `res/templates/codegen_templates.tg` | 1.4 | Template covers: ADD, SUB, MUL, DIV, MOD, GREATER, LESS, EQUAL, NOT_EQUAL, INDEX, INC, DEC. **Also check** if AND, OR, NOT, B_AND, B_OR, B_XOR, B_SHIFT_RIGHT, B_SHIFT_LEFT, B_NOT are needed (see A.7). |
| 2.2 | Add `@variant` handling to `tmpl_expand.gd` Pass 2 | `scenes/tmpl_expand.gd` | 1.4 | Variant switch resolves op name → correct template body. |
| 2.3 | Add `@temp` handling to `abi_scanner.gd` Pass 1 | `scenes/abi_scanner.gd` | 1.1 | Temp names discovered and added to manifest. |
| 2.4 | Add `@temp` resolution to `tmpl_expand.gd` Pass 2 | `scenes/tmpl_expand.gd` | 1.4 | `{tmp_a}` → `EAX` or `EBP[-4]` based on manifest. |
| 2.5 | Verify: All OP-using test programs match goldens | See test data files | 2.1-2.4 | `test_arr2.md`, `test_not_eq.md`, `array_test.md` golden matches. |
| 2.6 | Remove OP from old `generate_cmd_op()` + `op_map` | `scenes/codegen_md.gd:294-325`, `scenes/codegen_md.gd:12-25` | 2.5 | OP removed from old codegen. |

### Sprint 3 — Control Flow

**Goal**: IF, ELSE_IF, ELSE, WHILE migrated. `@label`, `@new_imm`, `@emit_cb`, context variables working.

| # | Task | File(s) | Dependencies | Acceptance Criteria |
|---|------|---------|--------------|-------------------|
| 3.1 | Add IF template to `.tg` | `res/templates/codegen_templates.tg` | 1.4 | Template uses `@label`, `@new_imm`, `@emit_cb` |
| 3.2 | Add ELSE_IF template to `.tg` | `res/templates/codegen_templates.tg` | 3.1 | Uses `{%if_block_lbl_end}` context variable |
| 3.3 | Add ELSE template to `.tg` | `res/templates/codegen_templates.tg` | 3.2 | Uses `{%if_block_lbl_end}` context variable |
| 3.4 | Add WHILE template to `.tg` | `res/templates/codegen_templates.tg` | 3.1 | Uses `@label`, `@new_imm`, `@emit_cb` |
| 3.5 | Implement context variable scoping in Pass 2 (see A.2) | `scenes/tmpl_expand.gd` | 1.4 | Add `ContextScope` object with per-if-chain `if_block_lbl_end`. Passed through `emit_node_list()`. |
| 3.6 | Add `@label` generation to `abi_scanner.gd` Pass 1 | `scenes/abi_scanner.gd` | 1.1 | Labels discovered, unique names pre-generated in manifest. Match `new_lbl()` naming scheme exactly: `lbl_N__hint` |
| 3.7 | Add `@new_imm` handling to `abi_scanner.gd` Pass 1 | `scenes/abi_scanner.gd` | 1.1 | Immediate values created as symbols. Match `new_imm()` naming scheme. |
| 3.8 | Add `@emit_cb` handling to `tmpl_expand.gd` Pass 2 | `scenes/tmpl_expand.gd` | 1.4, 1.5 | Recursive call to expand code block inline. **Must track currently-emitting blocks** to prevent infinite recursion (see A.12). |
| 3.9 | Implement `flatten_commands()` in `codegen_master.gd` (see A.5) | `scenes/codegen_master.gd` | 1.7 | Walks `manifest.reachable_cbs` in emit order, respecting `if_block_continued` semantics. |
| 3.10 | Verify: all if/while test programs match goldens | — | 3.5-3.9 | `test_arr_if.md`, `elif_test.md`, `if/while` golden matches |
| 3.11 | Remove old if/while functions | `scenes/codegen_md.gd:349-419` | 3.10 | `generate_cmd_if`, `generate_cmd_else_if`, `generate_cmd_else`, `generate_cmd_while` removed. |

### Sprint 4 — Complex Commands

**Goal**: CALL, CALL_INDIRECT, RETURN, ENTER, LEAVE migrated. Variadic args, `@ref_cb`, scope fixups working.

| # | Task | File(s) | Dependencies | Acceptance Criteria |
|---|------|---------|--------------|-------------------|
| 4.1 | Add CALL template to `.tg` | `res/templates/codegen_templates.tg` | 1.4 | Uses `variadic`, `@ref_cb`, `@reverse`, `for` loop |
| 4.2 | Add CALL_INDIRECT template to `.tg` | `res/templates/codegen_templates.tg` | 4.1 | Similar to CALL, no `@ref_cb` |
| 4.3 | Add RETURN template to `.tg` | `res/templates/codegen_templates.tg` | 1.4 | Uses `optional` slot |
| 4.4 | Add ENTER template to `.tg` | `res/templates/codegen_templates.tg` | 1.4 | Emits `__ENTER_{scope}` placeholder |
| 4.5 | Add LEAVE template to `.tg` | `res/templates/codegen_templates.tg` | 1.4 | Emits `__LEAVE_{scope}` placeholder |
| 4.6 | Implement `@ref_cb` in `abi_scanner.gd` Pass 1 | `scenes/abi_scanner.gd` | 1.1 | Code blocks registered as reachable in manifest. |
| 4.7 | Implement `@reverse` in Pass 2 (see A.4) | `scenes/tmpl_expand.gd` | 1.4 | Callback handler reverses a bound list. |
| 4.8 | Implement `for/endfor` iteration in Pass 2 | `scenes/tmpl_expand.gd` | 1.4 | Variadic list elements iterated, `element_name` bound per iteration. |
| 4.9 | Implement `optional` slot binding | `scenes/tmpl_expand.gd` | 1.4 | `$cmd.words[1]?` returns null if out of range. `if {val}:` skips block when null. |
| 4.10 | Implement `if/endif` conditional in Pass 2 | `scenes/tmpl_expand.gd` | 1.4 | Conditional emit based on slot presence/truthiness. |
| 4.11 | Add `__ENTER_`/`__LEAVE_` fixup in `asm_emit.gd` | `scenes/asm_emit.gd` | 1.5 | Matches `fixup_enter_leave()` logic exactly. |
| 4.12 | Verify: All call/return test programs match goldens | — | 4.6-4.11 | `printf_test.md`, `return_test.md` golden matches |
| 4.13 | Remove old call/return/enter/leave functions | `scenes/codegen_md.gd:421-474,708-725` | 4.12 | Old 8 functions removed. |

### Sprint 5 — Arrays + Hardening

**Goal**: ALLOC, MOV_ARR migrated. All 13 commands removed from old codegen. Full integration test.

| # | Task | File(s) | Dependencies | Acceptance Criteria |
|---|------|---------|--------------|-------------------|
| 5.1 | Add ALLOC template to `.tg` | `res/templates/codegen_templates.tg` | 1.4 | Uses ADDR_REF (`@{res}`) |
| 5.2 | Add MOV_ARR template to `.tg` | `res/templates/codegen_templates.tg` | 1.4 | Uses `@temp`, variadic, `for` loop |
| 5.3 | Implement `@needs_deref` in `abi_scanner.gd` Pass 1 | `scenes/abi_scanner.gd` | 1.1 | Sets `needs_deref` flag on symbol in manifest. |
| 5.4 | Implement `@needs_deref` in `tmpl_expand.gd` Pass 2 | `scenes/tmpl_expand.gd` | 1.4 | When resolving slot for a `needs_deref` symbol, emits indirect load/store. |
| 5.5 | Full integration test — all test programs through new pipeline | `tests/test_codegen_integration.gd` | 5.1-5.4, 0.9 | Every `.md` → assembly matches golden exactly. |
| 5.6 | Remove ALL old `generate_cmd_*` functions | `scenes/codegen_md.gd` | 5.5 | All 13 functions removed. `codegen_md.gd` retains only `deserialize()`, `allocate_vars()`, `allocate_value()`, globals, and utility functions. |
| 5.7 | Edge case tests: empty code blocks, deeply nested if/while, recursion | `tests/test_codegen_integration.gd` | 5.5 | No crashes. Output is deterministic. |
| 5.8 | Update `codegen_master.gd`: remove old codegen delegation | `scenes/codegen_master.gd` | 5.6 | `migrated_ops` covers ALL 13 commands. Old codegen path is dead code. |
| 5.9 | Performance benchmark: old vs new codegen | — | 5.8 | Document throughput comparison. |

---

## F. Interface Contract — `codegen_master.gd` ↔ Old Codegen

This is the critical interface during migration (Sprints 1-4). Both sides must agree on these contracts.

### F.1 `codegen_master.gd` public API

```gdscript
# scenes/codegen_master.gd
class_name CodegenMaster
extends Node

# Registry of which IR commands are handled by the new pipeline.
# Populated incrementally per sprint.
var migrated_ops: Dictionary = {}  # e.g. {"MOV": true, "OP": true}

# Reference to old codegen (codegen_md.gd instance)
@export var old_codegen: Node

# Reference to cached InflatedGraph
var graph: InflatedGraph

# Main entry point. Called from comp_compile_md.gd compile().
func generate(input: Dictionary) -> CodegenResult:
    # 1. Deserialize IR using old codegen (reuses deserialize logic)
    old_codegen.reset()
    old_codegen.deserialize(input.text)  # or input.filename → read file
    
    # 2. Flatten IR commands into emit-order list
    var flat_cmds = flatten_commands(old_codegen.IR, graph)
    
    # 3. Split migrated vs unmigrated
    var migrated = []
    var unmigrated = []
    for cmd in flat_cmds:
        if cmd.words[0] in migrated_ops:
            migrated.append(cmd)
        else:
            unmigrated.append(cmd)
    
    # 4. New pipeline for migrated commands
    var manifest = ABIScanner.discover(old_codegen.IR, graph)
    StorageAllocator.allocate(manifest, old_codegen.IR)
    var new_result = TemplateExpander.expand(migrated, graph, manifest)
    
    # 5. Old codegen for unmigrated commands
    #    IMPORTANT: Must reset old_codegen state first (see A.6)
    old_codegen.reset()
    old_codegen.IR = old_codegen.IR  # Keep IR data, reset emit state
    var old_text = old_codegen.generate_remaining(unmigrated, manifest)
    
    # 6. Combine assembly + location maps
    return new_result.combine_with(old_text)
```

### F.2 Old codegen interface — `generate_remaining()`

```gdscript
# Added to scenes/codegen_md.gd

# Called by codegen_master.gd during migration for unmigrated commands.
# Accepts a flat list of IR_Cmd objects AND the ABIManifest from Pass 1.
# The manifest contains pre-allocated storage, so this method should
# NOT re-allocate vars — use manifest symbols instead.
func generate_remaining(commands: Array[IR_Cmd], manifest: ABIManifest) -> String:
    # Reset emit state only (keep IR/scopes data)
    assy_block_stack = []
    cur_assy_block = null
    cur_stack_size = 0
    regs_in_use = {}
    referenced_cbs = []
    cur_block = null
    cb_stack = []
    entered_scopes = []
    cur_scope = null
    
    # Use manifest.symbols as all_syms (avoiding duplicate allocation)
    all_syms = {}
    for sym_name in manifest.symbols:
        all_syms[sym_name] = manifest.symbols[sym_name]
    
    # Walk commands, calling generate_cmd() for each
    # Must preserve emit ordering and location map generation
    ...
```

### F.3 Data flow diagram

```
comp_compile_md.gd::compile()
  │
  ▼
codegen_master.gd::generate(input)
  │
  ├─ 1. old_codegen.deserialize(input)      ◄── reuses current codegen_md.gd
  │
  ├─ 2. flatten_commands(IR)                ◄── NEW: walks reachable_cbs
  │
  ├─ 3. split commands by migrated_ops      ◄── simple Dictionary lookup
  │
  ├─ 4. migrated ▸ Pass 1 (abi_scanner)     ◄── NEW: discovers symbols
  │               ▸ StorageAllocator         ◄── NEW: pre-allocates
  │               ▸ Pass 2 (tmpl_expand)     ◄── NEW: emits assembly
  │               ▸ AsmEmitter               ◄── NEW: stringifies
  │               ▸ GlobalsEmitter           ◄── NEW: data section
  │
  └─ 5. unmigrated ▸ old codegen            ◄── existing codegen_md.gd
                     generate_remaining()        with reset state
```

---

## G. Dependency Graph Between Phases

```
  Sprint 0 ──────────────────────────────────────────────────────────
  │  0.1-0.5: Data types (ITG, ABIManifest, CodegenResult)
  │  0.6-0.7: Template parser
  │  0.8:     MOV template
  │  0.9:     Golden files (capture)
  │  0.10-0.11: Tests
  │
  ├──► Sprint 1 ────────────────────────────────────────────────────
  │    │  1.1:  abi_scanner.gd (Pass 1)
  │    │  1.2:  reg_resolve.gd
  │    │  1.3:  stor_alloc.gd
  │    │  1.4:  tmpl_expand.gd (Pass 2, MOV only)
  │    │  1.5:  asm_emit.gd
  │    │  1.6:  globals_emit.gd
  │    │  1.7:  codegen_master.gd
  │    │  1.8-1.9: Wire old + new
  │    │  1.10:  MOV migrated
  │    └──► 1.11: Verify: hello.md ✅
  │
  ├──► Sprint 2 ────────────────────────────────────────────────────
  │    │  2.1:  OP variants in .tg
  │    │  2.2:  @variant in Pass 2
  │    │  2.3-2.4: @temp in Pass 1 + Pass 2
  │    └──► 2.5: Verify: all OP goldens ✅
  │
  ├──► Sprint 3 ────────────────────────────────────────────────────
  │    │  3.1-3.4: IF/ELSE_IF/ELSE/WHILE templates
  │    │  3.5:    ContextScope for %if_block_lbl_end
  │    │  3.6-3.7: @label, @new_imm in Pass 1
  │    │  3.8-3.9: @emit_cb + flatten_commands()
  │    └──► 3.10: Verify: control flow goldens ✅
  │
  ├──► Sprint 4 ────────────────────────────────────────────────────
  │    │  4.1-4.5: CALL/RETURN/ENTER/LEAVE templates
  │    │  4.6-4.10: @ref_cb, @reverse, for/endfor, optional, if/endif
  │    │  4.11:    __ENTER__/__LEAVE__ fixup
  │    └──► 4.12: Verify: call/return goldens ✅
  │
  └──► Sprint 5 ────────────────────────────────────────────────────
       │  5.1-5.2: ALLOC/MOV_ARR templates
       │  5.3-5.4: @needs_deref
       │  5.5:     Full integration test
       │  5.6-5.8: Remove old codegen, clean up
       └──► 5.9: Performance benchmark 📊
```

**Critical path** (must complete sequentially):
- 0.2 → 0.6 → 0.8 → 1.1 → 1.4 → 1.7 → 1.10 (MOV working)
- 1.4 → 2.2 → 2.5 (OP working)
- 3.5 → 3.8 → 3.10 (control flow working)

**Parallelizable** (independent work):
- 0.9 (capture goldens) can start immediately, no dependencies
- 1.2 (reg_resolve) and 1.1 (abi_scanner) are independent
- 1.5 (asm_emit) and 1.4 (tmpl_expand) are independent
- Test files (0.10, 0.11, 1.12) can be written concurrently with implementation

---

## H. Risk Register

| Risk | Likelihood | Impact | Mitigation | Sprint |
|------|-----------|--------|------------|--------|
| `.tres` serialization fails for complex ITG types | Medium | High | Use Dictionary-based serialization (A.1 fix) | 0 |
| Golden files drift due to old codegen changes during migration | Medium | High | Re-capture goldens at start of each sprint. CI enforces match. | 1-5 |
| `if_block_continued` semantics incorrect in flattened commands | Medium | High | Test ALL if/elif/else combinations in Sprint 3. Use test data `elif_test.md` as primary oracle. | 3 |
| Location map mismatch breaks debugger | Medium | High | Add location map to `CodegenResult` in Sprint 0. Verify `loc_map` in Sprint 1 integration test. | 0-1 |
| 8 missing OP variants (AND, OR, B_*, etc.) surface late | Low | Medium | Audit `analyzer_md.gd` op_map + all test files in Sprint 0. Add placeholders to template if unused. | 0 |
