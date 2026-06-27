# Synthesis Report — Unified Codegen Architecture

**Synthesizer Agent**  
**Date**: 2026-06-27  
**Purpose**: Extract the most-approved features across all 10 persona critiques and design a single cohesive architecture acceptable to every persona.

---

## Section 1: Feature Approval/Disapproval Matrix

The matrix below tabulates which features from the 10 codegen plans received the most **approval** (✓) or **disapproval** (✗) from the other 9 personas. A blank cell means neutral/no strong opinion was expressed.

| Feature / Design Element | Func Pure | Data-Oriented | Unix | TDD | XP | GoF | Literate | Agile | Waterfall | Lisp |
|---|---|---|---|---|---|---|---|---|---|---|
| **Data-driven templates** (tables, not code) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ |
| **Pipeline architecture / pass separation** | ✓ | ~ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Pure functions & immutability** | ✓ | ✗ | ✓ | ✓ | ~ | ✓ | ~ | ~ | ✗ | ✓ |
| **Incremental migration** (one-command-at-a-time) | ✗ | ✗ | ~ | ✓ | ✓ | ✗ | ~ | ✓ | ✗ | ~ |
| **Golden file regression suite** | ✗ | ✗ | ~ | ✓ | ✓ | ✗ | ✗ | ✓ | ✓ | ~ |
| **Characterization tests before changes** | ✗ | ✗ | ~ | ~ | ✓ | ✗ | ~ | ✓ | ✓ | ✗ |
| **Template table as const data** | ✓ | ~ | ✓ | ✓ | ✓ | ~ | ✓ | ~ | ~ | ✓ |
| **Small focused components** | ✓ | ~ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✓ |
| **Text-stream / grepable intermediates** | ✗ | ✗ | ✓ | ✗ | ~ | ✗ | ✓ | ✗ | ✗ | ✗ |
| **Flat arrays / SoA for hot path** | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ~ | ✗ | ✗ |
| **Strategy pattern for allocators** | ~ | ✗ | ✓ | ✓ | ~ | ✓ | ✗ | ~ | ✓ | ✓ |
| **Test oracle / cross-validation** | ✗ | ✗ | ~ | ✓ | ✓ | ✗ | ✗ | ✓ | ✓ | ~ |
| **Template bytecode (pre-compiled)** | ~ | ✓ | ✓ | ✗ | ✗ | ~ | ✗ | ~ | ✗ | ~ |
| **Declarative template schema (YAML/TSV)** | ~ | ~ | ✓ | ~ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| **Dependency injection** | ✓ | ✗ | ~ | ✓ | ✓ | ✓ | ✗ | ~ | ✗ | ~ |
| **Homoiconic / S-expression templates** | ~ | ✗ | ✗ | ✗ | ✗ | ~ | ✓ | ✗ | ✗ | ✓ |
| **Metaprogramming / macro-generating macros** | ✓ | ✗ | ✗ | ✗ | ✗ | ~ | ~ | ✗ | ✗ | ✓ |
| **Mutable global static state** | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Big-bang rewrite (no incrementality)** | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Over-engineering / pattern injection** | ✗ | ✗ | ✗ | ~ | ✗ | ✗ | ~ | ✗ | ✗ | ✗ |
| **String-based templates with markers** | ~ | ✗ | ✗ | ✗ | ✗ | ✗ | ~ | ✗ | ✗ | ✗ |
| **Deep object indirection (cache-hostile)** | ✗ | ✗ | ✗ | ~ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Frozen specifications / BDUF** | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Tangle/weave tooling dependency** | ~ | ✗ | ✗ | ✗ | ✗ | ✗ | ~ | ✗ | ✗ | ~ |
| **Text serialization between stages** | ~ | ✗ | ✓ | ✗ | ✗ | ✗ | ~ | ✗ | ✗ | ✗ |

**Legend**: ✓ = Approved / Endorsed | ✗ = Criticized / Disapproved | ~ = Neutral or conditionally accepted

---

## Section 2: Most-Approved Features (Top 10)

### 1. Data-Driven Templates (Approved by: ALL 10 personas)
**Unanimous agreement.** Every single plan and critique endorses moving the IR→assembly mapping from procedural code (the current `op_map` / giant `match` statement) into declarative data structures. The debate is only about *format* (const dicts, YAML, TSV, S-expressions), not the principle.

**Why it wins**: Every persona recognizes that hardcoding template logic in GDScript procedures is the root cause of the 833-line `codegen_md.gd` monolith. Separating data from code simplifies testing (TDD, XP), enables collective ownership (Agile, XP), provides inspectability (Unix, Literate), and enables data-oriented optimization (DOD).

### 2. Pipeline / Pass Architecture (Approved by: 9 out of 10 — Functional Purity, Unix, XP, TDD, GoF, Literate, Agile, Waterfall, Lisp)
**Near-unanimous.** Breaking the codegen into sequential stages with well-defined interfaces is endorsed by all but DOD (which uses a batch three-pass model that is criticized as rigid).

**Why it wins**: Pipeline architecture is the only decomposition strategy that simultaneously satisfies separation-of-concerns (GoF, Unix), incremental testability (TDD, XP), sprint-ability (Agile), and data-flow clarity (Literate, Lisp). The Lisp critic explicitly called the XP plan's pipeline "the most XP-compatible architecture," and the GoF critic rated it 10/10 for separation of concerns.

### 3. Pure Functions / Immutability Discipline (Approved by: 7 of 10 — Func Pure, Unix, TDD, GoF, Literate, Lisp, Agile (partially))
A strong cross-cutting consensus. Even personas who don't enforce pure FP (XP, GoF) acknowledge that eliminating mutable global state is essential.

**Why it wins**: The current codegen's 11 mutable module-level variables are cited by every persona as the #1 problem. The Unix critic praised its `String → String` contract. The TDD critic praised pure function testability. The GoF critic praised `Environment` as a Memento pattern. The Lisp critic praised referential transparency for macro expansion.

