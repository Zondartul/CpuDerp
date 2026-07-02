# CpuDerp Project — Research Notes

## Commit-by-Commit Analysis of the Git History

A detailed chronological breakdown of the CpuDerp project's evolution, organized into 9 phases.

---

## Phase 0: Initial Setup (Commits 1–3)

The project begins with a bare repository skeleton, then receives a massive "big bang" import of an existing offline project, followed by initial assembler/VM expansion.

---

### Commit `2a3aa0c` — initial

**Key Files:**
- [`.gitignore`](.gitignore) — 22 lines

**Narrative:**
The very first commit creates a minimal git repository with nothing but a `.gitignore` file. This is the empty shell into which the entire existing project will be dumped.

---

### Commit `c442b70` — migrating

**Key Files:**
- [`scenes/CPU_vm.gd`](scenes/CPU_vm.gd) — 730 lines (core VM)
- [`scenes/GPU_cs.gd`](scenes/GPU_cs.gd) — 180 lines
- [`scenes/KB.gd`](scenes/KB.gd) — 52 lines
- [`scenes/RAM_64k.gd`](scenes/RAM_64k.gd) — 25 lines
- [`scenes/Bus.gd`](scenes/Bus.gd) — 60 lines
- [`scenes/Editor.gd`](scenes/Editor.gd) — 32 lines
- [`scenes/VM.gd`](scenes/VM.gd) — 29 lines
- [`scenes/comp_build.gd`](scenes/comp_build.gd) — 51 lines
- [`scenes/comp_file.gd`](scenes/comp_file.gd) — 212 lines
- [`scenes/comp_highlight.gd`](scenes/comp_highlight.gd) — 42 lines
- [`scenes/main.gd`](scenes/main.gd) — 86 lines
- [`scenes/main.tscn`](scenes/main.tscn) — 279 lines
- [`scenes/tile_text.gd`](scenes/tile_text.gd) — 113 lines
- [`scenes/lang_zvm.gd`](scenes/lang_zvm.gd) — 49 lines
- [`scenes/lang_zd.gd`](scenes/lang_zd.gd) — 49 lines
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — 73 lines (early assembler)
- [`scenes/debug_panel.gd`](scenes/debug_panel.gd) — 202 lines
- [`scenes/debug_panel.tscn`](scenes/debug_panel.tscn) — 107 lines
- [`editor/editor_file.gd`](editor/editor_file.gd) — 83 lines
- [`my_regex.gd`](my_regex.gd) — 303 lines
- Icons, tiles, scenes, [`project.godot`](project.godot), [`zderp_rules.gd`](zderp_rules.gd), [`comp_compile_zd.gd`](scenes/comp_compile_zd.gd), [`todo.gd`](todo.gd)

**Stats:** 83 files changed, 3824 insertions

**Narrative:**
A MASSIVE initial code dump — the entire project imported from an offline workspace into git in one shot. This is the "big bang" commit. The entire architecture appears: a CPU VM with a custom instruction set (ZVM), an assembler for a language called "zderp" (`.zd` files), a debug panel, a memory model (`RAM_64k`), a GPU/compute shader system, a keyboard handler, a file editor, syntax highlighting, a build pipeline, and a custom regex engine. The foundation for a full custom computing platform inside the Godot engine.

---

### Commit `f0bd6d9` — wip assembler

**Key Files:**
- [`lang_zvm.gd`](scenes/lang_zvm.gd) — +115 lines (opcodes, registers, control flags, shadow memory types)
- [`scenes/CPU_vm.gd`](scenes/CPU_vm.gd) — +201 lines (fetch/decode/execute loop with error handling)
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +129 lines
- [`scenes/main.tscn`](scenes/main.tscn) — +15/-2, [`main.gd`](scenes/main.gd) — +4

**Stats:** 7 files changed, 299 insertions, 167 deletions

**Narrative:**
Major expansion of the VM and ISA definition. `lang_zvm.gd` grows significantly to define opcodes, registers, control flags, and shadow memory types. `CPU_vm.gd` adds the full fetch/decode/execute loop with error handling — the CPU is now capable of executing instructions. This marks the transition from static definitions to a working execution engine.

---

## Phase 1: Assembler & VM Foundation (Commits 4–12)

The assembler becomes functional, assembly programs are created, code can upload to the CPU, a debugger emerges, and the first Hello World runs.

---

### Commit `6eb4b21` — wip assembler

**Key Files:**
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +92/-3

**Stats:** 1 file changed, 92 insertions, 3 deletions

**Narrative:**
The assembler receives additional work — 92 lines added to the ZDerp assembler script. Pure incremental progress.

---

### Commit `8b6f56f` — assembly seems to work

**Key Files:**
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +403/-107 (massive expansion)
- [`lang_zvm.gd`](scenes/lang_zvm.gd) — +78/-4
- Test files added: [`shell1.txt`](res/data/shell1.txt), [`shell2.txt`](res/data/shell2.txt), [`shell3.txt`](res/data/shell3.txt), [`main.txt`](res/data/main.txt)
- Library files: [`lib/libscreen.zd`](res/data/lib/libscreen.zd), [`lib/string.zd`](res/data/lib/string.zd), [`lib/main2.zd`](res/data/lib/main2.zd)
- [`debug_panel.gd`](debug_panel.gd) — +7/-1

**Stats:** 19 files changed, 1362 insertions, 107 deletions

**Narrative:**
A breakthrough commit — the assembler appears to work. `comp_asm_zd.gd` nearly quadruples in size with a 403-line addition. A test suite of assembly programs is added (shell1-3, main.txt) along with library files for screen and string operations. This is the first time the assembler pipeline produces viable output.

---

### Commit `0f610f4` — assembled code now uploads to CPU and debugger barely works

**Key Files:**
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +32/-6
- [`scenes/comp_build.gd`](scenes/comp_build.gd) — +21/-3
- [`scenes/RAM_64k.gd`](scenes/RAM_64k.gd) — +9/-2
- [`debug_panel.gd`](debug_panel.gd) — +24/-11
- [`todo.gd`](todo.gd) — +19/-8

**Stats:** 7 files changed, 78 insertions, 31 deletions

**Narrative:**
The end-to-end pipeline is connected: assembled code can now be uploaded to the CPU and executed. The debugger "barely works" — a candid status that reflects early-stage tooling. The build system (`comp_build.gd`) ties the assembler output to the CPU upload.

---

### Commit `00ffeec` — nitpicks

**Key Files:**
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +3/-1
- [`scenes/comp_build.gd`](scenes/comp_build.gd) — +7/-6
- [`scenes/tile_text.gd`](scenes/tile_text.gd) — +2/-1

**Stats:** 3 files changed, 9 insertions, 3 deletions

**Narrative:**
A minor cleanup pass — small adjustments to the assembler, build system, and text rendering.

---

### Commit `4cb18d5` — Merge pull request #1

**Narrative:**
A merge commit incorporating changes from a feature branch. The first pull request in the project's history.

---

### Commit `d2421b6` — build status messages

**Key Files:**
- [`scenes/Editor.gd`](scenes/Editor.gd) — +6
- [`scenes/comp_build.gd`](scenes/comp_build.gd) — +12/-2
- [`scenes/main.tscn`](scenes/main.tscn) — +4/-2

**Stats:** 3 files changed, 18 insertions, 4 deletions

**Narrative:**
The editor console gets build status messages so the user can see what's happening during the assembly/upload pipeline.

---

### Commit `75070d1` — added memory viewer

**Key Files:**
- [`scenes/Memory.gd`](scenes/Memory.gd) — 104 lines (NEW FILE)
- [`scenes/CPU_vm.gd`](scenes/CPU_vm.gd) — +14/-6
- [`scenes/comp_build.gd`](scenes/comp_build.gd) — +5
- [`scenes/main.gd`](scenes/main.gd) — +3
- [`scenes/main.tscn`](scenes/main.tscn) — +36/-2

**Stats:** 6 files changed, 158 insertions, 5 deletions

