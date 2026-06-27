# Unix Philosophy Codegen Plan

**Persona**: Unix Philosophy Advocate  
**Date**: 2026-06-27  
**Context**: Replace the ad-hoc [`codegen_md.gd`](../scenes/codegen_md.gd) (833 lines) with a pipeline of small, composable tools that communicate via text streams.

---

## 1. Diagnosis of the Current Codegen (Unix View)

The existing [`codegen_md.gd`](../scenes/codegen_md.gd) violates nearly every Unix principle:

| Violation | Location | Unix Critique |
|-----------|----------|---------------|
| **Does too many things** | Whole file (833 lines) | Parses IR, allocates vars, allocates registers, resolves operands, expands templates, emits assembly, tracks debug locations — all in one module. Violates "do one thing and do it well." |
| **No text-stream pipeline** | [`generate()`](../scenes/codegen_md.gd:143) | State is threaded through mutable globals (`all_syms`, `cur_assy_block`, `regs_in_use`) instead of passing text between stages. No stage can be tested or reused independently. |
| **Templates hardcoded in code** | [`op_map`](../scenes/codegen_md.gd:12) | Assembly templates are string literals embedded in source. Violates "data is data, code is code." Templates cannot be edited, versioned, or shared separately. |
| **Mixed debug and production** | [`ADD_DEBUG_TRACE`](../scenes/codegen_md.gd:7), [`ADD_IR_TRACE`](../scenes/codegen_md.gd:8) | Debug output branches on every emit call. Violates "rule of silence" — by default, the codegen should emit nothing but assembly. |
| **Side-effectful emit** | [`emit_raw()`](../scenes/codegen_md.gd:606) | Mutates `cur_assy_block.code` AND `cur_assy_block.write_pos` as side effects. A Unix filter reads input, writes output — it does not mutate hidden global state. |
| **String scanning on hot path** | [`find_reference()`](../scenes/codegen_md.gd:542) | Character-by-character scanning of template strings for `$`, `@`, `^` markers at emit time. Violates "simple and direct" — templates should be pre-compiled. |
| **Register allocator as hash map** | [`regs_in_use = {}`](../scenes/codegen_md.gd:32) | Four registers tracked with a dictionary. A 4-element bit vector or array is simpler, faster, and more Unix-like. |
| **Entangled IR ingestion** | [`deserialize()`](../scenes/codegen_md.gd:64) | Parses YAML AND inflates objects AND builds symbol table in one pass. Each of these should be a separate stage. |
| **No composable intermediate formats** | [`IR_Cmd`](../class_IR_cmd.gd), [`CodeBlock`](../class_CodeBlock.gd) | Data structures are Godot objects with methods. Can't pipe them between programs. Text is the universal interface. |

**Root cause**: The codegen is a monolith. Every feature is entangled with every other. There is no pipeline, no text interchange, no separation of concerns.

---

## 2. Unix Philosophy Foundation

### Core Principles Applied to Codegen

1. **Do One Thing and Do It Well**  
   Each stage of the codegen pipeline has exactly one responsibility. A stage reads text, transforms it, writes text. That's all.

2. **Text Is the Universal Interface**  
   Every intermediate format is line-oriented text. Stages communicate via text streams. You can pipe them together, redirect to files, or insert debugging stages (`tee`) anywhere in the pipeline.

3. **Pipeline Architecture**  
   The codegen is a series of small filters connected by pipes:
   ```
   IR (YAML) → ir2flat → sym_alloc → templ_expand → reg_resolve → line_assemble → assembly text
   ```
   Each stage reads from stdin, writes to stdout. No shared mutable state.

4. **Simplicity over Cleverness**  
   No reflection, no metaprogramming, no dynamic dispatch tables. Simple match/select statements. Flat data structures. Straight-line control flow.

5. **Rule of Silence**  
   The pipeline produces assembly text — and nothing else. No debug comments, no trace output, no status messages. Silence is the default. Errors go to stderr.