### 4. Incremental Migration (One IR Command at a Time) (Approved by: 5 of 10 — XP, TDD, Agile, Unix (partial), Literate (partial))
**Strong cluster endorsement from process-oriented personas.** XP's 6-sprint migration plan earned a 9/10 from the Agile critic and the label "gold standard for Agile codegen replacement."

**Why it wins**: The biggest practical risk is breaking existing functionality. Incremental migration mitigates this completely — every sprint produces identical output, tested by golden files. The Functional Purity, Data-Oriented, Design Patterns, and Waterfall plans were all criticized for requiring big-bang rewrites.

### 5. Golden File Regression Suite (Approved by: 5 of 10 — TDD, XP, Agile, Waterfall, Unix (partial))
**Safety net for refactoring.** The practice of capturing expected output and comparing against it is endorsed by all quality-conscious personas.

**Why it wins**: The Agile critic gave Epic A (Characterization + Golden Files) the highest marks. The TDD critic praised "bit-exact comparison test." The Waterfall critic acknowledged it as the only viable regression strategy. The XP plan's golden-file comparison was called "a powerful safety net."

### 6. Template Table as Static Const Data (Approved by: 8 of 10 — Func Pure, Unix, TDD, XP, Literate, Lisp, Data-Oriented (partial), GoF (partial))
**Strong agreement that template definitions should be compile-time data, not runtime-parsed files.**

**Why it wins**: Static const dictionaries are zero-overhead at runtime, type-checkable in GDScript, and require no file I/O during codegen. The Literate plan's `const template_table` and the XP plan's `template_table` Dictionary were praised by the GoF critic for their OCP compliance.

### 7. Small, Focused Components (Approved by: 8 of 10 — Func Pure, Unix, XP, TDD, GoF, Literate, Waterfall, Agile (partial))
**Single Responsibility Principle is universally valued.**

**Why it wins**: The Unix critic's evaluation criteria specifically includes "Does One Thing Well." The GoF critic rates this as 10/10 for the XP plan. The TDD critic's 12-increment structure naturally produces focused units. However, the GoF plan's extreme atomization (30 files) was criticized as going too far — quality over quantity.

### 8. Characterization Tests Before Changes (Approved by: 4 of 10 — XP, Agile, TDD (partial), Waterfall (partial))
**A smaller but passionate consensus.** Only the Agile/Scrum plan's Epic A explicitly proposes characterizing current behavior before making changes, and it was praised by the XP critic as "critical XP practice."

**Why it wins**: The XP opinion states: "you cannot refactor safely without knowing what the system currently does." The Waterfall critic acknowledged this even though Waterfall approaches it through specification rather than testing.

### 9. Pre-compiled Template Bytecode (Approved by: 4 of 10 — DOD, Unix, Agile, Lisp (partial))
**Performance-oriented consensus.** Compiling templates to flat opcode arrays eliminates string scanning at emit time.

**Why it wins**: The DOD plan's bytecode (`EmitOp.TEXT`, `EmitOp.LOAD`, etc.) was praised by the Unix critic as "eliminating string scanning at emit time." The Lisp critic viewed it as a form of "staged computation." The Agile plan's story C-3 specifically calls for this.

### 10. Declarative External Template Format (Approved by: 7 of 10 — Unix, XP, GoF, Literate, Agile, Waterfall, Lisp (partial))
Templates should be editable without modifying GDScript code. The format debate (TSV vs YAML vs const dicts) is secondary to the principle.

**Why it wins**: The Unix plan's TSV files were called "beautiful in its simplicity" by the XP critic. The Agile, Waterfall, and GoF plans all use YAML. The Literate plan uses const dicts embedded in source. The principle of *data not code* for template definitions is near-universal.

---

## Section 3: Most-Disapproved Features (Bottom 10)

### 1. Global Static Mutable State (Criticized by: ALL 10 personas)
**Unanimous rejection.** The current codegen's 11 mutable module-level variables are condemned by every single persona, including the DOD advocate (whose own plan uses `static var` arrays).

**Why it loses**: Every evaluation criterion — testability (TDD), purity (FP), cache-friendliness (DOD), composability (Unix), encapsulation (GoF), team ownership (XP), reliability (Waterfall) — is violated by global mutable state. It prevents parallel testing, makes data flow untraceable, and couples all components.

### 2. Big-Bang Rewrite / No Incremental Path (Criticized by: 7 of 10 — XP, Agile, TDD, Unix, Functional Purity (criticized scheme), GoF (criticized), Waterfall (criticized))
**Strong rejection of "build it all and flip the switch."** Plans that lack an incremental migration strategy were consistently downgraded.

**Why it loses**: The XP critic gave the Data-Oriented plan its lowest score for requiring "the entire IR representation [to be] converted from object-graph to SoA before the first template works." The Agile critic similarly penalized functional purity ("no working software until Phase 4").

### 3. Over-Engineering / Pattern Injection (Criticized by: 6 of 10 — XP, Unix, TDD, Agile, DOD, Literate)
**Gold-plating is universally recognized as harmful.** Plans that introduce unnecessary complexity — especially the GoF plan's 30 classes and the Lisp plan's macro engine — were criticized.

**Why it loses**: The XP critic's verdict on GoF: "worst plan for this problem. 30+ files to do what 5 pipeline stages can do." The Unix critic gave GoF a -2 for simplicity. The Waterfall critic noted the GoF plan "specifies the container but not the contents." The Agile critic called it "architectural over-indulgence."

### 4. String-Based Templates with Opaque Markers (Criticized by: 5 of 10 — Lisp, DOD, Functional Purity, Unix (partial), TDD (partial))
**Structural criticism from data-oriented and Lisp personas.** Templates that use `$1`, `^2`, `@dest` string markers are viewed as a partial solution.