**Narrative:**
A memory viewer is introduced — critical for debugging a CPU. `Memory.gd` is created as a 104-line standalone display component. This marks the beginning of proper debugging tooling beyond the raw CPU state.

---

### Commit `c98c965` — added shadow memory, color-coded memview, fixed ref_patch

**Key Files:**
- [`scenes/Memory.gd`](scenes/Memory.gd) — +102/-3 (major expansion)
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +78/-4
- [`scenes/comp_build.gd`](scenes/comp_build.gd) — +20/-2
- [`scene/lang_zvm.gd`](scenes/lang_zvm.gd) — +10
- [`scenes/main.gd`](scenes/main.gd) — +54
- [`scenes/main.tscn`](scenes/main.tscn) — +10/-1

**Stats:** 9 files changed, 525 insertions, 56 deletions

**Narrative:**
Shadow memory is introduced — a second layer that tracks metadata about each memory cell (type, access patterns). The memory viewer becomes color-coded to visually distinguish different memory regions. A reference patching bug (ref_patch byte offset) is fixed. The assembler and build system continue to mature.

---

### Commit `490cb72` — moved to Godot 4.5, IP highlight in memview, CPU works for first time (Hello World)

**Key Files:**
- [`scenes/CPU_vm.gd`](scenes/CPU_vm.gd) — +19/-16
- [`scenes/Memory.gd`](scenes/Memory.gd) — +25/-7
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +18/-3
- [`scenes/lang_zvm.gd`](scenes/lang_zvm.gd) — +1
- [`project.godot`](project.godot) — +2/-1

**Stats:** 8 files changed, 54 insertions, 16 deletions

**Narrative:**
A MILESTONE — the CPU executes a "Hello World" program for the first time. The project migrates to Godot 4.5. The memory viewer gains an Instruction Pointer (IP) highlight to show the current execution location. This is the first verified end-to-end execution of user code on the custom VM.

---

## Phase 2: MiniDerp Frontend (Commits 13–26)

Work begins on a high-level language called "MiniDerp" (`.md` files), adding a tokenizer, parser, analyzer, IR, and code generator alongside the existing ZDerp assembler.

---

### Commit `39b6389` — wip compiler

**Key Files:**
- [`scenes/word_boundary_tokenizer.gd`](scenes/word_boundary_tokenizer.gd) — +64 (NEW FILE)
- [`scenes/comp_compile_md.gd`](scenes/comp_compile_md.gd) — +20 (NEW FILE)
- [`scenes/lang_md.gd`](scenes/lang_md.gd) — +43 (NEW FILE)
- [`scenes/comp_build.gd`](scenes/comp_build.gd) — +35/-3
- [`scenes/main.tscn`](scenes/main.tscn) — +19/-2
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +12
- [`scenes/main.gd`](scenes/main.gd) — +18/-1

**Stats:** 15 files changed, 537 insertions, 18 deletions

**Narrative:**
The MiniDerp compiler is born. Three new files are created: a general-purpose word boundary tokenizer, a MiniDerp compiler orchestration file (`comp_compile_md.gd`), and a MiniDerp language definition (`lang_md.gd`). This is the humble beginning of a high-level language compiler that will generate ZDerp assembly.

---

### Commit `2469e05` — token view works with zderp and miniderp

**Key Files:**
- [`scenes/comp_compile_md.gd`](scenes/comp_compile_md.gd) — +78/-1
- [`scenes/win_token_view.gd`](scenes/win_token_view.gd) — +44 (NEW FILE)
- [`scenes/tile_label_tooltip.tscn`](scenes/tile_label_tooltip.tscn) — +16 (NEW FILE)
- [`scenes/comp_build.gd`](scenes/comp_build.gd) — +7/-3
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +7

**Stats:** 9 files changed, 189 insertions, 5 deletions

**Narrative:**
A token visualization window is added, allowing the developer to see how both ZDerp and MiniDerp source code is tokenized. This is a debugging tool for the compiler frontend.

---

### Commit `c848416` — better tokenization for miniderp

**Key Files:**
- [`scenes/md_tokenizer.gd`](scenes/md_tokenizer.gd) — +190 (NEW FILE)
- [`scenes/lang_md.gd`](scenes/lang_md.gd) — +12/-2
- [`scenes/comp_compile_md.gd`](scenes/comp_compile_md.gd) — +96/-97 (rewrite)
- [`scenes/word_boundary_tokenizer.gd`](scenes/word_boundary_tokenizer.gd) — +8/-1

**Stats:** 8 files changed, 236 insertions, 100 deletions

**Narrative:**
A dedicated MiniDerp tokenizer (`md_tokenizer.gd`) replaces the generic word-boundary approach. The compiler orchestration file is substantially rewritten. Tokenization becomes language-specific and more sophisticated.

---

### Commit `f69a819` — wip parser and AST stack view

**Key Files:**
- [`scenes/comp_compile_md.gd`](scenes/comp_compile_md.gd) — +64/-1
- [`scenes/win_parse.gd`](scenes/win_parse.gd) — +40 (NEW FILE)
- [`scenes/win_parse.tscn`](scenes/win_parse.tscn) — +22 (NEW FILE)
- [`scenes/main.tscn`](scenes/main.tscn) — +6/-4

**Stats:** 5 files changed, 131 insertions, 2 deletions

**Narrative:**
A parser enters the picture, accompanied by a parse tree visualization window (`win_parse`). Now the compiler can both tokenize and parse MiniDerp source code into an AST.

---

### Commit `a6138d4` — parse debug msgs

**Key Files:**
- [`scenes/comp_compile_md.gd`](scenes/comp_compile_md.gd) — +47/-7
- [`scenes/win_parse.gd`](scenes/win_parse.gd) — +26/-16
- [`scenes/Editor.gd`](scenes/Editor.gd) — +3/-2
- [`scenes/main.tscn`](scenes/main.tscn) — +5/-4
- [`scenes/win_parse.tscn`](scenes/win_parse.tscn) — +5/-2

**Stats:** 5 files changed, 59 insertions, 27 deletions

**Narrative:**
Debug messages are added to the parser, improving the visibility of the parsing process. UI adjustments to the parse window.

---

### Commit `3d310d4` — parsing is decent now

**Key Files:**
- [`scenes/lang_md.gd`](scenes/lang_md.gd) — +42/-1
- [`scenes/comp_compile_md.gd`](scenes/comp_compile_md.gd) — +23/-1
- [`scenes/comp_build.gd`](scenes/comp_build.gd) — +2/-1
- [`log.txt`](log.txt) — +12K lines (debug logging)

**Stats:** 4 files changed, 12337 insertions, 11 deletions

**Narrative:**
The parser reaches a "decent" quality level. The language definition is expanded with more grammar rules. A massive log dump indicates heavy debugging.

---

### Commit `15d7980` — wip analyzer

**Key Files:**
- [`scenes/comp_compile_md.gd`](scenes/comp_compile_md.gd) — +90/-89 (major rewrite)
- [`scenes/win_ir.gd`](scenes/win_ir.gd) — +28 (NEW FILE)
- [`scenes/win_ir.tscn`](scenes/win_ir.tscn) — +23 (NEW FILE)
- [`scenes/main.tscn`](scenes/main.tscn) — +7/-3

**Stats:** 5 files changed, 147 insertions, 2 deletions

**Narrative:**
An analyzer (semantic analysis phase) is started. An IR (Intermediate Representation) window is created to visualize the compiler's internal IR. The compiler pipeline is expanding: tokenize → parse → analyze → IR.

---

### Commit `a18cead` — analysis works

**Key Files:**
- [`scenes/comp_compile_md.gd`](scenes/comp_compile_md.gd) — +289/-1 (major expansion)
- [`scenes/Editor.gd`](scenes/Editor.gd) — +12/-1
- [`scenes/lang_md.gd`](scenes/lang_md.gd) — +24/-1
- [`scenes/main.gd`](scenes/main.gd) — +2/-1
- [`scenes/main.tscn`](scenes/main.tscn) — +12/-1
- [`scenes/win_ir.gd`](scenes/win_ir.gd) — +2/-1