6. **Composability**  
   Each stage is a self-contained script. You can run stages in isolation for testing. You can replace any stage with an alternative implementation. You can insert filters (e.g., `grep`, `sed`, `awk`) between stages.

7. **Data Is Data, Code Is Code**  
   Templates are data files (TSV/CSV), not string literals in source code. The instruction set definition is a data file, not a GDScript dictionary. Configuration is data.

8. **Write Programs That Handle Text Streams**  
   Every stage reads lines from stdin and writes lines to stdout. Input is line-oriented. Output is line-oriented. No binary protocols, no object graphs, no in-memory databases.

---

## 3. Architecture Overview

### Pipeline Diagram

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  IR YAML    │────▶│  ir2flat    │────▶│  sym_alloc  │────▶│ templ_expand │────▶│ reg_resolve  │────▶│ line_asm     │
│  (from      │     │             │     │             │     │              │     │              │     │              │
│   ir_md.gd) │     │ flattens IR │     │ assigns     │     │ expands IR   │     │ resolves $ @ │     │ assembles    │
│             │     │ to line-    │     │ storage for │     │ commands via │     │ ^ markers    │     │ text into    │
│             │     │ oriented    │     │ vars/funcs  │     │ templates    │     │ & registers  │     │ final asm    │
│             │     │ text format │     │              │     │              │     │              │     │              │
└─────────────┘     └─────────────┘     └─────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
                              │                 │                  │                   │                    │
                         stdout→stdin      stdout→stdin       stdout→stdin        stdout→stdin         stdout→stdin
```

### Stage Descriptions

#### Stage 1: [`ir2flat`](../scenes/codegen_ir2flat.gd) — IR Flattener

**Input**: YAML text from [`ir_md.gd`](../scenes/ir_md.gd) serialization  
**Output**: Line-oriented flat IR format (one line per command)  
**Responsibility**: Deserialize YAML and emit flat text IR. No allocation, no symbol table building.

**Output format** (tab-separated):
```
# columns: block_id, cmd_index, opcode, operands..., source_location
cmd	cb_0	0	MOV	var_1	imm_2	"test.md:12:5"
cmd	cb_0	1	OP	ADD	var_1	var_2	var_3	"test.md:13:3"
cmd	cb_0	2	IF	cb_1	var_3	cb_2	"test.md:15:2"
scope	scp_0	global	none
scope	scp_1	my_func	scp_0
val	scp_0	var_1	variable	int	stack	0
val	scp_1	func_1	func	code	cb_0
```

Each line is self-describing with a type tag (`cmd`, `scope`, `val`). This format can be grepped, sorted, filtered with standard Unix tools.

**Why this exists**: The YAML IR is a serialization format. The codegen should not parse YAML — that's a separate concern. This stage is the adapter between serialization and the pipeline.

---

#### Stage 2: [`sym_alloc`](../scenes/codegen_sym_alloc.gd) — Symbol Allocator

**Input**: Flat IR from [`ir2flat`](../scenes/codegen_ir2flat.gd) (stdin)  
**Output**: Flat IR with storage assignments annotated (stdout)  
**Responsibility**: Walk scopes, assign global/stack storage positions to all variables and temporaries. Pure text filter.

**Algorithm**:
1. First pass: collect all `scope` and `val` lines into a symbol table (in memory — but flat arrays, not dictionaries of objects)
2. Second pass: assign storage positions:
   - Global scope variables → global labels
   - Non-global scope variables → stack offsets (EBP-relative)
   - Arguments → positive stack offsets
   - Functions → code labels
3. Third pass: emit each input line, appending storage info to `val` lines

**Output** (appends storage column):
```
val	scp_0	var_1	variable	int	stack	0	global	var_1
val	scp_1	arg_0	variable	int	arg	0	stack	9
val	scp_1	local_0	variable	int	stack	0	stack	-3
```

**Why this exists**: Storage allocation is a well-defined transformation on the symbol table. Making it a separate stage means it can be tested independently and replaced (e.g., with a register coloring allocator).

---

#### Stage 3: [`templ_expand`](../scenes/codegen_templ_expand.gd) — Template Expander

**Input**: Flat IR with storage (from [`sym_alloc`](../scenes/codegen_sym_alloc.gd)) + template data file(s)  
**Output**: Semi-resolved assembly text with `$`, `@`, `^` markers still present  
**Responsibility**: Map each IR opcode to its assembly template, substitute IR operands into template slots.

**Core data: template file** ([`templates/templates.tsv`](../templates/templates.tsv)):
```
# Opcode	Template							Size
MOV		mov $dest, $src;\n					cmd_size
ADD		add $a, $b;\n						cmd_size
SUB		sub $a, $b;\n						cmd_size
IF		$cond\ncmp $res, 0;\njz $else_lbl;\n$body\njmp $end_lbl;\n$else_lbl:\n		calculated
CALL	$push_args\ncall @$fun;\nadd ESP, $stack_size;\nmov ^$res, EAX;\n	calculated
```

Templates are **pure data**. They live in a text file. They can be edited, versioned, and reviewed without touching code.

**Template syntax**:
- `$name` — value reference (will be resolved to a register or memory address by [`reg_resolve`](../scenes/codegen_reg_resolve.gd))
- `@name` — address reference (label name)
- `^name` — store reference (destination for writes)
- `$cond`, `$body`, `$else_lbl`, `$end_lbl` — template-local variables (substituted by the expander, not by [`reg_resolve`](../scenes/codegen_reg_resolve.gd))

**Expansion algorithm** (pseudocode):
```
for each cmd line from stdin:
    opcode = cmd[3]
    template = lookup(opcode, templates.tsv)
    if template is simple (one-line):
        emit template with IR operands substituted for $N references
    if template is complex (IF, CALL, etc.):
        emit multi-line expansion using template-local variables