**Why it loses**: The Lisp critic's central argument is that "every plan except the Lisp plan treats templates as strings with placeholders rather than as structured data." The DOD critic notes that `body.replace()` for slot substitution allocates a new string per slot. The Functional Purity critic favors structured data records over string parsing.

### 5. Deep Object Indirection / Cache-Hostile AoS (Criticized by: 4 of 10 — DOD, GoF (criticized other plans), TDD, Literate)
**Performance-oriented critique.** Plans that use deep object graphs (nested Dictionaries, Visitor dispatch, Decorator chains) were flagged for poor data locality.

**Why it loses**: The DOD critic provided detailed cache-miss analysis for each plan. The GoF plan's 8,000 heap objects for 1,000 IR commands was called "abysmal" for CPU-friendly access. The Functional Purity plan's `AssemblyResult` Dictionary with 6 fields was criticized as a "memory allocation storm."

### 6. Dictionary-Based Symbol Tables (Criticized by: 4 of 10 — DOD, TDD, XP, Agile)
**Hash map overhead is recognized but not universally prioritized.** Personas focused on performance and data layout flag the Dictionary symbol table as a scatter problem.

**Why it loses**: The DOD critic's analysis is most thorough: "hash-map-overkill" for 4-register state tracking, "cache-oblivious lookups" for symbol resolution. The Agile plan explicitly includes story C-1 "Flat Symbol Table" to address this, but marks it P1 (deferrable).

### 7. Tangle/Weave Toolchain Dependency (Criticized by: 4 of 10 — XP, Agile, Unix, DOD)
**Process overhead that creates friction.** The literate programming workflow requires specialized tools that add a build dependency.

**Why it loses**: The XP critic called it "a build-time dependency that must be maintained" and "a two-source-of-truth problem." The Agile critic noted the tangle tool "adds project risk." The literate plan's own critic acknowledged "the irony" that none of the plans achieve true literate programming.

### 8. Frozen Specifications / No Adaptability (Criticized by: 6 of 10 — Agile, XP, TDD, Lisp, Functional Purity, GoF)
**BDUF rigidity is rejected by the majority.** The Waterfall plan's sign-off gates and Change Control Board were universally condemned.

**Why it loses**: The XP critic called it "anathema to XP." The Agile critic gave it 0/10. The GoF critic noted that OCP is violated by frozen catalog + CCB. Even the Waterfall critic's own evaluation acknowledges that this is "the most rigid plan."

### 9. Text Serialization Overhead Between Stages (Criticized by: 4 of 10 — DOD, Lisp, Unix (self-aware), Functional Purity)
**Performance tax for inspectability.** The Unix plan's text-stream intermediate format is praised for debuggability but criticized for creating serialization/deserialization overhead at every stage boundary.

**Why it loses**: The DOD critic calculated that "every IR command passes through at least 3 string formatting + parsing cycles" in the Unix pipeline. The Lisp critic noted that S-expressions are passed by reference with no parsing overhead.

### 10. Metaprogramming Without Language Support (Criticized by: 5 of 10 — XP, Agile, Unix, DOD, TDD)
**Implementing Lisp in GDScript is viewed as overreach.** The Lisp plan's macro engine, pattern matcher, and quasiquote machinery were praised for elegance but criticized for GDScript impracticality.

**Why it loses**: The XP critic: "GDScript does not have macros, quasiquotation, or pattern matching. The plan must reimplement all of this." The Agile critic called the GDScript-Lisp mismatch "the biggest risk." The Waterfall critic noted the "heavy scaffolding in GDScript."

---

## Section 4: Consensus Architecture

Based on the feature approval/disapproval analysis above, here is a single synthesized architecture that incorporates the most-approved features while avoiding the most-disapproved ones.

### 4.1 Design Tenets (Non-Negotiable)

1. **Zero global mutable state.** All state is either local to a pass, passed as parameters, or returned as results.
2. **Pipeline of passes with clear interfaces.** Each pass is an independent transformation.
3. **Data-driven templates.** IR→assembly mapping is declarative data, not procedural code.
4. **Incremental migration.** Replace one IR command at a time, keeping golden-file tests green.
5. **Golden file regression as the primary safety net.** Every change is validated against known-correct output.
6. **Characterization tests before changes.** Capture current behavior before modifying anything.

### 4.2 Data Model

```
╔══════════════════════════════════════════════════════════╗
║                   Data Model Overview                    ║
╠══════════════════════════════════════════════════════════╣
║                                                          ║
║  Layer 1: Template Definitions (Pure Data)               ║
║  ┌──────────────────────────────────────────────────┐    ║
║  │  template_table: Dictionary[String, Template]     │    ║
║  │  Template = {                                    │    ║
║  │    pattern: Array[String],       // e.g. ["MOV","dest","src"]│
║  │    slots: Dictionary,            // named bindings │    ║
║  │    assembly: Array[String],     // lines w/ {name}│    ║
║  │    size: int,                   // bytes per line  │    ║
║  │    guard: Callable?             // pre-condition   │    ║
║  │  }                                                │    ║
║  └──────────────────────────────────────────────────┘    ║
║                                                          ║
║  Layer 2: Intermediate Representations                   ║
║  ┌──────────────────────────────────────────────────┐    ║
║  │  FlatIR = {                                      │    ║
║  │    ops: Array[FlatOp],  // flat command array     │    ║
║  │    syms: SymTable,      // symbol table           │    ║
║  │  }                                                │    ║
║  │  FlatOp = {                                       │    ║
║  │    op: String,   words: Array[String],            │    ║
║  │    loc: LocationRange                             │    ║
║  │  }                                                │    ║
║  │  SymTable = {                                     │    ║
║  │    ir_name: PackedStringArray,   // parallel arr  │    ║
║  │    val_type: PackedStringArray,  // SoA for hot    │    ║
║  │    storage_type: PackedStringArray, // path access  │    ║
║  │    storage_pos: PackedInt32Array,                  │    ║
║  │    scope: PackedStringArray,                      │    ║
║  │    lookup: Dictionary          // O(log n) hash   │    ║
║  │  }                                                │    ║
║  └──────────────────────────────────────────────────┘    ║
║                                                          ║
║  Layer 3: Assembly Result                                ║
║  ┌──────────────────────────────────────────────────┐    ║
║  │  AssemblyResult = {                              │    ║
║  │    text: PackedStringArray,   // emit buffer      │    ║
║  │    write_pos: int,                                │    ║
║  │    loc_map: Dictionary,          // source debug  │    ║
║  │  }                                                │    ║
║  └──────────────────────────────────────────────────┘    ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
```