**Stats:** 7 files changed, 6708 insertions, 2880 deletions

**Narrative:**
The semantic analyzer works. `comp_compile_md.gd` expands by 289 lines. Combined with log changes, this is a massive step — the compiler can now perform semantic analysis on parsed MiniDerp programs.

---

### Commit `8e0faed` — wip IR

**Key Files:**
- [`scenes/ir_md.gd`](scenes/ir_md.gd) — +133 (NEW FILE)
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +222 (NEW FILE)
- [`scenes/comp_compile_md.gd`](scenes/comp_compile_md.gd) — +312/-313 (complete rewrite)
- [`scenes/main.tscn`](scenes/main.tscn) — +13/-1
- [`scenes/win_ir.gd`](scenes/win_ir.gd) — +25/-3

**Stats:** 7 files changed, 394 insertions, 313 deletions

**Narrative:**
A formal IR module (`ir_md.gd`) and analyzer module (`analyzer_md.gd`) are created as standalone files, refactored out of the monolithic compiler file. The compiler orchestration is completely rewritten. Architecture cleanly separates the compiler phases.

---

### Commit `0c7647d` — done playing with IR, lol

**Key Files:**
- [`scenes/ir_md.gd`](scenes/ir_md.gd) — +140/-1 (major IR expansion)
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +154/-1
- [`scenes/lang_md.gd`](scenes/lang_md.gd) — +113/-1 (language feature expansion)
- [`scenes/editor_file.gd`](editor/editor_file.gd) — +2/-1
- [`scenes/md_tokenizer.gd`](scenes/md_tokenizer.gd) — +1

**Stats:** 9 files changed, 65796 insertions, 8065 deletions

**Narrative:**
A humorous commit message ("done playing with IR, lol") belies significant work. The IR is substantially expanded, the analyzer grows, and the language definition adds 113 lines of new rules. Large log changes suggest extensive testing.

---

### Commit `5d2bf78` — improved flow control and if-else

**Key Files:**
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +70/-13
- [`scenes/ir_md.gd`](scenes/ir_md.gd) — +47/-25
- [`scenes/win_ir.gd`](scenes/win_ir.gd) — +10/-7
- [`scenes/win_ir.tscn`](scenes/win_ir.tscn) — +11/-2

**Stats:** 6 files changed, 142 insertions, 75 deletions

**Narrative:**
Flow control and if-else constructs are improved in both the IR and analyzer. The IR visualization window is also updated.

---

### Commit `ecbd8f7` — wip micro-YAML

**Key Files:**
- [`scenes/uYaml.gd`](scenes/uYaml.gd) — +155 (NEW FILE)
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +57 (NEW FILE)
- [`scenes/comp_compile_md.gd`](scenes/comp_compile_md.gd) — +2
- [`scenes/main.tscn`](scenes/main.tscn) — +6/-1

**Stats:** 6 files changed, 221 insertions, 1 deletion

**Narrative:**
Two major new files: a micro-YAML library for data serialization (`uYaml.gd`) and the beginning of the code generator (`codegen_md.gd`). The code generator will translate the IR into ZDerp assembly.

---

### Commit `fa3525c` — wip code generator

**Key Files:**
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +412/-6 (major expansion)
- [`scenes/ir_md.gd`](scenes/ir_md.gd) — +140/-7
- [`scenes/uYaml.gd`](scenes/uYaml.gd) — +96/-3
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +8/-1
- [`scenes/comp_compile_md.gd`](scenes/comp_compile_md.gd) — +4/-1

**Stats:** 7 files changed, 611 insertions, 212 deletions

**Narrative:**
The code generator explodes from 57 to 412+ lines. IR and micro-YAML are also expanded. The backend of the MiniDerp compiler is taking shape.

---

### Commit `3b469dd` — codegen improved

**Key Files:**
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +216/-1
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +110/-1
- [`scenes/ir_md.gd`](scenes/ir_md.gd) — +120/-1
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +44/-1
- [`scenes/comp_compile_md.gd`](scenes/comp_compile_md.gd) — +20/-1
- [`scenes/lang_md.gd`](scenes/lang_md.gd) — +4
- [`scenes/lang_zd.gd`](scenes/lang_zd.gd) — +3
- [`scenes/main.gd`](scenes/main.gd) — +8/-1

**Stats:** 13 files changed, 125533 insertions, 34630 deletions

**Narrative:**
Continued improvement across the entire compiler stack: code generator, analyzer, IR, and assembler all receive significant additions. The massive log changes indicate extensive testing of the pipeline.

---

## Phase 3: First MiniDerp Compilation (Commits 27–35)

The assembler is refactored, the debugger receives major visual upgrades, and the first MiniDerp "Hello World" program compiles and runs.

---

### Commit `91b55b7` — refactored the assembler and improved error reporting

**Key Files:**
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +432/-162 (MAJOR refactor)
- [`globals.gd`](globals.gd) — +29 (NEW FILE)
- [`scenes/Editor.gd`](scenes/Editor.gd) — +9/-1
- [`scenes/comp_build.gd`](scenes/comp_build.gd) — +3/-1
- [`scenes/comp_file.gd`](scenes/comp_file.gd) — +3
- [`editor/editor_file.gd`](editor/editor_file.gd) — +8/-1

**Stats:** 11 files changed, 790 insertions, 162 deletions

**Narrative:**
A major refactoring of the assembler with +432/-162 changes. A new `globals.gd` is introduced as a shared global state module. Error reporting is improved across the build system.

---

### Commit `2ca05d8` — wip idk

**Key Files:**
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +28/-5
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +37/-5
- [`globals.gd`](globals.gd) — +3

**Stats:** 5 files changed, 71 insertions, 127 deletions

**Narrative:**
An "wip idk" commit — incremental work on codegen and assembler, no clear milestone.

---

### Commit `f7b0226` — miniderp compiles?

**Key Files:**
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +25/-3
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +3
- [`scenes/ir_md.gd`](scenes/ir_md.gd) — +3

**Stats:** 5 files changed, 123 insertions, 6 deletions

**Narrative:**
A tentative milestone — the MiniDerp compiler produces assembly output. The question mark in the commit message suggests this is early and likely buggy, but the pipeline produces output.

---

### Commit `9df489c` — cool debugger visuals wip

**Key Files:**
- [`debug_panel.gd`](debug_panel.gd) — +152/-3
- [`debug_panel.tscn`](debug_panel.tscn) — +94/-30
- [`scenes/Memory.gd`](scenes/Memory.gd) — +52/-17
- [`scenes/CPU_vm.gd`](scenes/CPU_vm.gd) — +28/-3
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +2/-1
- [`scenes/main.tscn`](scenes/main.tscn) — +4/-1

**Stats:** 7 files changed, 318 insertions, 30 deletions

**Narrative:**
The debug panel receives a major visual overhaul — 152 lines added. The memory view and CPU VM also get improvements. Debugging tooling is becoming more sophisticated.

---

### Commit `f2ae93b` — better local var handling at codegen

**Key Files:**
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +96/-1
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +2
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +4/-1
- [`res/data/hello.md`](res/data/hello.md) — +5/-1

**Stats:** 7 files changed, 25004 insertions, 21888 deletions

**Narrative:**
Local variable handling in the code generator is improved. This is critical for generating correct function-scoped code from MiniDerp.

---

### Commit `b7bb908` — wip codegen, handle.storage.pos still bork

**Key Files:**
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +111/-11

**Stats:** 3 files changed, 208 insertions, 293 deletions

**Narrative:**
The code generator continues to evolve. The commit message admits a known bug with storage position handling.

---

### Commit `c771566` — super duper debugger stuff

**Key Files:**
- [`debug_panel.gd`](debug_panel.gd) — +298/-4 (massive expansion)
- [`debug_panel.tscn`](debug_panel.tscn) — +64/-2
- [`editor/editor_file.gd`](editor/editor_file.gd) — +5/-1
- [`scenes/Editor.gd`](scenes/Editor.gd) — +3
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +10/-1
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +2
- [`scenes/comp_file.gd`](scenes/comp_file.gd) — +3
- [`scenes/CPU_vm.gd`](scenes/CPU_vm.gd) — +7