```

**Why this exists**: Separating templates from code is the core Unix data/code distinction. The template format is simple text. The expander is a simple text filter.

---

#### Stage 4: [`reg_resolve`](../scenes/codegen_reg_resolve.gd) — Register Resolver

**Input**: Semi-resolved assembly (from [`templ_expand`](../scenes/codegen_templ_expand.gd)) + symbol table (from [`sym_alloc`](../scenes/codegen_sym_alloc.gd))  
**Output**: Fully resolved assembly text (all `$`, `@`, `^` markers replaced with register/memory references)  
**Responsibility**: Allocate registers for temporary values, resolve `$` (load), `@` (address), `^` (store) references to concrete assembly operands.

**Algorithm**:
```
for each line from stdin:
    if line contains $ref:
        look up ref in symbol table
        if ref is immediate: replace $ref with literal value
        if ref is global:    replace $ref with *label_name
        if ref is stack:     replace $ref with EBP[offset]
        if ref is temporary: allocate register, replace $ref with register name
    if line contains @ref:
        replace @ref with label name (address)
    if line contains ^ref:
        replace ^ref with store-to memory reference
    if line uses register (EAX, EBX, etc.):
        mark register as in-use for this line
    emit resolved line
```

**Register allocator**: Simple linear-scan with 4 registers (EAX, EBX, ECX, EDX). Tracked as a 4-element array of booleans, not a dictionary. On exhaustion, spill to stack temporaries.

**Why this exists**: Register allocation is a distinct concern from template expansion. By separating them, each stage is simpler, and the register allocator can be replaced (e.g., with a graph-coloring allocator) without touching template logic.

---

#### Stage 5: [`line_asm`](../scenes/codegen_line_asm.gd) — Line Assembler

**Input**: Fully resolved assembly text (from [`reg_resolve`](../scenes/codegen_reg_resolve.gd))  
**Output**: Final assembly text, ready for the existing assembler ([`comp_asm_zd.gd`](../scenes/comp_asm_zd.gd))  
**Responsibility**: Collect resolved lines into a coherent assembly string. Minimal — just concatenation with correct ordering.

**Why this exists**: Every stage before this has been a text filter. This is the final output stage. Keeping it separate means you can redirect the pipeline output at any point before this stage.

---

### End-to-End Invocation

```gdscript
# In the compile pipeline (comp_compile_md.gd or equivalent):
func run_codegen_pipeline(ir_yaml: String) -> String:
    var p1 = ir2flat(ir_yaml)           # Stage 1: YAML → flat IR
    var p2 = sym_alloc(p1)               # Stage 2: assign storage
    var p3 = templ_expand(p2, templates) # Stage 3: expand templates
    var p4 = reg_resolve(p3)             # Stage 4: resolve registers
    var p5 = line_asm(p4)               # Stage 5: final assembly
    return p5

