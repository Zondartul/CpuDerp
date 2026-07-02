# The History of CpuDerp: Building a Virtual Computer from Scratch

---

## Preface

CpuDerp is not a game. It is a machine — a complete, self-contained virtual computer built inside the Godot engine by a solo developer over roughly twenty months of concentrated effort. It has a custom 32-bit CPU with fourteen registers and thirty-four opcodes. It has 64KB of byte-addressable RAM, a character-mode GPU driving a 56×36 tile display, an interrupt-driven keyboard, and a memory bus that wires them all together. It has an assembler for a custom assembly language called ZDerp, and a full high-level language compiler — tokenizer, parser, semantic analyzer, intermediate representation, and code generator — for a language called MiniDerp. It has a visual debugger with source-level stepping, shadow-memory visualization, and reverse execution. It runs a test operating system — a 251-line command-line shell that accepts keyboard input, processes commands, and prints output to the screen.

The commit log records 87 commits. But the real development time is larger. The project's first tracked commit is a `.gitignore` — an empty vessel — followed immediately by a single commit that dumped 83 files and 3,824 lines of code into the repository. That was a migration, not a birth. The offline history that preceded it — the months of solo hacking before version control arrived — is lost to record. What we have is the fossilized evidence: a complete, functional architecture that emerged from isolation and continued evolving in the light.

**This history was verified against actual git diffs and file snapshots**, not merely commit messages. Every claim about what a commit contained was cross-checked against the concrete insertions, deletions, and file additions recorded in the repository. This verification process uncovered several key discoveries that shaped the narrative:

- **Two CPUs at import** — the big bang commit [`c442b70`](https://github.com/) contained both a full VM interpreter ([`CPU_vm.gd`](scenes/CPU_vm.gd), 730 lines) and a simpler CPU ([`CPU_gd.gd`](scenes/CPU_gd.gd), 95 lines) with its own GPU driver and keyboard echo
- **The ISA was embedded, not extracted** — at import time, the Instruction Set Architecture lived entirely inside [`CPU_vm.gd`](scenes/CPU_vm.gd). The shared [`lang_zvm.gd`](lang_zvm.gd) module was created later, in commit [`f0bd6d9`](https://github.com/) on the same day, when the ISA was extracted into its own file
- **An ambitious ZDerp language stub** — [`comp_compile_zd.gd`](scenes/comp_compile_zd.gd) (73 lines) existed at import, mostly a 40-line comment block describing a high-level language (static and dynamic typing, lambdas, exceptions) with empty `tokenize()` and `compile()` functions
- **Nine assembly test programs** — commit [`8b6f56f`](https://github.com/) included the first real test suite: [`main.txt`](res/data/main.txt), [`shell1.txt`](res/data/shell1.txt), [`shell2.txt`](res/data/shell2.txt), [`shell3.txt`](res/data/shell3.txt), [`lib/libscreen.zd`](res/data/lib/libscreen.zd), [`lib/string.zd`](res/data/lib/string.zd), [`lib/main2.zd`](res/data/lib/main2.zd), proving the assembler produced valid bytecode
- **The June 21st four-feature sprint** — on a single day, four features landed: compound assignment operators, character literals, `#include`, and array literal syntax — the project's most productive 24 hours

This document is the definitive history of CpuDerp. It synthesizes the four-part narrative and the accompanying research notes into a single account that traces the project from its genesis through eight development chapters to its final recorded state. The journey spans emulation, compiler design, programming language engineering, debugger construction, and creative coding — all within the peculiar constraints of the Godot game engine. What follows is the story of a virtual computer, built from nothing, by one person, for the sheer love of building.

---

## Table of Contents

- **Chapter 1: Genesis** — Building a Computer From Nothing
- **Chapter 2: First Light** — The VM Comes Alive
- **Chapter 3: The High-Level Dream** — Enter MiniDerp
- **Chapter 4: Bridging Worlds** — The IR and Code Generator
- **Chapter 5: Source-Level Enlightenment** — High-Level Debugging
- **Chapter 6: Civilizing the Code** — Types and Refactoring
- **Chapter 7: The Feature Sprint** — Crossing Off the TODO List
- **Chapter 8: Deep Waters** — Arrays, Shadow Stacks, and Beyond
- **Epilogue: The State of the Machine**
- **Appendix A: Commit Timeline**
- **Appendix B: Architecture Diagram**

---

## Chapter 1: Genesis — Building a Computer From Nothing

*Commits `2a3aa0c` → `8b6f56f`*

The project begins not with a single line of code, but with an act of transplantation. The very first commit — [`2a3aa0c`](https://github.com/) — contains only a `.gitignore`, an empty promise. Then comes the deluge: commit [`c442b70`](https://github.com/) ("migrating") deposits 83 files and 3,824 lines into the repository in a single shot on **2025-06-09**. This is not a project starting from scratch; it is a fully-formed digital ecosystem, built in isolation offline, now surfacing into version control.

The scope of what arrives is staggering. **Two CPUs**: a 730-line full VM interpreter ([`CPU_vm.gd`](scenes/CPU_vm.gd)) with fetch-decode-execute loop, opcode dispatch, and interrupt handling — AND a 95-line simpler CPU ([`CPU_gd.gd`](scenes/CPU_gd.gd)) with its own GPU driver, keyboard echo, and a `postsetup()` printing "Hello from CPU_gd!". A character-mode GPU ([`GPU_cs.gd`](scenes/GPU_cs.gd)) driving a 56×36 tile display, each tile 7 bytes (char + 3 FG color + 3 BG color), addressed starting at offset 2000. A keyboard handler ([`KB.gd`](scenes/KB.gd)) using a circular buffer with raw unicode. 64KB of RAM ([`RAM_64k.gd`](scenes/RAM_64k.gd)), the full addressable memory space. A memory bus ([`Bus.gd`](scenes/Bus.gd)) capable of routing reads and writes to child devices. A code editor ([`Editor.gd`](scenes/Editor.gd)) with syntax highlighting, file management via [`comp_file.gd`](scenes/comp_file.gd), and a highlight engine. A debug panel ([`debug_panel.gd`](debug_panel.gd)) stretching 202 lines — which **duplicated** all ISA constants (register names, bit flags) independently of the CPU, a duplication that would later need deduplication. A hand-rolled regex engine ([`my_regex.gd`](my_regex.gd)) at 303 lines. A ZDerp language definition ([`lang_zd.gd`](scenes/lang_zd.gd)) defining 43 opcode and register name keywords. A **ZDerp "compiler" stub** ([`comp_compile_zd.gd`](scenes/comp_compile_zd.gd)) — 73 lines consisting mostly of a 40-line comment block describing an ambitious language (static and dynamic typing, lambdas, exceptions) but with empty `tokenize()` and `compile()` functions. A tokenizer rules file ([`zderp_rules.gd`](scenes/..)). A **broken build pipeline** ([`comp_build.gd`](scenes/comp_build.gd)) that referenced `$comp_asm_zd` as a child node — but no such node existed yet, ensuring a runtime error. An **accidentally-committed temp file** ([`scenes/mai9BA4.tmp`](scenes/mai9BA4.tmp)) — 189 lines of transient clutter. Icons, tiles, scenes, and the [`project.godot`](project.godot) configuration (Godot 4.4, GL Compatibility renderer, 512×700 window) binding them together. The architecture is already clear: a modular computer system simulated inside Godot, where a bus connects CPU, RAM, GPU, and keyboard into a harmonious whole. The [`VM.gd`](scenes/VM.gd) node acts as the system orchestrator — a motherboard in software.

**Critically, the ISA was not yet extracted into its own module.** At import time, all 14 register names, 30+ opcodes, control flags, and bit constants were defined directly inside [`CPU_vm.gd`](scenes/CPU_vm.gd). The shared [`lang_zvm.gd`](lang_zvm.gd) module did not exist yet — that refactoring was still hours away in the very next commit.

The heart of this system is the ZVM instruction set, which was embedded in [`CPU_vm.gd`](scenes/CPU_vm.gd) at import. Fourteen named registers — `EAX` through `EDX` for general purpose, `IP` for the instruction pointer, `ESP`/`ESZ`/`ESS` for the stack, `EBP` for stack frames, `IVT`/`IVS` for interrupt handling, `IRQ` for the interrupt flag, and `CTRL` for processor control flags. Thirty-four opcodes organized into control flow (`JMP`, `CALL`, `RET`, `CMP`), interrupt handling (`INT`, `INTRET`), memory operations (`MOV`, `PUSH`, `POP`), ALU arithmetic (`ADD` through `DEC`), ALU logic (`AND` through `NOT`), and bitwise operations (`BAND` through `BCLEAR`). Each instruction is 8 bytes — a fixed-length encoding that trades code density for simplicity.

### The ISA Extraction and First Assembler

Three follow-up commits push the assembler forward, all within the first few days. Commit [`f0bd6d9`](https://github.com/) — **2025-06-09 14:29:57** (same day as the big bang) — was a pivotal refactoring. [`lang_zvm.gd`](lang_zvm.gd) was **created** (115 lines), absorbing the full opcode table, register definitions, control flag bitmasks, and shadow memory type system that had previously been embedded in [`CPU_vm.gd`](scenes/CPU_vm.gd). The CPU lost 167 lines of inline ISA definitions and was refactored to use `const ISA = preload("res://lang_zvm.gd")`, referencing everything via the `ISA.*` prefix. This was a pure refactoring — no behavioral changes, just the birth of a shared, canonical ISA definition.

This commit also created the **first real assembler** ([`comp_asm_zd.gd`](scenes/comp_asm_zd.gd), 129 lines), featuring: comment removal and whitespace trimming, a character-class tokenizer with integer token classes, label detection, command parsing via opcode lookup in the freshly-minted `ISA.opcodes`, and bytecode emission at 8 bytes per instruction. However, the debug panel ([`debug_panel.gd`](debug_panel.gd)) was **not updated** — it still carried its own duplicate copies of all `regnames`, `BIT_*`, and `REG_*` constants.

Then came the breakthrough. Commit [`8b6f56f`](https://github.com/) — **2025-06-12** — bore the honest message: *"assembly seems to work"*. The assembler was **massively rewritten**: 403 insertions, 107 deletions. String token classes replaced integer classes, a proper iterator-based parser emerged with `parse_label()`, `parse_db()`, `parse_command()`, forward reference linking with `link_internally()` and `patch_ref()` was added, `db` directives with `emit_db_items()` supported raw data and string constants, and `Cmd_arg`/`Cmd_flags` inner classes formalized operand parsing. The ISA was extended with `spec_ops` — conditional jump aliases (`JG`, `JL`, `JE`, `JZ`, `JNZ`, `JNE`, `JNG`, `JNL`) mapped to opcode 3 (`JMP`) with different flag mask combinations.

For the first time, **nine assembly test programs** appeared in the repository, proving the assembler could produce real, structured code:
- [`main.txt`](res/data/main.txt) (88 lines): a Hello World program with conditional branching
- [`shell1.txt`](res/data/shell1.txt) (99 lines): a shell environment with `for_loop`, `puts`, `putch`, `scr_clear`, `set_color`
- [`shell2.txt`](res/data/shell2.txt) (124 lines): stack frame access tests via `ebp[9]`, `ebp[10]`
- [`shell3.txt`](res/data/shell3.txt) (163 lines): a full shell featuring `itoa`, `str_rev`, `strlen` — essentially a complete stdlib in ZVM assembly
- [`lib/libscreen.zd`](res/data/lib/libscreen.zd) (54 lines): reusable screen library
- [`lib/string.zd`](res/data/lib/string.zd) (57 lines): reusable string library
- [`lib/main2.zd`](res/data/lib/main2.zd) (54 lines): a keyboard test program

But there was a gap: the assembler could produce bytecode, but there was no way to run it yet.

---

## Chapter 2: First Light — The VM Comes Alive

*Commits `0f610f4` → `490cb72`*

The gap closes. Commit [`0f610f4`](https://github.com/) ("assembled code now uploads to CPU and debugger barely works") connects the pipeline end-to-end for the first time. The assembler gains the ability to export its code array. The build system ([`comp_build.gd`](scenes/comp_build.gd)) becomes the bridge, calling the assembler and feeding the result into the CPU. The RAM module ([`RAM_64k.gd`](scenes/RAM_64k.gd)) gains write access for program loading. The debugger (`debug_panel.gd`) tries — barely — to display something useful. This is the moment the system stops being a collection of parts and becomes a computer.

What follows is a period of essential tooling. A memory viewer ([`Memory.gd`](scenes/Memory.gd)) appears — a standalone hex dump display that lets the developer inspect what the assembler produces. Then comes shadow memory: commit [`c98c965`](https://github.com/) introduces a parallel memory layer that tracks the *type* of each byte in main RAM. Constants like `SHADOW_CMD_HEAD`, `SHADOW_DATA`, `SHADOW_CMD_UNRESOLVED` transform raw bytes into annotated artifacts. The memory viewer becomes color-coded — green for command headers, yellow for data, red for unresolved references. The developer can glance at memory and understand the layout at a high level.

The same commit fixes a critical "ref_patch byte offset" bug in the assembler — label resolution required patching forward references with correct addresses, and a byte offset error meant those patches landed on the wrong bytes. With that fixed, non-trivial programs become possible.

### The Three-Month Gap

The commit history tells a remarkable story: after the adrenaline of the big bang import on June 9th and the breakthrough "assembly seems to work" on June 12th, the narrative goes *silent*. **Three months pass.** The next commit — [`490cb72`](https://github.com/) — arrives on **2025-09-16**. What happened in those three months? The commit log doesn't say. But the code tells us: this was a period of solitary, offline development — testing, debugging, fixing, breaking, fixing again. Some problems cannot be solved by typing faster.

### The Great Migration and Hello World

The chapter climaxes with commit [`490cb72`](https://github.com/): "moved to Godot 4.5, IP highlight in memview, CPU works for first time (Hello World)." The [`project.godot`](project.godot) config changed from Godot **4.4** to **4.5**. A new function — [`decode_op_variant()`](scenes/CPU_vm.gd) — maps decoded flag combinations back to human-readable opcode mnemonics, so a `JMP` with `CMP_G` flags displays as `JG`. The [`debug_disasm_cmd()`](debug_panel.gd) output becomes vastly more readable.

A **subtle but critical fix** corrects the assembler's hardcoded immediate value of 0 — every instruction with an immediate operand had been encoding zero instead of the intended value for three months. The fix passes `arg1.offset+arg2.offset` as the immediate value. Array access via `eax[N]` is also fixed — `arg.is_deref = true` now activates after processing bracket syntax.

The memory viewer ([`Memory.gd`](scenes/Memory.gd)) gains an Instruction Pointer highlight — a single conditional `if i == ip` that paints the current execution address in dark blue, letting the developer watch the CPU march through memory. And after all of it — the big bang, the assembler iterations, the shadow memory, the Godot upgrade, the three-month silence — the CPU executes a real program. "Hello World" prints to the GPU screen. A computer, built from nothing, is alive.

---

## Chapter 3: The High-Level Dream — Enter MiniDerp

*Commits `39b6389` → `5d2bf78`*

Assembly works. But assembly is tedious. Writing ZDerp requires hand-managing registers, tracking stack frames, and resolving label addresses. The developer stares at the working assembler and makes a decision that will define the project's next phase: build a high-level language compiler. Not a transpiler, not a macro preprocessor — a real compiler with a tokenizer, parser, semantic analyzer, intermediate representation, and code generator.

MiniDerp is born in commit [`39b6389`](https://github.com/) ("wip compiler"). Three new files appear: a general-purpose word-boundary tokenizer ([`word_boundary_tokenizer.gd`](scenes/word_boundary_tokenizer.gd)), a compiler orchestration skeleton ([`comp_compile_md.gd`](scenes/comp_compile_md.gd)), and a language definition ([`lang_md.gd`](scenes/lang_md.gd)) declaring keywords (`var`, `func`, `if`, `else`, `while`, `return`), types (`int`, `char`, `float`, `u8`-`u64`, `s8`-`s64`, `Ref`, `String`), operators, and the first grammar rules.

The word-boundary tokenizer's `should_split_on_transition()` function at [`word_boundary_tokenizer.gd`](scenes/word_boundary_tokenizer.gd:28-52) decides the split logic: `WORD`+`NUMBER` stays together (allowing identifiers with trailing digits like `var2`), `STRING` tokens accumulate between quotes without splitting, and `PUNCT` always splits one-by-one.

The tokenizer evolves rapidly. A dedicated MiniDerp tokenizer ([`md_tokenizer.gd`](scenes/md_tokenizer.gd)) replaces the generic approach with a **four-stage pipeline**: `basic_tokenize()` → `recombine_tokens()` → `reclassify_tokens()` → `filter_tokens()`. Each stage refines the token stream: preprocessing handles `#include` directives; basic tokenization uses the word-boundary tokenizer; **recombination** merges adjacent tokens — `["+", "+"]` becomes `"++"`, `["!", "="]` becomes `"!="`; **reclassification** runs `WORD` tokens against keyword, type, operator, and punctuation dictionaries; **filtering** strips whitespace and comments. Character literal resolution converts `'a'` syntax into numeric values.

The grammar in [`lang_md.gd`](lang_md.gd) grows from 43 lines to over **130 shift-reduce rules** covering variable declarations, assignments, compound assignments, function definitions, `while` loops, `if`/`elif`/`else` chains, flow control, preprocessor directives, and the full expression hierarchy. Each rule is an array: `[input..., lookahead, result]`. The `SHIFT` pseudo-result forces the parser to consume a token without reducing — a critical mechanism for handling operator precedence. A rule like `["expr", "OP", "expr", "/[", "SHIFT"]` prevents premature reduction when array indexing follows an expression. By commit [`3d310d4`](https://github.com/), parsing is "decent."

The analyzer ([`analyzer_md.gd`](scenes/analyzer_md.gd)) maps MiniDerp operators to IR operations via a **22-operator `op_map`** spanning arithmetic (`+` → `ADD`, `-` → `SUB`, `*` → `MUL`, `/` → `DIV`, `%` → `MOD`), comparison (`>` → `GREATER`, `<` → `LESS`, `==` → `EQUAL`, `!=` → `NOT_EQUAL`), logical (`&&` → `AND`, `||` → `OR`, `!` → `NOT`), bitwise (`&` → `B_AND`, `|` → `B_OR`, `^` → `B_XOR`, `>>` → `B_SHIFT_RIGHT`, `<<` → `B_SHIFT_LEFT`, `~` → `B_NOT`), and increment/decrement (`++` → `INC`, `--` → `DEC`). It tracks symbols with a scope table, manages control flow stacks for `break` and `continue`, and walks the AST recursively to build IR commands.

The intermediate representation ([`ir_md.gd`](scenes/ir_md.gd)) defines typed values, code blocks, and IR commands. A custom serialization format called Micro-YAML ([`uYaml.gd`](scenes/uYaml.gd)) — built, as the developer notes, "because I was bored" — serializes the IR between pipeline stages.

By the end of the chapter, the compiler frontend is complete: Source Code → Tokenizer → Parser → Analyzer → IR → (serialized). Each stage has its own debug visualization. The developer can open a MiniDerp file, click "compile," and watch the transformation from raw text to structured intermediate representation. But the IR is just a plan. It describes what the program should do, but doesn't generate any code the ZVM can execute. That challenge lies ahead.

---

## Chapter 4: Bridging Worlds — The IR and Code Generator

*Commits `ecbd8f7` → `784a049`*

The frontend is beautiful. The back end does not exist. The code generator ([`codegen_md.gd`](scenes/codegen_md.gd)) begins as a 57-line skeleton — a `generate()` function and little else. Then commit [`fa3525c`](https://github.com/) ("wip code generator") explodes it to 412+ lines, making it one of the largest files in the project.

The code generator's architecture is a masterclass in pragmatic compiler design. Register allocation manages four general-purpose ZVM registers (`EAX`, `EBX`, `ECX`, `EDX`) with tracking and spilling. The `op_map` dictionary translates IR operations into sequences of ZDerp assembly instructions — for example, the `EQUAL` comparison becomes a sequence of `CMP`, `MOV`, `BAND`, and `BNOT` instructions that compare two values, extract the zero flag, and normalize it to a boolean without branching. Stack frame management tracks byte-level offsets for local variables, emitting `ENTER` and `LEAVE` instructions for function prologues and epilogues.

The struggle is real and documented in the commit messages. Commit [`b7bb908`](https://github.com/) admits "handle.storage.pos still bork" — stack frame offsets are broken. Then comes the low point: commit [`c67b2d8`](https://github.com/) — three words: **"codegen's fucked."** Three hundred sixty-two lines added, but something has collapsed. The next commit, "fixed a crash," patches the regression. The code generator limps back to life.

While the code generator struggles, the debug panel flourishes. Commit [`9df489c`](https://github.com/) ("cool debugger visuals wip") and commit [`c771566`](https://github.com/) ("super duper debugger stuff") transform the debug panel into the developer's primary window into the running system: register displays, step/run controls, IP tracking, color-coded memory. A visual indicator ([`indicator.gd`](scenes/indicator.gd)) and frequency control give the developer granular execution control.

Then the milestone: commit [`784a049`](https://github.com/) — **"miniderp hello world achieved! also perf_limiter."** The first MiniDerp program compiles through the entire pipeline — tokenize → parse → analyze → codegen → assemble → upload → execute — and produces "Hello World" on the GPU screen.

Several key additions made this possible:

- **GPU buffer memory model** — [`GPU_cs.gd`](scenes/GPU_cs.gd) gained a `mem:Array[int]` field alongside the existing direct-write path, and a `READ_RETURNS_BUFFER = true` constant decoupled the GPU's rendering pipeline from its memory interface, allowing compiled programs to write to memory without corrupting the display
- **Performance limiter** — [`PerfLimiter.gd`](PerfLimiter.gd) and [`PerfLimitDirectory.gd`](PerfLimitDirectory.gd) introduced a token-bucket rate limiter to prevent the CPU from running too fast during debugging
- **Screensaver victory lap** — the developer added two GPU screensaver functions ([`_screensaver_matrix()`](scenes/GPU_cs.gd) and [`_screensaver_nyan()`](scenes/GPU_cs.gd)), Matrix code rain and Nyan Cat scrolling across the display — a digital celebration

The emotional arc from "codegen's fucked" to "miniderp hello world achieved" was steep. The developer had stared at broken stack frame offsets, tangled register allocations, and type system integration failures for commit after commit. Each failed execution was another reminder that the bridge between high-level semantics and low-level bytes was still incomplete. Now, with the pipeline complete, MiniDerp was real. And it was *celebrating*.

---

## Chapter 5: Source-Level Enlightenment — High-Level Debugging

*Commits `19fffe4` → `7dde647`*

MiniDerp Hello World runs, but the developer sees the problem immediately: when the program executes, there is no way to know what it is doing at the MiniDerp source level. The assembler debugger shows registers and memory addresses — fine for assembly, useless for high-level code. What the project needs is source-level debugging: the ability to step through MiniDerp code and watch the current source line highlighted on screen.

This is the longest phase of the project — **29 commits** of grueling infrastructure work. The first prerequisite is backward stepping: commit [`19fffe4`](https://github.com/) ("implemented backwards stepping") adds reverse execution to the CPU, a nontrivial feature that requires decrementing the instruction pointer, undoing register changes, and rolling back memory writes. The performance limiter is extracted into dedicated classes ([`PerfLimiter.gd`](PerfLimiter.gd), [`PerfLimitDirectory.gd`](PerfLimitDirectory.gd)).

Commit [`256fcb1`](https://github.com/) ("more type hints, error callouts from analyzer") is a watershed 33-file, 1,295-line refactoring that transforms the codebase from ad-hoc dictionaries into a properly typed class hierarchy. **Seven new class files** appear:

- [`class_ErrorReporter.gd`](class_ErrorReporter.gd) — 45 lines, structured error reporting with caret annotation pointing at the error column, emitting `sig_highlight_line` for source-line highlighting
- [`class_Token.gd`](class_Token.gd) — 19 lines, a `RefCounted` with class properties `tok_class`, `text`, `loc`, with a `duplicate()` method using `G.duplicate_shallow`
- [`class_AST.gd`](class_AST.gd) — 15 lines, extends `Token` so every AST node is a token with source location, adding `children:Array[AST]`
- [`class_Chunk.gd`](class_Chunk.gd) — 25 lines, with `code:Array[int]` bytecode, `shadow:Array[int]`, `labels`, `refs`, `label_toks`, `error` bool, and `duplicate()` using `G.duplicate_deep`
- [`class_Cmd_arg.gd`](class_Cmd_arg.gd) — 11 lines, properties for `is_present`, `reg_name`, `reg_idx`, `offset`, `is_deref`, `is_imm`, `is_32bit`, `is_unresolved`
- [`class_Cmd_flags.gd`](class_Cmd_flags.gd) — 26 lines, with `to_byte()` packing flags into a single byte, `set_arg1()` and `set_arg2()` copying from `Cmd_arg` objects
- [`class_Iter.gd`](class_Iter.gd) — 12 lines, a token iterator with `tokens:Array` and `pos:int`, sharing the underlying token list on duplicate

**Error code constants** are defined in the autoloaded [`error_list.gd`](error_list.gd) singleton (registered as `E`), spanning `ERR_01` through `ERR_31`. Assembler errors cover unlinked references, invalid ops, byte overflow, bad addressing modes. Analyzer errors cover undefined identifiers (`ERR_29`), misplaced `continue` (`ERR_30`), and invalid operator usage (`ERR_31`). The parser is extracted into its own file ([`parser_md.gd`](scenes/parser_md.gd), 106 lines). The enormous `log.txt` — 186K+ lines — is deleted in a symbolic cleanup.

The hardest engineering challenge — consuming over 10 commits — is **location tracking**. Every IR command and assembly instruction must know which MiniDerp source line produced it. Two classes form the foundation: [`class_Location.gd`](class_Location.gd) with fields for `filename`, `line`, `line_idx`, `col`, and a unique `uid` for ordering; [`class_LocationRange.gd`](class_LocationRange.gd) as a pairing of `begin` and `end` locations. The Expanded Location Map (ELM), introduced in commit [`8baa478`](https://github.com/), maps assembly addresses to their corresponding source locations. The debug panel ([`debug_panel.gd`](debug_panel.gd)) grows by hundreds of lines to render these mappings.

The results come gradually: "HL highlight sort of works" (commit [`a3e63f4`](https://github.com/)), then step/unstep in high-level mode (commit [`8d68202`](https://github.com/)), then local variable display (commit [`8f2d368`](https://github.com/)). A two-line fix in commit [`4206d91`](https://github.com/) eliminates flicker. Finally, commit [`7dde647`](https://github.com/) — "fixed high-level debug" — delivers the culmination. The debugger window ([`win_ed_dbg.gd`](scenes/win_ed_dbg.gd)) shows the current MiniDerp source line highlighted in real time during execution. Step forward. Step backward. Watch variables change. The source-level debugger is no longer a prototype; it is a tool.

---

## Chapter 6: Civilizing the Code — Types and Refactoring

*Commits `e8e17fa` → `18f2880`*

MiniDerp was born a duck-typed language. Variables declared with `var x = 5` let the compiler infer their nature from context. This sufficed for Hello World, but as programs grew — as the developer began writing a test operating system — the limitations became clear. Without type annotations, the analyzer cannot catch mistakes. Without a type system, the code generator cannot optimize memory layout. MiniDerp needs to grow up.

### The Type System Is Born

The type system is born in commit [`e8e17fa`](https://github.com/) ("wip types"), dated **October 29, 2025**. The [`class_Type.gd`](class_Type.gd) file — initially 23 lines — defines a `RefCounted` class with three fields: `name` (the user-visible type name like `"int"` or `"Ref"`), `of` (an array of child types for **recursive generics** like `of:Array[Type]` representing `Ref[char]`), and `size` (bytes in memory). The [`get_full_name()`](class_Type.gd:13) method composes type names recursively — `Ref[char]` becomes `"Ref[char]"`. The [`from_string()`](class_Type.gd:25) static method parses type strings back into objects using a custom brace-counting state machine. A hierarchy of primitive sizes is defined: `u8`, `s8`, `char` at 1 byte, `u16`/`s16` at 2, `u32`/`s32`/`float` at 4, `u64`/`s64`/`int`/`double` at 8. Pointer types (`Ref`, `Array`, `String`) are all 4 bytes — the ZVM's native address width.

The analyzer gains **type aliases**: `"String"` → `"Ref[char]"`, `"char"` → `"u8"`, letting the developer write `str:String` in source code while the type checker resolves it to `Ref[char]` — a pointer to a character buffer. A `type_stack` tracks types through expression evaluation.

The language definition in [`lang_md.gd`](scenes/lang_md.gd) is extended with eight new grammar rules for type expressions: `TYPE` → `type_expr`, `TYPE[type_expr]` → `type_expr` for parameterized types like `Ref[char]`, and `IDENT : type_expr` → `expr_typed_ident` — the typed identifier syntax where a colon after an identifier declares its type.

Commit [`1546a09`](https://github.com/) ("Miniderp compiles with type hints") wires the type system through the entire pipeline. A test file ([`hello_typed.md`](res/data/hello_typed.md)) shows the type system in action: `func print(str:String, r:u8, g:u8, b:u8)` — every parameter annotated, every type checked.

### Type Safety Refactoring

Commit [`7d293c1`](https://github.com/) ("refactored for better type safety") is a landmark 377-line restructuring that introduces **four new typed class files**:

- [`class_AssyBlock.gd`](class_AssyBlock.gd) — 10 lines, assembly code blocks with an embedded [`LocationMap`](class_AssyBlock.gd:5), `code:String` for generated assembly text, `loc_map:LocationMap`, and `write_pos:int`
- [`class_CodeBlock.gd`](class_CodeBlock.gd) — 14 lines, **extends `IR_Value`** (meaning code blocks ARE values), with `code:Array[IR_Cmd]`, `lbl_from`, `lbl_to`, and `val_type` set to `"code"` — the foundation for function pointers and indirect calls
- [`class_IR_cmd.gd`](class_IR_cmd.gd) — 28 lines, IR commands as proper objects with `words:Array[String]` (instruction tokens) and `loc:LocationRange`
- [`class_LocationMap.gd`](class_LocationMap.gd) — 10 lines, a bidirectional map between instruction pointers and `LocationRange` objects with `begin` and `end` dictionaries

The code generator receives a 377-line rewrite to use these typed classes throughout. Every variable gets a **full type annotation**: `assy_block_stack:Array[AssyBlock]`, `cur_assy_block:AssyBlock`, `referenced_cbs:Array[CodeBlock]`, `cur_block:CodeBlock`, `cb_stack:Array[CodeBlock]`.

The `op_map` is restructured: previously each IR operation was a single string template; now each value is an **array of strings**, one line per instruction:
```gdscript
"ADD":["add %a, %b;\n"],
"GREATER":["cmp %a, %b;\n", "mov %a, CTRL;\n", "band %a, CMP_G;\n", "bnot %a;\n", "bnot %a;\n"],
```
This allows the code generator to insert location markers between individual instructions. A new **`imm_map`** maps comparison flags like `CMP_G`, `CMP_L`, `CMP_E` — a lookup table for immediate values in assembly templates. A system-wide **`val_idx`** numbering scheme with `bump_val_idx()` assigns unique numeric identities to every IR value. Debug mode is engaged — `ADD_DEBUG_TRACE` is set to `true` for verbose logging across the pipeline.

### The Codegen Crisis and Recovery

But the integration is painful. The **timeline insight is crucial**: the type system was born on **October 29, 2025** ([`e8e17fa`](https://github.com/)), while the codegen crisis — commit [`c67b2d8`](https://github.com/) — **"codegen's fucked"** — was dated **October 31, 2025**. The type system was designed and committed two days *before* the codegen broke. This wasn't a coincidence: the type system came first, and the code generator was struggling to *keep up* with the newly-typed IR. The IR now carried typed value references; the code generator had to allocate registers with type-appropriate sizes, emit correct memory access instructions for 8-bit vs 32-bit values, and track type information through the assembly output. The old ad-hoc codegen wasn't designed for any of this.

362 lines were added to [`codegen_md.gd`](scenes/codegen_md.gd). An [`export_presets.cfg`](export_presets.cfg) file appeared — the developer was contemplating packaging whatever worked and moving on.

The recovery comes in commit [`18f2880`](https://github.com/) ("fixed a crash"). The regression is diagnosed and patched. But the most significant addition is a new test file: [`res/data/testOS/main.md`](res/data/testOS/main.md) — 60 lines of MiniDerp code that will grow into a full test operating system. The testOS becomes a command-line shell running on the ZVM, accepting keyboard input, processing commands, and printing output. It expands to 251 lines by the project's end. The type system survives. MiniDerp is no longer a toy language; it has types, a type checker, and a test operating system proving the entire pipeline can build real software.

---

## Chapter 7: The Feature Sprint — Crossing Off the TODO List

*Commits `2ca5f3a` → `f1c3917`*

The type system is stable. The code generator has survived its crisis. High-level debugging works. But the developer knows exactly what doesn't work: a mental TODO list of sharp edges and missing features. The `!=` operator produces garbage. Array indexing has broken precedence. There is no character literal syntax, no `#include` directive, no compound assignment operators, no arity checking, no indirect calls, no arrays.

Before writing code, the developer writes documents. Commit [`2ca5f3a`](https://github.com/) ("wip") detonates 3,507 lines of documentation across 15 files. The [`docs/todo.md`](docs/todo.md) file — nine lines — is the shortest and most important: a raw checklist of bugs and missing features. [`docs/todo_implementation.md`](docs/todo_implementation.md) — 485 lines — documents the entire compiler pipeline phase by phase. [`docs/miniderp_syntax.md`](docs/miniderp_syntax.md) — 242 lines — formally defines the MiniDerp language with all 22 supported syntax constructs.

Then come the plans. Eight plan files in the new [`plans/`](plans/) directory, each addressing a specific deficiency: [`implementation_not_equal.md`](plans/implementation_not_equal.md) (191 lines), [`implementation_precedence.md`](plans/implementation_precedence.md) (177 lines), [`implementation_character_literals.md`](plans/implementation_character_literals.md) (113 lines), [`implementation_include.md`](plans/implementation_include.md) (159 lines), [`implementation_compound_operators.md`](plans/implementation_compound_operators.md) (155 lines), [`implementation_arity.md`](plans/implementation_arity.md) (298 lines), [`implementation_indirect_calls.md`](plans/implementation_indirect_calls.md) (190 lines), [`implementation_array.md`](plans/implementation_array.md) (260 lines).

### The June 21st Sprint

What follows is the most concentrated burst of feature development in the project's history. **Four of those features landed in a single day — June 21st, 2026.** The developer had planned, documented, and then executed with machine-gun precision:

| Commit | Feature | Scope |
|--------|---------|-------|
| [`5606e3a`](https://github.com/) | `!=` fix | One-line tokenizer fix + single-line codegen comparison table entry |
| [`e65e359`](https://github.com/) | Precedence fix | Two SHIFT lookahead rules in [`lang_md.gd`](scenes/lang_md.gd) (2 characters) |
| [`2401d5f`](https://github.com/) | Character literals | 12 files: `CHAR`/`ENDCHAR` tokenizer pattern, `resolve_char_tokens()`, KB rewrite |
| [`083faf5`](https://github.com/) | `#include` | Preprocessor text substitution, first library file [`lib/screen.md`](res/data/testOS/lib/screen.md) |
| [`2b28284`](https://github.com/) | Compound operators | 5 operators desugared: `x += 5` → `OP ADD + MOV` |
| [`428b3f5`](https://github.com/) | Arity check | Argument count validation with `ERR_35`/`ERR_36` |
| [`560c81a`](https://github.com/) | Indirect calls | Function pointers via runtime address resolution |
| [`f1c3917`](https://github.com/) | Arrays (begun) | Grammar rules, `ALLOC`/`MOV_ARR` IR commands, `expr_index` extraction |

#### Feature Details

**Compound assignment** desugaring in the analyzer ([`analyzer_md.gd`](scenes/analyzer_md.gd)): the trailing `=` is stripped from the operator text (turning `+=` into `+`), the base operator is looked up in `op_map`, the binary operation IR is emitted, then a `MOV` stores the result back into the LHS. `x += 5` becomes `OP ADD x, 5, tmp` followed by `MOV x, tmp`.

**Character literals** use the `CHAR`/`ENDCHAR` tokenizer pattern mirroring `STRING`/`ENDSTRING`: a single quote `'` triggers `CHAR` mode, a second `'` triggers `ENDCHAR`. The leading `'` is stripped, preserving only the character content. [`resolve_char_tokens()`](scenes/md_tokenizer.gd) calls `c_unescape()` for escape sequences (`\n` → newline, `\t` → tab, `\'` → literal quote), converts the result to an ASCII buffer, validates a single byte remains, and replaces the token text with the decimal ASCII value. The keyboard handler ([`KB.gd`](scenes/KB.gd)) is completely rewritten with a new [`get_special_ASCII()`](scenes/KB.gd) function using a `match` on `event.keycode` — Enter→10, Backspace→8, Tab→9, Escape→27, Delete→127, Space→32 — with multi-byte UTF-8 explicitly filtered out.

**`#include`** is implemented as a preprocessor step in [`md_tokenizer.gd`](scenes/md_tokenizer.gd) through three functions: `process_includes()` searches for `#include` directives via `text.find("#include")`, extracts the filename with `get_word_at()`, reads the file with `include_file()`, and replaces the `#include` line with the file contents through **text substitution**. It continues recursively, enabling transitive dependencies. Filenames are resolved relative to `cur_path`, the base directory of the current source file. The first library file — [`lib/screen.md`](res/data/testOS/lib/screen.md) — provides `print`, `putch`, `println`, `newline`, and screen I/O primitives.

**Array indexing** is extracted into its own grammar rule, `expr_index` ([`lang_md.gd`](scenes/lang_md.gd)), and promoted into the expression hierarchy: `["expr_index", "*", "expr_infix"]` — array indexing becomes a first-class expression with the same precedence as infix operations.

Seven items crossed off the TODO list. One item — arrays — remains. The sprint demonstrates a new workflow: plan first, then execute the precise, minimal change. The project has stopped being a hack and started being an engineering effort.

---

## Chapter 8: Deep Waters — Arrays, Shadow Stacks, and Beyond

*Commits `1b2dc74` → `833801`*

Arrays are the gateway drug to complexity in language implementation. Without arrays, variables are scalars, memory is flat, and life is simple. With arrays come pointer arithmetic, indexed addressing, bounds awareness, and layout calculations. MiniDerp now has array literal syntax — `var arr = [1, 2, 3]` — but the code generator's handling is incomplete.

The chapter opens with a mystery: commit [`1b2dc74`](https://github.com/) ("wip") adds a new scene file: [`contraption/panel_contraption.tscn`](contraption/panel_contraption.tscn). The word "contraption" is unusual in this project — most files have descriptive, functional names. A contraption is something experimental, a gadget. The scene is likely a UI element for array visualization or debugging — a panel that displays array contents during execution. The commit message offers no explanation.

Work continues. The array plan document is revised with new insights (+80/-19 lines). A test file ([`res/data/test_arr2.md`](res/data/test_arr2.md)) exercises both array declaration syntaxes — `var arr1[10]` and `var arr2 = [1027, 1028, 1029]`. Two massive new plan documents appear: [`plans/implementation_debug_panel_pointers.md`](plans/implementation_debug_panel_pointers.md) (549 lines) designs interactive pointer navigation in the debugger; [`plans/implementation_parser_dfa.md`](plans/implementation_parser_dfa.md) (1,013 lines) — the largest plan in the project — describes a complete rewrite of the shift-reduce parser as a DFA-based engine.

Array debugging proves stubborn. The developer writes a formal diagnosis document: [`docs/diagnosis_array_literal.md`](docs/diagnosis_array_literal.md) — 346 lines tracing the full pipeline for `var x = [1,2,3]`. This is debugging as scientific method: observe, hypothesize, test, repeat.

### The Shadow Stack

The most architecturally significant addition is shadow stack instrumentation. Commits [`6ebdc5a`](https://github.com/) and [`fe29c69`](https://github.com/) (both **June 29, 2026**) add a system for marking every stack memory cell with metadata about its role in the call frame.

Six new shadow constants join the ISA at [`lang_zvm.gd`](lang_zvm.gd:150-155):
```gdscript
const SHADOW_FRAME_PREV_EBP = 9;
const SHADOW_FRAME_PREV_IP = 10;
const SHADOW_FRAME_ARGUMENT = 11;
const SHADOW_FRAME_VAR = 12;
const SHADOW_FRAME_TEMP = 13;
const SHADOW_FRAME_PADDING = 14;
```

A new [`SHADOW_TO_STRING`](lang_zvm.gd) dictionary maps every constant to a human-readable label for debug display. The code generator grows by 180 total lines across the two commits. A key change: the `INDEX` op is modified from `add %a, %b` to **`mul %b, 4; add %a, %b`** — multiplying the index by 4 to perform byte-addressed 32-bit cell access.

The memory viewer ([`Memory.gd`](scenes/Memory.gd)) grows by 55 lines to render these new shadow types. A new **`interp_numbers()`** function adds a numeric column showing 4-byte groups decoded as u32 integers — letting the developer read raw memory as actual values. The **`shadow_colors`** dictionary is expanded with six new color entries for the **color-coded stack frame visualization**:

- **RED** for `PREV_EBP` (saved base pointer)
- **CYAN** for `PREV_IP` (saved return address)
- **ORANGE** for arguments
- **YELLOW** for local variables
- **PURPLE** for temporaries
- **DARK_BLUE** for padding

Each region of the stack becomes visually identifiable. The developer can look at the memory view and see the entire stack frame structure at a glance.

Arrays reach "mostly working" status in commit [`d59611f`](https://github.com/). The test operating system expands massively — from roughly 100 lines to 154 — exercising arrays with a character buffer (`var buff[80]`), keyboard input processing, string comparison, length calculation, reversal, number printing, and command dispatch. Two final commits close the history: a merge commit with no code changes, and then commit [`833801`](https://github.com/) — "small fixes, something still broken on compile" — the project's last recorded word. The commit message is characteristic: honest, direct, unpolished. The work is never finished.

---

## Epilogue: The State of the Machine

As the commit log falls silent, let us survey what has been built.

**The Virtual Computer** runs inside the Godot engine, but it is no less real for being virtual. The ZVM has a 64K address space with byte-addressable memory ([`RAM_64k.gd`](scenes/RAM_64k.gd)), a 32-bit CPU with 14 registers and 34 opcodes defined in [`lang_zvm.gd`](lang_zvm.gd:4-127), a fetch-decode-execute loop in [`CPU_vm.gd`](scenes/CPU_vm.gd) that runs forward and backward, an interrupt system with an interrupt vector table, shadow memory tracking every byte's role, and comparison flags for conditional execution.

**The Two-Language Compiler Pipeline** transforms high-level MiniDerp source into executable ZDerp assembly. The tokenizer ([`md_tokenizer.gd`](scenes/md_tokenizer.gd)) handles keywords, operators, string and character literals, comments, and preprocessor directives. The parser ([`parser_md.gd`](scenes/parser_md.gd)) applies 176 shift-reduce grammar rules from [`lang_md.gd`](scenes/lang_md.gd). The analyzer ([`analyzer_md.gd`](scenes/analyzer_md.gd)) performs semantic analysis with symbol resolution, type checking, arity validation, and 58 error codes. The intermediate representation ([`ir_md.gd`](scenes/ir_md.gd)) carries typed values and commands. The code generator ([`codegen_md.gd`](scenes/codegen_md.gd)) translates IR to ZDerp assembly with register allocation, stack frame management, and shadow stack instrumentation. The assembler ([`comp_asm_zd.gd`](scenes/comp_asm_zd.gd)) produces machine code with reference resolution and patching.

**The Visual Debugger** ([`debug_panel.gd`](debug_panel.gd), ~1,000+ lines) provides source-level stepping with line highlighting, register state display for all 14 registers, color-coded memory visualization via shadow types, stack frame exploration showing arguments, locals, temporaries, and saved frame pointers, forward and backward execution at controllable speed, and high-level local variable inspection with type and value display.

**The Editor and IDE** ([`Editor.gd`](scenes/Editor.gd), [`comp_file.gd`](scenes/comp_file.gd), [`comp_search.gd`](scenes/comp_search.gd)) provides multi-tab editing with syntax highlighting for both MiniDerp and ZDerp, file management with open/save/close, text search across open files, build console with status messages and error reporting, and language auto-detection from file extension.

**The MiniDerp Language** supports 22 defined syntax constructs spanning declarations (variable, function, extern, typed, array), assignment (simple and compound), control flow (while, if/elif/else, break, continue, return), expressions (arithmetic, comparison, logical, bitwise, indexing, direct and indirect calls, all literal forms), preprocessor directives (`#include`), and a typed type system (int, char, float, double, u8-u64, s8-s64, Ref, String).

**The Test Operating System** ([`res/data/testOS/main.md`](res/data/testOS/main.md), 251 lines) is the project's crowning test case — a command-line shell with keyboard input, screen output, string processing, number formatting, and command dispatch, all running on the custom ZVM. It is supported by a standard library ([`res/data/testOS/lib/screen.md`](res/data/testOS/lib/screen.md)) providing screen I/O primitives.

**What remains unfinished** is documented honestly in [`docs/todo.md`](docs/todo.md) and the [`plans/`](plans/) directory. Arrays need final polish — the commit log ends with a broken compile. The debug panel could support interactive pointer navigation (549-line plan waiting). The parser could be rewritten as a DFA-based engine (1,013-line plan waiting). The contraption scene ([`contraption/panel_contraption.tscn`](contraption/panel_contraption.tscn)) sits in the scenes directory, its purpose still unexplained. The developer who wrote "codegen's fucked" and then fixed it, who planned eight features and implemented them in seven commits, who built a virtual computer inside a game engine and a two-language compiler to program it — that developer will be back. The commit log is silent, but the machine hums.

---

## Appendix A: Commit Timeline

| Chapter | Phase | Date | Commit Range | Key Events | Key Files |
|---------|-------|------|-------------|------------|-----------|
| Ch. 1 | Phase 0: Import & ISA Extraction | **2025-06-09** | `2a3aa0c` → `8b6f56f` | Git init, big bang import (83 files, 3,824 lines), two CPUs at import, embedded ISA, ZDerp compiler stub, accidental temp file, ISA extraction into `lang_zvm.gd` (f0bd6d9), assembler created, `comp_build.gd` broken reference | `.gitignore`, [`CPU_vm.gd`](scenes/CPU_vm.gd), [`CPU_gd.gd`](scenes/CPU_gd.gd), [`GPU_cs.gd`](scenes/GPU_cs.gd), [`KB.gd`](scenes/KB.gd), [`RAM_64k.gd`](scenes/RAM_64k.gd), [`Bus.gd`](scenes/Bus.gd), [`comp_asm_zd.gd`](scenes/comp_asm_zd.gd), [`lang_zvm.gd`](lang_zvm.gd), [`comp_compile_zd.gd`](scenes/comp_compile_zd.gd), [`scenes/mai9BA4.tmp`](scenes/mai9BA4.tmp) |
| Ch. 1–2 | Phase 0: Assembly Works | **2025-06-12** | `8b6f56f` | Massive assembler rewrite (403 insertions), nine test programs proving the VM works, conditional jumps via spec_ops | [`comp_asm_zd.gd`](scenes/comp_asm_zd.gd), [`main.txt`](res/data/main.txt), [`shell1-3.txt`](res/data/shell1.txt), [`lib/libscreen.zd`](res/data/lib/libscreen.zd), [`lib/string.zd`](res/data/lib/string.zd) |
| Ch. 2 | Phase 1: Assembler & VM | **2025-09-16** | `0f610f4` → `490cb72` | End-to-end pipeline connected, memory viewer, shadow memory, color-coded memview, three-month gap, immediate value fix (`arg1.offset+arg2.offset`), `decode_op_variant()` disassembly, Hello World | [`Memory.gd`](scenes/Memory.gd), [`comp_build.gd`](scenes/comp_build.gd), [`debug_panel.gd`](debug_panel.gd) |
| Ch. 3 | Phase 2: MiniDerp Frontend | (gap) | `39b6389` → `5d2bf78` | Tokenizer, parser, analyzer, IR creation, language definition growth, `should_split_on_transition`, four-stage pipeline, 30+ grammar rules with SHIFT lookahead, 22-operator op_map | [`word_boundary_tokenizer.gd`](scenes/word_boundary_tokenizer.gd), [`md_tokenizer.gd`](scenes/md_tokenizer.gd), [`lang_md.gd`](scenes/lang_md.gd), [`parser_md.gd`](scenes/parser_md.gd), [`analyzer_md.gd`](scenes/analyzer_md.gd), [`ir_md.gd`](scenes/ir_md.gd) |
| Ch. 4 | Phase 2–3: Codegen + First Compilation | (gap) | `ecbd8f7` → `784a049` | Code generator creation, Micro-YAML serialization, GPU buffer memory model, PerfLimiter, screensaver victory lap, emotional arc from "codegen's fucked" to "miniderp hello world achieved" | [`codegen_md.gd`](scenes/codegen_md.gd), [`uYaml.gd`](scenes/uYaml.gd), [`globals.gd`](globals.gd), [`PerfLimiter.gd`](PerfLimiter.gd) |
| Ch. 5 | Phase 4: High-Level Debugging | **2025-10-09** | `19fffe4` → `7dde647` | Backward stepping, 33-file 1,295-line refactoring, seven data class files (ErrorReporter with caret annotation, Token, AST inheriting Token, Chunk, Cmd_arg, Cmd_flags with byte packing, Iter), error code constants (ERR_01–ERR_31), 29-commit location tracking ordeal, HL debug highlight | [`PerfLimiter.gd`](PerfLimiter.gd), [`PerfLimitDirectory.gd`](PerfLimitDirectory.gd), [`class_ErrorReporter.gd`](class_ErrorReporter.gd), [`class_Token.gd`](class_Token.gd), [`class_Location.gd`](class_Location.gd), [`class_LocationRange.gd`](class_LocationRange.gd), [`error_list.gd`](error_list.gd), [`win_ed_dbg.gd`](scenes/win_ed_dbg.gd) |
| Ch. 6 | Phase 5: Type System | **2025-10-23** → **2025-10-31** | `e8e17fa` → `18f2880` | Type class with recursive generics (`of:Array[Type]`) and `get_full_name()`, type aliases (String→Ref[char]), type safety refactor with four typed classes (AssyBlock with LocationMap, CodeBlock extending IR_Value, IR_Cmd with words/loc, LocationMap), codegen type annotations, op_map restructuring from strings to arrays, imm_map, typed Hello World (`hello_typed.md`), loop counter, codegen crisis ("codegen's fucked" on Oct 31 — type system came BEFORE crisis on Oct 29), testOS creation | [`class_Type.gd`](class_Type.gd), [`class_AssyBlock.gd`](class_AssyBlock.gd), [`class_CodeBlock.gd`](class_CodeBlock.gd), [`class_IR_cmd.gd`](class_IR_cmd.gd), [`class_LocationMap.gd`](class_LocationMap.gd), [`res/data/testOS/main.md`](res/data/testOS/main.md) |
| Ch. 7 | Phase 6–7: Planning + Feature Sprint | **2026-06-21** | `2ca5f3a` → `f1c3917` | Documentation infrastructure (3,507 lines), 8 plan files, 4 features on June 21st (compound ops, char literals, #include, array begin), compound operator desugaring (x += 5 → OP ADD + MOV), CHAR/ENDCHAR tokenizer pattern, KB rewrite with `get_special_ASCII()`, #include text substitution, expr_index grammar extraction | [`docs/todo.md`](docs/todo.md), [`docs/todo_implementation.md`](docs/todo_implementation.md), [`docs/miniderp_syntax.md`](docs/miniderp_syntax.md), [`res/data/testOS/lib/screen.md`](res/data/testOS/lib/screen.md), 8 plan files |
| Ch. 8 | Phase 8: Final Development | **2026-06-29** | `1b2dc74` → `833801` | Array implementation, INDEX op change (`mul %b, 4` for byte addressing), six SHADOW_FRAME_* constants, SHADOW_TO_STRING map, `interp_numbers()` numeric decode column, color-coded stack frame visualization (RED=prev EBP, CYAN=prev IP, ORANGE=arg, YELLOW=var, PURPLE=temp, DARK_BLUE=padding), large forward-looking plans, contraption scene, testOS expansion to 251 lines | [`contraption/panel_contraption.tscn`](contraption/panel_contraption.tscn), [`docs/diagnosis_array_literal.md`](docs/diagnosis_array_literal.md), [`plans/implementation_debug_panel_pointers.md`](plans/implementation_debug_panel_pointers.md), [`plans/implementation_parser_dfa.md`](plans/implementation_parser_dfa.md) |

---

## Appendix B: Architecture Diagram

The following diagram shows the system's final architecture at the time of the last commit. Data flows from top to bottom: the developer interacts with the User Interface, which orchestrates the IDE and debugger. The MiniDerp compiler pipeline transforms high-level source into assembly, the assembler converts that to machine code, and the ZVM executes it on the virtual hardware. The Debug Panel observes every layer simultaneously.

```
┌─────────────────────────────────────────────────────────────────────┐
│                         USER INTERFACE                              │
│              (Godot Engine — main.tscn, main.gd)                     │
└──────┬──────────────────────────────────────────────────────┬───────┘
       │                                                      │
       ▼                                                      ▼
┌─────────────────────────┐                    ┌─────────────────────────┐
│   EDITOR / IDE          │                    │   DEBUG PANEL          │
│  ┌───────────────────┐  │                    │  ┌─────────────────┐   │
│  │ Code Editor       │  │                    │  │ Register View   │   │
│  │ (Editor.gd)       │  │                    │  │ (all 14 regs)   │   │
│  ├───────────────────┤  │                    │  ├─────────────────┤   │
│  │ Syntax Highlight  │  │                    │  │ Memory Viewer   │   │
│  │ (comp_highlight)  │  │                    │  │ (shadow color-  │   │
│  ├───────────────────┤  │                    │  │  coded hexdump  │   │
│  │ File Management   │  │                    │  │  + interp_num)  │   │
│  │ (comp_file.gd)    │  │                    │  ├─────────────────┤   │
│  ├───────────────────┤  │                    │  │ Stack Frames    │   │
│  │ Text Search       │  │                    │  │ (shadow stack   │   │
│  │ (comp_search.gd)  │  │                    │  │  color-coded:   │   │
│  ├───────────────────┤  │                    │  │  RED PREV_EBP,  │   │
│  │ Build Console     │  │                    │  │  CYAN PREV_IP,  │   │
│  │ (comp_build.gd)   │  │                    │  │  ORG arg,       │   │
│  └───────────────────┘  │                    │  │  YEL var,       │   │
│                         │                    │  │  PUR temp,      │   │
│                         │                    │  │  DB pad)        │   │
│                         │                    │  ├─────────────────┤   │
│                         │                    │  │ Local Variables │   │
│                         │                    │  │ (names, types,  │   │
│                         │                    │  │  values)        │   │
│                         │                    │  ├─────────────────┤   │
│                         │                    │  │ Controls:       │   │
│                         │                    │  │ ▶ ⏸ ⏹ ⏪ ⏩    │   │
│                         │                    │  └─────────────────┘   │
└─────────┬───────────────┘                    └──────────┬──────────────┘
          │                                               │
          ▼                                               │
┌──────────────────────────────────────────────────┐      │
│           MINIDERP COMPILER PIPELINE             │      │
│                                                  │      │
│  ┌─────────────┐    ┌──────────┐    ┌─────────┐ │      │
│  │  TOKENIZER  │───▶│  PARSER  │───▶│ANALYZER │ │      │
│  │ md_tokenizer│    │parser_md │    │analyzer │ │      │
│  │ word_bound. │    │lang_md.gd│    │_md.gd   │ │      │
│  │ should_split│    │30+ rules │    │22-op    │ │      │
│  │ _on_trans.  │    │SHIFT lkhd│    │op_map   │ │      │
│  │ 4-stage pip.│    │         │    │type chk  │ │      │
│  └─────────────┘    └──────────┘    └────┬────┘ │      │
│                                          │       │      │
│                                          ▼       │      │
│                                  ┌──────────────┐│      │
│                                  │  IR (Layer)  ││      │
│                                  │  ir_md.gd    ││      │
│                                  └──────┬───────┘│      │
│                                         │        │      │
│                                         ▼        │      │
│                                  ┌──────────────┐│      │
│                                  │ CODE GENERATOR│      │
│                                  │ codegen_md.gd │      │
│                                  │ (reg alloc,   │      │
│                                  │  stack frames,│      │
│                                  │  shadow instr,│      │
│                                  │  op_map arr,  │      │
│                                  │  imm_map,     │      │
│                                  │  val_idx)     │      │
│                                  └──────┬───────┘│      │
│                                         │        │      │
│                                         ▼        │      │
│                                  ┌──────────────┐│      │
│                                  │  ZDERP ASM   ││      │
│                                  └──────┬───────┘│      │
└──────────────────────────────────────────┼────────┘      │
                                           │               │
                                           ▼               │
┌──────────────────────────────────────────────────────────┘
│                    ZDERP ASSEMBLER
│  (comp_asm_zd.gd — parsing, encoding, reference patching)
│  (error reporting via class_ErrorReporter.gd / error_list.gd)
└──────────────────────────────┬───────────────────────────────
                               │
                               ▼
┌──────────────────────────────────────────────────────────────────────┐
│                          THE ZVM (VIRTUAL MACHINE)                   │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                     SYSTEM BUS (Bus.gd)                      │   │
│  │       Routes read/write requests to child devices            │   │
│  └──┬──────────┬──────────────┬───────────────┬─────────────────┘   │
│     │          │              │               │                      │
│     ▼          ▼              ▼               ▼                       │
│  ┌────────┐ ┌────────┐ ┌────────────┐ ┌────────────┐                │
│  │  CPU   │ │  RAM   │ │    GPU     │ │    KB      │                │
│  │CPU_vm  │ │RAM_64k │ │  GPU_cs.gd │ │  KB.gd     │                │
│  │.gd     │ │.gd     │ │ 56x36 tile │ │ interrupt- │                │
│  │14 regs │ │64K     │ │ display    │ │ driven buf │                │
│  │34 ops  │ │addr    │ │ w/color    │ │ get_special│                │
│  │fwd/bwd │ │space   │ │ shader     │ │ _ASCII()   │                │
│  │exec    │ │        │ │ buf memmod │ │            │                │
│  │decode_ │ │        │ │ screensaver│ │            │                │
│  │op_var. │ │        │ │            │ │            │                │
│  └────────┘ └────────┘ └────────────┘ └────────────┘                │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────┐        │
│  │         SHADOW MEMORY LAYER                              │        │
│  │  (lang_zvm.gd shadow constants — 15 types)               │        │
│  │  SHADOW_FRAME_PREV_EBP RED, SHADOW_FRAME_PREV_IP CYAN,   │        │
│  │  SHADOW_FRAME_ARGUMENT ORANGE, SHADOW_FRAME_VAR YELLOW,  │        │
│  │  SHADOW_FRAME_TEMP PURPLE, FRAME_PADDING DARK_BLUE       │        │
│  │  SHADOW_TO_STRING map, interp_numbers() numeric decoder   │        │
│  └──────────────────────────────────────────────────────────┘        │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────┐        │
│  │         REFERENCE DATA FILES                             │        │
│  │  • testOS/main.md (251-line shell)                       │        │
│  │  • testOS/lib/screen.md (std lib with #include)          │        │
│  │  • Various test and example .md/.zd files                │        │
│  │  • Nine original assembly test programs (June 12)        │        │
│  └──────────────────────────────────────────────────────────┘        │
└──────────────────────────────────────────────────────────────────────┘
```

---

*This master document was synthesized from the four-part narrative at [`docs/narrative_ch1_ch2.md`](docs/narrative_ch1_ch2.md), [`docs/narrative_ch3_ch4.md`](docs/narrative_ch3_ch4.md), [`docs/narrative_ch5_ch6.md`](docs/narrative_ch5_ch6.md), [`docs/narrative_ch7_ch8.md`](docs/narrative_ch7_ch8.md), and the research notes at [`docs/research_notes.md`](docs/research_notes.md). The history was verified against actual git diffs and file snapshots, not merely commit messages. Full commit-level details, including per-commit file changes and line counts, are available in the research notes document. Remaining work is documented in [`docs/todo.md`](docs/todo.md) and the [`plans/`](plans/) directory.*