**Stats:** 10 files changed, 654 insertions, 110 deletions

**Narrative:**
The debug panel nearly doubles in size with 298 lines added. The debugger is becoming the central tool for understanding program execution.

---

### Commit `34d2239` — improved go/stop and freq control; codegen cmd index deref

**Key Files:**
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +82/-1
- [`debug_panel.gd`](debug_panel.gd) — +76/-1
- [`scenes/CPU_vm.gd`](scenes/CPU_vm.gd) — +17/-1
- [`scenes/Editor.gd`](scenes/Editor.gd) — +3
- [`scenes/GPU_cs.gd`](scenes/GPU_cs.gd) — +24/-1
- [`scenes/Memory.gd`](scenes/Memory.gd) — +17/-1
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +14/-1
- [`scenes/comp_build.gd`](scenes/comp_build.gd) — +13
- [`scenes/indicator.gd`](scenes/indicator.gd) — +4 (NEW FILE)

**Stats:** 17 files changed, 14627 insertions, 11054 deletions

**Narrative:**
Execution control (go/stop/frequency) is improved. Command index dereferencing is added to the code generator. A visual indicator is introduced as a new file. The debugger gains finer control over CPU execution.

---

### Commit `784a049` — miniderp hello world achieved! also perf_limiter

**Key Files:**
- [`debug_panel.gd`](debug_panel.gd) — +60/-1
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +62/-1
- [`scenes/GPU_cs.gd`](scenes/GPU_cs.gd) — +24/-1
- [`scenes/Memory.gd`](scenes/Memory.gd) — +17/-1
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +14/-1
- [`scenes/comp_build.gd`](scenes/comp_build.gd) — +13
- [`res/data/hello.md`](res/data/hello.md) — +20/-1
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +4/-1

**Stats:** 11 files changed, 80791 insertions, 64068 deletions

**Narrative:**
THE MILESTONE — "miniderp hello world achieved!" The MiniDerp high-level language compiles, assembles, uploads, and executes successfully to print "Hello World." This is the culmination of Phase 3. A performance limiter is also introduced for execution speed control. Massive log changes reflect the testing effort.

---

## Phase 4: High-Level Debugging (Commits 36–64)

After achieving MiniDerp compilation, the focus shifts to debugging at the high-language level. This extended phase adds backward stepping, type hints, error reporting, an editor-debugger integration, location tracking, and the high-level debug view.

---

### Commit `19fffe4` — implemented backwards stepping; also better perf_limiter

**Key Files:**
- [`PerfLimiter.gd`](PerfLimiter.gd) — +76 (NEW FILE)
- [`PerfLimitDirectory.gd`](PerfLimitDirectory.gd) — +30 (NEW FILE)
- [`debug_panel.gd`](debug_panel.gd) — +198/-5
- [`debug_panel.tscn`](debug_panel.tscn) — +27/-3
- [`res/icons/control_start_blue.png`](res/icons/control_start_blue.png) — new icon

**Stats:** 12 files changed, 595 insertions, 48 deletions

**Narrative:**
Backward stepping is implemented in the debugger — a challenging feature for a custom VM. Performance limiter code is extracted into dedicated classes. The debug panel gains 198 lines of new functionality. Debug icons are added.

---

### Commit `256fcb1` — more type hints, error callouts from analyzer

**Key Files:**
- [`class_ErrorReporter.gd`](class_ErrorReporter.gd) — +45 (NEW FILE)
- [`class_Token.gd`](class_Token.gd) — +19 (NEW FILE)
- [`class_Chunk.gd`](class_Chunk.gd) — +25 (NEW FILE)
- [`class_Cmd_arg.gd`](class_Cmd_arg.gd) — +11 (NEW FILE)
- [`class_Cmd_flags.gd`](class_Cmd_flags.gd) — +26 (NEW FILE)
- [`class_Iter.gd`](class_Iter.gd) — +12 (NEW FILE)
- [`class_AST.gd`](class_AST.gd) — +15
- [`error_list.gd`](error_list.gd) — +29 (NEW FILE)
- [`globals.gd`](globals.gd) — +23/-1
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +212/-1 (major expansion)
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +238/-1
- [`scenes/comp_compile_md.gd`](scenes/comp_compile_md.gd) — +116/-1
- [`scenes/md_tokenizer.gd`](scenes/md_tokenizer.gd) — +103/-1
- [`scenes/parser_md.gd`](scenes/parser_md.gd) — +106 (NEW FILE)
- [`scenes/word_boundary_tokenizer.gd`](scenes/word_boundary_tokenizer.gd) — +17/-1
- [`log.txt`](log.txt) — -186447 lines (deleted!)

**Stats:** 33 files changed, 1295 insertions, 186961 deletions

**Narrative:**
A massive architectural refactoring. Seven new class files are created as standalone autoloads/singletons: `class_ErrorReporter`, `class_Token`, `class_Chunk`, `class_Cmd_arg`, `class_Cmd_flags`, `class_Iter`, and the existing `class_AST` is expanded. The parser is extracted into its own file (`parser_md.gd`). The enormous `log.txt` (186K+ lines) is deleted — a symbolic cleanup. This commit professionalizes the codebase with type hints and proper error reporting from the analyzer.

---

### Commit `2824e91` — wip types, changed parsing of assignment

**Key Files:**
- [`globals.gd`](globals.gd) — +26
- [`scenes/parser_md.gd`](scenes/parser_md.gd) — +40
- [`scenes/lang_md.gd`](scenes/lang_md.gd) — +11/-2
- [`scenes/md_tokenizer.gd`](scenes/md_tokenizer.gd) — +32/-5
- [`class_AST.gd`](class_AST.gd) — +5

**Stats:** 6 files changed, 113 insertions, 224 deletions

**Narrative:**
Type system work begins. The parsing of assignment expressions is changed, suggesting a shift toward a more type-aware syntax.

---

### Commit `11b970d` — fixed if-else labels?

**Key Files:**
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +94/-2
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +72/-2
- [`scenes/comp_compile_md.gd`](scenes/comp_compile_md.gd) — +10/-1
- [`scenes/lang_md.gd`](scenes/lang_md.gd) — +8/-1
- [`scenes/md_tokenizer.gd`](scenes/md_tokenizer.gd) — +6/-1
- [`scenes/Memory.gd`](scenes/Memory.gd) — +5/-1
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +10
- [`scenes/comp_build.gd`](scenes/comp_build.gd) — +7/-1
- [`scenes/main.gd`](scenes/main.gd) — +5/-1
- [`debug_panel.gd`](debug_panel.gd) — +4
- [`scenes/lang_zvm.gd`](scenes/lang_zvm.gd) — +10
- [`scenes/parser_md.gd`](scenes/parser_md.gd) — +11
- [`res/data/elif_test.md`](res/data/elif_test.md) — +8 (NEW test file)

**Stats:** 18 files changed, 1645 insertions, 200 deletions

**Narrative:**
If-else label generation is fixed — a critical bug in control flow compilation. A new test file (`elif_test.md`) is added. Multiple compiler modules are touched in this broad fix.

---

### Commit `489f0bc` — wip

**Key Files:**
- [`scenes/comp_file.gd`](scenes/comp_file.gd) — +13/-1
- [`scenes/md_tokenizer.gd`](scenes/md_tokenizer.gd) — +34/-1
- [`scenes/parser_md.gd`](scenes/parser_md.gd) — +22/-1
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +18/-1
- [`scenes/ir_md.gd`](scenes/ir_md.gd) — +4/-1
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +6/-1
- [`class_Token.gd`](class_Token.gd) — +6
- [`scenes/win_token_view.gd`](scenes/win_token_view.gd) — +6/-1
- [`scenes/tile_text.gd`](scenes/tile_text.gd) — +2/-1
- Test files: [`array_test.md`](res/data/array_test.md), [`return_test.md`](res/data/return_test.md), [`printf_test.md`](res/data/printf_test.md)