# Each stage is also callable standalone:
# ir2flat("input.yaml") → flat text
# sym_alloc("flat_ir.txt") → flat IR with storage
```

In a true Unix environment, these would be shell commands:
```bash
cat ir_program.yaml | ir2flat | sym_alloc | templ_expand templates.tsv | reg_resolve | line_asm > output.asm
```

In Godot, they are separate GDScript nodes/scripts, each exposing a single `transform(input: String) -> String` method.

---

## 4. Template Engine Specification

### Template Data Format ([`templates/templates.tsv`](../templates/templates.tsv))

A tab-separated file with columns:
1. **opcode** — IR command name (e.g., `MOV`, `ADD`, `IF`, `CALL`)
2. **template** — assembly template string
3. **size** — size in bytes, or `calculated` for multi-line expansions
4. **flags** — optional: `mono` for unary ops, `cond` for conditional, etc.

**Simple templates** (one IR command → one assembly line):
```
MOV		mov ^dest, $src;\n	8
ADD		add $a, $b;\n		8
PUSH	push $val;\n		8
RET		ret;\n			8
CALL	call @fun;\n		8
```

**Compound templates** (one IR command → multiple assembly lines):
```
IF	$cond\ncmp $res, $zero;jz $else_lbl;\n$body\njmp $end_lbl;\n$else_lbl:\n	calculated	control
WHILE	$next_lbl:\n$cond\ncmp $res, $zero;jz $end_lbl;\n$body\njmp $next_lbl;\n$end_lbl:\n	calculated	control
CALL	$push_args\ncall @$fun;\nadd ESP, $4*nargs;\nmov ^$res, EAX;\n	calculated
```

**Op-specific templates** (complex operations like `GREATER`, `EQUAL`):
```
GREATER	cmp $a, $b; mov $a, CTRL; band $a, CMP_G; bnot $a; bnot $a;\n	32
EQUAL	cmp $a, $b; mov $a, CTRL; band $a, CMP_Z; bnot $a; bnot $a;\n	32
```

### Template Variable Substitution

Variables in templates are bracketed with sigils:
- `$name` — **load** the value at this reference into a register, then substitute the register name
- `@name` — **address** of the value (label name or EBP+offset expression)
- `^name` — **store** to the value at this reference (write destination)
- `$name` (no sigil change) — for template-local variables like `$cond`, `$body`, `$else_lbl`, these are substituted by the expander, not the resolver

### Template Pre-compilation

On pipeline startup, [`templ_expand`](../scenes/codegen_templ_expand.gd) reads [`templates/templates.tsv`](../templates/templates.tsv) and builds an in-memory lookup (flat array indexed by opcode ID, not a dictionary). This is **not** a runtime string scan — it's a one-time load.

---

## 5. Data Flow Through the Pipeline

### Example: Compiling `a = b + c`

**Input IR (YAML)**:
```yaml
scopes:
  scp_0:
    user_name: global
    parent: none
    vars:
      - [var_1, variable, a, int, NULL, NULL, NULL, NULL, NULL, 0, 0]
      - [var_2, variable, b, int, NULL, NULL, NULL, NULL, NULL, 0, 0]
      - [var_3, variable, c, int, NULL, NULL, NULL, NULL, NULL, 0, 0]
code_blocks:
  cb_0:
    lbl_from: lbl_f_0
    lbl_to: lbl_t_0
    code:
      - [MOV, var_1, var_3, "test.md:10:2"]
      - [OP, ADD, var_2, var_3, var_1, "test.md:10:5"]
