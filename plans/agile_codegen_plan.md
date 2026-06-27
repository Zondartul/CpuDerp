# Agile/Scrum Codegen Plan

**Persona**: Agile/Scrum Advocate  
**Date**: 2026-06-27  
**Context**: Replace the ad-hoc [`codegen_md.gd`](../scenes/codegen_md.gd) (833 lines) with a data-driven, templated codegen for the CpuDerp IR-to-assembly stage. Organized as a Scrum project from sprint zero through delivery.

---

## Table of Contents

1. [Product Vision & Stakeholders](#1-product-vision--stakeholders)
2. [Epic Breakdown & Product Backlog](#2-epic-breakdown--product-backlog)
3. [Definition of Done](#3-definition-of-done)
4. [Sprint Plan](#4-sprint-plan)
5. [Delivery Roadmap](#5-delivery-roadmap)
6. [Velocity & Capacity Planning](#6-velocity--capacity-planning)
7. [Risk & Impediment Backlog](#7-risk--impediment-backlog)
8. [Retrospective Themes & Process Improvement](#8-retrospective-themes--process-improvement)
9. [Technical Architecture (Agile — Just Enough)](#9-technical-architecture-agile--just-enough)

---

## 1. Product Vision & Stakeholders

### Product Vision Statement

> **For** CpuDerp developers and users who need fast, maintainable, and correct assembly output,  
> **the** Data-Driven Codegen Module  
> **is a** template-based IR-to-assembly engine  
> **that** replaces the current ad-hoc 833-line codegen with declarative opcode templates, flat data structures, and a clean pipeline architecture —  
> **unlike** the current [`codegen_md.gd`](../scenes/codegen_md.gd) which embeds logic per IR command in hard-coded `generate_cmd_*` functions,  
> **our product** enables new instruction support via data changes alone, predictable performance, and testable compositions.

### Key Stakeholders

| Stakeholder | Role | Primary Concern |
|---|---|---|
| **Compiler Pipeline Owner** | [`comp_compile_md.gd`](../scenes/comp_compile_md.gd) consumer | Correct assembly output with zero regressions across the test suite |
| **ZVM Language Designer** | [`lang_zvm.gd`](../scenes/lang_zvm.gd) maintainer | New IR ops must be easy to add without touching codegen logic |
| **Performance Tester** | CpuDerp benchmarking | Predictable emit throughput; no O(n) string scanning in hot path |
| **Debugger / IDE User** | [`debug_panel.gd`](../scenes/debug_panel.gd) user | Source location maps must remain accurate after refactor |
| **Scrum Team** | 2–3 developers | Clear backlog, estimated stories, no more than 2-week sprints |

---

## 2. Epic Breakdown & Product Backlog

The backlog is structured into **5 epics**. Each epic contains user stories prioritized by business value and technical dependency.

### Epic A — Foundation & Inspection (Sprint 0–1)

> *"As a team, we need safe refactoring ground before we change a single line of codegen."*

| ID | Story | Story Points | Priority | Acceptance Criteria |
|---|---|---|---|---|
| A-1 | **Characterize the current codegen** — Add comprehensive assertions + logging to [`codegen_md.gd`](../scenes/codegen_md.gd) to capture all IR commands and emitted patterns across the test suite | 5 | P0 (Must) | CI runs on all `res/data/*.md` files; a `codegen_characterization.json` artifact is produced |
| A-2 | **Define the Template Schema** — Write a formal schema (in a README or JSON Schema) for what a "template" looks like, including placeholders, conditionals, and storage references | 3 | P0 (Must) | Schema document reviewed and approved by team; stored at [`docs/template_schema.md`](docs/template_schema.md) |
| A-3 | **Write a Test Oracle** — Create a golden-file test harness that runs current codegen, captures assembly output for each test program, and commits it as "expected" output | 8 | P0 (Must) | `tests/test_codegen_oracle.gd` exists; all golden files pass on CI |
| A-4 | **Agree on Definition of Done** — Team charter: code review required, test coverage ≥ 80% for new code, golden file diff must be zero | 1 | P0 (Must) | DoD checklist posted in repo `CONTRIBUTING.md` |

### Epic B — Template Engine Core (Sprints 1–2)

> *"As a compiler pipeline owner, I want to define opcode expansion as data so that adding a new instruction does not require writing a new `generate_cmd_*` function."*

| ID | Story | Story Points | Priority | Acceptance Criteria |
|---|---|---|---|---|
| B-1 | **Template Parser** — Implement a parser that reads YAML/JSON template definitions and compiles them into an internal IR of emit instructions | 8 | P0 (Must) | Given `{"ADD": "add %a, %b;"}`, the parser produces an AST with nodes `[Literal("add "), Placeholder("a"), Literal(", "), Placeholder("b"), Literal(";")]` |
| B-2 | **Placeholder Resolution** — Resolve `$`, `@`, `^` placeholders against the symbol table (load value, address value, store value) using the existing [`load_value`](../scenes/codegen_md.gd:551), [`address_value`](../scenes/codegen_md.gd:577), [`store_val`](../scenes/codegen_md.gd:612) semantics | 5 | P0 (Must) | All current [`op_map`](../scenes/codegen_md.gd:12) entries work identically through the template engine |
| B-3 | **Conditional Template Support** — Templates with optional segments (e.g., `%b` only for binary ops) controlled by template parameters | 5 | P1 (Should) | The INC/DEC mono-op case (see [`generate_cmd_op`](../scenes/codegen_md.gd:294):307) is expressed as a conditional template |
| B-4 | **Operator Template Registry** — Central registry mapping IR command names (`MOV`, `OP`, `CALL`, etc.) to their template definitions, loadable from an external data file | 3 | P0 (Must) | `var template_registry = preload("res://data/opcode_templates.tres")` loads and validates all templates at startup |

### Epic C — Emit Engine Refactor (Sprints 2–3)

> *"As a performance tester, I want the emit pipeline to use flat data structures so that codegen throughput is predictable and string operations are minimized."*

| ID | Story | Story Points | Priority | Acceptance Criteria |
|---|---|---|---|---|
| C-1 | **Flat Symbol Table** — Replace the Dictionary-of-Dictionaries symbol table [`all_syms = {}`](../scenes/codegen_md.gd:28) with a packed array structure: parallel arrays for `ir_name`, `val_type`, `storage_type`, `storage_pos` | 8 | P0 (Must) | Memory allocation reduced; symbol lookup is O(1) index into flat arrays |
| C-2 | **Register Allocator as Bitfield** — Replace [`regs_in_use = {}`](../scenes/codegen_md.gd:32) with a 4-bit integer bitmask | 2 | P1 (Should) | `alloc_register()` and `free_val()` operate on bitwise ops; zero Dictionary overhead |
| C-3 | **Pre-compiled Template Bytecode** — Templates are compiled to a sequence of emit opcodes (LOAD_ARG, EMIT_LITERAL, LOAD_SYM, STORE_SYM) executed by a lightweight interpreter | 8 | P1 (Should) | No string scanning in hot emit path; [`find_reference`](../scenes/codegen_md.gd:542) eliminated |
| C-4 | **Buffered Assembly Output** — Replace string concatenation in [`emit_raw`](../scenes/codegen_md.gd:606) with a `PackedByteArray` or `PackedStringArray` that is joined once at the end | 5 | P1 (Should) | Assembly output uses `"\n".join(buffer)` instead of `+=` on every emit call |

### Epic D — IR Command Migration (Sprints 3–4)

> *"As a ZVM language designer, I can add a new IR command by adding a template entry — no GDScript changes needed."*

| ID | Story | Story Points | Priority | Acceptance Criteria |
|---|---|---|---|---|
| D-1 | **Migrate Arithmetic/Comparison Ops** — All entries in [`op_map`](../scenes/codegen_md.gd:12) are migrated from hard-coded strings to template definitions | 5 | P0 (Must) | Golden files identical for all test programs with arithmetic |
| D-2 | **Migrate Control Flow (`IF`, `ELSE_IF`, `ELSE`, `WHILE`)** — The label-generation + conditional branch patterns in [`generate_cmd_if`](../scenes/codegen_md.gd:349)–[`generate_cmd_while`](../scenes/codegen_md.gd:401) are expressed as multi-step templates with label allocation | 8 | P0 (Must) | Golden files identical for all test programs with conditionals and loops |
| D-3 | **Migrate Call/Return (`CALL`, `CALL_INDIRECT`, `RETURN`)** — Stack frame management and call sequences in [`generate_cmd_call`](../scenes/codegen_md.gd:421)–[`generate_cmd_return`](../scenes/codegen_md.gd:708) are data-driven | 5 | P0 (Must) | Golden files identical for all test programs with function calls |
| D-4 | **Migrate Array Operations (`ALLOC`, `MOV_ARR`)** — Array allocation and initialization in [`generate_cmd_alloc`](../scenes/codegen_md.gd:726)–[`generate_cmd_mov_arr`](../scenes/codegen_md.gd:734) use templates | 5 | P1 (Should) | Golden files identical for all array test programs |
| D-5 | **Migrate Scope/Enter/Leave** — The `ENTER`/`LEAVE` commands and [`fixup_enter_leave`](../scenes/codegen_md.gd:754) are template-driven | 3 | P0 (Must) | Golden files identical for all test programs with nested scopes |
| D-6 | **External Template File** — All templates live in `res/data/opcode_templates.yaml` instead of inside `op_map` constant | 3 | P1 (Should) | Adding `NEG` requires only a YAML entry, no GDScript |

### Epic E — Validation & Hardening (Sprint 4–5)

> *"As the compiler pipeline consumer, I want zero regressions in production so that I can ship with confidence."*

| ID | Story | Story Points | Priority | Acceptance Criteria |
|---|---|---|---|---|
| E-1 | **Golden File Regression Suite** — Automate comparison of new codegen output against golden files for every test program in `res/data/` | 5 | P0 (Must) | CI runs `test_codegen_oracle.gd` and fails on any diff |
| E-2 | **Stress Test: Large Programs** — Generate a synthetic 10,000-line IR program and measure codegen throughput; establish performance baseline | 3 | P1 (Should) | Throughput is within 2× of current codegen or better |
| E-3 | **Error Recovery Testing** — Inject malformed templates and IR commands; verify the error reporter produces helpful diagnostics | 3 | P2 (Could) | Error messages include template name, line number, and offending symbol |
| E-4 | **Edge Case: Empty Code Blocks** — Test programs with zero IR commands in a code block produce valid assembly | 2 | P1 (Should) | Empty `cb.code` produces `""` or valid no-op |
| E-5 | **Edge Case: Maximum Register Pressure** — Test programs that force spilling (all 4 registers in use) exercise the spill-to-stack path in [`alloc_temporary`](../scenes/codegen_md.gd:594) | 3 | P1 (Should) | Golden file with register spilling matches expected assembly |
| E-6 | **Performance Benchmark CI Job** — Track codegen wall-clock time and memory allocation per test program; alert on regression >10% | 3 | P2 (Could) | `benchmarks/codegen_benchmark.gd` runs on every PR |

---

## 3. Definition of Done

Every story must satisfy **all** of the following before it can be moved to "Done":

1. ✅ **Code Review** — Pull request approved by at least one other team member
2. ✅ **Golden File Pass** — `test_codegen_oracle.gd` reports zero diffs against committed golden files
3. ✅ **Unit Tests** — New code has ≥80% line coverage (measured by GDScript coverage tool)
4. ✅ **No Linter Warnings** — `gdscript-linter` passes with zero errors on new/changed files
5. ✅ **Documentation Updated** — `docs/template_schema.md` reflects any schema changes
6. ✅ **Backward Compatible** — Existing consumer files ([`comp_compile_md.gd`](../scenes/comp_compile_md.gd), [`debug_panel.gd`](../scenes/debug_panel.gd)) require zero changes
7. ✅ **Definition of Done Checkbox** — Each story's acceptance criteria are individually verified in the PR description

---

## 4. Sprint Plan

### Velocity Assumption

- Team size: **2 developers**
- Sprint length: **2 weeks**
- Estimated velocity: **15–20 story points per sprint** (based on team capacity, accounting for meetings, code review, and spike time)

---

### Sprint 0 — "Inspect & Adapt" (Week 1–2)

**Goal**: Characterize the current system, build the safety net, and agree on the plan.

| Story | Points | Owner | Dependencies |
|---|---|---|---|
| A-1 Characterize current codegen | 5 | Dev A | None |
| A-2 Define Template Schema | 3 | Dev B | A-1 (needs full op list) |
| A-4 Definition of Done | 1 | Team | None |
| **Sprint 0 subtotal** | **9** | | |

**Sprint Goal**: By end of Sprint 0, we have a test oracle, a documented schema, and full characterization of the current codegen behavior. No production code is changed.

**Sprint 0 Deliverables**:
- [`tests/test_codegen_oracle.gd`](tests/test_codegen_oracle.gd) — golden file test harness
- `res/test_data/golden/` — committed golden assembly outputs
- [`docs/template_schema.md`](docs/template_schema.md) — template format specification
- `codegen_characterization.json` — trace of every IR command + emit pattern

**Sprint 0 Ceremonies**:
- **Sprint Planning** — 2h: Break down A-1/A-2 into tasks, assign pairs
- **Daily Stand-up** — 15min: What did I do? What will I do? Blockers?
- **Sprint Review** — 1h: Demo golden file harness and template schema
- **Retrospective** — 1h: How did Sprint 0 go? Process adjustments?

---

### Sprint 1 — "Template Engine Core" (Week 3–4)

**Goal**: Build and unit-test the template parser and placeholder resolver.

| Story | Points | Owner | Dependencies |
|---|---|---|---|
| A-3 Write a Test Oracle | 8 | Dev B | A-1 (complete characterization) |
| B-1 Template Parser | 8 | Dev A | A-2 (schema agreed) |
| B-2 Placeholder Resolution | 5 | Dev A | B-1 (parser exists) |
| **Sprint 1 subtotal** | **21** | | |

**Sprint Goal**: The template parser can read YAML definitions and produce a compiled template AST. Placeholder resolution works for `$` (load), `@` (address), `^` (store) markers. Unit tests cover all template structures.

**Risk**: If B-1 + B-2 exceed 13 points, defer B-4 (Template Registry) to Sprint 2.

---

### Sprint 2 — "Emit Engine + Registry" (Week 5–6)

**Goal**: Wire the template engine into the emit pipeline; replace `op_map`.

| Story | Points | Owner | Dependencies |
|---|---|---|---|
| B-4 Operator Template Registry | 3 | Dev A | B-1, B-2 |
| C-1 Flat Symbol Table | 8 | Dev B | A-3 (golden files to verify) |
| C-2 Register Allocator as Bitfield | 2 | Dev B | C-1 |
| **Sprint 2 subtotal** | **13** | | |

**Sprint Goal**: Template registry loads from data file. Symbol table is flat arrays. Golden files still pass. If we have capacity, begin C-3 (pre-compiled template bytecode).

---

### Sprint 3 — "Migration Wave 1: Ops & Control Flow" (Week 7–8)

**Goal**: Migrate arithmetic ops and control flow from hard-coded functions to template-driven codegen.

| Story | Points | Owner | Dependencies |
|---|---|---|---|
| D-1 Migrate Arithmetic/Comparison Ops | 5 | Dev A | B-4 (registry), A-3 (golden oracle) |
| D-2 Migrate Control Flow | 8 | Dev B | D-1 |
| C-3 Pre-compiled Template Bytecode | 8 | Dev A | B-1, D-1 (real templates to compile) |
| **Sprint 3 subtotal** | **21** | | |

**Sprint Goal**: All arithmetic, comparison, `IF`/`ELSE`/`WHILE` commands are data-driven. Template bytecode interpreter is operational. Golden files remain identical.

**Risk**: D-2 (control flow) is complex due to label allocation. If blocked, swap to C-4 (buffered output) which is lower risk.

---

### Sprint 4 — "Migration Wave 2: Calls, Arrays, Scope" (Week 9–10)

**Goal**: Complete migration of all remaining IR commands.

| Story | Points | Owner | Dependencies |
|---|---|---|---|
| D-3 Migrate Call/Return | 5 | Dev A | D-1 (ops stable) |
| D-5 Migrate Scope/Enter/Leave | 3 | Dev A | D-3 (stack frame concept shared) |
| D-4 Migrate Array Operations | 5 | Dev B | D-1 |
| C-4 Buffered Assembly Output | 5 | Dev B | D-2, D-3 (emit path stable) |
| **Sprint 4 subtotal** | **18** | | |

**Sprint Goal**: Every IR command in the current test suite is handled by templates. String concatenation emit is replaced with buffered output. Golden files pass.

---

### Sprint 5 — "Hardening & Ship" (Week 11–12)

**Goal**: Validation, edge cases, performance benchmarks, and final release.

| Story | Points | Owner | Dependencies |
|---|---|---|---|
| D-6 External Template File | 3 | Dev A | D-1–D-5 (all templates migrated) |
| E-1 Golden File Regression Suite | 5 | Dev B | A-3 (oracle exists) |
| E-2 Stress Test Large Programs | 3 | Dev B | C-4 (buffered output) |
| E-4 Edge Case: Empty Code Blocks | 2 | Dev A | D-1–D-5 |
| E-5 Edge Case: Register Pressure | 3 | Dev A | C-2 (register bitfield) |
| E-3 Error Recovery Testing | 3 | Dev B | B-1 (parser error handling) |
| E-6 Performance Benchmark CI Job | 3 | Dev A | C-3, C-4 |
| **Sprint 5 subtotal** | **22** | | |

**Sprint Goal**: Production-ready codegen with zero regressions, documented edge cases, and CI performance monitoring.

**Sprint 5 Deliverables**:
- All templates in `res/data/opcode_templates.yaml`
- `test_codegen_oracle.gd` passes on CI
- Performance benchmark report
- Updated `docs/template_schema.md` with final schema

---

### Backlog Items (Future Sprints)

| ID | Story | Points | Priority | Notes |
|---|---|---|---|---|
| F-1 | **Template Editor UI** — In-editor GUI for editing opcode templates | 8 | P3 (Won't) | Deferred; not critical for MVP |
| F-2 | **Pluggable Backend Targets** — Template engine supports x86, ARM, or custom backends | 13 | P3 (Won't) | Requires architecture spike first |
| F-3 | **Hot-Reload Templates** — Templates can be reloaded at runtime without recompilation | 5 | P2 (Could) | Useful for rapid iteration |
| F-4 | **Visual Template Debugger** — Step-through template expansion in debug panel | 8 | P3 (Won't) | Nice-to-have visualization |

---

## 5. Delivery Roadmap

```
Sprint 0    Sprint 1     Sprint 2     Sprint 3     Sprint 4     Sprint 5
 (Week 1-2)  (Week 3-4)   (Week 5-6)   (Week 7-8)   (Week 9-10)  (Week 11-12)
│            │             │             │             │             │
├ A-1 ───────┤             │             │             │             │
├ A-2 ───────┤             │             │             │             │
├ A-4 ───────┤             │             │             │             │
│            ├ A-3 ───────────────────────────────────────────── E-1 ┤
│            ├ B-1 ───────────────────────────────────────────── D-6 ┤
│            ├ B-2 ─────────┤             │             │             │
│                          ├ B-4 ────────┤             │             │
│                          ├ C-1 ────────┤             │             │
│                          ├ C-2 ────────┤             │             │
│                                        ├ D-1 ────────┤             │
│                                        ├ D-2 ────────┤             │
│                                        ├ C-3 ────────┤             │
│                                                      ├ D-3 ────────┤
│                                                      ├ D-4 ────────┤
│                                                      ├ D-5 ────────┤
│                                                      ├ C-4 ────────┤
│                                                                    ├ E-2
│                                                                    ├ E-3
│                                                                    ├ E-4
│                                                                    ├ E-5
│                                                                    ├ E-6
│                                                                    │
└────────────┴──────────────┴──────────────┴──────────────┴──────────────┘
         ▲               ▲               ▲               ▲               ▲
         │               │               │               │               │
    Sprint Review    Sprint Review    Sprint Review    Sprint Review    Release
    + Retro          + Retro          + Retro          + Retro          Party!
```

### Key Milestones

| Milestone | Sprint | What "Done" Looks Like |
|---|---|---|
| **Safety Net** | Sprint 0 | Golden file oracle + characterization data captured |
| **Template Engine MVP** | Sprint 2 | Template parser resolves placeholders; flat symbol table live |
| **Migration Complete** | Sprint 4 | All IR commands data-driven; old `generate_cmd_*` functions deprecated |
| **Production Release** | Sprint 5 | Zero regressions, performance benchmarked, external template file shipped |

---

## 6. Velocity & Capacity Planning

### Team Capacity

| Role | Person | Availability | Notes |
|---|---|---|---|
| Developer A (lead) | — | 80% (6d/sprint) | Template engine, emit pipeline, symbol table |
| Developer B | — | 80% (6d/sprint) | Test oracle, migrations, edge cases |

### Velocity Tracking

| Sprint | Planned Points | Actual Points | Velocity | Notes |
|---|---|---|---|---|
| 0 | 9 | — | — | *First sprint: estimate baseline* |
| 1 | 13–21 | — | — | *Adjust after Retrospective* |
| 2 | 13 | — | — | |
| 3 | 21 | — | — | |
| 4 | 18 | — | — | |
| 5 | 22 | — | — | |

**Rule of Thumb**: If a story is >8 points, break it down further in Sprint Planning. If velocity drops below 12 for two consecutive sprints, reduce scope (defer low-priority stories).

---

## 7. Risk & Impediment Backlog

| Risk | Likelihood | Impact | Mitigation | Owner |
|---|---|---|---|---|
| **Golden files drift during migration** | High | Medium | Commit golden files per Sprint Review; diff check in CI | Dev B |
| **Template parser complexity underestimated** | Medium | High | Spike in Sprint 0 (B-1); limit template syntax to MVP | Dev A |
| **`find_reference` string scanning not fully replaceable** | Medium | Medium | Keep hot-path scan; optimize with pre-compiled bytecode later (C-3) | Dev A |
| **Regressions in debug location maps** | Medium | High | Add `mark_loc_begin`/`mark_loc_end` assertions to golden oracle | Dev B |
| **Team member unavailable mid-sprint** | Low | High | Cross-train on template engine and oracle; pair program on critical paths | Team |

---

## 8. Retrospective Themes & Process Improvement

### Sprint 0 Retrospective (Template)

1. **What went well?**
   - Golden file oracle gives us confidence
   - Team agreed on Definition of Done quickly

2. **What could be improved?**
   - Story point estimation accuracy
   - Time spent in daily stand-ups

3. **Action Items:**
   - Experiment with Planning Poker for future sprints
   - Strict 15-min timebox for stand-ups

### Ongoing Process Improvements

- **Burndown Chart** — Track remaining points per sprint in a visible location
- **Pair Programming** — For complex stories (D-2 control flow, B-1 template parser), pair for at least 50% of implementation
- **Spike Time** — Reserve 10% of each sprint for technical spikes (new template features, performance profiling)
- **Sprint Review Demo** — Always run `test_codegen_oracle.gd` live to show zero regressions

---

## 9. Technical Architecture (Agile — Just Enough)

This section provides **just enough** architecture to guide implementation without over-engineering before validated learning.

### High-Level Pipeline

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐     ┌───────────────┐
│  IR (YAML)   │────▶│  Deserializer    │────▶│  Symbol Table    │────▶│  Emit Engine  │────▶ Assembly
│              │     │  (codegen_md.gd   │     │  (flat arrays)   │     │  (template    │      Text
│  res/data/   │     │   deserialize()) │     │  + all_syms       │     │   bytecode    │
│  *.md files  │     └──────────────────┘     └──────────────────┘     │   interpreter) │
                                                                       └───────────────┘
                                                                                │
┌──────────────────┐                                                           │
│ Template Registry│────▶ Compiled templates (AST or bytecode) ────────────────┘
│ (YAML data file) │         ↑
└──────────────────┘         │
                    ┌────────────────┐
                    │ Template Parser│
                    │ (B-1)          │
                    └────────────────┘
```

### Template Format (MVP)

```yaml
# res/data/opcode_templates.yaml
templates:
  ADD:
    args: [a, b]
    template: "add $a, $b;"
    size: 8          # bytes per instruction

  GREATER:
    args: [a, b]
    template: >
      cmp $a, $b;
      mov ^a, CTRL;
      band ^a, CMP_G;
    size: 32

  IF:
    args: [cond, res, block]
    template: >
      $cond
      cmp $res, $imm_0;
      jz $lbl_else;
      $block
      jmp $lbl_end;
    dynamic_labels: [lbl_else, lbl_end]
    auto_imm: [imm_0: 0]

  CALL:
    args: [fun, args..., res]
    template: >
      push $args;
      call @fun;
      add ESP, {args_count * 4};
      mov ^res, EAX;
    auto_stack: {push: args, pop: args_count}
```

### Key Interfaces

```gdscript
# Template.gd — compiled template object
class_name Template
var name: String
var arg_names: PackedStringArray
var compiled: Array[TemplateOp]  # bytecode for emit interpreter
var static_size: int              # bytes this opcode contributes

# TemplateOp.gd — single emit instruction
enum OpType { EMIT_LITERAL, LOAD_ARG, LOAD_SYM, STORE_SYM, ADDR_SYM, ALLOC_LABEL, EMIT_LABEL, AUTO_IMM }
class_name TemplateOp
var op_type: OpType
var payload: String  # literal text or placeholder name

# TemplateRegistry.gd
class_name TemplateRegistry
var templates: Dictionary  # String → Template

func load_from_yaml(path: String) -> void ...
func get_template(name: String) -> Template ...
```

### Migration Strategy

1. **Parallel Implementation** — New template engine lives in `scenes/codegen_templated.gd` alongside existing `scenes/codegen_md.gd`. Both are instantiated in test suite.
2. **Output Comparison** — `test_codegen_oracle.gd` runs both codegens and diffs output.
3. **Feature Flag** — A constant `USE_TEMPLATE_ENGINE` controls which codegen is active in `comp_compile_md.gd`.
4. **Cut-Over** — When template engine passes all golden files for 3 consecutive sprints, flip the flag to default `true`. Remove old codegen in Sprint 6.

### Directory Layout (After Implementation)

```
res/
  data/
    opcode_templates.yaml          # Template definitions (D-6)
scenes/
  codegen_md.gd                    # OLD — kept for reference, then deleted
  codegen_templated.gd             # NEW — template engine orchestrator
  codegen/
    template_parser.gd             # B-1 — YAML → CompiledTemplate
    template_registry.gd           # B-4 — registry + validation
    template_op.gd                 # TemplateOp enum + class
    template.gd                    # Compiled template object
    symbol_table_flat.gd           # C-1 — flat array symbol table
    emit_interpreter.gd            # C-3 — template bytecode interpreter
    emit_buffer.gd                 # C-4 — PackedStringArray output buffer
    register_allocator.gd          # C-2 — bitfield register allocator
tests/
    test_codegen_oracle.gd         # A-3 / E-1 — golden file test
    test_template_parser.gd        # B-1 unit tests
    test_placeholder_resolution.gd # B-2 unit tests
    test_emit_interpreter.gd       # C-3 unit tests
    test_edge_cases.gd             # E-4, E-5
benchmarks/
    codegen_benchmark.gd           # E-6
docs/
    template_schema.md             # A-2 — template format docs
```