**Stats:** 16 files changed, 197 insertions, 1548 deletions

**Narrative:**
Broad "wip" commit touching the entire compiler stack. Three new test files are introduced testing arrays, return statements, and printf functionality — indicating what features are being worked on.

---

### Commit `3098d4e` — printf works in miniderp

**Key Files:**
- [`res/data/printf_test.md`](res/data/printf_test.md) — +235/-5
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +8/-1
- [`debug_panel.gd`](debug_panel.gd) — +13/-1
- [`scenes/lang_md.gd`](scenes/lang_md.gd) — +4/-1
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +2/-1
- [`scenes/main.tscn`](scenes/main.tscn) — +2/-1
- [`todo.gd`](todo.gd) — +5

**Stats:** 9 files changed, 1744 insertions, 139 deletions

**Narrative:**
printf-style formatted output is working in MiniDerp — a significant language feature milestone.

---

### Commit `70bc02d` — fixed bug: language now tracks with cur_efile and tab

**Key Files:**
- [`scenes/win_ed_dbg.gd`](scenes/win_ed_dbg.gd) — +55 (NEW FILE)
- [`scenes/win_ed_dbg.tscn`](scenes/win_ed_dbg.tscn) — +26 (NEW FILE)
- [`scenes/Editor.gd`](scenes/Editor.gd) — +9/-1
- [`scenes/comp_highlight.gd`](scenes/comp_highlight.gd) — +18/-1
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +15/-1
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +62/-2
- [`scenes/main.tscn`](scenes/main.tscn) — +41/-1
- [`scenes/parser_md.gd`](scenes/parser_md.gd) — +6/-1

**Stats:** 17 files changed, 274 insertions, 1640 deletions

**Narrative:**
An editor-debugger window (`win_ed_dbg`) is introduced, integrating the editor and debugger views. Language tracking is fixed to follow the current file and tab.

---

### Commit `a78f114` — added [file->close]

**Key Files:**
- [`scenes/Editor.gd`](scenes/Editor.gd) — +4
- [`scenes/comp_build.gd`](scenes/comp_build.gd) — +11/-1
- [`scenes/comp_file.gd`](scenes/comp_file.gd) — +14/-1
- [`scenes/comp_highlight.gd`](scenes/comp_highlight.gd) — +6/-1
- [`scenes/main.tscn`](scenes/main.tscn) — +8/-1

**Stats:** 8 files changed, 493 insertions, 63 deletions

**Narrative:**
A "Close File" feature is added to the editor menu — basic IDE functionality.

---

### Commit `c11cacc` — added search GUI

**Key Files:**
- [`scenes/comp_search.gd`](scenes/comp_search.gd) — +88 (NEW FILE)
- [`scenes/Editor.gd`](scenes/Editor.gd) — +11/-3
- [`scenes/comp_file.gd`](scenes/comp_file.gd) — +4/-1
- [`scenes/main.tscn`](scenes/main.tscn) — +109/-26
- [`project.godot`](project.godot) — +5
- [`globals.gd`](globals.gd) — +35
- New icons: [`cancel.png`](res/icons/cancel.png), [`resultset_first.png`](res/icons/resultset_first.png)

**Stats:** 12 files changed, 316 insertions, 33 deletions

**Narrative:**
A search GUI is added — text search functionality within the editor. New icons and scene changes support the UI.

---

### Commit `4bed03e` — language inferred from file extension

**Key Files:**
- [`scenes/comp_file.gd`](scenes/comp_file.gd) — +14/-12
- [`todo.gd`](todo.gd) — +52/-33

**Stats:** 2 files changed, 45 insertions, 21 deletions

**Narrative:**
The IDE now infers the programming language (ZDerp vs MiniDerp) from the file extension, enabling proper syntax highlighting and compilation.

---

### Commit `3014253` — fixed [build clear console] and [build save file]

**Key Files:**
- [`class_ErrorReporter.gd`](class_ErrorReporter.gd) — +15/-8
- [`scenes/Editor.gd`](scenes/Editor.gd) — +13
- [`scenes/comp_build.gd`](scenes/comp_build.gd) — +2
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +1
- [`scenes/parser_md.gd`](scenes/parser_md.gd) — +1
- [`scenes/main.tscn`](scenes/main.tscn) — +1
- [`todo.gd`](todo.gd) — +95/-48

**Stats:** 8 files changed, 89 insertions, 40 deletions

**Narrative:**
Bug fixes for the build system: clearing the console and saving files now work correctly.

---

### Commit `90b5c47` — reimported in godot 4.4 standalone

**Key Files:**
- Multiple `.png.import` files updated for standalone build compatibility

**Stats:** 15 files changed, 90 insertions

**Narrative:**
Assets are reimported for a standalone Godot 4.4 build. No code changes — purely asset pipeline maintenance.

---

### Commit `0bda5e8` — fixed [clear compiler]

**Key Files:**
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +77/-15
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +49/-9
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +104/-28
- [`scenes/comp_compile_md.gd`](scenes/comp_compile_md.gd) — +12/-2
- [`scenes/ir_md.gd`](scenes/ir_md.gd) — +13/-5
- [`scenes/md_tokenizer.gd`](scenes/md_tokenizer.gd) — +63/-10
- [`scenes/parser_md.gd`](scenes/parser_md.gd) — +46/-8

**Stats:** 10 files changed, 257 insertions, 218 deletions

**Narrative:**
A significant cleanup and fix of the compiler reset mechanism. Every major compiler module receives fixes to properly clear their state when rebuilding.

---

### Commit `e76f4ea` — fixed [build reset]

**Key Files:**
- [`scenes/VM.gd`](scenes/VM.gd) — +1
- [`scenes/comp_build.gd`](scenes/comp_build.gd) — +3
- [`scenes/main.tscn`](scenes/main.tscn) — +3/-2
- [`todo.gd`](todo.gd) — +4/-2

**Stats:** 4 files changed, 8 insertions, 3 deletions

**Narrative:**
Build reset functionality is fixed.

---

### Commit `803b060` — Merge remote-tracking branch 'origin/remote-dev'

**Narrative:**
A merge from a remote development branch.

---

### Commit `7c65ac4` — oops

**Key Files:**
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — -33
- [`scenes/parser_md.gd`](scenes/parser_md.gd) — -3

**Stats:** 3 files changed, 467 insertions, 36 deletions

**Narrative:**
An "oops" recovery commit — some changes reverted and a temporary scene file generated.

---

### Commit `6642d5d` — wip high level debug

**Key Files:**
- [`debug_panel.gd`](debug_panel.gd) — +35/-6
- [`debug_panel.tscn`](debug_panel.tscn) — +32/-6
- [`globals.gd`](globals.gd) — +29/-2
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +30
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +23/-1
- [`scenes/comp_build.gd`](scenes/comp_build.gd) — +11/-2
- [`scenes/comp_compile_md.gd`](scenes/comp_compile_md.gd) — +3
- [`scenes/ir_md.gd`](scenes/ir_md.gd) — +5/-1
- [`scenes/main.tscn`](scenes/main.tscn) — +1

**Stats:** 11 files changed, 469 insertions, 77 deletions

**Narrative:**
High-level debugging work begins — the ability to debug MiniDerp source code at the language level, not just the assembly level.

---

### Commit `8f2d368` — added HL local debug view

**Key Files:**
- [`debug_panel.gd`](debug_panel.gd) — +61/-5
- [`debug_panel.tscn`](debug_panel.tscn) — +2/-1
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +15/-2
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +13/-5

**Stats:** 7 files changed, 99 insertions, 20 deletions

**Narrative:**
The high-level debug view can now display local variables at the MiniDerp source level.

---

### Commit `4206d91` — fixed debug locals flicker

**Key Files:**
- [`debug_panel.gd`](debug_panel.gd) — +2
- [`todo.gd`](todo.gd) — +2/-1