#### Design Rationale

- **Named slots** (`{dest}`, `{src}`) instead of positional markers (`$1`, `^2`): Satisfies the Literate critic's requirement for self-documenting templates, and the Lisp critic's desire for structural (not string-opaque) representation.
- **SymTable as hybrid**: Parallel arrays (SoA) satisfy the DOD critic's demand for cache-friendly hot-path access, while the `lookup` Dictionary satisfies the XP/TDD/Agile need for straightforward symbol access. The lookup hash is a thin index over the flat arrays.
- **PackedStringArray for assembly output**: Satisfies the DOD critic's demand for buffered output (story C-4 in the Agile plan), while remaining human-readable (unlike `PackedByteArray`).

### 4.3 Pipeline / Processing Stages

```
┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
│  Stage 1 │   │  Stage 2 │   │  Stage 3 │   │  Stage 4 │   │  Stage 5 │
│ Flat IR  │──▶│ Storage  │──▶│ Template │──▶│ Register │──▶│ Assembly │
│ Build    │   │ Allocate │   │ Expand   │   │ Resolve  │   │ Emit     │
└──────────┘   └──────────┘   └──────────┘   └──────────┘   └──────────┘
     │              │              │              │              │
     ▼              ▼              ▼              ▼              ▼
  IR_Prog →    FlatIR →       FlatIR →       Buffer →        String →
  FlatIR       FlatIR         Buffer         Buffer           String
     (flat)     (+storage)     (+text)        (+resolved)      (final)
```

**Stage 1 — FlatIR Builder** (`flatir_build.gd`)
- **Input**: `IR_Program` (original parsed form)
- **Output**: `FlatIR` (flat command array + symbol table)
- **Contract**: Pure function. `static func build(ir: IR_Program) -> FlatIR`
- **Responsibility**: Flatten IR commands into `FlatOp` array. Populate initial `SymTable` entries.
- **Testable by**: Feed crafted `IR_Program`, assert flat command array contents.
- **Satisfies**: Unix (text-like flat format), DOD (flat arrays), TDD/X (testable isolation)

**Stage 2 — Storage Allocator** (`stor_alloc.gd`)
- **Input**: `FlatIR` (from Stage 1)
- **Output**: `FlatIR` (with `storage_type` and `storage_pos` filled in `SymTable`)
- **Contract**: Pure function. `static func allocate(ir: FlatIR) -> FlatIR`
- **Responsibility**: Determine storage: global → position in data section; stack → EBP offset; immediate → value-only.
- **Testable by**: Assert specific storage assignments for known symbols.
- **Satisfies**: XP/SlotAllocator role, Literate slot resolution, TDD isolate-and-test

**Stage 3 — Template Expander** (`tmpl_expand.gd`)
- **Input**: `FlatIR` with storage assigned
- **Output**: `Buffer` — a mutable accumulator with `text: PackedStringArray`, `write_pos: int`, `loc_map: Dictionary`
- **Contract**: `static func expand(ir: FlatIR, templates: Dictionary) -> Buffer`
- **Responsibility**: Match each `FlatOp` to a template entry. Perform named slot binding (`{dest}` → resolved storage reference). Append resolved assembly lines to buffer.
- **Template format**:
  ```gdscript
  const TEMPLATES = {
    "MOV": {
      pattern: ["MOV", "dest", "src"],
      slots: {
        dest: { type: "store", default: "EAX" },
        src:  { type: "load" }
      },
      assembly: [
        "mov {dest}, {src};",
      ],
      size: 8,
    },
    # ... more entries
  }
  ```
- **Testable by**: Assert specific buffer contents for specific input FlatOps.
- **Satisfies**: Functional Purity (data-driven templates), XP/PatternMatcher, GoF (OCP — new ops = new entries)

**Stage 4 — Register Resolver** (`reg_resolve.gd`)
- **Input**: `Buffer` with unresolved register references
- **Output**: `Buffer` with all registers resolved
- **Contract**: `static func resolve(buffer: Buffer) -> Buffer`
- **Responsibility**: Allocate physical registers for virtual register references. Resolve `^dest` → `EAX`, `$src` → `[EBP-4]`, etc.
- **Register allocator**: 4-element `Array[bool]` (NOT a Dictionary), returns `(reg_name, new_state)` tuple — pure state threading.
- **Testable by**: Assert specific register assignments for known input patterns.
- **Satisfies**: TDD (pure RegAllocState pattern), DOD (flat bitmask-friendly), Functional Purity (state threading)

**Stage 5 — Assembly Emitter** (`asm_emit.gd`)
- **Input**: `Buffer` with all slots and registers resolved
- **Output**: `String` — final assembly text
- **Contract**: `static func emit(buffer: Buffer) -> String`
- **Responsibility**: Join `PackedStringArray` into final string. Apply fixups (ENTER/LEAVE label resolution, branch target offsets). Return complete assembly.
- **Testable by**: Golden file comparison against known-correct output.
- **Satisfies**: Unix (final text output), Waterfall (verifiable output), Agile (golden file oracle)

