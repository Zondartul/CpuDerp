# Data-Oriented Design Critique: All 9 Personas' Codegen Plans

**Author**: Data-Oriented Design Advocate  
**Date**: 2026-06-27  
**Context**: A systematic evaluation of all 9 personas' plans for the CpuDerp codegen refactor, judged by the standards of cache efficiency, memory layout, hot/cold splitting, SoA vs AoS, and CPU-friendly data access patterns.

---

## Table of Contents

1. [Scoring Rubric](#scoring-rubric)
2. [Functional Purity](#1-functional-purity)
3. [Unix Philosophy](#2-unix-philosophy)
4. [Test-Driven Development](#3-test-driven-development)
5. [Extreme Programming](#4-extreme-programming)
6. [Design Patterns (GoF)](#5-design-patterns-gof)
7. [Literate Programming](#6-literate-programming)
8. [Agile/Scrum](#7-agilescrum)
9. [Waterfall/BDUF](#8-waterfallbdUF)
10. [Lisp/Macro-Driven](#9-lispmacro-driven)
11. [Summary Comparison Table](#summary-comparison-table)

---

## Scoring Rubric

Each plan receives scores (1–5) in five categories:

| Score | Meaning |
|-------|---------|
| 5 | Actively designs for cache/memory efficiency (SoA, flat arrays, hot/cold split) |
| 4 | Recognizes data layout issues and proposes partial improvements |
| 3 | Neutral — doesn't harm but doesn't improve data locality |
| 2 | Actively uses patterns that harm cache efficiency (pointer chasing, hash maps, object indirection) |
| 1 | Aggressively multiplies cache misses (nested objects, deep indirection, no locality awareness) |

---

## 1. Functional Purity

**Overall Data-Oriented Score: 2/5 — "Pure functions, impure data layout"**

### On Cache Efficiency and Memory Layout

The Functional Purity plan is the most **data-agnostic** of all 9 plans. It is deeply concerned with *control flow purity* (no side effects, referential transparency, immutable state threading) but gives **zero consideration** to how data lives in memory.

The plan's core data types tell the whole story:

- [`AssemblyResult`](plans/functional_purity_codegen_plan.md:145) is a **Dictionary** containing 6 fields: `text`, `write_pos`, `loc_map`, `labels`, `reg_alloc`, `new_syms`. Each of these is itself a Dictionary or object. The entire pipeline state is one deeply nested heap-allocated dictionary per command.
- [`RegAllocState`](plans/functional_purity_codegen_plan.md:156) uses a **Dictionary of booleans** for 4 registers — the exact same hash-map-overkill the DOD plan identifies as a violation.
- [`SymTable`](plans/functional_purity_codegen_plan.md:161) is **also a Dictionary**, preserving the same hash-map symbol table that causes cache-oblivious lookups in the current code.

### On Hot/Cold Splitting

**None.** The plan threads all state — hot emit data and cold symbol data — through the same `Environment` dictionary. Every template expansion carries the entire symbol table, scope chain, register state, and location map as one monolithic blob. There is zero separation between the hot path (command dispatch) and the cold path (scope traversal, label generation).

### On Structure-of-Arrays vs Array-of-Structures

The plan remains firmly **Array-of-Structures** (or rather, **Array-of-HashMaps**). Every IR command is an `IR_Cmd` object with a `.words: Array[String]` and `.loc: LocationRange`. The `AssemblyResult` aggregates state by bundling disparate concerns into a single mutable-but-copied dictionary.

**Ironically**, the plan goes *backwards* from the current code: by making `RegAllocState.duplicate()` on every register operation (line 337, 420), it multiplies heap allocations. Each `_expand_direct` call duplicates the entire `new_syms` dictionary, allocates a new `AssemblyResult`, and copies the location map. The hot path becomes a **memory allocation storm**.

### On CPU-Friendly Data Access Patterns

The recursive `match` dispatch in [`expand_template`](plans/functional_purity_codegen_plan.md:316) follows unpredictable branches. The `template_table` is a linear search through tagged dictionaries (line 484-488). There is no sequential data access — every element is reached through a chain of pointer dereferences: `env → env.cmd → cmd.words[i]`, each hop potentially a cache miss.

### Where Data Layout Concerns Are Ignored

1. **No flat arrays at all.** The entire plan uses Dictionaries for everything.
2. **`RegAllocState`** duplicates its `regs_in_use` dictionary on every alloc/free — that's 4 dictionary allocations per instruction even though the data is 4 booleans.
3. **Template strings** are parsed at emit time via `body.replace()` (line 349), which allocates a new string per slot substitution.
4. **Location maps** remain nested Dictionaries (`loc_map.begin[wp] = [LocationRange]`), which the DOD plan specifically identifies as a multi-level cache miss.

### Constructive Suggestion

The plan's pure-function architecture is *compatible* with DOD, but the data structures must change. Replace all Dictionaries with flat arrays. Replace `env` threading with a batch-processing pipeline where each pass returns a densely packed result. The copying approach works mathematically (referentially transparent) but is catastrophic for cache. Instead of `duplicate()`, use **generational indices** that are cheap to snapshot.

---

## 2. Unix Philosophy

**Overall Data-Oriented Score: 3/5 — "Text pipelines are data-friendly, but serialization costs kill cache"**

### On Cache Efficiency and Memory Layout

The Unix plan has a **surprising strength** from a DOD perspective: its text-stream pipeline is a batch-oriented design. Each stage reads all input, processes it in bulk, and writes all output. This *naturally* encourages working memory to be reused and batches to be processed sequentially.

However, the **text serialization** is a deal-breaker. Every stage serializes its entire state to a tab-separated text format, then the next stage parses it back. For the IR-to-assembly codegen, this means:

- Stage [1 (`ir2flat`)](plans/unix_philosophy_codegen_plan.md:82) serializes the entire IR to text — parsing YAML, then formatting each command as a TSV line.
- Stage [2 (`sym_alloc`)](plans/unix_philosophy_codegen_plan.md:106) parses that text back into in-memory structures ("flat arrays, not dictionaries of objects" — line 113, a nod to DOD).
- Stage [3 (`templ_expand`)](plans/unix_philosophy_codegen_plan.md:132) parses the output again.

The serialization/deserialization pipeline means every IR command passes through **at least 3 string formatting + parsing cycles**. Each cycle allocates strings, splits them, and builds temporary data structures. For a codegen processing 10,000 IR commands, this is gigabytes of temporary string allocation.

### On Hot/Cold Splitting

**Partial.** The pipeline architecture *forces* a kind of hot/cold separation: storage allocation ([`sym_alloc`](plans/unix_philosophy_codegen_plan.md:106)) runs as a pre-pass, then template expansion ([`templ_expand`](plans/unix_philosophy_codegen_plan.md:132)) runs as the hot path. This is conceptually correct.

But the hot path (`templ_expand` → [`reg_resolve`](plans/unix_philosophy_codegen_plan.md:171) → [`line_asm`](plans/unix_philosophy_codegen_plan.md:201)) is still three serialization stages that each parse and re-format. The hot path should ideally be a single pass over a flat memory buffer, not three text transformations.

### On Structure-of-Arrays vs Array-of-Structures

The plan uses **text lines** as its universal data structure. Each line is a tab-separated array: `cmd\tcb_0\t0\tMOV\tvar_1\timm_2\t"test.md:12:5"`. This is a text form of AoS — each "row" bundles all fields for one command. Parsing this back into in-memory arrays could *become* SoA, but the plan doesn't specify this.

The register allocator (line 195) is correctly identified as "a 4-element array of booleans, not a dictionary" — a win. But the symbol table during [`sym_alloc`](plans/unix_philosophy_codegen_plan.md:113) is described as "flat arrays" only one line (line 113), then immediately presented as in-memory structures used to annotate text lines — no actual SoA design is given.

### On CPU-Friendly Data Access Patterns

**Text parsing is the antithesis of cache-friendly computation.** The `reg_resolve` stage (line 178) describes a loop over text lines where each line is scanned for `$`, `@`, `^` markers — **exactly the same string scanning** the DOD plan identifies as a hot-path violation in the current code. The Unix plan has merely moved the scanning to a different stage, not eliminated it.

### Where Data Layout Concerns Are Ignored

1. **Text serialization cost.** Every stage serializes → next stage parses. This is the single largest performance cost, and it's entirely ignored.
2. **Template TSV file** (line 138) is parsed on every pipeline run. Templates should be compiled once to a flat lookup table, not parsed on each invocation.
3. **No batch processing within stages.** Each [`sym_alloc`](plans/unix_philosophy_codegen_plan.md:106) stage describes "three passes" but each pass is a full text parse+emit cycle.
4. **Symbol table in [`sym_alloc`](plans/unix_philosophy_codegen_plan.md:113)** is "in memory — but flat arrays, not dictionaries of objects" — this shows awareness but no actual design.
5. **Strings, strings, strings.** Everything is represented as text. In GDScript, strings are immutable and any manipulation allocates. The entire pipeline is allocation-bound.

### Constructive Suggestion

Keep the pipeline architecture — it's good for separation of concerns. But replace the text intermediate format with **flat binary arrays** (PackedInt32Array, PackedStringArray). Each stage reads from shared memory, not serialized text. The template file should be compiled once at startup into a flat lookup table (opcode ID → emit ops array). The `reg_resolve` string scanning should be eliminated by pre-compiling templates into emit opcodes.

---

## 3. Test-Driven Development

**Overall Data-Oriented Score: 1/5 — "Tests don't care about cache lines"**

### On Cache Efficiency and Memory Layout

The TDD plan is **entirely concerned with testability**, with zero attention to data layout. Its data structures are designed for easy assertion, not cache efficiency. This is the natural consequence of Red-Green-Refactor: the first pass ("Green") produces the simplest passing implementation, and data layout optimization rarely survives that filter.

Specific data structure decisions that harm performance:

- [`AssemblyBuffer`](plans/tdd_codegen_plan.md:247) uses **string concatenation** (`text += fragment`) for assembly output — the same `+=` pattern the DOD plan identifies as allocation-heavy.
- [`RegAllocState`](plans/tdd_codegen_plan.md:325) uses an **Array[bool]** for 4 registers. Better than a Dictionary, but still an Array of boxed Variants (each bool is a 16-byte Variant in GDScript). A 4-bit bitmask would be 4 bytes of stack.
- [`SymTable`](plans/tdd_codegen_plan.md:410) uses a **Dictionary of Dictionaries** (`_syms: Dictionary = {}`). This is the exact same scattered hash map the DOD plan diagnoses as a violation.
- [`OperandResolver`](plans/tdd_codegen_plan.md:472) is a class that wraps a `SymTable` reference and calls `lookup()` — each lookup is a hash table traversal.

### On Hot/Cold Splitting

**None.** The plan's layer diagram (line 85-113) shows 6 layers but they're all functional decomposition, not hot/cold separation. Every layer is equally active on every IR command. The test plan's increments proceed from simplest component (AssemblyBuffer) to most complex (driver integration), which is logical for TDD but ensures no thought is given to what runs on the hot path vs cold path.

### On Structure-of-Arrays vs Array-of-Structures

**Purely AoS.** Every data structure is an object with fields:

- `AssemblyBuffer` has `.text`, `.write_pos`, `.loc_map` as separate fields on one object.
- `SymTable` stores all symbols in one Dictionary.
- `RegAllocState` keeps `_in_use` as an Array field.

There is exactly **one** nod to SoA: `RegAllocState._in_use` uses `Array[bool]` instead of individual bool fields. But this is an array of Variants, not a packed array.

### On CPU-Friendly Data Access Patterns

The TDD approach actively **works against** CPU-friendly patterns. Each test case constructs a new object, calls a method, and asserts on the result. The design that emerges from this process is naturally **object-per-operation**: AssemblyBuffer per test, RegAllocState per alloc, SymTable per lookup. This teaches the design to allocate heavily.

The register allocator (line 324-352) is a **pure state machine that duplicates** on every call. `alloc()` allocates a new `RegAllocState` and duplicates `_in_use`. For a simple MOV instruction that allocates 2 registers, that's 2 allocations for the states + 2 array duplications.

### Where Data Layout Concerns Are Ignored

1. **Entirely.** There is no section, paragraph, or sentence about data layout, memory access patterns, cache efficiency, or performance.
2. Hash map symbol table (`_syms: Dictionary`) is the default choice.
3. Template matching is a **linear search through an Array** of entries (implicit in the template table design).
4. AssemblyBuffer `append_with_size` uses `text += fragment` — repeated string concatenation.
5. `LocMap` remains a Dictionary representation (lines 267-271).
6. No batch processing — each command is processed one at a time through the full pipeline.

### Constructive Suggestion

TDD and DOD are not incompatible. Start with a test for a `FlatIR` structure: "given 3 MOV commands, the flat arrays have 3 entries." Write the SoA data structure *first*, then build the pure functions on top. The test for `allocate_register` should assert on a bitmask, not on a boolean array. The test for `lookup_symbol` should test flat-array binary search, not Dictionary access.

---

## 4. Extreme Programming

**Overall Data-Oriented Score: 2/5 — "YAGNI means 'you aren't gonna need cache performance'"**

### On Cache Efficiency and Memory Layout

The XP plan explicitly **defers** performance concerns. The risk table at [line 397](plans/xp_codegen_plan.md:397) states: *"Performance regression — The pipeline makes extra object allocations (Fragment). If it matters, optimize last — not first."* This is the XP philosophy applied to data layout: correctness and simplicity first, optimization when profiled.

The data structures reflect this:

- [`Fragment`](plans/xp_codegen_plan.md:306) is a class with `.template`, `.bindings`, `.generated`, `.resolved_lines`, `.loc` — a tree of heap objects. Each IR command produces a `Fragment`. For 10,000 commands, that's 10,000 `Fragment` allocations + their internal dictionary/array allocations.
- [`SlotAllocator`](plans/xp_codegen_plan.md:142) returns a Dictionary — the same Dictionary-of-objects structure.
- [`Emitter`](plans/xp_codegen_plan.md:222) uses `ab.code += line + "\n"` — string concatenation.

### On Hot/Cold Splitting

**Partial.** The pipeline (Slot Allocator → Pattern Matcher → Slot Resolver → Emitter) separates concerns in a way that *could* map to hot/cold, but it's incidental. The Slot Allocator (cold: runs once per program) and Pattern Matcher (hot: runs per command) are separated, but the Pattern Matcher and Slot Resolver are not separated into hot/cold substages.

### On Structure-of-Arrays vs Array-of-Structures

**Purely AoS.** The `template_table` (line 84-119) is a Dictionary of Dictionaries. Each template has `out`, `slots`, `generated_slots`, `size` — all packed into one object per opcode. The `Fragment` tree is AoS. The Emitter processes `Array[Fragment]` — that's an Array of objects.

### On CPU-Friendly Data Access Patterns

The [Pattern Matcher](plans/xp_codegen_plan.md:161) iterates `for tmpl in env.template_table` for each command. The template table is a Dictionary, so iteration order is non-deterministic and access pattern is scattered. The match is a linear search through dictionary entries.

The [Slot Resolver](plans/xp_codegen_plan.md:197) calls `line.replace("{" + slot_name + "}", replacement)` — string allocation and scanning on every slot resolution. With 3 slots per command and 10,000 commands, that's 30,000 string allocations from `replace` alone.

### Where Data Layout Concerns Are Ignored

1. **Explicitly deferred** (line 397: "optimize last — not first").
2. **Fragment object allocation** per command — each Fragment carries template references, binding dictionaries, generated slot dictionaries, resolved line arrays.
3. **String replace in Slot Resolver** — the exact `find_reference` pattern the DOD plan diagnoses.
4. **Dictionary-based template_table** — scattered memory.
5. **No flat representation** for any data structure.
6. **Emitter uses string concatenation** (`ab.code += line`).

### Constructive Suggestion

The XP plan's incremental migration is actually *good* for DOD: each sprint replaces one `generate_cmd_*` function. Add a **Sprint 0.5**: "Convert the symbol table from Dictionary-of-Dictionaries to parallel arrays." This is a safe refactoring (same external behavior) that establishes the flat data substrate before any new features are built. Then each subsequent sprint can assume flat arrays.

---

## 5. Design Patterns (GoF)

**Overall Data-Oriented Score: 1/5 — "The most cache-hostile design imaginable"**

### On Cache Efficiency and Memory Layout

The GoF plan is the **single worst plan** from a data-oriented perspective. It multiplies object count by an order of magnitude compared to the current code, introducing indirection layers that guarantee cache misses on every operation.

The damage:

1. **Visitor Pattern** ([`IrCommandVisitor`](plans/design_patterns_codegen_plan.md:126)): Every IR command calls `cmd.accept(visitor)`, which is a virtual dispatch through the visitor's vtable. For 12 command types, that's 12 virtual calls per command. The visitor interface requires a `visit_*` method for *every* command type — adding a new command means adding a method to the interface and implementing it in every visitor.

2. **Composite Pattern** ([`AssyComposite`](plans/design_patterns_codegen_plan.md:305)): Assembly output is a tree of `AssyComponent` objects — `AssyInstruction` and `AssyBlock` nodes. The `get_text()` method recursively traverses the tree. For the CpuDerp assembly output (a flat sequence of instructions), this is a **tree-indirection over a fundamentally linear structure**. A `PackedStringArray` would occupy 1 contiguous allocation; this design creates N objects + N references.

3. **Decorator Pattern** ([`DebugTraceDecorator`](plans/design_patterns_codegen_plan.md:368), [`LocationTrackingDecorator`](plans/design_patterns_codegen_plan.md:379)): Each emit call passes through a chain of decorator objects. Each decorator wraps the next, adding virtual dispatch + heap allocation per decoration layer. Compare with the DOD approach: debug trace is a compile-time flag that adds a conditional branch, not an object wrapper.

4. **Strategy Pattern** ([`RegisterAllocator` interface](plans/design_patterns_codegen_plan.md:188)): Pluggable register allocators sound good, but the interface is designed for `allocate(operand) → reg` — a per-operand operation. A DOD register allocator would allocate **all registers in one batch pass** over the flat command array, not one-at-a-time through a virtual interface.

### On Hot/Cold Splitting

**Actively harmful.** The Decorator pattern interleaves debug tracing (cold) and location tracking (warm) with template expansion (hot) on every `emit()` call. The chain of decorators means the hot path includes cold-path branches even when decorations are disabled, because each decorator is still in the call chain performing a check.

### On Structure-of-Arrays vs Array-of-Structures

**Extreme AoS.** Every concept is an object:

- Each IR command is an `IrCommand` subclass (MovCommand, OpCommand, IfCommand, etc.)
- Each command has typed operand fields as object references
- Assembly output is a tree of `AssyComposite` objects
- Templates are `Template` objects with `params` dictionaries
- [`TemplateRegistry`](plans/design_patterns_codegen_plan.md:433) stores prototypes in a Dictionary (hash map of objects)

For 1,000 IR commands, the GoF design creates:
- 1,000 `IrCommand` objects (12 subclasses)
- ~3,000 `Operand` objects (3 operands per command)
- ~3,000 `AssyInstruction` or `AssyBlock` objects
- ~1,000 `Template` instantiations (one per command)
- Decorator objects for debug/location

That's **~8,000 heap objects** vs the DOD approach's ~10 flat `PackedInt32Array` allocations.

### On CPU-Friendly Data Access Patterns

**Abysmal.** Every operation is:

1. Virtual dispatch: `cmd.accept(visitor)` → vtable lookup → `visitor.visit_mov(cmd)`
2. Object dereference: `cmd.dest` → heap object
3. Method call: `resolver.resolve(operand)` → chain-of-responsibility iterator
4. Decorator chain: `emitter.emit()` → `DebugTraceDecorator.emit()` → `LocationTrackingDecorator.emit()` → `BaseAssyEmitter.emit()`
5. String concatenation: Composite tree traversal with recursion

Each instruction emission touches 10-15 different heap objects across 5-8 indirection levels. The I-cache is polluted by visitor dispatch, decorator chains, and strategy method calls. The D-cache is polluted by scattered object accesses.

### Where Data Layout Concerns Are Ignored

1. **Everywhere.** The plan is a catalog of GoF patterns applied without consideration for their data access patterns.
2. **Visitor + Composite + Decorator + Strategy + Prototype + Chain of Responsibility** — six patterns in one codegen, each adding object indirection.
3. **22 files** proposed (line 352 of the linked plan) for what the DOD plan does in 1-2 files of flat arrays.
4. **Template as Prototype** — `self.duplicate()` on every instantiation (line 424).
5. **Chain of Responsibility** for operand resolution — a linear search through handler objects.
6. No consideration of **batch processing** — everything is per-command, per-operand.

### Constructive Suggestion

The GoF patterns are useful for large, long-lived systems with many variants. For a codegen in GDScript targeting a single ISA, they are architectural overkill that happens to also be cache-hostile. Replace the Visitor with a flat lookup table (opcode enum → emit function index). Replace the Composite with a `PackedStringArray`. Replace the Decorator with compile-time feature flags. Replace Strategy with function pointers or enum-dispatch. The resulting code will be shorter, faster, and more cache-friendly.

---

## 6. Literate Programming

**Overall Data-Oriented Score: 2/5 — "Beautiful documentation, ugly data layout"**

### On Cache Efficiency and Memory Layout

The Literate Programming plan is **slightly better** than the GoF plan, but only because it avoids the pattern avalanche. Its data structures are similar to the XP and TDD plans: Dictionaries for symbol table, objects for components, strings for everything.

The plan actually shows *awareness* of data-driven design. The central insight on [line 41](plans/literate_codegen_plan.md:41) — *"the mapping from IR to assembly is data, not code"* — is something the DOD plan agrees with. But the plan then implements this insight using **Dictionaries of Dictionaries** for the template table, when the DOD approach would use flat arrays.

Specific issues:

- [`template_table`](plans/literate_codegen_plan.md:120) is a Dictionary mapping string keys to Dictionary values. Each template has `pattern`, `assembly`, `size`, `slots` — all Dictionary fields. Lookup is `_templates.get(key)` — hash computation per command.
- [`RegisterAllocator`](plans/literate_codegen_plan.md:453) uses `var _in_use = {}` — a Dictionary for 4 registers. This is the same violation as the current code.
- [`SlotResolver`](plans/literate_codegen_plan.md:373) holds `var _all_syms: Dictionary` — the original hash map.
- Assembly is built via string concatenation throughout.

### On Hot/Cold Splitting

**Minimal.** The pipeline (Pattern Matcher → Slot Resolver → Emitter) is a sequence of stages, but there's no analysis of which stages are hot vs cold. The Slot Resolver mixes register allocation (hot) with scope/label resolution (cold) in the same pass.

### On Structure-of-Arrays vs Array-of-Structures

**AoS.** Every component stores its state as fields on a class instance. The template table is AoS (one Dictionary per template). The symbol table is AoS (one Dictionary per symbol). The register allocator is AoS (one object with an `_in_use` field).

### On CPU-Friendly Data Access Patterns

The [`match(cmd)`](plans/literate_codegen_plan.md:324) function performs a **two-level lookup**: first try compound key `OP:EQUAL`, fall back to `OP`. This requires two hash computations and two Dictionary lookups per command. The `_resolve_operand` function (line 409) does a `match` on `handle.val_type` — a 5-branch switch with unpredictable branching.

The Slot Resolver's [`_resolve_storage`](plans/literate_codegen_plan.md:426) does a `match` on `storage.get("type")` — each access is a Dictionary lookup on the storage dictionary.

### Where Data Layout Concerns Are Ignored

1. **Symbol table remains a Dictionary.** The plan identifies this as wrong in the diagnosis section but doesn't fix it.
2. **Register allocator Dictionary** — same as current code.
3. **No flat arrays** anywhere in the design.
4. **`body.replace()` for template substitution** (line 429 in the linked `Template` class) — string allocation per slot.
5. **Two-level hash lookup** per command dispatch.
6. **No consideration of batch processing** — commands are processed one at a time through the pipeline.

### Constructive Suggestion

The Literate Programming plan is the *easiest* to retrofit with DOD, because it already has the right architecture (pipeline of stages, data-driven templates, separation of concerns). Replace the Dictionary-based symbol table and template table with parallel arrays. Replace the per-command pipeline with batch-oriented passes. The documentation structure is excellent — add sections on "Data Layout for This Stage" to explain the memory access patterns.

---

## 7. Agile/Scrum

**Overall Data-Oriented Score: 2/5 — "Process is not a substitute for data design"**

### On Cache Efficiency and Memory Layout

The Agile plan is notable for having **two stories** that directly address DOD concerns:

- **[Story C-1](plans/agile_codegen_plan.md:78): Flat Symbol Table** — "Replace the Dictionary-of-Dictionaries symbol table with a packed array structure: parallel arrays for ir_name, val_type, storage_type, storage_pos." This is exactly what the DOD plan proposes.
- **[Story C-2](plans/agile_codegen_plan.md:79): Register Allocator as Bitfield** — "Replace regs_in_use with a 4-bit integer bitmask." Also correct.
- **[Story C-3](plans/agile_codegen_plan.md:80): Pre-compiled Template Bytecode** — "Templates compiled to a sequence of emit opcodes... no string scanning in hot emit path." Also correct.
- **[Story C-4](plans/agile_codegen_plan.md:81): Buffered Assembly Output** — "Replace string concatenation with PackedByteArray or PackedStringArray joined once at the end."

**However**, these are all in Epic C (Sprints 2-3), prioritized as P1 (Should) rather than P0 (Must). The P0 stories (Epic A and B) are about test oracles and template parser architecture — which use Dictionaries and objects. The data layout improvements are **deferred to later sprints** and marked as optional.

This means if the team runs out of time (likely, given 22 points in Sprint 5 vs velocity of 15-20), the flat symbol table, bitfield register allocator, and pre-compiled bytecode are the first to be cut. The resulting system would have a nice template parser (Dictionary-based) on top of the old data structures.

### On Hot/Cold Splitting

**Implicit but not designed.** The pipeline architecture (Deserializer → Symbol Table → Emit Engine) gives a natural cold/hot split, but there's no explicit design for what data lives in which cache level, what gets pre-computed, or what gets streamed.

### On Structure-of-Arrays vs Array-of-Structures

Story C-1 explicitly calls for "parallel arrays" — the SoA approach. But this is a single story (8 points) in a 6-sprint plan. The rest of the design (Template Registry, Template Parser, Placeholder Resolution) uses Dictionaries and objects. The SoA symbol table is a **component** that other components consume through an interface, not a **fundamental data model** that shapes the entire design.

### On CPU-Friendly Data Access Patterns

The template parser (Story B-1) would parse YAML templates and produce `TemplateOp` objects. These objects are then interpreted by the emit engine (Story C-3). The interpretation loop would be:

```
for each command:
    for each emit_op in compiled_template:
        match emit_op.op_type:
            EMIT_LITERAL: append literal text
            LOAD_ARG: resolve and append
            LOAD_SYM: hash lookup in symbol table
            ...
```

This is a bytecode interpreter — not bad, but the matching on `op_type` is a computed goto/virtual dispatch. The DOD approach would flatten this into **direct function calls** indexed by opcode ID, eliminating the inner match.

### Where Data Layout Concerns Are Ignored

1. **Data layout improvements are P1 (Should), not P0 (Must)** — the first to be cut.
2. **Template parser** (B-1, 8 points, P0) produces Dictionary-based objects.
3. **Placeholder resolution** (B-2, 5 points, P0) uses string-based `$`/`@`/`^` scanning.
4. **No batch processing design** — the emit engine processes one command at a time.
5. **Template Op AST** (B-1) is an array of `TemplateOp` objects — could be a flat opcode array.
6. **No discussion of memory access patterns** in the technical architecture section.

### Constructive Suggestion

Move C-1 (Flat Symbol Table) from Sprint 2 to Sprint 0 as a P0 story. The entire pipeline becomes easier to design if the symbol table is flat arrays from the start. The template parser (B-1) should output **PackedInt32Array opcodes** not an Array of TemplateOp objects. Make the data layout the foundation, not an optimization.

---

## 8. Waterfall/BDUF

**Overall Data-Oriented Score: 2/5 — "Everything specified, nothing optimized"**

### On Cache Efficiency and Memory Layout

The Waterfall plan is **comprehensive** — 1,705 lines of requirements, architecture, design, and verification. But for all that detail, there is **exactly zero** discussion of data layout, memory access patterns, or cache efficiency.

The design specifies:

- [22 files](plans/waterfall_codegen_plan.md:353) in 6 directories
- 5 pipeline stages with detailed component specs
- YAML template format with versioning
- Requirements Traceability Matrix

But the data structures are all **Dictionaries and objects**:

- [`AllocatorStrategy`](plans/waterfall_codegen_plan.md:491) operates on `Dictionary handle` and `Dictionary scope`
- [`CommandRegistry`](plans/waterfall_codegen_plan.md:421) stores descriptors in a Dictionary
- [`TemplateEngine.expand()`](plans/waterfall_codegen_plan.md:400) takes a template_name and params Dictionary
- [`RegisterAllocator`](plans/waterfall_codegen_plan.md:339) is mentioned as a file but not designed

### On Hot/Cold Splitting

**Explicit but wrong.** The plan has a 5-stage pipeline (Validator → Allocate → Expand → Fixup → Output) which separates cold (Validate, Allocate, Fixup) from hot (Expand). But within the Expand stage, every command goes through the full template engine: load from YAML, parse params, resolve, emit. There's no splitting of the hot path into cache-friendly inner loop vs cold helper.

Furthermore, the **Validator stage** (Stage 1) validates the entire IR before processing. For a correct program, this is pure overhead — it touches every byte of the IR twice.

### On Structure-of-Arrays vs Array-of-Structures

**Purely AoS.** The plan's data dictionary (Section 2.4) defines all types as objects with fields. The [`command_descriptor`](plans/waterfall_codegen_plan.md:439) is a YAML Dictionary with nested Dictionaries for operands and phases. The `TemplateResult` is a Dictionary `{text, size}`.

The plan even introduces **more** objects than necessary: `CommandDescriptor`, `TemplateResult`, `AllocationResult`, `PhaseResult` — all Dictionary types that add indirection.

### On CPU-Friendly Data Access Patterns

The YAML-based template system loads templates from disk at startup (requirement NFR-03: ≤50ms). Each template expansion means:

1. Lookup template by name in Dictionary
2. Parse template text for `%name` references
3. Build parameter Dictionary
4. Call `_resolve_params` which does string replacement

Compare with DOD: load templates once, compile to flat opcode array, execute via linear loop.

### Where Data Layout Concerns Are Ignored

1. **1705 lines, zero about memory layout.** The requirements don't mention cache efficiency.
2. **Dictionary-based everything** — symbol table, command registry, template engine, parameter resolver.
3. **YAML as runtime format** — parsing overhead on every template operation.
4. **No flat arrays in any component specification.**
5. **22 files** means 22 separate allocations, 22 potential cache lines to load.
6. **Validator stage** doubles the IR traversal for no benefit on valid inputs.
7. **Requirement NFR-01** ("not slower than current implementation") sets a low bar and doesn't measure cache misses or allocation count.

### Constructive Suggestion

Before signing off Phase 2 (Architecture), add a **Data Layout Specification** section that answers: What is the memory footprint per component? How are arrays laid out? What is accessed on the hot path vs cold path? Which data structures are SoA vs AoS? The 1705-line plan should include at least 200 lines on data layout.

---

## 9. Lisp/Macro-Driven

**Overall Data-Oriented Score: 1/5 — "Layers of abstraction, layers of cache misses"**

### On Cache Efficiency and Memory Layout

The Lisp/Macro plan introduces **massive indirection** through its S-expression tree representation. Every IR command, every assembly instruction, every intermediate value is a **nested Array** (the GDScript equivalent of a cons cell list). The macro expansion engine recursively walks these trees, creating new tree nodes at every step.

The damage:

1. **S-expression trees** ([`IR_Sexpr`](plans/lisp_macro_codegen_plan.md:97), [`Asm_Sexpr`](plans/lisp_macro_codegen_plan.md:98)): Represented as `Array` (GDScript's equivalent of a linked list of Variants). Each Array is a heap object. Each element is a Variant (16+ bytes). A simple `mov EAX, 5;` becomes `["mov", "^dest", "$src"]` — an Array of 3 Variant elements.

2. **Quasiquote representation** ([line 112](plans/lisp_macro_codegen_plan.md:112)): `["quasiquote", ["mov", ["unquote", "dest"], ["unquote", "src"]]]` — 4-level nested Array for one instruction. Every level is a heap allocation.

3. **Pattern matching** ([`PatternVar`](plans/lisp_macro_codegen_plan.md:157), [`Pattern`](plans/lisp_macro_codegen_plan.md:161)): Pattern variables are objects with `name` and `constraint: Callable` fields. The `_match_recursive` function (line 171) recursively descends into nested arrays, creating a hash-map of bindings. Each match allocates bindings, intermediate arrays, and callable invocations.

4. **Gensym** ([`env.gensym()`](plans/lisp_macro_codegen_plan.md:295)): Each label/temporary allocation creates a new symbol and adds it to the environment Dictionary.

5. **5 macro passes** (lines 347-468): Each pass transforms the entire S-expression tree. Pass 1 produces a tree. Pass 2 walks that tree to produce another tree. Each pass allocates a completely new tree. For 10,000 commands, that's 50,000 tree transformations, millions of Array allocations.

### On Hot/Cold Splitting

**Worse than none.** The 5-pass pipeline forces *everything* through every pass. The S-expression tree representation means there's no distinction between hot data (operand types, register assignments) and cold data (scope depths, source locations) — they're all nested arrays in the same tree.

### On Structure-of-Arrays vs Array-of-Structures

**Linked-list-of-Structures.** S-expressions are the polar opposite of SoA. They're nested structures accessed via recursive tree walking. Every element is reached through a chain of Array references and Variant unboxing.

The [`expand`](plans/lisp_macro_codegen_plan.md:131) function recursively descends the tree. For a command like `["OP", "ADD", "a", "b", "res"]`:
- `expand` is called on the outer array
- `head = "OP"` triggers Dictionary lookup in `macro_table`
- `macro_fn.call()` invokes the macro, which produces a new tree
- `expand` is called recursively on the result
- Sub-expressions are expanded recursively

Each recursion level is a function call, a stack frame, and potential cache misses for the macro table, pattern variables, and bindings.

### Where Data Layout Concerns Are Ignored

1. **Entirely.** The plan is about achieving Lisp-like homoiconicity, not about data that lives in memory.
2. **Nested Arrays** for everything — maximum indirection.
3. **Tree transformation pipeline** — each pass builds a new tree from the old one.
4. **Pattern matching with recursive descent** — unpredictable memory access.
5. **Gensym** adds to a growing Dictionary.
6. **Quasiquote expansion** allocates nested Arrays.
7. **No flat representation** anywhere in the design.
8. **Symbolic references everywhere** — `$"a"`, `^"res"`, `@"fun"` — all string-keyed lookups.

### Constructive Suggestion

The macro-expansion concept is powerful, but the S-expression tree representation is actively harmful. Replace nested Arrays with flat opcode sequences. Replace recursive `expand` with a linear bytecode interpreter. Replace `env.gensym()` with pre-allocated label pools. Keep the *idea* of passes-as-transformations but operate on flat arrays, not trees. The quasiquote syntax is elegant for humans but should compile to flat emit operations.

---

## Summary Comparison Table

| Persona | Cache Efficiency | Memory Layout | Hot/Cold Split | SoA vs AoS | CPU-Friendly Patterns | **Overall** |
|---------|:----------------:|:-------------:|:--------------:|:----------:|:---------------------:|:----------:|
| **Functional Purity** | 1 (Dictionary dup storms) | 1 (all Dicts) | 1 (all threaded) | 1 (AoS Dicts) | 2 (recursive match) | **2/5** |
| **Unix Philosophy** | 3 (batch text, but parse thrash) | 2 (text heavy) | 3 (pipelines) | 2 (text AoS) | 2 (string scanning) | **3/5** |
| **TDD** | 1 (objects per test) | 1 (all Dicts) | 1 (no split) | 1 (AoS objects) | 1 (linear search) | **1/5** |
| **Extreme Programming** | 2 (deferred) | 2 (objects) | 2 (partial) | 1 (AoS Fragments) | 2 (string replace) | **2/5** |
| **Design Patterns (GoF)** | 1 (8k objects) | 1 (pattern avalanche) | 1 (decorator chain) | 1 (extreme AoS) | 1 (virtual dispatch) | **1/5** |
| **Literate Programming** | 2 (aware but not fixing) | 2 (Dicts) | 2 (pipeline) | 2 (AoS) | 2 (hash lookups) | **2/5** |
| **Agile/Scrum** | 3 (has stories for SoA) | 3 (planned but deferred) | 2 (implicit) | 3 (C-1 calls for SoA) | 2 (bytecode planned) | **2/5** |
| **Waterfall/BDUF** | 1 (zero layout analysis) | 1 (all Dicts) | 2 (pipeline but no split) | 1 (AoS) | 2 (YAML parsing cost) | **2/5** |
| **Lisp/Macro-Driven** | 1 (nested Array trees) | 1 (sexpr trees) | 1 (5-pass tree realloc) | 1 (linked-list AoS) | 1 (recursive descent) | **1/5** |

### Key Takeaways

1. **No plan prioritizes data layout** as a primary concern. The Unix plan comes closest (batch pipelines) and the Agile plan has the right stories (flat symbol table, bitfield registers), but both treat it as secondary.

2. **Functional approaches are worst for cache** because they duplicate state on every transformation. Every `duplicate()`, `copy()`, or immutable-return allocates fresh memory.

3. **OOP approaches are worst for indirection** — Visitor, Composite, Decorator, and Strategy patterns each add a layer of indirection that becomes a cache miss on the target hardware.

4. **The Unix and Agile plans are the most salvageable** because their pipeline/batch architecture is compatible with flat data. They need data structure replacement (Dictionaries → PackedArrays) but their control flow is already batch-oriented.

5. **Literate Programming is closest in spirit** — it identifies that "the mapping from IR to assembly is data, not code" — but fails to follow through with actual data-oriented data structures.

6. **The DOD plan is the only one** that starts from data layout and derives the architecture from it. Every other plan starts from *control flow* (purity, testability, patterns, process) and treats data as an afterthought.