**Stats:** 2 files changed, 3 insertions, 1 deletion

**Narrative:**
A two-line fix to eliminate flickering in the debug locals display.

---

### Commit `1c965fc` — wip locations

**Key Files:**
- [`class_Location.gd`](class_Location.gd) — +24 (expanded)
- [`class_LocationRange.gd`](class_LocationRange.gd) — +24 (expanded)
- [`class_AST.gd`](class_AST.gd) — +14
- [`globals.gd`](globals.gd) — +10
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +43/-10
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +8
- [`scenes/md_tokenizer.gd`](scenes/md_tokenizer.gd) — +10/-2
- [`scenes/word_boundary_tokenizer.gd`](scenes/word_boundary_tokenizer.gd) — +11/-2
- [`class_Token.gd`](class_Token.gd) — +4/-2
- [`scenes/ir_md.gd`](scenes/ir_md.gd) — +5/-2

**Stats:** 13 files changed, 164 insertions, 61 deletions

**Narrative:**
Location tracking classes (`class_Location`, `class_LocationRange`) are introduced. These map low-level assembly addresses back to high-level source code positions — essential for source-level debugging.

---

### Commit `fde749a` — wip

**Key Files:**
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +111/-17
- [`scenes/comp_compile_md.gd`](scenes/comp_compile_md.gd) — +17/-4
- [`scenes/comp_build.gd`](scenes/comp_build.gd) — +5/-2

**Stats:** 8 files changed, 136 insertions, 90 deletions

**Narrative:**
Continued work on the code generator, likely involving location mapping for the high-level debugger.

---

### Commit `7d293c1` — refactored for better type safety

**Key Files:**
- [`class_AssyBlock.gd`](class_AssyBlock.gd) — +10 (NEW FILE)
- [`class_CodeBlock.gd`](class_CodeBlock.gd) — +14 (NEW FILE)
- [`class_IR_cmd.gd`](class_IR_cmd.gd) — +28 (NEW FILE)
- [`class_IR_value.gd`](class_IR_value.gd) — +5 (NEW FILE)
- [`class_LocationMap.gd`](class_LocationMap.gd) — +10 (NEW FILE)
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +377/-18 (rewritten for type safety)
- [`globals.gd`](globals.gd) — +31
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +34/-2
- [`class_AST.gd`](class_AST.gd) — +9/-1
- [`class_LocationRange.gd`](class_LocationRange.gd) — +10/-1
- [`scenes/comp_compile_zd.gd`](scenes/comp_compile_zd.gd) — REMOVED

**Stats:** 19 files changed, 364 insertions, 252 deletions

**Narrative:**
A major type safety refactoring. Five new class files are created: `class_AssyBlock`, `class_CodeBlock`, `class_IR_cmd`, `class_IR_value`, `class_LocationMap`. The code generator is completely rewritten (+377/-18). An old file (`comp_compile_zd.gd`) is deleted. The codebase is becoming more structured and type-safe.

---

### Commit `7cea3b8` — wip hl debug highlight

**Key Files:**
- [`debug_panel.gd`](debug_panel.gd) — +67/-2
- [`debug_panel.tscn`](debug_panel.tscn) — +53/-4
- [`editor/editor_file.gd`](editor/editor_file.gd) — +19/-1
- [`scenes/comp_build.gd`](scenes/comp_build.gd) — +17/-1
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +12/-1
- [`scenes/comp_file.gd`](scenes/comp_file.gd) — +6/-1
- [`class_AST.gd`](class_AST.gd) — +4/-1
- [`class_ErrorReporter.gd`](class_ErrorReporter.gd) — +2/-1
- [`class_LocationRange.gd`](class_LocationRange.gd) — +10/-1

**Stats:** 12 files changed, 609 insertions, 55 deletions

**Narrative:**
High-level debug highlighting work — the ability to highlight the current MiniDerp source line during debugging.

---

### Commit `a3e63f4` — HL highlight sort of works

**Key Files:**
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +67/-4
- [`scenes/comp_build.gd`](scenes/comp_build.gd) — +28/-8
- [`scenes/comp_file.gd`](scenes/comp_file.gd) — +7/-2
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +6/-2
- [`globals.gd`](globals.gd) — +4
- [`class_Location.gd`](class_Location.gd) — +4/-2
- [`debug_panel.gd`](debug_panel.gd) — +12/-3

**Stats:** 8 files changed, 104 insertions, 25 deletions

**Narrative:**
High-level source highlighting "sort of works" — progress but still imperfect.

---

### Commit `8d68202` — debugger window [step] and [unstep] now work in HL mode

**Key Files:**
- [`debug_panel.gd`](debug_panel.gd) — +84/-31

**Stats:** 1 file changed, 53 insertions, 31 deletions

**Narrative:**
A focused commit: step and unstep (reverse step) operations now work in high-level debug mode.

---

### Commit `48caca0` — wip location debug

**Key Files:**
- [`globals.gd`](globals.gd) — +38
- [`class_Location.gd`](class_Location.gd) — +36/-2
- [`class_LocationRange.gd`](class_LocationRange.gd) — +11/-2
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +32/-16
- [`scenes/ir_md.gd`](scenes/ir_md.gd) — +72/-20
- [`debug_panel.gd`](debug_panel.gd) — +13/-6

**Stats:** 12 files changed, 176 insertions, 109 deletions

**Narrative:**
Location tracking infrastructure is enhanced. The IR and code generator are updated to carry richer location information.

---

### Commit `bb0ea53` — wip better locations

**Key Files:**
- [`debug_panel.gd`](debug_panel.gd) — +116
- [`class_Location.gd`](class_Location.gd) — +18/-4
- [`class_LocationRange.gd`](class_LocationRange.gd) — +3

**Stats:** 6 files changed, 134 insertions, 8 deletions

**Narrative:**
Better location tracking in the debug panel — 116 lines added. The location classes continue to evolve.

---

### Commit `8baa478` — wip locations - expanded location map (ELM)

**Key Files:**
- [`debug_panel.gd`](debug_panel.gd) — +166/-12
- [`class_LocationRange.gd`](class_LocationRange.gd) — +34/-2
- [`class_Location.gd`](class_Location.gd) — +15/-4

**Stats:** 5 files changed, 172 insertions, 48 deletions

**Narrative:**
The "expanded location map" (ELM) is introduced — a more comprehensive mapping between assembly addresses and source code locations.

---

### Commit `7dde647` — fixed high-level debug

**Key Files:**
- [`class_AST.gd`](class_AST.gd) — +38/-5
- [`class_Location.gd`](class_Location.gd) — +9/-2
- [`class_LocationRange.gd`](class_LocationRange.gd) — +8/-3
- [`debug_panel.gd`](debug_panel.gd) — +21/-6
- [`globals.gd`](globals.gd) — +5
- [`scenes/word_boundary_tokenizer.gd`](scenes/word_boundary_tokenizer.gd) — +33/-7
- [`scenes/win_token_view.gd`](scenes/win_token_view.gd) — +11/-5
- [`scenes/win_ed_dbg.gd`](scenes/win_ed_dbg.gd) — +17/-2
- [`scenes/md_tokenizer.gd`](scenes/md_tokenizer.gd) — +3/-1

**Stats:** 11 files changed, 140 insertions, 79 deletions

**Narrative:**
High-level debugging is finally "fixed" — the culmination of extensive location-tracking work. Source-level debugging now works reliably.

---

## Phase 5: Type System (Commits 65–69)

A type system is introduced for MiniDerp, with type hints, type checking in the analyzer, and type-aware code generation.

---

### Commit `e8e17fa` — wip types

**Key Files:**
- [`class_Type.gd`](class_Type.gd) — +23 (NEW FILE)
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +156/-3
- [`scenes/lang_md.gd`](scenes/lang_md.gd) — +32/-2
- [`error_list.gd`](error_list.gd) — +3
- [`res/data/hello_typed.md`](res/data/hello_typed.md) — +41 (NEW test file)

**Stats:** 8 files changed, 690 insertions, 200 deletions