#### Pipeline Composition

```gdscript
static func compile(ir: IR_Program, templates: Dictionary) -> String:
    var flat    = FlatIRBuilder.build(ir)
    var allocd  = StorageAllocator.allocate(flat)
    var buf     = TemplateExpander.expand(allocd, templates)
    var resolved = RegisterResolver.resolve(buf)
    return AssemblyEmitter.emit(resolved)
```

This pipeline:
- Is **pure function composition** (✓ Functional Purity, Unix, TDD)
- Has **5 stages with clear single responsibilities** (✓ Unix, XP, GoF)
- Passes **structured data between stages** (✓ Lisp — not serialized text)
- Enables **stage-by-stage incremental testing** (✓ TDD, XP)
- Can be **built incrementally** — Stage 1 first, verify with golden files, then Stage 2, etc. (✓ XP, Agile)
- Has **no global mutable state** (✓ everyone)

### 4.4 Template Format

```yaml
# templates/templates.yaml
# Format: YAML — editable by non-developers, version-controllable, parseable

MOV:
  description: "Move src value into dest register/location"
  pattern: ["MOV", "dest", "src"]
  slots:
    dest:
      type: store
      resolve: "format_operand"  # references a Resolver function
    src:
      type: load
      resolve: "format_operand"
  assembly:
    - "mov {dest}, {src};"
  size: 8

OP:
  description: "Arithmetic/logic operation: res = a OP b"
  pattern: ["OP", "op", "a", "b", "res"]
  slots:
    a:   { type: load }
    b:   { type: load }
    res: { type: store }
  assembly:
    - "mov EAX, {a};"
    - "{op} EAX, {b};"
    - "mov {res}, EAX;"
  size: 24

IF:
  description: "Conditional branch"
  pattern: ["IF", "cond", "label"]
  slots:
    cond: { type: load }
    label: { type: label }
  assembly:
    - "cmp {cond}, 0;"
    - "jnz {label};"
  size: 16

# ... (remaining templates from current op_map migrated incrementally)
```

#### Why YAML (and why it satisfies each persona)

| Concern | How YAML Addresses It |
|---------|----------------------|
| **Functional Purity** | Template data is immutable after parsing. Pure function reads it at expansion time. |
| **Data-Oriented** | YAML is parsed once at startup into flat lookup structures. No runtime parsing. |
| **Unix** | YAML is text — greppable, diffable, pipeable through `grep` or `sed`. |
| **TDD** | Templates can be loaded as test fixtures. Test-specific templates can be injected. |
| **XP** | YAML is the simplest external format. No schema compilation step. |
| **GoF** | YAML templates provide OCP — new ops = new YAML entries, no code changes. |
| **Literate** | YAML is human-readable. Template entries are self-documenting with `description` fields. |
| **Agile** | YAML matches story A-2 (Template Schema). Marked as P0 deliverable. |
| **Waterfall** | YAML schema can be specified, validated, and version-controlled. |
| **Lisp** | YAML is not S-expressions, but the parsed result is structured data (Dictionaries), not strings — a significant improvement over opaque markers. |

### 4.5 Testing Strategy

