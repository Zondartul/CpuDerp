# Waterfall / Big Design Up Front (BDUF) Codegen Plan

**Persona**: Waterfall / BDUF Advocate  
**Date**: 2026-06-27  
**Context**: Replace the ad-hoc [`codegen_md.gd`](../scenes/codegen_md.gd) (833 lines) with a data-driven, templated codegen for the CpuDerp IR-to-assembly stage. Phases are strictly sequential with documented sign-offs before proceeding.

> **Core Principle**: *"Measure twice, cut once."* The cost of changing requirements increases exponentially over time. Every detail is specified and frozen before a single line of implementation code is written.

---

## Table of Contents

1. [Phase 1: Requirements Specification](#phase-1-requirements-specification)
    - 1.1 System Overview
    - 1.2 Functional Requirements
    - 1.3 Non-Functional Requirements
    - 1.4 Interface Requirements
    - 1.5 Constraints & Assumptions
    - 1.6 Requirements Traceability Matrix
    - 1.7 Sign-Off
2. [Phase 2: Architecture & Design Specification](#phase-2-architecture--design-specification)
    - 2.1 Architectural Overview
    - 2.2 Decomposition View
    - 2.3 Component Specifications
    - 2.4 Data Dictionary & Schema
    - 2.5 Template Engine Design
    - 2.6 Template Catalog (Complete)
    - 2.7 Pipeline Design
    - 2.8 Error Handling Strategy
    - 2.9 Design Review Checklist
    - 2.10 Sign-Off
3. [Phase 3: Implementation Specification](#phase-3-implementation-specification)
    - 3.1 File Manifest
    - 3.2 Implementation Order
    - 3.3 Coding Standards
    - 3.4 Unit Implementation Specifications
    - 3.5 Integration Points
    - 3.6 Sign-Off
4. [Phase 4: Verification Plan](#phase-4-verification-plan)
    - 4.1 Test Strategy
    - 4.2 Test Case Catalog
    - 4.3 Acceptance Criteria
    - 4.4 Regression Suite
    - 4.5 Performance Benchmarks
    - 4.6 Sign-Off
5. [Phase 5: Maintenance Plan](#phase-5-maintenance-plan)
    - 5.1 Change Control Board
    - 5.2 Template Lifecycle
    - 5.3 Versioning Strategy
    - 5.4 Support Procedures
6. [Appendices](#appendices)
    - A. Glossary
    - B. References
    - C. Risk Register

---

## Phase 1: Requirements Specification

**Document Status**: DRAFT — not yet signed off  
**Estimated effort to complete**: 40 person-hours  
**Deliverable**: Signed-off Requirements Specification (this section)

---

### 1.1 System Overview

The existing codegen subsystem ([`codegen_md.gd`](../scenes/codegen_md.gd)) transforms IR (Intermediate Representation) data structures into ZVM assembly text. It is consumed by the assembler ([`comp_asm_zd.gd`](../scenes/comp_asm_zd.gd)) which compiles assembly into machine code for the ZVM CPU.

**Current architecture problems identified:**

1. **Hard-coded opcode expansion** — The `op_map` dictionary and `generate_cmd_op` function at [`codegen_md.gd:294-325`](../scenes/codegen_md.gd:294) encode per-operator expansion logic in imperative code. Adding a new operator requires modifying both `op_map` and the `generate_cmd_op` function body.
2. **Per-IR-command dispatch** — The `generate_cmd` function at [`codegen_md.gd:266-283`](../scenes/codegen_md.gd:266) dispatches via a 12-way `match` block. Each branch has a dedicated `generate_cmd_*` function that is imperative and non-parameterizable.
3. **Interleaved concern: register allocation** — Register allocation logic is embedded within the `emit` function at [`codegen_md.gd:474-533`](../scenes/codegen_md.gd:474) via `alloc_register` and `free_val` calls, making it impossible to swap allocation strategies without rewriting the emit pipeline.
4. **String-level template processing** — The `emit` function uses runtime `find_reference` calls (lines 542–548) to locate `$`, `@`, and `^` markers and perform string substitution at emit time, incurring O(n) scans per emitted instruction.

**Target system**: A data-driven codegen where:
- All IR-to-assembly mappings are expressed as **parameterized templates** stored in data files
- Per-IR-command dispatch is driven by a **template registry** rather than a match block
- Register allocation is a **pluggable strategy** separated from template expansion
- Template expansion is a **single pass** with no runtime string scanning

---

### 1.2 Functional Requirements

#### FR-01: Template-Driven Opcode Expansion
| ID | Description | Priority | Source |
|---|---|---|---|
| FR-01a | The system SHALL expand IR `OP` commands into assembly using named templates loaded from a data file | 1 (Critical) | [`op_map` at codegen_md.gd:12-25](../scenes/codegen_md.gd:12) |
| FR-01b | Each template SHALL support positional parameters (`%1`, `%2`, ...) and named parameters (`%dest`, `%src`, `%res`) | 1 (Critical) | Novel requirement |
| FR-01c | The system SHALL support template inheritance, where one template can extend another with additional assembly lines | 2 (Major) | Novel requirement |
| FR-01d | The system SHALL support conditional expansion within templates (e.g., `%if imm %then ... %else ... %end`) | 3 (Minor) | Novel requirement |
| FR-01e | Template files SHALL be loadable at startup or reloadable at runtime via a debug command | 2 (Major) | Novel requirement |

#### FR-02: Data-Driven IR Command Dispatch
| ID | Description | Priority | Source |
|---|---|---|---|
| FR-02a | The system SHALL dispatch IR commands by matching `cmd.words[0]` against a registry of command descriptors loaded from a data file | 1 (Critical) | [`generate_cmd` at codegen_md.gd:266-283](../scenes/codegen_md.gd:266) |
| FR-02b | Each command descriptor SHALL specify: command name, number of operands, operand types, and the template(s) to apply | 1 (Critical) | Novel requirement |
| FR-02c | The system SHALL support multi-phase command expansion (e.g., PRE, MAIN, POST phases) for commands requiring setup/teardown | 2 (Major) | [`generate_cmd_if` at codegen_md.gd:349-370](../scenes/codegen_md.gd:349) |

#### FR-03: Variable & Storage Management
| ID | Description | Priority | Source |
|---|---|---|---|
| FR-03a | The system SHALL allocate storage (global, stack, register) for IR values using a pluggable allocation strategy | 1 (Critical) | [`allocate_value` at codegen_md.gd:667-698](../scenes/codegen_md.gd:667) |
| FR-03b | The system SHALL support at least three storage backends: global (label-based), stack (EBP-relative), and register (EAX/EBX/ECX/EDX) | 1 (Critical) | [`load_value` at codegen_md.gd:551-574](../scenes/codegen_md.gd:551) |
| FR-03c | The system SHALL separate register allocation from template expansion via a `RegisterAllocator` interface | 2 (Major) | [`alloc_register` at codegen_md.gd:634-640](../scenes/codegen_md.gd:634) |
| FR-03d | The system SHALL support a "spill-to-stack" policy when registers are exhausted | 2 (Major) | [`alloc_temporary` at codegen_md.gd:594-604](../scenes/codegen_md.gd:594) |

#### FR-04: Control Flow Constructs
| ID | Description | Priority | Source |
|---|---|---|---|
| FR-04a | The system SHALL generate assembly for IR `IF`/`ELSE_IF`/`ELSE` commands using label-based control flow | 1 (Critical) | [`generate_cmd_if` at codegen_md.gd:349-370](../scenes/codegen_md.gd:349) |
| FR-04b | The system SHALL generate assembly for IR `WHILE` commands with loop labels | 1 (Critical) | [`generate_cmd_while` at codegen_md.gd:401-419](../scenes/codegen_md.gd:401) |
| FR-04c | The system SHALL generate assembly for IR `CALL`/`CALL_INDIRECT` commands with stack frame management | 1 (Critical) | [`generate_cmd_call` at codegen_md.gd:421-449](../scenes/codegen_md.gd:421) |
| FR-04d | The system SHALL generate assembly for IR `ENTER`/`LEAVE`/`RETURN` commands with scope-based fixup | 1 (Critical) | [`generate_cmd_enter` at codegen_md.gd:716-724](../scenes/codegen_md.gd:716) |

#### FR-05: Location Mapping
| ID | Description | Priority | Source |
|---|---|---|---|
| FR-05a | The system SHALL maintain a source-location-to-assembly-byte-offset map for debugging | 1 (Critical) | [`mark_loc_begin`/`mark_loc_end` at codegen_md.gd:790-798](../scenes/codegen_md.gd:790) |
| FR-05b | The system SHALL translate sub-block location maps into the parent block's address space via offset addition | 1 (Critical) | [`translate_ab_locations` at codegen_md.gd:816-824](../scenes/codegen_md.gd:816) |

#### FR-06: Template Metadata
| ID | Description | Priority | Source |
|---|---|---|---|
| FR-06a | Each template SHALL declare its assembly size (in bytes) to enable accurate location mapping | 1 (Critical) | `wp_diff` parameter in [`emit` at codegen_md.gd:474](../scenes/codegen_md.gd:474) |
| FR-06b | Templates SHALL support debug annotations that can be optionally emitted as assembly comments | 3 (Minor) | `ADD_DEBUG_TRACE` at codegen_md.gd:7 |

---

### 1.3 Non-Functional Requirements

| ID | Description | Measurable Target | Priority |
|---|---|---|---|
| NFR-01 | Template expansion speed: the new codegen SHALL NOT be slower than the current `generate_cmd_op` + `emit` pipeline | ≤ current 833-line implementation on a 10k-op benchmark | 1 (Critical) |
| NFR-02 | Memory footprint: the template registry SHALL NOT exceed 256 KB at runtime | ≤ 256 KB | 2 (Major) |
| NFR-03 | Startup time: template loading SHALL complete within 50 ms | ≤ 50 ms | 2 (Major) |
| NFR-04 | Maintainability: adding a new IR command SHALL require changes to data files only (0 lines of GDScript changed) | 0 GDScript lines for new simple commands | 1 (Critical) |
| NFR-05 | Backward compatibility: the generated assembly SHALL be byte-identical to the current codegen for all existing test IR inputs | 100% identical output | 1 (Critical) |
| NFR-06 | Error reporting: template syntax errors SHALL produce a human-readable message with file, line, and column | Parse error → file:line:col + description | 2 (Major) |

---

### 1.4 Interface Requirements

#### IR-01: Input Interface
The codegen SHALL accept an IR dictionary matching the structure produced by [`ir_md.gd`](../scenes/ir_md.gd):
```gdscript
# Shape of the input IR dictionary
{
    "code_blocks": {
        "<ir_name>": CodeBlock { code: Array[IR_Cmd], lbl_from: String, lbl_to: String },
        ...
    },
    "scopes": {
        "<ir_name>": {
            "vars": Array[Dictionary],
            "funcs": Array[Dictionary],
            "user_name": String,
            "ir_name": String
        },
        ...
    }
}
```

Where each `IR_Cmd` has:
```gdscript
IR_Cmd {
    words: Array[String],    # [command_name, arg1, arg2, ..., location_string]
    loc: LocationRange       # source location for debugging
}
```

#### IR-02: Output Interface
The codegen SHALL output assembly text compatible with [`comp_asm_zd.gd`](../scenes/comp_asm_zd.gd) assembly format:
- Lines ending with `;\n`
- Labels: `:<label_name>:\n`
- Registers: `EAX`, `EBX`, `ECX`, `EDX`, `ESP`, `EBP`, `IP`, `CTRL`
- Memory: `*<label>`, `EBP[<offset>]`
- Instructions: `<opcode> <arg1>, <arg2>;`

#### IR-03: Template File Format
Templates SHALL be stored in YAML files (parsed via [`uYaml.gd`](../scenes/uYaml.gd)) with the following schema:
```yaml
# template_group.yaml
version: "1.0"
templates:
  add:
    description: "ADD instruction"
    params: ["dest", "src"]
    assembly: "add %dest, %src;\n"
    size: 8
  cmp_cond:
    description: "Compare and set condition flag"
    params: ["a", "b", "flag"]
    assembly: |
      cmp %a, %b;
      mov %a, CTRL;
      band %a, CMP_%flag;
    size: 24
```

---

### 1.5 Constraints & Assumptions

**Constraints:**

1. **C-01**: The system SHALL be implemented in GDScript (Godot 4.x), the existing language of the project.
2. **C-02**: The system SHALL NOT introduce external dependencies beyond what the project already uses (Godot built-ins + `uYaml.gd`).
3. **C-03**: The generated assembly SHALL target the ZVM instruction set as defined in [`lang_zvm.gd`](../lang_zvm.gd).
4. **C-04**: The existing `IR_Cmd`, `IR_Value`, `CodeBlock`, `AssyBlock`, `LocationMap`, `LocationRange` classes SHALL NOT be modified (backward compatibility constraint).
5. **C-05**: The system SHALL produce output consumable by [`comp_asm_zd.gd`](../scenes/comp_asm_zd.gd) without changes to that module.

**Assumptions:**

1. **A-01**: The IR structure produced by [`ir_md.gd`](../scenes/ir_md.gd) will remain stable throughout the project lifetime.
2. **A-02**: Template data files will be checked into version control alongside source code.
3. **A-03**: The `uYaml.gd` parser can handle the template file format (nested dictionaries, multi-line strings, arrays).
4. **A-04**: No more than 200 distinct IR commands will need templates in the foreseeable future.

---

### 1.6 Requirements Traceability Matrix

| Req ID | Source File / Function | Test Case ID | Design Component | Implementation File |
|---|---|---|---|---|
| FR-01a | [`codegen_md.gd:12-25`](../scenes/codegen_md.gd:12) | TC-OP-01 | Template Registry | `template_engine.gd` |
| FR-01b | Novel | TC-OP-02 | Parameter Resolver | `template_engine.gd` |
| FR-01c | Novel | TC-OP-03 | Template Inheritance | `template_engine.gd` |
| FR-01d | Novel | TC-OP-04 | Conditional Expander | `template_engine.gd` |
| FR-01e | Novel | TC-OP-05 | Template Loader | `template_loader.gd` |
| FR-02a | [`codegen_md.gd:266-283`](../scenes/codegen_md.gd:266) | TC-DI-01 | Command Registry | `command_registry.gd` |
| FR-02b | Novel | TC-DI-02 | Command Descriptor | `command_descriptor.gd` |
| FR-03a | [`codegen_md.gd:667-698`](../scenes/codegen_md.gd:667) | TC-AL-01 | Allocator Strategy | `allocator_strategy.gd` |
| FR-03b | [`codegen_md.gd:551-574`](../scenes/codegen_md.gd:551) | TC-AL-02 | Storage Backends | `storage_backend.gd` |
| FR-03c | [`codegen_md.gd:634-640`](../scenes/codegen_md.gd:634) | TC-AL-03 | RegisterAllocator | `register_allocator.gd` |
| FR-04a | [`codegen_md.gd:349-370`](../scenes/codegen_md.gd:349) | TC-CF-01 | Control Flow Handler | `control_flow_handler.gd` |
| FR-04b | [`codegen_md.gd:401-419`](../scenes/codegen_md.gd:401) | TC-CF-02 | Loop Handler | `control_flow_handler.gd` |
| FR-04c | [`codegen_md.gd:421-449`](../scenes/codegen_md.gd:421) | TC-CF-03 | Call Handler | `call_handler.gd` |
| FR-05a | [`codegen_md.gd:790-798`](../scenes/codegen_md.gd:790) | TC-LM-01 | LocationMapper | `location_mapper.gd` |
| FR-06a | [`codegen_md.gd:474`](../scenes/codegen_md.gd:474) | TC-TM-01 | Size Declaration | All templates |

---

### 1.7 Sign-Off

Once this section is reviewed and approved, Phase 1 is locked. No further requirement changes will be accepted without a formal Change Request through the Change Control Board (see §5.1).

| Role | Name | Signature | Date |
|---|---|---|---|
| Requirements Analyst | | | |
| Lead Architect | | | |
| Project Manager | | | |
| QA Lead | | | |
| Stakeholder Representative | | | |

---

## Phase 2: Architecture & Design Specification

**Document Status**: DRAFT — not yet signed off  
**Estimated effort to complete**: 60 person-hours  
**Prerequisite**: Signed-off Requirements Specification (§1.7)  
**Deliverable**: Signed-off Design Specification (this section)

---

### 2.1 Architectural Overview

The new codegen SHALL follow a **Pipeline + Strategy** pattern with five discrete stages:

```
┌─────────────┐     ┌──────────────┐     ┌───────────────┐     ┌──────────────┐     ┌──────────────┐
│  IR Input   │────►│   Pre-pass   │────►│  Command      │────►│  Post-pass   │────►│  Assembly    │
│  Validator  │     │  (Allocate)  │     │  Expander     │     │  (Fixup)     │     │  Output      │
└─────────────┘     └──────────────┘     └───────────────┘     └──────────────┘     └──────────────┘
                                                     │
                                                     ▼
                                            ┌─────────────────┐
                                            │  Template       │
                                            │  Engine         │
                                            │  ┌───────────┐  │
                                            │  │ Registry  │  │
                                            │  │ Resolver  │  │
                                            │  │ Expander  │  │
                                            │  └───────────┘  │
                                            └─────────────────┘
```

**Stage responsibilities:**

1. **IR Input Validator** — Validates incoming IR structure against schema. Reports structural errors (missing fields, invalid types) before any processing.
2. **Pre-pass (Allocate)** — Walks all scopes and variables, assigns storage (global/stack/register) via pluggable `AllocatorStrategy`. Populates `all_syms` dictionary.
3. **Command Expander** — The core pipeline. Iterates referenced `CodeBlock`s, dispatches each `IR_Cmd` through the `CommandRegistry`, applies templates via the `TemplateEngine`, and appends assembly to the current `AssyBlock`.
4. **Post-pass (Fixup)** — Replaces placeholder markers (e.g., `__ENTER_<scope>`, `__LEAVE_<scope>`) with concrete stack adjustment instructions. Translates location maps.
5. **Assembly Output** — Returns the final assembly string and location map.

**Key design decisions:**

| Decision | Rationale |
|---|---|
| Pipeline stages are sequential with no back-edges | Enables reasoning about each stage independently; simplifies testing |
| Template engine is a separate subsystem | Templates can be tested, versioned, and reloaded independently of pipeline logic |
| Storage allocation is a pre-pass rather than on-the-fly | Eliminates interleaving of allocation and emission; enables future optimization passes |
| Command descriptors are data (YAML) rather than code | Adding a new IR command requires zero GDScript changes (NFR-04) |

---

### 2.2 Decomposition View

The system decomposes into the following modules. Each module corresponds to exactly one file.

```
codegen/
├── pipeline/
│   ├── codegen_pipeline.gd        # Orchestrates the 5 pipeline stages
│   ├── ir_validator.gd            # Stage 1: IR input validation
│   ├── allocation_pass.gd         # Stage 2: Storage allocation pre-pass
│   ├── command_expander.gd        # Stage 3: IR command dispatch & expansion
│   ├── fixup_pass.gd              # Stage 4: Post-processing fixup
│   └── assembly_output.gd         # Stage 5: Final assembly assembly & debug info
├── template/
│   ├── template_engine.gd         # Core template loading, caching, & expansion
│   ├── template_registry.gd       # Named template storage & lookup
│   ├── parameter_resolver.gd      # Resolves %param references in template text
│   └── conditional_expander.gd    # Handles %if/%then/%else/%end blocks
├── command/
│   ├── command_registry.gd        # Maps IR command names to descriptors
│   └── command_descriptor.gd      # Data class for command metadata
├── alloc/
│   ├── allocator_strategy.gd      # Abstract base class for allocation strategies
│   ├── default_allocator.gd       # Default strategy (mirrors current behavior)
│   ├── storage_backend.gd         # Abstract base for storage backends
│   ├── global_backend.gd          # Global memory (label-based)
│   ├── stack_backend.gd           # Stack memory (EBP-relative)
│   └── register_allocator.gd      # Register allocator (EAX/EBX/ECX/EDX)
├── control/
│   ├── control_flow_handler.gd    # IF/ELSE_IF/ELSE/WHILE label generation
│   └── call_handler.gd            # CALL/CALL_INDIRECT stack frame gen
├── loc/
│   └── location_mapper.gd         # Source-location-to-assembly-offset mapping
└── data/
    ├── opcode_templates.yaml       # ALU opcode templates (ADD, SUB, etc.)
    ├── command_descriptors.yaml    # IR command dispatch table
    └── control_templates.yaml      # Control flow construct templates
```

**Total**: 22 files (13 GDScript source files + 9 supporting files including data)

---

### 2.3 Component Specifications

#### 2.3.1 `codegen_pipeline.gd` — Pipeline Orchestrator

```
Class: CodegenPipeline
Extends: Node
Signals: locations_ready(loc_map: Dictionary)

Public Methods:
  - func generate(ir: Dictionary) -> String
    Runs all 5 stages sequentially. Returns assembly text.

  - func reset() -> void
    Resets internal state for a fresh generation.

Internal Methods:
  - func _stage_validate(ir: Dictionary) -> void
  - func _stage_allocate(ir: Dictionary) -> void
  - func _stage_expand(ir: Dictionary) -> AssyBlock
  - func _stage_fixup(assy: AssyBlock) -> void
  - func _stage_output(assy: AssyBlock) -> String

Configuration:
  - var template_loader_path: String = "res://codegen/data/"
    Directory to load template and descriptor YAML files from.

  - var allocator: AllocatorStrategy = DefaultAllocator.new()
    Pluggable allocation strategy.
```

#### 2.3.2 `template_engine.gd` — Template Engine

```
Class: TemplateEngine
Extends: RefCounted

Public Methods:
  - func load_templates(path: String) -> void
    Loads all .yaml files from the given directory.

  - func reload_templates() -> void
    Reloads all templates from the previously loaded path (runtime hot-reload).

  - func expand(template_name: String, params: Dictionary) -> TemplateResult
    Expands the named template with the given parameter bindings.
    Returns { text: String, size: int }.

  - func has_template(name: String) -> bool
    Checks if a template exists in the registry.

Internal Methods:
  - func _resolve_params(text: String, params: Dictionary) -> String
    Replaces %name and %N references with bound values.

  - func _expand_conditionals(text: String, params: Dictionary) -> String
    Processes %if <param> %then ... %else ... %end blocks.

State:
  - var registry: TemplateRegistry
  - var loader_path: String
  - var loaded_files: Array[String]
```

#### 2.3.3 `command_registry.gd` — Command Registry

```
Class: CommandRegistry
Extends: RefCounted

Public Methods:
  - func load_descriptors(path: String) -> void
    Loads command descriptors from a YAML file.

  - func get_descriptor(command_name: String) -> CommandDescriptor
    Returns the descriptor for a command, or null if unknown.

  - func get_all_command_names() -> Array[String]
    Returns all registered command names.

Descriptor Format (YAML):
  command_descriptors:
    MOV:
      operands:
        - name: dest
          type: value_ref
        - name: src
          type: value_ref
      phases:
        main:
          template: mov_template
          param_map: { dest: "%1", src: "%2" }
      size: 8

    OP:
      operands:
        - name: op
          type: opcode
        - name: arg1
          type: value_ref
        - name: arg2
          type: value_ref
        - name: res
          type: value_ref
      phases:
        main:
          template: op_dispatch
          param_map: { op: "%1", arg1: "%2", arg2: "%3", res: "%4" }
      size: variable  # Computed from template

    IF:
      operands:
        - name: cb_cond
          type: code_block_ref
        - name: res
          type: value_ref
        - name: cb_block
          type: code_block_ref
      phases:
        pre:
          template: if_pre
          param_map: { res: "%2", lbl_else: auto, lbl_end: auto }
        main:
          template: emit_cb
          param_map: { cb: "%1" }
        post:
          template: if_post
          param_map: { cb_block: "%3", lbl_else: auto, lbl_end: auto }
      size: variable
```

#### 2.3.4 `allocator_strategy.gd` — Abstract Allocator

```
Class: AllocatorStrategy
Extends: RefCounted
# Abstract base class

Methods (to be overridden):
  - func allocate_value(handle: Dictionary, scope: Dictionary) -> void
    Assigns storage to a single IR value handle within a scope.

  - func allocate_scope(scope: Dictionary) -> void
    Per-scope allocation setup (e.g., counting local vars).

  - func allocate_all(ir: Dictionary) -> void
    Top-level allocation pass over the entire IR.
```

#### 2.3.5 `default_allocator.gd` — Default Allocator (mirrors current behavior)

```
Class: DefaultAllocator
Extends: AllocatorStrategy

Behavior:
  - Global scope variables → global storage (label-based)
  - Non-global scope variables → stack storage (EBP-relative, negative offset)
  - Function arguments → stack storage (EBP-relative, positive offset)
  - Arrays → consecutive stack/global slots (4 bytes × array_size)
  - Functions → code storage (label reference)
  - Temporaries → register first, spill to stack when exhausted
  - Immediates → no storage (value embedded in instruction or string literal label)

Implementation Note:
  The offset mapping follows the existing convention:
  - Local var base: to_local_pos(0) = -3  (see [`codegen_md.gd:701-702`](../scenes/codegen_md.gd:701))
  - Argument base:  to_arg_pos(0) = 9   (see [`codegen_md.gd:705-706`](../scenes/codegen_md.gd:705))
```

#### 2.3.6 `register_allocator.gd` — Register Allocator

```
Class: RegisterAllocator
Extends: RefCounted

Public Methods:
  - func alloc() -> String or null
    Returns a register name or null if none available.

  - func free(reg: String) -> void
    Marks a register as available.

  - func is_available(reg: String) -> bool
    Checks register availability.

  - func reset() -> void
    Marks all registers as available.

Constants:
  const REGISTERS = ["EAX", "EBX", "ECX", "EDX"]

State:
  var in_use: Dictionary = {}   # reg_name → bool
```

#### 2.3.7 `control_flow_handler.gd` — Control Flow

```
Class: ControlFlowHandler
Extends: RefCounted

Public Methods:
  - func new_label(base_name: String) -> Dictionary
    Generates a unique label handle with `{ ir_name, val_type: "label" }`.

  - func generate_if(cmd: IR_Cmd, expander) -> void
  - func generate_else_if(cmd: IR_Cmd, expander) -> void
  - func generate_else(cmd: IR_Cmd, expander) -> void
  - func generate_while(cmd: IR_Cmd, expander) -> void

Design Note:
  These methods encapsulate the label-generation logic currently in
  [`generate_cmd_if` (349-370)](../scenes/codegen_md.gd:349) and
  [`generate_cmd_while` (401-419)](../scenes/codegen_md.gd:401).
  They call into the template engine for individual assembly lines
  (cmp, jz, jmp, label emission) rather than emitting raw strings.
```

#### 2.3.8 `location_mapper.gd` — Location Mapping

```
Class: LocationMapper
Extends: RefCounted

Public Methods:
  - func mark_begin(loc: LocationRange, write_pos: int) -> void
  - func mark_end(loc: LocationRange, write_pos: int) -> void
  - func translate(sub_map: LocationMap, offset: int) -> LocationMap
  - func get_map() -> LocationMap

State:
  var begin_map: Dictionary = {}  # write_pos → Array[LocationRange]
  var end_map: Dictionary = {}    # write_pos → Array[LocationRange]
```

---

### 2.4 Data Dictionary & Schema

#### 2.4.1 IR Value Handle Schema (from [`ir_md.gd`](../scenes/ir_md.gd))

```gdscript
# Dictionary shape for an IR value handle:
{
    "val_type": String,     # "temporary" | "variable" | "immediate" | "func" | "code" | "error" | "none"
    "ir_name": String,      # unique identifier (e.g., "var_3__x")
    "user_name": String,    # source-level name (e.g., "x")
    "data_type": String,    # "int" | "string" | "error"
    "value": String,        # literal value (for immediates)
    "storage": Dictionary or String,  # {"type": "global"|"stack"|"code"|"extern", "pos": int} or "NULL"|"extern"|"arg"
    "is_array": String,     # "0" or "1" (from yaml deserialization)
    "array_size": String,   # number of elements (from yaml deserialization)
    "scope": String,        # parent scope ir_name
    "needs_deref": bool     # set by codegen during emission
}
```

#### 2.4.2 Scope Schema

```gdscript
{
    "ir_name": String,
    "user_name": String,        # "global" or function name
    "vars": Array[Dictionary],  # Array of value handles
    "funcs": Array[Dictionary], # Array of function value handles
    # Added by allocation pass:
    "local_vars_count": int,
    "local_vars_write_pos": int,
    "args_count": int,
    "args_write_pos": int
}
```

#### 2.4.3 Template Schema (YAML)

```yaml
# Each template file contains a version header and a templates dictionary.
# The "templates" key maps template_name → template_definition.

version: "1.0"

templates:
  <template_name>:
    description: "<human-readable description>"      # optional
    extends: "<parent_template_name>"                 # optional, for template inheritance
    params:                                           # optional, list of expected parameter names
      - "<param_name>"
    assembly: "<assembly text with %param references>"  # required
    size: <int>                                       # assembly size in bytes; "auto" to compute from semicolon count
    debug: "<debug annotation template>"              # optional, emitted when ADD_DEBUG_TRACE is true
```

#### 2.4.4 Command Descriptor Schema (YAML)

```yaml
command_descriptors:
  <command_name>:
    description: "<human-readable description>"
    operands:
      - name: "<name>"
        type: "<type>"    # "value_ref" | "opcode" | "code_block_ref" | "label" | "int_literal"
    phases:
      <phase_name>:       # "pre" | "main" | "post"
        template: "<template_name>"
        param_map:        # maps template parameters to operand references
          <param_name>: "<%N or auto>"
    size: <int or "variable">
```

---

### 2.5 Template Engine Design

#### 2.5.1 Parameter Resolution Algorithm

The `parameter_resolver.gd` SHALL implement the following parameter resolution algorithm:

```
Input:  template_text (String), params (Dictionary)
Output: resolved_text (String)

Algorithm:
1. For each key-value pair in params:
   a. Find all occurrences of "%<key>" in template_text using regex: %(\w+)
   b. Replace each occurrence with the corresponding value from params
2. Find all positional references "%N" (where N is 1-9) not yet replaced:
   a. Replace with params["%N"] if present, else raise TemplateError
3. Return resolved_text
```

#### 2.5.2 Conditional Expansion

The `conditional_expander.gd` SHALL support the following syntax:

```
%if <param_name>
  <text when param is truthy>
%else
  <text when param is falsy>
%end
```

Where "truthy" means the parameter value is non-empty, non-zero, and not `false`.

#### 2.5.3 Template Inheritance

When a template declares `extends: <parent_name>`, the engine SHALL:

1. Load the parent template text
2. Replace the literal `%{super}` in the parent with the child's assembly text
3. Merge child params into parent params (child wins on conflict)
4. Apply parameter resolution to the merged result

#### 2.5.4 Template Caching

The `TemplateRegistry` SHALL cache loaded templates in a `Dictionary` keyed by template name. On `reload_templates()`, the cache is cleared and all files are re-parsed.

---

### 2.6 Template Catalog (Complete)

This section defines every template that SHALL exist in the final system. This is a frozen specification — no templates shall be added, removed, or changed without a formal Change Request.

#### 2.6.1 ALU Opcode Templates (`opcode_templates.yaml`)

```yaml
version: "1.0"
templates:

  add:
    description: "ADD instruction: arg1 + arg2 → arg1"
    params: [a, b]
    assembly: "add %a, %b;\n"
    size: 8

  sub:
    description: "SUB instruction: arg1 - arg2 → arg1"
    params: [a, b]
    assembly: "sub %a, %b;\n"
    size: 8

  mul:
    description: "MUL instruction: arg1 * arg2 → arg1"
    params: [a, b]
    assembly: "mul %a, %b;\n"
    size: 8

  div:
    description: "DIV instruction: arg1 / arg2 → arg1"
    params: [a, b]
    assembly: "div %a, %b;\n"
    size: 8

  mod:
    description: "MOD instruction: arg1 % arg2 → arg1"
    params: [a, b]
    assembly: "mod %a, %b;\n"
    size: 8

  inc:
    description: "INC instruction: arg1 + 1 → arg1"
    params: [a]
    assembly: "inc %a;\n"
    size: 8

  dec:
    description: "DEC instruction: arg1 - 1 → arg1"
    params: [a]
    assembly: "dec %a;\n"
    size: 8

  greater:
    description: "GREATER comparison: sets CTRL.CMP_G if arg1 > arg2"
    params: [a, b]
    assembly: |
      cmp %a, %b;
      mov %a, CTRL;
      band %a, CMP_G;
      bnot %a;
      bnot %a;
    size: 40

  less:
    description: "LESS comparison: sets CTRL.CMP_L if arg1 < arg2"
    params: [a, b]
    assembly: |
      cmp %a, %b;
      mov %a, CTRL;
      band %a, CMP_L;
      bnot %a;
      bnot %a;
    size: 40

  equal:
    description: "EQUAL comparison: sets CTRL.CMP_Z if arg1 == arg2"
    params: [a, b]
    assembly: |
      cmp %a, %b;
      mov %a, CTRL;
      band %a, CMP_Z;
      bnot %a;
      bnot %a;
    size: 40

  not_equal:
    description: "NOT_EQUAL comparison: sets CTRL.CMP_NZ if arg1 != arg2"
    params: [a, b]
    assembly: |
      cmp %a, %b;
      mov %a, CTRL;
      band %a, CMP_NZ;
      bnot %a;
      bnot %a;
    size: 40

  index:
    description: "INDEX operation: base + offset → result (deref handled later)"
    params: [a, b]
    assembly: "add %a, %b;\n"
    size: 8
    # Note: The IR_Cmd.needs_deref flag is set externally after this template is applied
    # See [codegen_md.gd:323](../scenes/codegen_md.gd:323)

  op_dispatch:
    description: "Dispatches an OP command by loading operands, applying the op template, and storing result"
    params: [op, arg1_load, arg2_load, arg1_ref, arg2_ref, res_load, res_store, tmpA, tmpB]
    assembly: |  # Pseudo-assembly: actual expansion is multi-step as in [codegen_md.gd:294-325]
      # Step 1: Check if op is mono (INC/DEC)
      # Step 2: Load arg1 into tmpA (or res for mono ops)
      # Step 3: If binary op, load arg2 into tmpB
      # Step 4: Apply op-specific template (add/sub/...)
      # Step 5: Store tmpA into res
    size: variable
    # Note: This is a meta-template that orchestrates sub-templates.
    # Its expansion logic is detailed in §2.6.1a.
```

#### 2.6.1a OP Command Expansion Logic (Meta-Process)

The `OP` command is the most complex single command because it must:
1. Determine if the operation is monadic (`INC`, `DEC`) or dyadic (all others)
2. Load operands into temporaries (registers or stack slots)
3. Apply the op-specific template (add/sub/mul/etc.) with `%a` and `%b` replaced by temporaries
4. Store the result back to the destination

This cannot be expressed purely as a static template string. Instead, the `OP` command descriptor declares a **handler** rather than a simple template:

```yaml
command_descriptors:
  OP:
    operands:
      - name: op
        type: opcode
      - name: arg1
        type: value_ref
      - name: arg2
        type: value_ref
      - name: res
        type: value_ref
    handler: "expand_op_command"  # references a method in command_expander.gd
    size: variable
```

The `expand_op_command` handler SHALL implement the following algorithm (mirroring [`codegen_md.gd:294-325`](../scenes/codegen_md.gd:294)):

```
Algorithm expand_op_command(cmd, expander):
1. op = cmd.words[1], arg1 = cmd.words[2], arg2 = cmd.words[3], res = cmd.words[4]
2. If op in MONO_OPS:
   a. tmpA = "^%arg1" (store reference)
   b. Emit "mov ^%res, $%arg1;\n"  # copy arg1 to result first
   c. Apply template for op with params { a: tmpA }
3. Else (binary op):
   a. tmpA = alloc_temporary()
   b. Emit "mov %tmpA, $%arg1;\n"   # load arg1 into tmpA
   c. tmpB = alloc_temporary()
   d. Emit "mov %tmpB, $%arg2;\n"   # load arg2 into tmpB
   e. Apply template for op with params { a: tmpA, b: tmpB }
   f. Emit "mov ^%res, %tmpA;\n"    # store result
4. If op == "INDEX": res_handle.needs_deref = true
5. free_val(tmpA), free_val(tmpB) if allocated
```

#### 2.6.2 Data Movement Templates (`opcode_templates.yaml`, continued)

```yaml
  mov:
    description: "MOV instruction: copy src to dest"
    params: [dest, src]
    assembly: "mov %dest, %src;\n"
    size: 8

  mov_deref:
    description: "MOV with dereference: load value through pointer"
    params: [dest, src_ptr]
    assembly: |
      mov %dest, %src_ptr;
      mov %dest, *%dest;
    size: 16

  mov_store_deref:
    description: "MOV with store through pointer: write value to address held in ptr"
    params: [val, ptr]
    assembly: |
      mov *%ptr, %val;
    size: 8

  mov_arr_init:
    description: "Initialize array copy: load array base address"
    params: [tmp, dest]
    assembly: "mov %tmp, $%dest;\n"
    size: 8

  mov_arr_element:
    description: "Copy single element into array position"
    params: [tmp, val]
    assembly: |
      mov *%tmp, $%val;
      add %tmp, 4;
    size: 16

  push:
    description: "Push value onto stack"
    params: [val]
    assembly: "push %val;\n"
    size: 8

  pop:
    description: "Pop value from stack into register"
    params: [reg]
    assembly: "pop %reg;\n"
    size: 8

  call_func:
    description: "Call a named function"
    params: [func_name]
    assembly: "call @%func_name;\n"
    size: 8

  call_indirect:
    description: "Call through a function pointer"
    params: [func_var]
    assembly: "call $%func_var;\n"
    size: 8

  adjust_stack:
    description: "Adjust stack pointer after call cleanup"
    params: [amount]
    assembly: "add ESP, %amount;\n"
    size: 8

  mov_result:
    description: "Move EAX to result destination"
    params: [res]
    assembly: "mov ^%res, eax;\n"
    size: 8

  mov_return:
    description: "Move value to EAX for return"
    params: [val]
    assembly: "mov EAX, $%val;\n"
    size: 8
```

#### 2.6.3 Control Flow Templates (`control_templates.yaml`)

```yaml
version: "1.0"
templates:

  cmp_zero:
    description: "Compare value against immediate zero"
    params: [val, imm_zero]
    assembly: "cmp $%val, $%imm_zero;\n"
    size: 8

  jz:
    description: "Jump if zero to label"
    params: [label]
    assembly: "jz %label;\n"
    size: 8

  jmp:
    description: "Unconditional jump to label"
    params: [label]
    assembly: "jmp %label;\n"
    size: 8

  label:
    description: "Emit a label"
    params: [name]
    assembly: ":%name:\n"
    size: 0

  enter_scope_placeholder:
    description: "Placeholder for scope enter (fixed up in post-pass)"
    params: [scope_name]
    assembly: "__ENTER_%scope_name;\n"
    size: 8

  leave_scope_placeholder:
    description: "Placeholder for scope leave (fixed up in post-pass)"
    params: [scope_name]
    assembly: "__LEAVE_%scope_name;\n"
    size: 8

  ret:
    description: "Return from function"
    assembly: "ret;\n"
    size: 8

  global_var_decl:
    description: "Declare a global variable (zero-initialized)"
    params: [ir_name]
    assembly: ":%ir_name: db 0;\n"
    size: 0

  global_array_decl:
    description: "Declare a global array"
    params: [ir_name, byte_size]
    assembly: ":%ir_name: alloc %byte_size;\n"
    size: 0

  string_literal_decl:
    description: "Declare a string literal in data section"
    params: [ir_name, value]
    assembly: ":%ir_name: db %value, 0;\n"
    size: 0

  debug_comment:
    description: "Emit a debug trace comment"
    params: [message]
    assembly: "#%message\n"
    size: 0
```

#### 2.6.4 Command Dispatch Registry (`command_descriptors.yaml`) — Complete

```yaml
version: "1.0"
command_descriptors:

  MOV:
    description: "Copy src value to dest location"
    operands:
      - { name: dest, type: value_ref }
      - { name: src,  type: value_ref }
    phases:
      main:
        template: mov
        param_map: { dest: "%1", src: "%2" }
    size: 8

  OP:
    description: "ALU operation: op arg1 arg2 → res"
    operands:
      - { name: op,   type: opcode }
      - { name: arg1, type: value_ref }
      - { name: arg2, type: value_ref }
      - { name: res,  type: value_ref }
    handler: expand_op_command
    size: variable

  IF:
    description: "Conditional branch"
    operands:
      - { name: cb_cond,  type: code_block_ref }
      - { name: res,      type: value_ref }
      - { name: cb_block, type: code_block_ref }
    handler: expand_if_command
    size: variable

  ELSE_IF:
    description: "Else-if branch"
    operands:
      - { name: cb_cond,  type: code_block_ref }
      - { name: res,      type: value_ref }
      - { name: cb_block, type: code_block_ref }
    handler: expand_else_if_command
    size: variable

  ELSE:
    description: "Else branch"
    operands:
      - { name: cb_block, type: code_block_ref }
    handler: expand_else_command
    size: variable

  WHILE:
    description: "While loop"
    operands:
      - { name: cb_cond,  type: code_block_ref }
      - { name: res,      type: value_ref }
      - { name: cb_block, type: code_block_ref }
      - { name: lbl_next, type: label }
      - { name: lbl_end,  type: label }
    handler: expand_while_command
    size: variable

  CALL:
    description: "Function call by name"
    operands:
      - { name: fun,  type: func_ref }
      - { name: args, type: arg_list }
      - { name: res,  type: value_ref }
    handler: expand_call_command
    size: variable

  CALL_INDIRECT:
    description: "Function call via pointer"
    operands:
      - { name: funvar, type: value_ref }
      - { name: args,   type: arg_list }
      - { name: res,    type: value_ref }
    handler: expand_call_indirect_command
    size: variable

  RETURN:
    description: "Return from function"
    operands:
      - { name: val, type: value_ref, optional: true }
    handler: expand_return_command
    size: variable

  ENTER:
    description: "Enter a scope"
    operands:
      - { name: scope_name, type: scope_ref }
    handler: expand_enter_command
    size: 8

  LEAVE:
    description: "Leave current scope"
    operands: []
    handler: expand_leave_command
    size: 8

  ALLOC:
    description: "Allocate an array"
    operands:
      - { name: size, type: int_literal }
      - { name: res,  type: value_ref }
    handler: expand_alloc_command
    size: 8

  MOV_ARR:
    description: "Move values into array"
    operands:
      - { name: dest, type: value_ref }
      - { name: vals, type: list }
    handler: expand_mov_arr_command
    size: variable
```

---

### 2.7 Pipeline Design

#### 2.7.1 Stage 1: IR Validation (`ir_validator.gd`)

```
Input:  ir (Dictionary) — raw IR from [ir_md.gd](../scenes/ir_md.gd)
Output: validated IR or ErrorReport

Validation rules:
1. ir MUST contain "code_blocks" key (non-empty Dictionary)
2. ir MUST contain "scopes" key (non-empty Dictionary)
3. Each code_block MUST have "lbl_from" and "lbl_to" (Strings)
4. Each code_block MAY have "code" (Array)
5. Each IR_Cmd in "code" MUST have non-empty "words" Array
6. Each IR_Cmd MUST have "loc" (LocationRange)
7. Each scope MUST have "vars" and "funcs" Arrays
8. Each scope MUST have "ir_name" and "user_name" Strings
9. Each value handle MUST have "ir_name" and "val_type" Strings

On validation failure:
- Return ErrorReport with list of violations
- Pipeline halts (no further stages executed)
```

#### 2.7.2 Stage 2: Allocation Pass (`allocation_pass.gd`)

```
Input:  validated IR, AllocatorStrategy
Output: IR with storage assigned to all values

Algorithm:
1. For each scope in ir.scopes:
   a. Initialize scope counters: local_vars_count = 0, local_vars_write_pos = to_local_pos(0), etc.
   b. For each var in scope.vars: allocator.allocate_value(var, scope)
   c. For each func in scope.funcs: allocate code storage
2. Populate all_syms dictionary: all code_blocks + all scope vars/funcs → all_syms
3. Result: every value handle in all_syms has a storage field of form {"type": ..., "pos": ...}
```

#### 2.7.3 Stage 3: Command Expansion (`command_expander.gd`)

```
Input:  IR with allocated storage, CommandRegistry, TemplateEngine
Output: AssyBlock with assembly text and location map

Algorithm:
1. Determine entry point: first code_block in ir.code_blocks
2. Initialize referenced_cbs queue with entry point
3. Initialize emitted_cbs set (empty)
4. While referenced_cbs is not empty:
   a. cb = referenced_cbs.pop_front()
   b. If cb in emitted_cbs: continue
   c. emitted_cbs.add(cb)
   d. Generate code block:
      - Emit begin-comment (if ADD_DEBUG_TRACE)
      - Emit lbl_from label
      - For each IR_Cmd in cb.code:
        - Check if_block_continued (set cur_block.if_block_continued)
        - Dispatch via command_registry: get descriptor for cmd.words[0]
        - If descriptor has handler: call handler function
        - Else: for each phase in descriptor.phases:
          - Resolve param_map against cmd.words
          - Call template_engine.expand(phase.template, resolved_params)
          - Emit expanded text, advance write_pos by template.size
      - Emit maybe_emit_func_ret (if cb is a function body)
      - Emit lbl_to label
      - Emit end-comment
   e. Translate sub-block location maps into parent block's address space
5. Append global variable declarations
```

#### 2.7.4 Stage 4: Fixup Pass (`fixup_pass.gd`)

```
Input:  AssyBlock with __ENTER_<scope> and __LEAVE_<scope> placeholders
Output: Fixed-up AssyBlock with concrete stack adjustments

Algorithm:
1. For each scope in ir.scopes:
   a. scp_name = scope.ir_name
   b. stack_bytes = scope.local_vars_write_pos (always negative or zero)
   c. Replace all "__ENTER_<scp_name>" with "sub ESP, < -stack_bytes >"
   d. Replace all "__LEAVE_<scp_name>" with "sub ESP, <stack_bytes>"
2. Translation:
   - "sub ESP, -N" where N is negative → "add ESP, N" (simplified)
```

#### 2.7.5 Stage 5: Output (`assembly_output.gd`)

```
Input:  Fixed-up AssyBlock
Output: String (assembly text)

Algorithm:
1. Emit locations_ready signal with assy_block.loc_map
2. Return assy_block.code
```

---

### 2.8 Error Handling Strategy

| Error Category | Example | Detection Point | Handler Behavior |
|---|---|---|---|
| Template Syntax Error | Missing `%end` in conditional | Template load time | Log error with file:line:col; skip template; pipeline fails at Stage 3 |
| Undefined Template Reference | Command descriptor references unknown template | Stage 3 expansion | Abort pipeline; return ErrorReport with descriptor name |
| Missing Parameter | Template requires `%dest` but param_map doesn't provide it | Template expansion | Raise TemplateError; abort pipeline |
| IR Structural Error | `code_blocks` key missing | Stage 1 validation | Return ErrorReport; pipeline halts |
| Unknown IR Command | `cmd.words[0]` not in registry | Stage 3 dispatch | Emit error via `push_error`; continue with next command |
| Storage Allocation Error | Unknown storage type string | Stage 2 allocation | Abort pipeline; raise AllocError |
| Register Exhaustion | All 4 registers in use | Stage 3 expansion | Spill to stack (automatic via `alloc_temporary`) |

**Error report structure**:
```gdscript
class ErrorReport:
    var errors: Array[ErrorItem] = []
    
class ErrorItem:
    var stage: String          # "validation" | "allocation" | "expansion" | "fixup"
    var message: String
    var location: String       # file:line or IR path
    var severity: String       # "error" | "warning"
```

---

### 2.9 Design Review Checklist

Before signing off Phase 2, the following MUST be verified:

| # | Check Item | Status |
|---|---|---|
| DR-01 | All 14 command types from [`codegen_md.gd:268-282`](../scenes/codegen_md.gd:268) are covered in `command_descriptors.yaml` | |
| DR-02 | All 12 operators in `op_map` ([`codegen_md.gd:12-25`](../scenes/codegen_md.gd:12)) have corresponding templates | |
| DR-03 | Register allocation mirrors `alloc_register` / `free_val` behavior ([`codegen_md.gd:634-640`](../scenes/codegen_md.gd:634)) | |
| DR-04 | Storage allocation mirrors `allocate_value` / `to_local_pos` / `to_arg_pos` ([`codegen_md.gd:667-698`](../scenes/codegen_md.gd:667)) | |
| DR-05 | Location mapping matches `mark_loc_begin` / `mark_loc_end` / `translate_ab_locations` ([`codegen_md.gd:790-828`](../scenes/codegen_md.gd:790)) | |
| DR-06 | Enter/leave placeholder fixup matches `fixup_enter_leave` ([`codegen_md.gd:754-762`](../scenes/codegen_md.gd:754)) | |
| DR-07 | Emit logic for `$`/`@`/`^` markers ([`codegen_md.gd:474-533`](../scenes/codegen_md.gd:474)) is correctly distributed across template resolution and expansion | |
| DR-08 | No dependency cycles exist between modules | |
| DR-09 | All 22 files listed in §2.2 have defined responsibilities with no overlap | |
| DR-10 | The `emit_cb` / `generate_code_block` recursion pattern ([`codegen_md.gd:179-200`](../scenes/codegen_md.gd:179)) is preserved | |

---

### 2.10 Sign-Off

| Role | Name | Signature | Date |
|---|---|---|---|
| Lead Architect | | | |
| Design Reviewer | | | |
| Implementation Lead | | | |
| QA Lead | | | |
| Project Manager | | | |

---

## Phase 3: Implementation Specification

**Document Status**: DRAFT — not yet signed off  
**Estimated effort to complete**: 80 person-hours  
**Prerequisite**: Signed-off Design Specification (§2.10)  
**Deliverable**: All 22 files (§2.2) implemented, unit-tested, and code-reviewed

---

### 3.1 File Manifest

Total: 22 files across 6 directories, plus 1 updated integration file.

| # | File Path | Lines (est.) | Purpose |
|---|---|---|---|
| 1 | `codegen/pipeline/codegen_pipeline.gd` | 180 | Pipeline orchestrator |
| 2 | `codegen/pipeline/ir_validator.gd` | 80 | IR input validation |
| 3 | `codegen/pipeline/allocation_pass.gd` | 60 | Storage allocation pre-pass |
| 4 | `codegen/pipeline/command_expander.gd` | 350 | Core command dispatch & expansion |
| 5 | `codegen/pipeline/fixup_pass.gd` | 50 | Post-processing fixup |
| 6 | `codegen/pipeline/assembly_output.gd` | 30 | Final output assembly |
| 7 | `codegen/template/template_engine.gd` | 200 | Template loading, caching, expansion |
| 8 | `codegen/template/template_registry.gd` | 80 | Named template storage |
| 9 | `codegen/template/parameter_resolver.gd` | 60 | Parameter resolution |
| 10 | `codegen/template/conditional_expander.gd` | 70 | Conditional block expansion |
| 11 | `codegen/command/command_registry.gd` | 80 | Command name→descriptor mapping |
| 12 | `codegen/command/command_descriptor.gd` | 40 | Command descriptor data class |
| 13 | `codegen/alloc/allocator_strategy.gd` | 30 | Abstract allocator base |
| 14 | `codegen/alloc/default_allocator.gd` | 100 | Default allocation strategy |
| 15 | `codegen/alloc/storage_backend.gd` | 20 | Abstract storage backend |
| 16 | `codegen/alloc/global_backend.gd` | 30 | Global label-based storage |
| 17 | `codegen/alloc/stack_backend.gd` | 30 | Stack EBP-relative storage |
| 18 | `codegen/alloc/register_allocator.gd` | 50 | Register allocator |
| 19 | `codegen/control/control_flow_handler.gd` | 120 | IF/ELSE_IF/ELSE/WHILE logic |
| 20 | `codegen/control/call_handler.gd` | 100 | CALL/CALL_INDIRECT logic |
| 21 | `codegen/loc/location_mapper.gd` | 60 | Location mapping |
| 22 | `codegen/data/opcode_templates.yaml` | 100 | ALU opcode templates |
| 23 | `codegen/data/command_descriptors.yaml` | 120 | Command dispatch descriptors |
| 24 | `codegen/data/control_templates.yaml` | 60 | Control flow templates |
| 25 | `scenes/codegen_md.gd` (UPDATED) | ~100 | Thin wrapper delegating to `CodegenPipeline` |

**Total estimated lines**: ~2,150

---

### 3.2 Implementation Order

Implementation SHALL proceed in strict order. Each unit MUST be complete and unit-tested before the next unit begins.

| Phase | Units | Depends On | Estimated Hours |
|---|---|---|---|
| **3.2.1** | Storage backend classes (15–18), `RegisterAllocator` | None (self-contained) | 12 |
| **3.2.2** | `AllocatorStrategy` (13), `DefaultAllocator` (14) | 3.2.1 | 8 |
| **3.2.3** | `TemplateRegistry` (8), `ParameterResolver` (9), `ConditionalExpander` (10) | None (self-contained) | 10 |
| **3.2.4** | `TemplateEngine` (7) | 3.2.3 | 6 |
| **3.2.5** | `CommandDescriptor` (12), `CommandRegistry` (11) | None (self-contained) | 4 |
| **3.2.6** | `ControlFlowHandler` (19), `CallHandler` (20) | 3.2.4 | 10 |
| **3.2.7** | `LocationMapper` (21) | None | 4 |
| **3.2.8** | `IRValidator` (2), `AllocationPass` (3), `FixupPass` (5), `AssemblyOutput` (6) | 3.2.2, 3.2.7 | 8 |
| **3.2.9** | `CommandExpander` (4) | 3.2.4, 3.2.5, 3.2.6, 3.2.7 | 10 |
| **3.2.10** | `CodegenPipeline` (1) | 3.2.8, 3.2.9 | 4 |
| **3.2.11** | Data files (22–24) | None | 4 |
| **3.2.12** | `codegen_md.gd` thin wrapper | 3.2.10 | 2 |
| | **Total** | | **82** |

---

### 3.3 Coding Standards

1. **Naming**: GDScript conventions (`snake_case` for variables/functions, `PascalCase` for classes)
2. **Documentation**: Every public method SHALL have a doc comment describing its contract
3. **Error handling**: Use `assert` for invariant checks; use `push_error` + return `ErrorReport` for user-facing errors
4. **Type annotations**: All method parameters and return types SHALL be annotated
5. **Line length**: Maximum 120 characters
6. **File header**: Each file SHALL begin with a comment block identifying the file, its purpose, and its phase of origin

---

### 3.4 Unit Implementation Specifications

Each unit listed in §3.2 SHALL be implemented according to its specification in §2.3. Additionally:

- **Unit 3.2.1** (`RegisterAllocator`): Must reproduce the exact allocation order of the existing [`alloc_register`](../scenes/codegen_md.gd:634) (EAX → EBX → ECX → EDX, first available).
- **Unit 3.2.2** (`DefaultAllocator`): Must reproduce the exact storage assignment behavior of [`allocate_value`](../scenes/codegen_md.gd:667) including `to_local_pos`/`to_arg_pos` offset mappings.
- **Unit 3.2.4** (`TemplateEngine`): Must handle the `%{super}` inheritance marker, nested conditionals (up to 3 levels), and parameter substitution with GDScript string formatting.
- **Unit 3.2.9** (`CommandExpander`): The `emit` function SHALL be replaced by a `template_engine.expand` call, but the `$`/`@`/`^` marker resolution logic from [`emit`](../scenes/codegen_md.gd:474) SHALL be moved into the template engine's parameter resolver (i.e., template parameters are already resolved to concrete register/memory references before template expansion, removing the need for runtime marker scanning).

#### 3.4.1 Migration of `$`/`@`/`^` Marker Resolution

The existing [`emit`](../scenes/codegen_md.gd:474) function performs runtime string scanning for three marker types:

| Marker | Current Behavior (codegen_md.gd:474-515) | New Location |
|---|---|---|
| `$name` | Calls `load_value(name)` → returns CPU addressable string | Resolved in `CommandExpander` before template expansion |
| `@name` | Calls `address_value(name)` → returns label for address-of | Resolved in `CommandExpander` before template expansion |
| `^name` | Calls `store_val(name)` → returns writable address; may trigger deref | Resolved in `CommandExpander` before template expansion; deref logic in emit lines 482-493 migrated to `CommandExpander` |

This eliminates the O(n) runtime string scanning and moves marker resolution to a pre-processing step before template expansion.

---

### 3.5 Integration Points

| Integration Point | Consumer | Producer | Data Exchanged |
|---|---|---|---|
| Pipeline ↔ External | `comp_compile_md.gd` | `CodegenPipeline.generate()` | Assembly `String` + `loc_map` signal |
| Pipeline Stage 1 → 2 | `ir_validator.gd` | `allocation_pass.gd` | Validated `Dictionary` IR |
| Pipeline Stage 2 → 3 | `allocation_pass.gd` | `command_expander.gd` | IR with storage assigned |
| Pipeline Stage 3 → 4 | `command_expander.gd` | `fixup_pass.gd` | `AssyBlock` with enter/leave placeholders |
| Pipeline Stage 4 → 5 | `fixup_pass.gd` | `assembly_output.gd` | Fixed-up `AssyBlock` |
| Expander ↔ Template | `command_expander.gd` | `template_engine.gd` | Template name + param dict → expanded text |
| Expander ↔ Registry | `command_expander.gd` | `command_registry.gd` | Command name → `CommandDescriptor` |

The existing [`codegen_md.gd`](../scenes/codegen_md.gd) SHALL be updated to become a thin wrapper:

```gdscript
# Updated codegen_md.gd (Phase 3)
extends Node

const CodegenPipeline = preload("res://codegen/pipeline/codegen_pipeline.gd")

signal locations_ready(loc_map)

var pipeline: CodegenPipeline

func _ready():
    pipeline = CodegenPipeline.new()
    pipeline.locations_ready.connect(_on_locations_ready)

func generate(ir: Dictionary) -> String:
    return pipeline.generate(ir)

func reset():
    pipeline.reset()

func _on_locations_ready(loc_map: Dictionary):
    locations_ready.emit(loc_map)
```

---

### 3.6 Sign-Off

| Role | Name | Signature | Date |
|---|---|---|---|
| Implementation Lead | | | |
| Code Reviewer | | | |
| Integration Tester | | | |

---

## Phase 4: Verification Plan

**Document Status**: DRAFT — not yet signed off  
**Estimated effort to complete**: 40 person-hours  
**Prerequisite**: Signed-off Implementation (§3.6)  
**Deliverable**: Signed-off Test Results with 100% pass rate

---

### 4.1 Test Strategy

1. **Unit Tests** (70% of effort): Each module tested in isolation with mocked dependencies
2. **Integration Tests** (15%): Full pipeline execution with known IR inputs
3. **Regression Tests** (10%): Compare output of new codegen against saved output of old codegen for identical IR inputs
4. **Performance Tests** (5%): Benchmark against current implementation

All tests SHALL be automated GDScript tests run via Godot's test runner.

---

### 4.2 Test Case Catalog

#### 4.2.1 Template Engine Tests

| ID | Description | Input | Expected Output |
|---|---|---|---|
| TC-TE-01 | Simple parameter substitution | template: `"add %a, %b;\n"`, params: `{a: "EAX", b: "EBX"}` | `"add EAX, EBX;\n"` |
| TC-TE-02 | Positional parameter | template: `"mov %1, %2;\n"`, params: `{"%1": "EAX", "%2": "5"}` | `"mov EAX, 5;\n"` |
| TC-TE-03 | Template inheritance | parent: `"push %1;\n"`, child extends with `"pop %1;\n"` | Child expands to `"push EAX;\npop EAX;\n"` |
| TC-TE-04 | Conditional expansion (true) | `"%if debug\n# debug mode\n%end"`, params: `{debug: "true"}` | `"# debug mode\n"` |
| TC-TE-05 | Conditional expansion (false) | `"%if debug\n# debug mode\n%end"`, params: `{debug: ""}` | `""` |
| TC-TE-06 | Unknown template | `expand("nonexistent", {})` | `null` (or `TemplateError`) |
| TC-TE-07 | Missing parameter | template `"%missing"`, params: `{}` | `TemplateError` |
| TC-TE-08 | Nested conditionals (2 levels) | See conditional_expander test spec | Correct expansion |

#### 4.2.2 Command Registry Tests

| ID | Description | Input | Expected Output |
|---|---|---|---|
| TC-CR-01 | Load valid descriptors | Valid YAML file | All 14 commands registered |
| TC-CR-02 | Lookup known command | `"MOV"` | Non-null `CommandDescriptor` with 2 operands |
| TC-CR-03 | Lookup unknown command | `"BOGUS"` | `null` |
| TC-CR-04 | Malformed descriptor YAML | Invalid YAML | Parse error reported |

#### 4.2.3 Register Allocator Tests

| ID | Description | Input | Expected Output |
|---|---|---|---|
| TC-RA-01 | Allocate 4 registers sequentially | 4× `alloc()` | `"EAX"`, `"EBX"`, `"ECX"`, `"EDX"` |
| TC-RA-02 | Allocate when all in use | 5× `alloc()` | 5th call returns `null` |
| TC-RA-03 | Free and re-allocate | alloc/free/alloc sequence | Correct reuse |
| TC-RA-04 | Reset | alloc 4, reset, alloc 1 | `"EAX"` |

#### 4.2.4 Command Expansion Tests

| ID | Description | Input | Expected Output |
|---|---|---|---|
| TC-CE-01 | MOV command | IR: `["MOV", "var_x", "imm_5"]` | `"mov *var_x, 5;\n"` |
| TC-CE-02 | ADD opcode | IR: `["OP", "ADD", "var_a", "var_b", "var_r"]` | `"mov EAX, *var_a;\nmov EBX, *var_b;\nadd EAX, EBX;\nmov *var_r, EAX;\n"` |
| TC-CE-03 | IF command | Complete IF IR command | Labels + cmp + jz + block + jmp |
| TC-CE-04 | WHILE command | Complete WHILE IR command | Loop label + cond + block + jump |
| TC-CE-05 | Function CALL with args | IR: `["CALL", "func_f", "[", "arg1", "]", "res"]` | Push args + call + stack adjust + mov result |
| TC-CE-06 | RETURN with value | IR: `["RETURN", "var_x"]` | `"mov EAX, *var_x;\n__LEAVE_scope;\nret;\n"` |
| TC-CE-07 | ENTER/LEAVE | IR: `["ENTER", "scope_main"]` + `["LEAVE"]` | `"__ENTER_scope_main;\n"` + `"__LEAVE_scope_main;\n"` |
| TC-CE-08 | ALLOC array | IR: `["ALLOC", "10", "arr_x"]` | Allocates storage, emits `"mov ^arr_x, @arr_N;\n"` |
| TC-CE-09 | MOV_ARR | IR: `["MOV_ARR", "arr_x", "[", "v1", "v2", "]"]` | Init tmp + per-element mov + add |
| TC-CE-10 | CALL_INDIRECT | Indirect call IR | `"call $funvar;\n"` |

#### 4.2.5 Full Pipeline Integration Tests

| ID | Description | Input | Expected Output |
|---|---|---|---|
| TC-PI-01 | Empty IR | `{code_blocks: {global: {lbl_from: "start", lbl_to: "end"}}, scopes: {global: {vars: [], funcs: []}}}` | Valid empty assembly with just labels |
| TC-PI-02 | Single assignment (x = 5) | IR with MOV + OP | Assembly matching existing codegen output |
| TC-PI-03 | If-then-else | IR with IF/ELSE/END | Structured assembly with labels |
| TC-PI-04 | While loop | IR with WHILE | Looping assembly with labels |
| TC-PI-05 | Function call | IR with CALL + ENTER/LEAVE/RETURN | Full function prologue/epilogue |
| TC-PI-06 | Nested scopes | Multiple ENTER/LEAVE | Correct __ENTER/__LEAVE placeholders |
| TC-PI-07 | Array operations | ALLOC + MOV_ARR + INDEX | Array setup and element access |
| TC-PI-08 | Complex expression | Nested OP commands | Correct temporary management |

#### 4.2.6 Location Mapping Tests

| ID | Description | Input | Expected Outcome |
|---|---|---|---|
| TC-LM-01 | Single command location | MARK + emit + MARK | begin/end entries at correct offsets |
| TC-LM-02 | Sub-block translation | Nested code block | Translated locations offset by parent write_pos |
| TC-LM-03 | Multiple locations at same IP | Two commands same offset | Array with both LocationRanges |

---

### 4.3 Acceptance Criteria

The implementation SHALL be considered accepted when **all** of the following are true:

1. **AC-01**: All 30+ test cases in §4.2 pass with zero failures
2. **AC-02**: Output byte-identity (NFR-05): For each of the 10 test IR inputs in the regression suite, the new codegen output is byte-identical to the old codegen output
3. **AC-03**: Performance parity (NFR-01): The new codegen is NOT slower than the old codegen on the 10k-op benchmark (≤ 5% tolerance for variance)
4. **AC-04**: Zero GDScript lines added for new simple commands (NFR-04): Demonstrate by adding a new `NEG` operator with only template file changes
5. **AC-05**: Error reporting (NFR-06): Intentional template syntax errors produce human-readable file:line:col messages
6. **AC-06**: All 14 existing IR command types are handled without fallthrough to `push_error`

---

### 4.4 Regression Suite

The following 10 IR input files SHALL constitute the regression suite. Each SHALL have a saved "golden" assembly output from the current [`codegen_md.gd`](../scenes/codegen_md.gd).

| # | Test Input | Description | Generated From |
|---|---|---|---|
| RS-01 | `ir_simple_assign.yaml` | Single variable assignment | Manual test |
| RS-02 | `ir_arithmetic.yaml` | ADD/SUB/MUL/DIV operations | Manual test |
| RS-03 | `ir_comparisons.yaml` | All comparison operators | Manual test |
| RS-04 | `ir_if_else.yaml` | If-then-else chain | Manual test |
| RS-05 | `ir_while_loop.yaml` | Simple while loop | Manual test |
| RS-06 | `ir_func_call.yaml` | Function with arguments | Manual test |
| RS-07 | `ir_nested_scopes.yaml` | Multiple ENTER/LEAVE scopes | Manual test |
| RS-08 | `ir_array_ops.yaml` | Array allocation and access | Manual test |
| RS-09 | `ir_complex.yaml` | Combined constructs | Integration test |
| RS-10 | `ir_full_program.yaml` | Complete program IR | End-to-end test |

---

### 4.5 Performance Benchmarks

| Benchmark ID | Description | Metric | Target |
|---|---|---|---|
| PB-01 | Expand 10,000 simple MOV instructions | Total time (ms) | ≤ current |
| PB-02 | Expand 1,000 OP commands with register pressure | Total time (ms) | ≤ current |
| PB-03 | Load and parse 3 template files | Time (ms) | ≤ 50 ms |
| PB-04 | Expand 100 IF/ELSE chains | Total time (ms) | ≤ current |

---

### 4.6 Sign-Off

| Role | Name | Signature | Date |
|---|---|---|---|
| QA Lead | | | |
| Test Engineer | | | |
| Project Manager | | | |

---

## Phase 5: Maintenance Plan

**Document Status**: DRAFT — not yet signed off  
**Estimated effort to complete**: Ongoing  

---

### 5.1 Change Control Board (CCB)

Any change to the codegen system after Phase 4 sign-off SHALL follow this process:

1. **Change Request** submitted documenting: description, rationale, impact analysis, risk assessment
2. **CCB Review** (weekly): Architect + QA Lead + Implementation Lead review the request
3. **Approval/Rejection**: Change is approved, rejected, or deferred
4. **Implementation**: Approved changes go through the full waterfall cycle for their scope (Requirements → Design → Implementation → Verification)
5. **Documentation Update**: All affected documents (§§1-5) are updated

**CCB Members:**
- Lead Architect (chair)
- QA Lead
- Implementation Lead
- Project Manager (secretary)

---

### 5.2 Template Lifecycle

| State | Description | Transition |
|---|---|---|
| **Draft** | Template being designed, not in production | Design review → Candidate |
| **Candidate** | Template passes unit tests, staged in test environment | QA sign-off → Active |
| **Active** | Template is the current production version | Replacement → Deprecated |
| **Deprecated** | Template still present but scheduled for removal | Removal date → Retired |
| **Retired** | Template removed from codebase | n/a |

---

### 5.3 Versioning Strategy

- **Template data files** SHALL follow semantic versioning: `MAJOR.MINOR.PATCH`
  - MAJOR: Backward-incompatible template parameter changes
  - MINOR: New templates added
  - PATCH: Bug fixes to existing templates
- **Pipeline code** SHALL follow the project's existing versioning scheme
- The `version` field in template YAML files SHALL be checked at load time; a version mismatch SHALL produce a warning but NOT block loading

---

### 5.4 Support Procedures

| Scenario | Procedure | Responsible |
|---|---|---|
| Template load failure at startup | Log error; fall back to embedded defaults | Pipeline owner |
| Runtime template reload | Call `template_engine.reload_templates()` | Debug console |
| Regression in assembly output | Re-run regression suite (RS-01 through RS-10); diff against golden files | QA Lead |
| New IR command required | Write template → add command descriptor → run test suite (TC-CE-N) | Implementation Lead |
| Performance degradation | Run performance benchmarks (PB-01 through PB-04); profile bottleneck | Performance team |

---

## Appendices

### Appendix A: Glossary

| Term | Definition |
|---|---|
| **BDUF** | Big Design Up Front — a software development approach where comprehensive design precedes implementation |
| **CCB** | Change Control Board — governing body for post-deployment changes |
| **CodeBlock** | A named block of IR commands with entry/exit labels ([`class_CodeBlock.gd`](../class_CodeBlock.gd)) |
| **IR** | Intermediate Representation — the data structure representing program semantics before assembly generation |
| **IR_Cmd** | A single IR command consisting of a words array and a source location ([`class_IR_cmd.gd`](../class_IR_cmd.gd)) |
| **LocationMap** | A mapping from assembly byte offsets to source LocationRanges for debugging |
| **Template** | A parameterized assembly text pattern with `%param` substitution markers |
| **ZVM** | ZonVM — the custom CPU instruction set target ([`lang_zvm.gd`](../lang_zvm.gd)) |

### Appendix B: References

| Ref | Document | Location |
|---|---|---|
| R1 | Existing codegen implementation | [`scenes/codegen_md.gd`](../scenes/codegen_md.gd) |
| R2 | IR generation module | [`scenes/ir_md.gd`](../scenes/ir_md.gd) |
| R3 | ZVM instruction set definition | [`lang_zvm.gd`](../lang_zvm.gd) |
| R4 | Assembler module | [`scenes/comp_asm_zd.gd`](../scenes/comp_asm_zd.gd) |
| R5 | IR command data class | [`class_IR_cmd.gd`](../class_IR_cmd.gd) |
| R6 | IR value data class | [`class_IR_value.gd`](../class_IR_value.gd) |
| R7 | Code block data class | [`class_CodeBlock.gd`](../class_CodeBlock.gd) |
| R8 | Assembly block data class | [`class_AssyBlock.gd`](../class_AssyBlock.gd) |
| R9 | YAML parser | [`scenes/uYaml.gd`](../scenes/uYaml.gd) |

### Appendix C: Risk Register

| Risk ID | Description | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R-01 | Template engine is slower than hard-coded emit | Medium | High | Early performance benchmark (PB-01) during 3.2.4; optimize template cache if needed |
| R-02 | Storage allocation behavior diverges from current | Low | Critical | Comprehensive unit tests (TC-AL-*) comparing against saved allocation snapshots |
| R-03 | Template YAML schema is too rigid for complex commands | Medium | Medium | OP command uses `handler` pattern for complex expansion; templates cover simple cases |
| R-04 | Team unfamiliarity with waterfall process | Medium | Low | Detailed phase documentation; explicit sign-off gates prevent ambiguity |
| R-05 | Requirement change mid-implementation | Low (by design) | High | No mid-implementation changes; deferred to post-deployment via CCB |
| R-06 | Template file loading fails at runtime | Low | Medium | Embedded default templates as fallback; clear error logging |
| R-07 | Location mapping produces wrong offsets after pipeline refactor | Medium | Critical | Exhaustive location mapping tests (TC-LM-*) and regression suite RS-01..10 |