**Narrative:**
The type system is born. A `class_Type` file is created, the analyzer gains 156 lines of type-checking logic, and the language definition adds type-related rules. A typed Hello World test file is added.

---

### Commit `1546a09` — Miniderp compiles with type hints

**Key Files:**
- [`class_Type.gd`](class_Type.gd) — +109/-9 (major expansion)
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +64/-2
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +16/-1
- [`scenes/ir_md.gd`](scenes/ir_md.gd) — +2
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +2/-1
- [`class_ErrorReporter.gd`](class_ErrorReporter.gd) — +2

**Stats:** 9 files changed, 852 insertions, 74 deletions

**Narrative:**
MiniDerp now compiles with type hints. The type system grows substantially (+109/-9 in `class_Type.gd`). The analyzer, codegen, and IR all get type-awareness tweaks.

---

### Commit `21a780b` — miniderp printf compiles with new type stuff; performance improvement

**Key Files:**
- [`class_LoopCounter.gd`](class_LoopCounter.gd) — +12 (NEW FILE)
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +29/-1
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +44/-2
- [`scenes/ir_md.gd`](scenes/ir_md.gd) — +8/-1
- [`class_Type.gd`](class_Type.gd) — +6/-1
- [`class_AST.gd`](class_AST.gd) — +22/-1
- [`globals.gd`](globals.gd) — +4/-1
- [`scenes/parser_md.gd`](scenes/parser_md.gd) — +13/-1
- [`todo.gd`](todo.gd) — +11/-1
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +7
- Test files: [`printf_test2.md`](res/data/printf_test2.md), [`printf_test3.md`](res/data/printf_test3.md)

**Stats:** 22 files changed, 1760 insertions, 267 deletions

**Narrative:**
printf compiles with the new type system. A `class_LoopCounter` is introduced for performance optimization. The type-ahead is now compatible with formatted output.

---

### Commit `c67b2d8` — codegen's fucked

**Key Files:**
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +362/-1 (major expansion, but broken)
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +5
- [`scenes/ir_md.gd`](scenes/ir_md.gd) — +5/-1
- [`debug_panel.gd`](debug_panel.gd) — +6/-1
- [`globals.gd`](globals.gd) — +2/-1
- [`class_ErrorReporter.gd`](class_ErrorReporter.gd) — +2/-1
- [`export_presets.cfg`](export_presets.cfg) — +67 (NEW FILE)

**Stats:** 14 files changed, 7607 insertions, 1370 deletions

**Narrative:**
A brutally honest commit message — the code generator is broken. 362 lines added but something went wrong. An export preset is added for standalone builds. This represents a setback in the type system integration.

---

### Commit `18f2880` — fixed a crash

**Key Files:**
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +8
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +6/-1
- [`scenes/main.tscn`](scenes/main.tscn) — +152/-7
- [`class_CodeBlock.gd`](class_CodeBlock.gd) — +1
- [`project.godot`](project.godot) — +6/-1
- [`res/data/testOS/main.md`](res/data/testOS/main.md) — +60 (NEW test file)

**Stats:** 10 files changed, 1007 insertions, 284 deletions

**Narrative:**
Crash recovery — the regression from the previous commit is fixed. A new `testOS/main.md` test file is added, suggesting a "test operating system" concept for MiniDerp.

---

## Phase 6: Plans & Documentation (Commit 70)

A pure documentation and planning commit that creates the project's formal documentation infrastructure.

---

### Commit `2ca5f3a` — wip

**Key Files:**
- [`docs/todo.md`](docs/todo.md) — +12 (NEW)
- [`docs/todo_implementation.md`](docs/todo_implementation.md) — +485 (NEW)
- [`docs/miniderp_syntax.md`](docs/miniderp_syntax.md) — +242 (NEW)
- [`plans/implementation_arity.md`](plans/implementation_arity.md) — +298 (NEW)
- [`plans/implementation_array.md`](plans/implementation_array.md) — +260 (NEW)
- [`plans/implementation_character_literals.md`](plans/implementation_character_literals.md) — +113 (NEW)
- [`plans/implementation_compound_operators.md`](plans/implementation_compound_operators.md) — +155 (NEW)
- [`plans/implementation_include.md`](plans/implementation_include.md) — +159 (NEW)
- [`plans/implementation_indirect_calls.md`](plans/implementation_indirect_calls.md) — +190 (NEW)
- [`plans/implementation_not_equal.md`](plans/implementation_not_equal.md) — +191 (NEW)
- [`plans/implementation_precedence.md`](plans/implementation_precedence.md) — +177 (NEW)
- [`res/data/test_arr_if.md`](res/data/test_arr_if.md) — +19 (NEW test file)
- [`res/data/testOS/main.md`](res/data/testOS/main.md) — +106/-3

**Stats:** 15 files changed, 3507 insertions, 385 deletions

**Narrative:**
A PURE DOCUMENTATION commit. Twelve new files are created, organized into `docs/` (project documentation) and `plans/` (implementation plans for specific features). The `miniderp_syntax.md` document formally defines the MiniDerp language. Each plan file addresses a specific feature: arity checking, arrays, character literals, compound operators, `#include`, indirect calls, not-equal operator, and operator precedence. This marks the project's transition from pure hacking to planned development.

---

## Phase 7: Feature Implementation Sprint (Commits 71–78)

The planned features from the documentation phase are implemented one by one.

---

### Commit `5606e3a` — fixed !=

**Key Files:**
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +1
- [`scenes/md_tokenizer.gd`](scenes/md_tokenizer.gd) — +2/-1
- [`scenes/lang_zvm.gd`](scenes/lang_zvm.gd) — +1
- [`res/data/test_not_eq.md`](res/data/test_not_eq.md) — +14 (NEW test file)

**Stats:** 7 files changed, 84 insertions, 80 deletions

**Narrative:**
The not-equal (`!=`) operator is implemented. A single line in the code generator, a tokenizer tweak, and a VM ISA addition make it work.

---

### Commit `e65e359` — fixed precedence of x[I]

**Key Files:**
- [`scenes/lang_md.gd`](scenes/lang_md.gd) — +2

**Stats:** 3 files changed, 6 insertions, 4 deletions

**Narrative:**
A two-line fix in the grammar rules corrects the precedence of array index expressions (`x[I]`).

---

### Commit `2401d5f` — character literals work now

**Key Files:**
- [`scenes/md_tokenizer.gd`](scenes/md_tokenizer.gd) — +34/-1
- [`scenes/word_boundary_tokenizer.gd`](scenes/word_boundary_tokenizer.gd) — +6
- [`scenes/KB.gd`](scenes/KB.gd) — +30/-1
- [`scenes/lang_md.gd`](scenes/lang_md.gd) — +1
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +3
- [`scenes/main.gd`](scenes/main.gd) — +5
- [`scenes/main.tscn`](scenes/main.tscn) — +9/-1
- [`docs/miniderp_syntax.md`](docs/miniderp_syntax.md) — +6
- [`error_list.gd`](error_list.gd) — +1

**Stats:** 12 files changed, 841 insertions, 778 deletions

**Narrative:**
Character literals are implemented. The tokenizer, keyboard handler, and analyzer are updated to support single-character constants.

---

### Commit `083faf5` — implemented #include

**Key Files:**
- [`scenes/md_tokenizer.gd`](scenes/md_tokenizer.gd) — +36/-1
- [`scenes/comp_compile_md.gd`](scenes/comp_compile_md.gd) — +7/-1
- [`scenes/comp_build.gd`](scenes/comp_build.gd) — +3/-1
- [`error_list.gd`](error_list.gd) — +2
- [`res/data/testOS/lib/screen.md`](res/data/testOS/lib/screen.md) — +54 (NEW library file)

**Stats:** 8 files changed, 933 insertions, 891 deletions

**Narrative:**
The `#include` directive is implemented, enabling modular code organization. A screen library in MiniDerp is added as the first standard library file.

---

### Commit `2b28284` — implemented compound assignment +=

