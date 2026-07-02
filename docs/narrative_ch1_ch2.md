# CpuDerp: A Development Narrative

## Chapter 1: Genesis — Building a Computer From Nothing

> *Commits `2a3aa0c` → `8b6f56f`*

---

### The Empty Shell

Every creation myth begins with a void. On a cold Git repository somewhere, the first commit — hash [`2a3aa0c`](https://github.com/) — contained nothing but a `.gitignore`. Twenty-two lines of ignored file patterns, an empty vessel waiting to be filled. It was a promise: *something will be built here*.

What came next was not gradual. It was a detonation.

### The Big Bang

Commit [`c442b70`](https://github.com/) — hash casually titled "migrating" — detonated 83 files and 3,824 lines of code into existence on **2025-06-09 10:54:52 +0300** by **zondartul**. This was not a project starting from scratch. This was a complete, pre-existing offline codebase being transplanted into version control for the first time. A fully-formed digital ecosystem, built in isolation, now seeing the light of day.

The scope of what arrived in that single commit is staggering:

- **TWO CPUs**: a 730-line full VM interpreter ([`CPU_vm.gd`](scenes/CPU_vm.gd)) with fetch-decode-execute loop, opcode dispatch, and interrupt handling — AND a 95-line simpler CPU ([`CPU_gd.gd`](scenes/CPU_gd.gd)) that had its own GPU driver, keyboard echo, and a `postsetup()` printing "Hello from CPU_gd!"
- A **character-mode GPU** ([`GPU_cs.gd`](scenes/GPU_cs.gd)) driving a 56×36 tile display, each tile 7 bytes (char + 3 FG color + 3 BG color), addressed starting at offset 2000
- A **keyboard handler** ([`KB.gd`](scenes/KB.gd)) using a circular buffer with raw unicode, where `buffer[0]` doubled as a size counter
- **64KB of RAM** ([`RAM_64k.gd`](scenes/RAM_64k.gd)), the full addressable memory space
- A **memory bus** ([`Bus.gd`](scenes/Bus.gd)) capable of routing reads and writes to child devices
- A **code editor** ([`Editor.gd`](scenes/Editor.gd)) with syntax highlighting, file management via [`comp_file.gd`](scenes/comp_file.gd), and a highlight engine
- A **debug panel** ([`debug_panel.gd`](debug_panel.gd)) — 202 lines that **duplicated** all ISA constants (register names, bit flags) independently of the CPU, a duplication that would later need deduplication
- A **custom regex engine** ([`my_regex.gd`](my_regex.gd)) — 303 lines of hand-rolled pattern matching
- A **ZDerp "compiler" stub** ([`comp_compile_zd.gd`](scenes/comp_compile_zd.gd)) — 73 lines consisting mostly of a 40-line comment block describing an ambitious language (static and dynamic typing, lambdas, exceptions) but with empty `tokenize()` and `compile()` functions
- A **ZDerp assembly syntax highlighter** ([`lang_zd.gd`](scenes/lang_zd.gd)) defining 43 opcode and register name keywords
- A **tokenizer rules file** ([`zderp_rules.gd`](scenes/..)) with regex patterns for the not-yet-implemented ZDerp high-level language
- A **broken build pipeline** ([`comp_build.gd`](scenes/comp_build.gd)) that referenced `$comp_asm_zd` as a child node — but no such node existed yet, ensuring a runtime error
- An **accidentally-committed temp file** ([`scenes/mai9BA4.tmp`](scenes/mai9BA4.tmp)) — 189 lines of transient clutter
- Scenes, tiles, icons, and the [`project.godot`](project.godot) configuration (Godot **4.4**, GL Compatibility renderer, 512×700 window)

The ISA was not yet extracted into its own module. All 14 register names, 30+ opcodes, control flags, and bit constants were defined directly inside [`CPU_vm.gd`](scenes/CPU_vm.gd). The shared [`lang_zvm.gd`](lang_zvm.gd) module did not exist yet — that refactoring was still weeks away.

Nothing in this dump was boilerplate. Every file was purpose-built. The architecture was already clear: a modular computer system simulated inside the Godot engine, where a bus connected CPU, RAM, GPU, and keyboard into a harmonious whole. The [`VM.gd`](scenes/VM.gd) node acted as the system orchestrator — a motherboard in software — wiring the bus to the CPU and exposing `setup()` and `reset()` to the outside world.

Why build all this inside a game engine? The answer lies in the GPU. Godot's rendering pipeline gave this virtual machine a screen — a tile-based character display rendered through a `SubViewport` and a custom shader scene. This wasn't just a CPU simulator in a terminal. This was a *computer* you could look at.

### The Instruction Set Architecture

At the heart of the system lay the ZVM instruction set. But at the time of the big bang import, it had no home of its own — the ISA was **embedded directly inside** [`CPU_vm.gd`](scenes/CPU_vm.gd). Every register name, opcode constant, control flag bitmask, and `BIT_*` definition was hardcoded as script-local constants in the 730-line CPU file. The shared [`lang_zvm.gd`](lang_zvm.gd) module — which would later become the canonical ISA definition — did not exist yet.

The ISA itself was a creature of deliberate design, neither a toy nor an x86 clone, but something in between.

The register file was a careful selection of 14 named registers:

| Register | Purpose |
|----------|---------|
| `EAX`, `EBX`, `ECX`, `EDX` | General purpose |
| `IP` | Instruction Pointer |
| `ESP`, `ESZ`, `ESS` | Stack Pointer, Stack Zero (underflow guard), Stack Size |
| `EBP` | Base Pointer (stack frames) |
| `IVT`, `IVS` | Interrupt Vector Table, Interrupt Vector Size |
| `IRQ` | Interrupt Request flag |
| `CTRL` | Control register (flags: PWR, STEP, IRS, CMP_L/G/Z, IE) |

The opcode table spanned 34 operations, organized into families: control flow (`JMP`, `CALL`, `RET`, `CMP`), interrupt handling (`INT`, `INTRET`), memory (`MOV`, `PUSH`, `POP`), ALU arithmetic (`ADD` through `DEC`), ALU logic (`AND` through `NOT`), bitwise operations (`BAND` through `BCLEAR`), and the humble `NOP`.

Each instruction was 8 bytes — a fixed-length encoding that traded code density for simplicity. The layout was: `[opcode][flags][reg1|reg2][4-byte immediate][pad]`. Wildcards like dereference flags, immediate-mode toggles, and 8-bit vs 32-bit data modes gave the ISA surprising expressiveness. Jump instructions could be conditional — `JG`, `JL`, `JE`, `JZ`, `JNZ`, `JNE`, `JNG`, `JNL` — all encoded as variants of the base `JMP` opcode with different flag masks.

This was an architecture designed by someone who had thought deeply about what a virtual CPU needed: stack operations with overflow protection, interrupt vectors, bit-level manipulation, and conditional execution. It was, in the truest sense, a *real* computer.

### The Assembler Takes Shape
With the CPU defined but untested, work turned to the tool that would feed it: the assembler. Three commits followed in rapid succession, each titled simply "wip assembler" — work in progress — as if the developer lacked the breath to write anything longer.

Commit [`f0bd6d9`](https://github.com/) — **2025-06-09 14:29:57**, the same day as the big bang — was a pivotal refactoring. [`lang_zvm.gd`](lang_zvm.gd) was **created** (115 lines), absorbing the full opcode table, register definitions, control flag bitmasks, and shadow memory type system that had previously been embedded in [`CPU_vm.gd`](scenes/CPU_vm.gd). The CPU lost 167 lines of inline ISA definitions and was refactored to use `const ISA = preload("res://lang_zvm.gd")`, referencing everything via the `ISA.*` prefix. This was a pure refactoring — no behavioral changes, just the birth of a shared, canonical ISA definition.

But this was also the commit where the **first real assembler** was born. [`comp_asm_zd.gd`](scenes/comp_asm_zd.gd) was created (129 lines), featuring:

- **Preprocessing**: comment removal and whitespace trimming
- **Character-class tokenizer**: integer token classes (`TOK_ERROR=0`, `TOK_SPACE=1`, `TOK_WORD=2`, `TOK_NUMBER=3`, `TOK_PUNCT=4+`)
- **Label detection**: `proc_is_label` matched `WORD :` patterns
- **Command parsing**: `proc_is_command` looked up opcodes in the freshly-minted `ISA.opcodes`
- **Bytecode emission**: `emit_opcode` emitted 8 bytes per instruction, with a different flags-byte arrangement than the final scheme

This first assembler was simpler and cruder than what would follow — its tokenizer used integer classes rather than strings, there was no string-literal support, and the instruction encoding differed from the final layout. But it was a genuine assembler, capable of parsing real assembly text and producing bytecode.

However, there was a notable gap: the debug panel ([`debug_panel.gd`](debug_panel.gd)) was **not updated** in this commit. It still carried its own duplicate copies of all `regnames`, `BIT_*`, and `REG_*` constants — a refactoring debt that would need cleaning later.

### Assembly Seems to Work

Then came the breakthrough.

Commit [`8b6f56f`](https://github.com/) — **2025-06-12**, three days of steady work after the big bang — bore the honest message: *"assembly seems to work"*.

That "seems" carried the weight of genuine uncertainty. The assembler had been **massively rewritten**: 403 insertions, 107 deletions. [`comp_asm_zd.gd`](scenes/comp_asm_zd.gd) was transformed from a simple character-class tokenizer into a proper, iterator-based parser engine. The changes were surgical and deep:

- **Tokenizer rewrite**: integer token classes (`TOK_ERROR=0`, `TOK_SPACE=1`, etc.) were replaced with string classes (`"WORD"`, `"NUMBER"`, `"PUNCT"`, `"STRING"`, `"SPACE"`). String literal support was added with `"` delimiters and `ENDSTRING` filtering. A `should_split_on_transition()` function handled smarter token boundary detection.
- **Proper parser**: the old `proc_is_label`/`proc_is_command` functions were replaced with a structured iterator-based parser featuring `parse_label()`, `parse_db()`, `parse_command()` with `peek_tokens()`/`match_tokens()` lookahead.
- **Data directives**: `db` directives with `emit_db_items()` could now emit raw data bytes, string constants, and label addresses.
- **Forward reference linking**: `label_refs` tracking and `link_internally()` with `patch_ref()` handled unresolved forward references — essential for any non-trivial program with jumps to labels defined later in the code.
- **32-bit support**: a `.32` size specifier was added for 32-bit immediate operands.
- **Structured operands**: `Cmd_arg` and `Cmd_flags` inner classes gave the assembler a formal model for parsing and encoding instruction operands.
- **Error reporting**: `error_code` tracking and `point_out_error()` with `^`-caret annotation told the developer exactly where parsing failed.
- **Punctuation expansion**: the punctuation set grew to `.,:[]+;` — including bracket support for array-style memory access.

The ISA was also extended. All opcode numbers shifted up by 1 (slot 0 became `NONE`), and `spec_ops` was born — a set of conditional jump aliases: `JG`, `JL`, `JE`, `JZ`, `JNZ`, `JNE`, `JNG`, `JNL`. Each mapped to opcode 3 (`JMP`) but carried different flag mask combinations, granting the assembler the ability to write readable conditional jumps.

And for the first time, **nine assembly test programs** appeared in the repository, proving the assembler could produce real, structured code:

- [`main.txt`](res/data/main.txt) (88 lines): a Hello World program using `putch3` and `set_color`, with a `test` routine that branched on comparison results — the first real proof that conditional assembly worked.
- [`shell1.txt`](res/data/shell1.txt) (99 lines): a shell environment with `for_loop`, `puts`, `putch`, `scr_clear`, `set_color` — the scaffolding of an interactive system.
- [`shell2.txt`](res/data/shell2.txt) (124 lines): an extended shell that tested stack frame access, reading `ebp[9]`, `ebp[10]`, etc. — proving the calling convention and stack discipline worked.
- [`shell3.txt`](res/data/shell3.txt) (163 lines): a full shell featuring `itoa` (integer-to-ASCII), `str_rev` (string reverse), and `strlen` (string length) — essentially a complete stdlib, written entirely in ZVM assembly.
- [`lib/libscreen.zd`](res/data/lib/libscreen.zd) (54 lines): a reusable screen library with `scr_clear`, `puts`, `putch`.
- [`lib/string.zd`](res/data/lib/string.zd) (57 lines): a reusable string library with `itoa`, `str_rev`, `strlen`.
- [`lib/main2.zd`](res/data/lib/main2.zd) (54 lines): a keyboard test program referencing `adr_kb` at address 81648, with `has_key`/`get_key` routines.

These test programs reveal just how capable the ZVM already was. The assembler could express: **conditional jumps** via `JG`/`JL`/`JE` aliases, **function calls and returns** with stack frame management, **stack frame access** via EBP offsets (`ebp[9]`, `ebp[10]`), **pointer dereference** with `*` syntax, **array-style indexing** (`eax[N]`), **32-bit immediate operands**, **string data** via `db` directives, and **computed addresses** through label references.

The presence of libraries is significant. The developer wasn't just testing the assembler's syntax parsing; they were building a *runtime environment*. Screen handling routines, string operations — these were the building blocks of real programs.

But there was a gap: the assembler could produce bytecode, but there was no way to run it. Not yet.

---

## Chapter 2: First Light — The VM Comes Alive

> *Commits `0f610f4` → `490cb72`*

---

### The Bridge

Commit [`0f610f4`](https://github.com/) bore a confession in its title: *"assembled code now uploads to CPU and debugger barely works"*.

That word — "barely" — is the hallmark of honest engineering. The end-to-end pipeline was connected for the first time. The assembler's output could be loaded into the CPU's memory space. The CPU could attempt to execute it. And the debugger? It could *barely* keep up.

The changes were surgical. [`comp_asm_zd.gd`](scenes/comp_asm_zd.gd) +32/-6 — the assembler gained the ability to export its code array for upload. [`comp_build.gd`](scenes/comp_build.gd) +21/-3 — the build system became the bridge, calling the assembler and feeding the result into the CPU. [`RAM_64k.gd`](scenes/RAM_64k.gd) +9/-2 — the memory module gained write access for program loading. [`debug_panel.gd`](debug_panel.gd) +24/-11 — the debugger tried, valiantly, to display something useful.

This was the moment the system stopped being a collection of parts and became a computer.

### Nitpicks and Merges

Commit [`00ffeec`](https://github.com/) — "nitpicks" — was a minor cleanup pass. Three files, nine insertions, three deletions. Small adjustments to the assembler, the build system, and text rendering. The kind of commit that says "I noticed something slightly wrong and fixed it before it became a problem."

Commit [`4cb18d5`](https://github.com/) — "Merge pull request #1" — marked the project's first merge. A feature branch had been created, work had been done on it, and now it was folded back. The project was growing beyond a single linear stream of consciousness.

Commit [`d2421b6`](https://github.com/) — "build status messages" — added feedback to the editor console. The user could now see what was happening during the assembly and upload pipeline. [`Editor.gd`](scenes/Editor.gd) grew by 6 lines, [`comp_build.gd`](scenes/comp_build.gd) by 12. A small thing, but essential: a computer is not usable if it's silent about its operations.

### The Memory Viewer

Up until this point, debugging was done through print statements and raw register dumps. The CPU had registers, the RAM had bytes, but there was no window into memory. That changed with commit [`75070d1`](https://github.com/): *"added memory viewer"*.

[`Memory.gd`](scenes/Memory.gd) was born — 104 lines of a standalone hex dump display. It was simple but functional: a `TextEdit` widget that read from RAM and displayed bytes in hexadecimal format. [`CPU_vm.gd`](CPU_vm.gd) gained +14/-6 lines to support memory access signals. [`comp_build.gd`](comp_build.gd) gained +5 lines to connect the viewer to the build pipeline. The main scene ([`main.tscn`](scenes/main.tscn)) added the memory tab to the interface.

The memory viewer was more than a tool; it was a philosophy. You cannot debug what you cannot see. With a hex dump on screen, the developer could finally inspect what the assembler produced, confirm that bytecode was loaded correctly, and watch memory change as the CPU executed.

### Shadow Memory and the Color-Coded Memview

The hex dump was useful, but raw bytes are inscrutable. A block of memory might contain code, data, padding, or unresolved references — and without knowing *what* each byte represents, debugging remained guesswork.

Commit [`c98c965`](https://github.com/) solved this with elegant metadata: *"added shadow memory, color-coded memview, fixed ref_patch"*.

Shadow memory was a second memory layer — a parallel array that tracked the *type* of each byte in main RAM. The type system, defined in [`lang_zvm.gd`](lang_zvm.gd) as constants like `SHADOW_UNUSED`, `SHADOW_DATA`, `SHADOW_CMD_HEAD`, `SHADOW_CMD_TAIL`, `SHADOW_CMD_UNRESOLVED`, `SHADOW_CMD_RESOLVED`, and a dozen more, turned raw bytes into annotated artifacts.

The memory viewer ([`Memory.gd`](scenes/Memory.gd)) expanded by 102 lines to become color-coded. A lookup table mapped shadow types to colors:

```python
SHADOW_UNUSED → Gray
SHADOW_DATA → Yellow
SHADOW_CMD_HEAD → Green
SHADOW_CMD_TAIL → Dark Green
SHADOW_CMD_RESOLVED → Yellow-Green
SHADOW_CMD_UNRESOLVED → Red
SHADOW_DATA_UNRESOLVED → Orange
SHADOW_DATA_RESOLVED → Cyan
SHADOW_FRAME_PREV_EBP → Red
SHADOW_FRAME_PREV_IP → Cyan
SHADOW_FRAME_ARGUMENT → Orange
SHADOW_FRAME_VAR → Yellow
SHADOW_FRAME_TEMP → Purple
SHADOW_FRAME_PADDING → Dark Blue
```

The memory view transformed from a monochrome grid into a color-coded map of the computer's state. Green command headers, yellow data, red unresolved references — the developer could now glance at memory and understand the layout at a high level.

The same commit fixed a "ref_patch byte offset" bug in the assembler ([`comp_asm_zd.gd`](scenes/comp_asm_zd.gd) +78/-4). Label resolution required patching forward references — replacing placeholder bytes with actual addresses once the label's position was known. A byte offset error meant those patches landed on the wrong bytes, corrupting instructions. Fixing it was essential for any non-trivial program to work.

The build system ([`comp_build.gd`](scenes/comp_build.gd)) grew by 20 lines, and [`main.gd`](scenes/main.gd) gained 54 lines of orchestration logic. The system was becoming more integrated, more automated, more *real*.

### The Three-Month Gap

The commit history tells a remarkable story: after the adrenaline of the big bang import on June 9th and the breakthrough "assembly seems to work" on June 12th, the narrative goes *silent*. Three months pass. The next commit — [`490cb72`](https://github.com/) — arrives on **2025-09-16**.

What happened in those three months? The commit log doesn't say. But the code tells us. This was not a flurry of commits; it was a period of solitary, offline development — testing, debugging, fixing, breaking, fixing again. Some problems cannot be solved by typing faster. Some require staring at hex dumps, tracing through register states in your head, and slowly, painstakingly, making the machine obey.

### The Great Migration

Commit [`490cb72`](https://github.com/) opened with an administrative note: *"moved to Godot 4.5"*. The [`project.godot`](project.godot) config changed from Godot **4.4** to **4.5**, a version bump that might have hidden risks of API changes and breaking modifications. But then came the real changes — the fixes that finally brought the system to life.

**A disassembly improvement.** The CPU gained a new function — [`decode_op_variant()`](scenes/CPU_vm.gd) — that maps decoded flag combinations back to human-readable opcode mnemonics. A `JMP` instruction with `CMP_G` flags would now display as `JG`, not just a bare `JMP`. The [`debug_disasm_cmd()`](debug_panel.gd) output became vastly more readable, letting the developer see exactly which conditional jump was encoded.

**A subtle but critical fix.** The assembler had been emitting hardcoded immediate values of 0 for all instructions. The line `emit_opcode(opcode, flags, reg1, reg2, 0, ..)` — that `0` was the killer. Commit [`490cb72`](https://github.com/) fixed it to pass `arg1.offset+arg2.offset` as the immediate value. Without this fix, every instruction with an immediate operand — every `MOV eax, 42`, every `CALL my_label`, every `JMP target` — would encode a zero instead of the intended value. The assembler had been producing *technically valid* but *semantically wrong* bytecode for three months.

**Array access unblocked.** The `eax[N]` syntax — dereferencing memory at a register-plus-offset address — was also fixed. The parser had been correctly processing the `[N]` bracket notation but then discarding the result. The fix added `arg.is_deref = true` after processing the brackets, finally enabling array-style memory access in assembly.

**IP highlighting goes live.** The memory viewer ([`Memory.gd`](scenes/Memory.gd)) was wired to the CPU's step cycle. A new callback — [`_on_cpu_vm_cpu_step_done()`](Memory.gd) — refreshed the memory display every time the CPU completed an instruction. The IP address was fetched via `var ip = cpu_vm.regs[ISA.REG_IP]`, and lines where `i == ip` were annotated with `[bgcolor=darkblue]` BBCode tags. The developer could now watch the blue bar slide forward through the hex dump, one instruction at a time, as the CPU executed.

```
if i == ip: line_text += "[bgcolor=darkblue]...[/bgcolor]"
```

A single conditional check — `if i == ip` — transformed the static memory view into a dynamic window into the running machine.

### Hello World

And then, the milestone that made everything worthwhile. The commit message said it all: *"CPU works for the first time (Hello World)"*.

Three months after the big bang import. Three months after the assembler was born. Three months of silent debugging, of staring at bytecode that wouldn't run, of fixing immediate values and bracket syntax and forward-reference patching.

The changes were modest: [`CPU_vm.gd`](scenes/CPU_vm.gd) +19/-16, [`Memory.gd`](scenes/Memory.gd) +25/-7, [`comp_asm_zd.gd`](scenes/comp_asm_zd.gd) +18/-3, [`lang_zvm.gd`](lang_zvm.gd) +1. Fifty-four insertions, sixteen deletions across eight files. Not a massive commit, but one that represented the culmination of everything that came before.

But the impact was monumental. The assembler could convert human-readable assembly into machine code. The build system could upload that code into RAM. The CPU could fetch, decode, and execute instructions. The memory viewer could display the execution in real time. The GPU could render output to the screen.

The first program to ever run on the ZVM printed "Hello World" — and in that moment, the digital computer that had existed only as potential, as lines of code in a Godot scene tree, became real. A computer, built from nothing, was alive.

---

*End of Chapters 1–2. The narrative continues with the MiniDerp compiler frontend and the evolution of a high-level language ecosystem.*