```

**Stage 1: [`ir2flat`](../scenes/codegen_ir2flat.gd)** → Flat IR:
```
scope	scp_0	global	none
val	scp_0	var_1	variable	int	NULL		NULL		a
val	scp_0	var_2	variable	int	NULL		NULL		b
val	scp_0	var_3	variable	int	NULL		NULL		c
block	cb_0	lbl_f_0	lbl_t_0
cmd	cb_0	0	MOV	var_1	var_3	"test.md:10:2"
cmd	cb_0	1	OP	ADD	var_2	var_3	var_1	"test.md:10:5"
```

**Stage 2: [`sym_alloc`](../scenes/codegen_sym_alloc.gd)** → Flat IR with storage:
```
scope	scp_0	global	none
val	scp_0	var_1	variable	int	global	var_1	a
val	scp_0	var_2	variable	int	global	var_2	b
val	scp_0	var_3	variable	int	global	var_3	c
block	cb_0	lbl_f_0	lbl_t_0
cmd	cb_0	0	MOV	var_1	var_3	"test.md:10:2"
cmd	cb_0	1	OP	ADD	var_2	var_3	var_1	"test.md:10:5"
```

**Stage 3: [`templ_expand`](../scenes/codegen_templ_expand.gd)** → Semi-resolved assembly:
```
# Begin code block cb_0
:lbl_f_0:
mov ^var_1, $var_3;
# OP ADD var_2 var_3 var_1
mov $tmp_1, $var_2;
add $tmp_1, $var_3;
mov ^var_1, $tmp_1;
:lbl_t_0:
```

**Stage 4: [`reg_resolve`](../scenes/codegen_reg_resolve.gd)** → Resolved assembly:
```
# Begin code block cb_0
:lbl_f_0:
mov *var_1, *var_3;
# OP ADD var_2 var_3 var_1
mov EAX, *var_2;
add EAX, *var_3;
mov *var_1, EAX;
:lbl_t_0:
```

**Stage 5: [`line_asm`](../scenes/codegen_line_asm.gd)** → Final assembly text:
```
:lbl_f_0:
mov *var_1, *var_3;
mov EAX, *var_2;
add EAX, *var_3;
mov *var_1, EAX;
:lbl_t_0:
```

---

## 6. Unix Tooling and Composability

### Debugging the Pipeline

Because every stage is a text filter, you can **insert debugging anywhere**:

```gdscript
# Insert a "tee" stage to inspect pipeline state:
func debug_stage(label: String, text: String) -> String:
    print("=== %s ===" % label)
    print(text)
    return text

var p1 = ir2flat(ir_yaml)
var p1_dbg = debug_stage("After ir2flat", p1)
var p2 = sym_alloc(p1_dbg)
# ... etc.
```

### Testing Stages in Isolation

```gdscript
# Test sym_alloc with crafted input:
func test_sym_alloc_globals():
    var input = "scope\tscp_0\tglobal\tnone\n"
    input += "val\tscp_0\tx\tvariable\tint\tNULL\t\tx\n"
    var expected = "scope\tscp_0\tglobal\tnone\n"
    expected += "val\tscp_0\tx\tvariable\tint\tglobal\tx\tx\n"
    assert(sym_alloc(input) == expected)
```

### Replacing Stages

Want a better register allocator? Write a new [`reg_resolve`](../scenes/codegen_reg_resolve.gd) that reads the same flat IR format. Drop it in. No other stage changes.

Want to add optimization passes? Insert them between existing stages:
```
ir_yaml → ir2flat → opt_peephole → sym_alloc → opt_dead_code → templ_expand → reg_resolve → line_asm
```

### Using Standard Unix Tools (When Migrating to Shell)

In a shell pipeline, you could use standard tools:
```bash
# Grep for all MOV commands in the IR:
cat ir_flat.txt | grep '^cmd.*MOV'

# Count commands per block:
cat ir_flat.txt | grep '^cmd' | cut -f2 | sort | uniq -c