**Key Files:**
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +55/-2
- [`scenes/lang_md.gd`](scenes/lang_md.gd) — +7 (new grammar rules: `+=`, `-=`, `*=`, `/=`, `%=`)
- [`res/data/testOS/main.md`](res/data/testOS/main.md) — +6/-1

**Stats:** 5 files changed, 444 insertions, 404 deletions

**Narrative:**
Compound assignment operators are implemented: `+=`, `-=`, `*=`, `/=`, `%=`. The analyzer handles the desugaring of these operators.

---

### Commit `428b3f5` — added arity check

**Key Files:**
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +35/-2
- [`scenes/ir_md.gd`](scenes/ir_md.gd) — +4/-1
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +2/-1
- [`error_list.gd`](error_list.gd) — +2

**Stats:** 5 files changed, 187 insertions, 170 deletions

**Narrative:**
Function arity checking is added — the analyzer now verifies that function calls pass the correct number of arguments.

---

### Commit `560c81a` — indirect calls supported now

**Key Files:**
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +24
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +8/-1
- [`res/data/testOS/main.md`](res/data/testOS/main.md) — +3

**Stats:** 5 files changed, 253 insertions, 175 deletions

**Narrative:**
Indirect (dynamic/function pointer) calls are supported — a significant language feature that enables higher-order programming patterns.

---

### Commit `f1c3917` — wip array

**Key Files:**
- [`scenes/lang_md.gd`](scenes/lang_md.gd) — +9/-1 (array literal grammar rules)
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +45/-2
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +19/-1
- [`scenes/ir_md.gd`](scenes/ir_md.gd) — +4/-1
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +33
- [`error_list.gd`](error_list.gd) — +1

**Stats:** 9 files changed, 840 insertions, 790 deletions

**Narrative:**
Array literal support begins. Grammar rules for array syntax are added to `lang_md.gd`, the analyzer handles array types, and the code generator starts producing array-related assembly.

---

## Phase 8: Arrays, Shadow Stack, and Final Polish (Commits 79–87)

The array feature is completed, shadow stack instrumentation is added for debugging, and the project receives final polish.

---

### Commit `1b2dc74` — wip

**Key Files:**
- [`contraption/panel_contraption.tscn`](contraption/panel_contraption.tscn) — +92 (NEW FILE)
- [`project.godot`](project.godot) — +6/-1

**Stats:** 4 files changed, 625 insertions, 6646 deletions

**Narrative:**
A new UI scene is added (`panel_contraption`). IR.txt and a.zd are significantly contracted (recompiled output files).

---

### Commit `427b03f` — wip arrays

**Key Files:**
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +28/-12
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +13/-3
- [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) — +33
- [`plans/implementation_array.md`](plans/implementation_array.md) — +80/-19
- [`res/data/test_arr2.md`](res/data/test_arr2.md) — +12 (NEW test file)

**Stats:** 8 files changed, 179 insertions, 86 deletions

**Narrative:**
Array implementation continues. The array plan document is updated with new insights.

---

### Commit `da685db` — some plans

**Key Files:**
- [`plans/implementation_debug_panel_pointers.md`](plans/implementation_debug_panel_pointers.md) — +549 (NEW)
- [`plans/implementation_parser_dfa.md`](plans/implementation_parser_dfa.md) — +1013 (NEW)

**Stats:** 2 files changed, 1562 insertions

**Narrative:**
Two new detailed plan documents: one for debug panel pointers (549 lines) and one for a DFA-based parser rewrite (1013 lines). The DFA parser plan is the largest plan document in the project.

---

### Commit `4277052` — wip

**Key Files:**
- [`docs/diagnosis_array_literal.md`](docs/diagnosis_array_literal.md) — +346 (NEW diagnosis document)
- [`plans/implementation_debug_panel_pointers.md`](plans/implementation_debug_panel_pointers.md) — +91/-3
- [`.gitignore`](.gitignore) — +4
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +2/-1

**Stats:** 6 files changed, 534 insertions, 1283 deletions

**Narrative:**
A diagnosis document for array literal bugs is created (346 lines). The debug panel pointers plan is updated.

---

### Commit `6ebdc5a` — added codegen instrumentation for stack shadows

**Key Files:**
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +121/-16
- [`scenes/Memory.gd`](scenes/Memory.gd) — +19
- [`scenes/lang_zvm.gd`](scenes/lang_zvm.gd) — +24
- SHADOW_FRAME_* constants added to ISA

**Stats:** 8 files changed, 491 insertions, 78 deletions

**Narrative:**
Stack shadow instrumentation is added to the code generator. Shadow frame constants (`SHADOW_FRAME_*`) are added to the ZVM ISA. This enables the debugger to track high-level call frames and local variables through shadow memory.

---

### Commit `fe29c69` — codegen stuff and shadow stack

**Key Files:**
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +59/-2
- [`scenes/Memory.gd`](scenes/Memory.gd) — +36/-1
- [`scenes/lang_zvm.gd`](scenes/lang_zvm.gd) — +4/-1

**Stats:** 6 files changed, 1763 insertions, 374 deletions

**Narrative:**
Continued work on the shadow stack system and code generation.

---

### Commit `d59611f` — arrays mostly work

**Key Files:**
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +24/-1
- [`debug_panel.gd`](debug_panel.gd) — +6/-1
- [`res/data/testOS/main.md`](res/data/testOS/main.md) — +154 (major test program expansion)

**Stats:** 5 files changed, 4498 insertions, 574 deletions

**Narrative:**
"Arrays mostly work" — a significant milestone. The testOS main program expands by 154 lines, suggesting a substantial test program exercising array functionality.

---

### Commit `950b1cb` — merged

**Narrative:**
A merge commit with no net code changes.

---

### Commit `833801` — small fixes, something still broken on compile

**Key Files:**
- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +6/-1
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +14/-1
- [`scenes/ir_md.gd`](scenes/ir_md.gd) — +2/-1
- [`class_CodeBlock.gd`](class_CodeBlock.gd) — +1/-1
- [`error_list.gd`](error_list.gd) — +1/-1

**Stats:** 10 files changed, 10345 insertions, 14 deletions

**Narrative:**
The most recent commit in the history. Small fixes applied across the compiler stack, but a compilation bug remains unfixed. The project is in a state of ongoing development.

---

## Summary Statistics

| Metric | Value |
|--------|-------|
| **Total Commits** | 87 |
| **Total Phases** | 8 (9 counting Phase 0 as setup) |
| **Core VM File** | `CPU_vm.gd` — grew from initial import to ~800+ lines |
| **Assembler** | `comp_asm_zd.gd` — grew from 73 to ~1,200+ lines |
| **Code Generator** | `codegen_md.gd` — created in Phase 2, grew to ~1,500+ lines |
| **Debug Panel** | `debug_panel.gd` — grew from 202 to ~1,000+ lines |
| **MiniDerp Files** | Tokenizer, parser, analyzer, IR, codegen — ~15+ core files |
| **Class Files** | 15+ standalone class files for type safety |
| **Plan Documents** | 11 detailed implementation plans |
| **Documentation** | 3 docs files + 1 diagnosis document |
| **Languages** | ZDerp (assembly) and MiniDerp (high-level) |

---

## Architectural Evolution Summary

The project began as a single monolithic vision — a custom CPU VM inside Godot with an assembler (ZDerp). It evolved through:

1. **Core VM & Assembler** — Making the CPU execute instructions and the assembler produce them
2. **High-Level Language** — Adding MiniDerp, a C-like language that compiles to ZDerp
3. **Compiler Pipeline** — Tokenizer → Parser → Analyzer → IR → Code Generator → Assembler
4. **Debugger** — From basic register view to full high-level source debugging with variable inspection
5. **Type System** — Adding type hints, checking, and type-aware code generation
6. **Language Features** — printf, character literals, `#include`, compound assignment, arity checking, indirect calls, arrays
7. **Shadow Memory** — Stack shadow frames for debugging and runtime introspection

The project is still actively developed with a known compile bug at the latest commit.