#### Three-Layer Test Architecture
```
┌─────────────────────────────────────────────────────────┐
│                  Layer 1: Unit Tests                     │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Each pipeline stage tested in isolation         │   │
│  │  Input: crafted data structure                   │   │
│  │  Assert: expected output data structure          │   │
│  │  No file I/O, no global state, no mocks required │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│                  Layer 2: Integration Tests               │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Adjacent stages tested together                 │   │
│  │  e.g., FlatIRBuilder → StorageAllocator chain     │   │
│  │  Assert: intermediate + final state consistency  │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│                  Layer 3: Golden File Regression          │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Full pipeline on all res/data/* programs         │   │
│  │  Compare output against saved golden files        │   │
│  │  Any difference = test failure                    │   │
│  │  Golden files committed to version control        │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

#### Test First, Not Test After

For each pipeline stage, the implementation sequence is:
1. **Characterize**: Run current codegen on all test inputs, capture golden files
2. **Write test**: Craft input for the stage, assert expected output
3. **Implement**: Write just enough code to pass the test
4. **Verify**: Run golden file comparison — output must be identical
5. **Refactor**: Clean up with tests still passing

#### What each persona gets from this strategy

| Persona | Satisfaction |
|---------|-------------|
| **TDD** | True Red-Green-Refactor. 100% coverage target. Tests written before code. |
| **XP** | Golden file safety net. Incremental verification after each sprint. Collective ownership enabled by tests. |
| **Agile** | Sprint-level acceptance criteria. Definition of Done includes passing goldens. |
| **Waterfall** | Requirements traceability through test cases. Regression suite for every change. |
| **Functional Purity** | Pure function testability — no mocks, no global state setup. |
| **Literate** | Tests serve as executable documentation. Each test is a documented use case. |

### 4.6 Migration Strategy

```
Sprint 0: Characterize & Foundation
  - Capture golden files for all res/data/* programs
  - Define template YAML schema (story A-2 equivalent)
  - Build TemplateExpander test infrastructure
  - Outcome: Golden files committed. Schema approved.

Sprint 1: Template Engine + MOV
  - Build TemplateExpander stage (template matching + named slot binding)
  - Build AssemblyEmitter stage (buffer → final string)
  - Migrate MOV command only
  - Outcome: MOV assembly generated by new pipeline. Golden files match.

Sprint 2: Storage Allocation + More Ops
  - Build StorageAllocator stage
  - Build FlatIRBuilder stage (minimal — only needed fields)
  - Migrate OP, CMP, JMP commands
  - Outcome: Arithmetic pipeline working.

Sprint 3: Register Resolution + Branching
  - Build RegisterResolver stage (pure state machine)
  - Migrate IF, WHILE control flow
  - Outcome: Full control flow pipeline.

Sprint 4: Complex Commands
  - Migrate CALL, RETURN (stack frame handling)
  - Migrate ARRAY operations (INDEX, ARR)
  - Migrate DATA/DEFINE (data section placement)
  - Outcome: All commands migrated. Old codegen can be removed.

Sprint 5: Hardening & Performance
  - Performance regression testing
  - Edge case coverage
  - Documentation update
  - Remove old generate_cmd_* functions
  - Outcome: 100% migrated, fully tested, documented.
```

#### Migration Principles

- **One IR command at a time**: Each sprint migrates a subset of commands. The remaining commands continue using the old `generate_cmd_*` functions.
- **Always green**: Golden file comparison runs after each migration. Any difference blocks the sprint.
- **Parallel pipeline**: Old and new codegen coexist during migration. The driver dispatches to new pipeline for migrated commands, old codegen for unmigrated ones.
- **Reversible**: Each migration is a single PR. If golden files don't match, the PR is rejected.

### 4.7 Error Handling Approach

```gdscript
# Unified error result type for all stages
# Satisfies: Functional Purity (discriminated union), TDD (testable error paths),
#            GoF (Strategy for error reporting), XP (simple)

class_name CodegenResult

enum ErrorType {
    OK,
    UNKNOWN_OP,
    TEMPLATE_NOT_FOUND,
    REGISTER_EXHAUSTED,
    STORAGE_OVERFLOW,
    INVALID_SLOT,
    LABEL_MISMATCH,
}

var ok: bool
var value  # AssemblyResult | FlatIR | Buffer | null
var error: ErrorType
var message: String
var loc: LocationRange

static func success(v) -> CodegenResult:
    return CodegenResult.new(true, v, OK, "", null)

static func failure(err: ErrorType, msg: String, loc: LocationRange) -> CodegenResult:
    return CodegenResult.new(false, null, err, msg, loc)
```

#### Key design decisions

1. **All errors are values, not exceptions.** No `push_error()`, no runtime crashes. Every stage returns a `CodegenResult`. This satisfies Functional Purity (error as data) and TDD (testable error paths).
2. **Early termination on error.** The pipeline driver checks `result.ok` after each stage. If any stage fails, the pipeline stops and reports the first error. This satisfies Waterfall (predictable behavior) and Agile (fast feedback).
3. **Location tracking is first-class.** Every error carries a `LocationRange` pointing to the source code that caused it. This satisfies Literate (traceability to source) and Unix (diagnostic messages are text).
4. **No silent fallbacks.** Unknown commands produce `UNKNOWN_OP` errors, not empty strings. This satisfies Lisp (no hidden defaults) and Functional Purity (no implicit error handling).

### 4.8 Extensibility Mechanism

#### Adding a New IR Command

1. Add a template entry to `templates/templates.yaml`:
   ```yaml
   MY_NEW_OP:
     pattern: ["MY_NEW_OP", "input", "output"]
     slots:
       input:  { type: load }
       output: { type: store }
     assembly:
       - "my_asm {input}, {output};"
     size: 8
   ```
2. Write a golden file test case:
   ```gdscript
   func test_my_new_op():
       var ir = make_ir(["MY_NEW_OP", "var_x", "var_y"])
       var result = compile(ir, TEMPLATES)
       assert(result.ok)
       assert(result.value.text == "my_asm var_x, var_y;\n")
   ```
3. Run the pipeline — no code changes needed.

**This satisfies**:
- **GoF/OCP**: Open for extension (add template), closed for modification (no code changes)
- **XP/YAGNI**: Only build what you need — templates are just data
- **Agile**: Each new command is a single story with clear acceptance criteria
- **Literate**: Template entry is self-documenting with `description` field
- **Waterfall**: Traceable from requirement (new command) → template entry → test case
- **Lisp**: Template-as-data extends the system without modifying existing transformations

#### Adding a New Pipeline Stage

1. Create a new file `new_stage.gd` with a pure function:
   ```gdscript
   static func process(input: IntermediateType, config: Dictionary) -> CodegenResult
   ```
2. Insert it in the pipeline composition:
   ```gdscript
   var new_result = NewStage.process(prev_result.value, config)
   ```
3. Write unit tests for the new stage + update golden files.

**This satisfies**:
- **Unix**: Insert a new filter in the pipeline
- **Functional Purity**: Pure function composition
- **TDD**: Testable in isolation before integration
- **Lisp**: Adding a macro pass to the pipeline

---

## Section 5: Persona Satisfaction Scorecard

### Functional Purity Advocate
| Core Concern | How It's Addressed |
|---|---|
| **No global mutable state** | ✅ Zero `static var` declarations. All stage functions are pure: `static func(input) → Result`. |
| **Referential transparency** | ✅ Same input always → same output. No hidden state. Pipeline is function composition. |
| **Immutable data** | ✅ `Template` entries are `const`. `FlatIR`, `SymTable` passed by value-copy between stages. |
| **State threading** | ✅ `RegisterResolve.alloc()` returns `(reg, new_state)` tuple — pure state threading as in TDD's `RegAllocState`. |
| **No side effects** | ✅ `CodegenResult` type makes errors explicit return values. No `push_error()`. |

**Satisfaction**: 9/10 — Would prefer even more rigid immutability enforcement (e.g., never using Dictionaries), but accepts the practical compromise of hybrid SymTable.

---

### Data-Oriented Design Advocate
| Core Concern | How It's Addressed |
|---|---|
| **Cache-friendly data layout** | ✅ `SymTable` uses parallel `PackedStringArray`/`PackedInt32Array` for hot-path symbol access. |
| **Hot/cold splitting** | ✅ 5-stage pipeline naturally separates cold (FlatIR Build, Storage Alloc) from hot (Template Expand, Register Resolve, Assembly Emit). |
| **SoA over AoS** | ✅ Symbol table is SoA. Template table is an Array of structs (AoS) but accessed via pattern index, not linear search. |
| **No Dictionary scatter** | ✅ `SymTable` uses Dictionary only for index lookup. Hot-path access goes through parallel arrays. |
| **Buffered assembly output** | ✅ `Buffer.text` is `PackedStringArray`. Joined once at end. No `+=` string concatenation. |

**Satisfaction**: 7/10 — The template expansion stage still uses structured data (Dictionaries) rather than pure flat bytecode. Would prefer pre-compiled template opcodes. However, the SoA SymTable and buffered output are significant wins.

---

### Unix Philosophy Advocate
| Core Concern | How It's Addressed |
|---|---|
| **Pipeline of filters** | ✅ 5 clearly defined stages, each with a single `static func(input) → Result`. |
| **Text-stream intermediate format** | ⚠️ Compromise: Stages pass structured data (FlatIR, Buffer), not text. But every stage *can* serialize to text for debugging (`FlatIR.to_text()`, `Buffer.to_text()`). |
| **Grepable / debuggable intermediates** | ⚠️ Structured data is not directly greppable, but text serialization functions are provided for debugging. The YAML template format is greppable. |
| **Do one thing well** | ✅ Each stage has exactly one responsibility. 5 stages for 5 concerns. |
| **Composability** | ✅ `compile()` composes 5 pure functions. Stages can be reordered, inserted, or removed. |

**Satisfaction**: 8/10 — Would prefer true text-stream intermediates (piped `String → String`) for maximum Unix composability. The use of structured data is accepted as a pragmatic concession for performance, and debug serialization functions are provided as a middle ground.

---

### TDD Advocate
| Core Concern | How It's Addressed |
|---|---|
| **Testability** | ✅ Every stage is a pure function. Input → output. No global state, no file I/O, no mocks needed. |
| **Dependency injection** | ✅ Template table is passed as parameter to `TemplateExpander.expand()`. Config is passed to stages. |
| **Tests as first-class citizens** | ✅ Testing strategy defines 3 layers (unit, integration, golden). Tests written *before* implementation code. |
| **Incremental testable increments** | ✅ 6-sprint migration plan, each sprint testable via golden files. Each stage testable in isolation. |
| **100% coverage goal** | ✅ Pure functions make exhaustive testing feasible. Error paths are explicit return values. |

**Satisfaction**: 9/10 — The migration strategy's Sprint 0 (characterization before changes) addresses a specific concern raised about the original TDD plan. The `CodegenResult` type makes error paths explicitly testable.

---

### XP Advocate
| Core Concern | How It's Addressed |
|---|---|
| **Incremental delivery** | ✅ 6-sprint migration, one IR command at a time. Always green. Golden file verification after each sprint. |
| **Simplicity (YAGNI)** | ✅ No pattern injection. No macro engine. No quasiqoute machinery. Templates are simple data. |
| **Collective ownership** | ✅ Templates are YAML files in version control. Any team member can edit. Small stage files (< 100 lines each). |
| **Courage to refactor** | ✅ Golden file safety net. Each stage testable independently. Pipeline composition makes stage replacement trivial. |
| **Working software as measure** | ✅ Sprint 1 produces working MOV assembly. Each subsequent sprint produces more working assembly. |

**Satisfaction**: 10/10 — The synthesized architecture is essentially the XP plan refined with input from every other persona. The 6-sprint incremental migration, golden file verification, and YAGNI-driven simplicity are pure XP values.

---

### Design Patterns (GoF) Advocate
| Core Concern | How It's Addressed |
|---|---|
| **Encapsulation** | ✅ Each stage is a self-contained file with a single public static function. Internal implementation is private. |
| **Loose coupling** | ✅ Stages communicate through data structures (FlatIR, Buffer), not through shared objects. Template table is injected. |
| **Open-Closed Principle** | ✅ New IR command = new YAML template entry + new test. No existing code modified. OCP score: 10/10. |
| **Separation of concerns** | ✅ 5 pipeline stages, each with a distinct responsibility. Concerns are clearly separated at the stage level. |
| **Pattern usage** | ✅ Strategy (template format), Pipeline (core architecture), Memento (CodegenResult as discriminated union). Used sparingly and intentionally — not injected. |

**Satisfaction**: 8/10 — Would prefer more explicit GoF patterns (Visitor for command dispatch, Composite for assembly tree, Decorator for debug tracing). The simpler pipeline approach achieves OCP without pattern overhead, which is accepted. The Strategy pattern for template resolution is acknowledged.

---

### Literate Programming Advocate
| Core Concern | How It's Addressed |
|---|---|
| **Human communication** | ✅ Named slots (`{dest}`, `{src}`) are self-documenting. YAML templates include `description` fields. Pipeline stages have clear contracts. |
| **Documentation as first-class** | ✅ The template YAML file IS documentation of the IR→assembly mapping. Tests serve as executable documentation. |
| **Interleaving explanation & code** | ⚠️ This plan document interleaves design reasoning with implementation details, but the actual `.gd` files are separated. No tangling/weaving toolchain. |
| **Tangling/weaving capability** | ❌ Not provided. The source of truth is the code files, not this document. |
| **Readability** | ✅ The design is presented as a narrative with clear rationale for each decision. |

**Satisfaction**: 7/10 — Would prefer a tangling toolchain that extracts `.gd` files from this document. Accepts that the practical constraints of a GDScript project make full literate programming infeasible. Named slots and self-documenting YAML templates are positive steps.

---

### Agile/Scrum Advocate
| Core Concern | How It's Addressed |
|---|---|
| **Iterative delivery** | ✅ 6-sprint migration. Each sprint produces working, tested assembly output. No big-bang phases. |
| **Stakeholder visibility** | ✅ Sprint reviews show real assembly output (progressive — MOV in Sprint 1, arithmetic in Sprint 2, etc.). Golden file reports show pass/fail status. |
| **Adaptability to change** | ✅ YAML templates can be changed without code modifications. Pipeline stages are independently replaceable. If requirements change mid-project, only affected sprints need adjustment. |
| **Sprint-ability** | ✅ Each sprint has a clear goal (migrate specific commands), clear acceptance criteria (golden files match), and is independently shippable. |
| **Risk management** | ✅ Primary risk (breaking existing codegen) is mitigated by golden file regression. Migration risk is mitigated by one-command-at-a-time approach. Performance risk is deferred to Sprint 5. |

**Satisfaction**: 10/10 — The synthesized architecture adopts the Agile plan's sprint structure, golden file regression suite, and Definition of Done. The incremental migration strategy is the exact approach the Agile critic praised in the XP plan.

---

### Waterfall/BDUF Advocate
| Core Concern | How It's Addressed |
|---|---|
| **Completeness of specification** | ⚠️ This document specifies the architecture, data model, pipeline, template format, testing strategy, migration plan, and extensibility mechanism. However, it does not include a full requirements traceability matrix or a complete template catalog. |
| **Traceability** | ⚠️ Stories are mapped to sprints. Test cases trace to stages. But there is no formal requirements decomposition with IDs. |
| **Phase discipline** | ✅ 5 pipeline stages + 6 migration sprints provide phase-like structure. Golden file verification at each sprint boundary is a quality gate. |
| **Change control** | ⚠️ The extensibility mechanism defines how to add new commands (add YAML entry + test). But there is no formal Change Control Board or sign-off process for architectural changes. |
| **Verification rigor** | ✅ Three-layer test architecture (unit, integration, golden). Golden files provide regression safety. Error handling is explicit via `CodegenResult`. |

**Satisfaction**: 6/10 — Would prefer a complete requirements specification and traceability matrix before coding begins. However, the structured pipeline design and explicit verification strategy provide more rigor than most non-waterfall plans. The golden file approach satisfies the verification criterion. The six-phase sprint plan provides phase discipline, even if the sign-off gates are softer than waterfall prefers.

---

### Lisp/Macro-Driven Advocate
| Core Concern | How It's Addressed |
|---|---|
| **Code is data** | ✅ Templates are pure data (YAML parsed to Dictionaries). Stage functions are data transformations. Pipeline composition is data flow. |
| **Homoiconicity** | ⚠️ Templates are structured data (nested Dictionaries), not strings with opaque markers. This is structurally closer to S-expressions than any string-based approach. However, they are not true S-expressions — they cannot be composed with quasiquote. |
| **Metaprogramming** | ❌ No macro-generating macros. No `defmacro` equivalent. No runtime template generation. Template table is static. |
| **Macro extensibility** | ⚠️ Adding a new command = adding a data entry. This is macro-like extensibility through data, not through code. |
| **Pipeline of transformations** | ✅ The 5-stage pipeline is conceptually a macro-pass pipeline: each stage transforms a representation. However, there is no recursive expansion (expand until stable). |

**Satisfaction**: 6/10 — The structured template data (nested Dictionaries with named slots) is a significant improvement over string-based templates and is philosophically aligned with S-expression representation. The pure-function pipeline architecture is structurally similar to macro passes. However, the absence of quasiquote, `gensym`, recursive expansion, and macro-generating macros means this architecture does not achieve full Lisp-style metaprogramming. The Literate plan's spirit (explanation as code) and the Functional Purity plan's ethos (pure transformations) are present, but the Lisp plan's full vision would require deeper structural changes than this consensus can support.

---

## Summary Scorecard

| Persona | Score | Key Win | Key Gap |
|---------|:-----:|---------|---------|
| **Functional Purity** | 9/10 | Zero globals, pure function pipeline | Dictionary use in SymTable |
| **Data-Oriented Design** | 7/10 | SoA SymTable, buffered output | Templates not pre-compiled to bytecode |
| **Unix Philosophy** | 8/10 | Clear pipeline, debug serialization | Structured data, not text streams |
| **TDD** | 9/10 | Pure function testability, pre-written tests | No infrastructure for 100% coverage enforcement |
| **XP** | 10/10 | Incremental migration, golden files, YAGNI | None |
| **Design Patterns (GoF)** | 8/10 | OCP via template data, 5 clean stages | No Visitor/Composite/Decorator patterns |
| **Literate Programming** | 7/10 | Named slots, self-documenting YAML | No tangling toolchain |
| **Agile/Scrum** | 10/10 | Sprint structure, golden files, DoD | None |
| **Waterfall/BDUF** | 6/10 | Structured pipeline, explicit verification | No requirements traceability matrix |
| **Lisp/Macro** | 6/10 | Structured template data, pure transformations | No quasiquote, macros, or metaprogramming |

---

## Final Synthesis Statement

The synthesized architecture delivers **zero global mutable state**, **5 stage pure-function pipeline**, **YAML-driven data templates**, **golden file regression safety**, and **6-sprint incremental migration**. Every persona finds something to agree with, and no persona finds a dealbreaker.

The architecture achieves **universal acceptability** (though not universal love) by:
1. **Adopting** the universal consensus on data-driven templates and pipeline architecture
2. **Avoiding** the nearly-universal rejection of global mutable state and big-bang rewrites
3. **Compromising** on text-stream vs structured-data intermediates (debug serialization provided)
4. **Deferring** the Lisp plan's full homoiconic vision and the DOD plan's full bytecode compilation
5. **Borrowing** the XP/Agile incremental migration strategy that earned the highest cross-persona scores
6. **Integrating** the TDD testing discipline with the Waterfall verification rigor
7. **Documenting** with Literate-friendly explanations and named slots

The result is a design that can **actually be built** — incrementally, testably, and with the confidence that every persona's core concern has been addressed.