# Sort blocks by command count:
cat ir_flat.txt | grep '^cmd' | cut -f2 | sort | uniq -c | sort -rn
```

---

## 7. File Layout

```
scenes/
├── codegen_ir2flat.gd       # Stage 1: IR YAML → flat text
├── codegen_sym_alloc.gd     # Stage 2: storage assignment
├── codegen_templ_expand.gd  # Stage 3: template expansion
├── codegen_reg_resolve.gd   # Stage 4: register allocation & resolution
├── codegen_line_asm.gd      # Stage 5: final assembly output
├── codegen_pipeline.gd      # Orchestrator: connects stages
templates/
├── templates.tsv            # Assembly template data file
```

### Stage Interface Contract

Every stage file implements exactly one public method:

```gdscript
# Each stage is a Node with a single transform function:
func transform(input: String) -> String:
    # Read input (text lines)
    # Process (one well-defined transformation)
    # Write output (text lines)
    pass
```

No globals. No mutable state. No side effects. Input is a string, output is a string.

### Pipeline Orchestrator ([`codegen_pipeline.gd`](../scenes/codegen_pipeline.gd))

```gdscript
extends Node

@export var stage_ir2flat: Node
@export var stage_sym_alloc: Node
@export var stage_templ_expand: Node
@export var stage_reg_resolve: Node
@export var stage_line_asm: Node

func generate(ir_yaml: String) -> String:
    var flat      = stage_ir2flat.transform(ir_yaml)
    var allocated = stage_sym_alloc.transform(flat)
    var expanded  = stage_templ_expand.transform(allocated)
    var resolved  = stage_reg_resolve.transform(expanded)
    var assembly  = stage_line_asm.transform(resolved)
    return assembly
```

The orchestrator does **nothing** but connect stages. It is the pipeline — a series of pipes. Its entire existence is composability.

---

## 8. Migration Strategy

### Phase 1: Extraction (Minimal Change)
1. Extract [`ir2flat`](../scenes/codegen_ir2flat.gd) by pulling deserialization out of [`codegen_md.gd`](../scenes/codegen_md.gd) 
2. Keep the old codegen working via a compatibility wrapper that calls [`ir2flat`](../scenes/codegen_ir2flat.gd) then the old monolithic codegen
3. Verify output is identical

### Phase 2: Template Extraction
1. Move [`op_map`](../scenes/codegen_md.gd:12) from code to `templates/templates.tsv`
2. Write [`templ_expand`](../scenes/codegen_templ_expand.gd) to read the TSV and expand templates
3. Test against existing output

### Phase 3: Storage and Register Separation
1. Extract [`sym_alloc`](../scenes/codegen_sym_alloc.gd) from [`allocate_vars()`](../scenes/codegen_md.gd:642)
2. Extract [`reg_resolve`](../scenes/codegen_reg_resolve.gd) from [`emit()`](../scenes/codegen_md.gd:474) and [`find_reference()`](../scenes/codegen_md.gd:542)
3. Wire them into the pipeline

### Phase 4: Deprecation
1. Once all stages are separated and tested, remove the old [`codegen_md.gd`](../scenes/codegen_md.gd)
2. The pipeline [`codegen_pipeline.gd`](../scenes/codegen_pipeline.gd) is the sole codegen entry point
3. Zero global mutable state. Zero side effects. Each stage is a pure text filter.

---

## 9. Verification

### Correctness
- Each stage has a test harness that feeds known input and checks output
- Integration test runs the full pipeline on every test program in `res/data/`
- Output comparison against the old codegen (Phase 1-3) or against the assembler (Phase 4)

### Performance
- Pipeline overhead is negligible (each stage is a string → string transform)
- Template loading is one-time, not per-command
- Register allocation is a 4-element linear scan, not a dictionary
- String scanning in templates is eliminated (templates are pre-loaded and indexed)

### Composability
- Each stage can be replaced independently
- New stages (optimization, debugging, profiling) can be inserted anywhere in the pipeline
- The pipeline can be reconfigured without code changes (via Godot's `@export` references)
