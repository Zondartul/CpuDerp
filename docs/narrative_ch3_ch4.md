# CpuDerp: A Development Narrative

## Chapter 3: The High-Level Dream — Enter MiniDerp

> *Commits `39b6389` → `5d2bf78`*

---

### The Wager

The ZVM was alive. Assembly programs assembled, uploaded to memory, and executed on the custom CPU. Hello World had printed across the GPU screen. But writing ZDerp assembly was tedious — hand-managing registers, tracking stack frames, resolving label addresses. Every program required intimate knowledge of the CPU's instruction encoding. It was *powerful*, but it was not *productive*.

The developer stared at the working assembler and made a decision that would define the next phase of the project: build a high-level language compiler on top of this machine. Not a simple transpiler, not a macro preprocessor, but a *real compiler* — tokenizer, parser, semantic analyzer, intermediate representation, and code generator.

Thus MiniDerp was born.

### The First Seed

Commit [`39b6389`](https://github.com/) — "wip compiler" — planted the seed. Three new files appeared in the repository:

- [`word_boundary_tokenizer.gd`](scenes/word_boundary_tokenizer.gd:1) — a 64-line generic tokenizer that split text on punctuation boundaries. It didn't know about MiniDerp or any specific language; it simply understood that words, numbers, punctuation, and strings were different token classes. It was a reusable foundation, pulled from the assembler's existing tokenization logic (comment in line 2: *"this tokenizer was grabbed from comp_asm_zd"*). The tokenizer's `should_split_on_transition()` function at [`word_boundary_tokenizer.gd`](scenes/word_boundary_tokenizer.gd:28-52) decided the split logic: `WORD`+`NUMBER` stayed together — allowing identifiers with trailing digits like `var2` — `STRING` tokens kept accumulating between quotes without splitting, and `PUNCT` always split one-by-one so each punctuation character became its own token for later recombination.

- [`comp_compile_md.gd`](scenes/comp_compile_md.gd:1) — the compiler orchestration file, initially just 20 lines. A skeleton waiting for organs.

- [`lang_md.gd`](scenes/lang_md.gd:1) — 43 lines of language definition. It declared keywords (`var`, `func`, `if`, `else`, `while`, `return`), types (`int`, `char`, `float`, `u8`-`u64`, `s8`-`s64`, `Ref`, `String`), operators, and punctuation. And importantly, it held the first grammar rules — the seed of a shift-reduce parser.

The build system ([`comp_build.gd`](scenes/comp_build.gd)) grew by 35 lines to accommodate the new language. The main scene added UI elements. The assembler gained 12 lines of integration glue. The compiler pipeline was beginning to take shape alongside the existing assembler pipeline.

### The Tokenizer Evolves

The word-boundary tokenizer was generic, but MiniDerp needed *specificity*. Comments (`//`), string literals, character literals, number formats, keyword classification — these required language-aware handling.

Commit [`c848416`](https://github.com/) delivered [`md_tokenizer.gd`](scenes/md_tokenizer.gd:1) — a 190-line dedicated tokenizer for MiniDerp. The [`comp_compile_md.gd`](scenes/comp_compile_md.gd) file was substantially rewritten (+96/-97) to orchestrate the new tokenization pipeline.

The tokenization process was a multi-stage pipeline orchestrated by the `tokenize()` entry point at [`md_tokenizer.gd`](scenes/md_tokenizer.gd:55-75), which chained four core functions: `basic_tokenize()` → `recombine_tokens()` → `reclassify_tokens()` → `filter_tokens()`. Each stage refined the token stream before passing it to the next:

1. **Preprocessing** — handling `#include` directives
2. **Basic tokenization** (`basic_tokenize()`) — using the word-boundary tokenizer to split text into raw tokens
3. **Recombination** (`recombine_tokens()`) — merging adjacent tokens based on specific patterns: `["+", "+"]` became `"++"`, `["!", "="]` became `"!="`, `["=", "="]` became `"=="`, and `["/WORD", "/NUMBER"]` kept identifiers with trailing numbers intact. Single-character punctuation like `,` and `;` were left alone.
4. **Reclassification** (`reclassify_tokens()`) — running `WORD` tokens against the language definition's keyword, type, operator, and punctuation dictionaries ([`lang_md.gd`](scenes/lang_md.gd)). Tokens matching known keywords became `KEYWORD`, types became `TYPE`, operators became `OP`, and punctuation became `PUNCT`. Numbers were classified as `NUMBER`, strings as `STRING`, and `#` tokens as `PREPROC`.
5. **Character literal resolution** — converting `'a'` syntax into numeric values
6. **Colorization** — assigning display colors for the token viewer
7. **Filtering** (`filter_tokens()`) — stripping whitespace and comments from the final token stream

A token visualization window ([`win_token_view.gd`](scenes/win_token_view.gd)) was added in commit [`2469e05`](https://github.com/), giving the developer a window into how both ZDerp and MiniDerp source code was tokenized. Debugging the tokenizer meant seeing what the tokenizer saw.

### The Grammar

At commit [`3d310d4`](scenes/lang_md.gd) — *"parsing is decent now"* — the language definition in [`lang_md.gd`](scenes/lang_md.gd:18-138) housed about 30+ shift-reduce rules. These rules defined the complete syntax of MiniDerp in a form consumable by an LR(1) parser. Key productions included:

- **`stmt_list` / `stmt`** — statement lists and individual statements, forming the backbone of every program
- **`block`** — `{ stmt_list }` or `{ }` for empty blocks, the fundamental grouping construct
- **`var_decl_stmt`** — `var IDENT ;`, simple variable declarations
- **`assignment_stmt`** — `expr = expr ;`, the assignment production
- **`func_decl_stmt` / `func_def_stmt`** — function declarations and full definitions with `func name() { block }`
- **`while_stmt`** — `while_start` paired with `block`, the loop construct
- **`if_stmt` / `if_block` / `if_else_block`** — the full if/elif/else chain
- **`flow_stmt`** — `break ;`, `continue ;`, `return ;`, `return expr ;` for control flow
- **`preproc_stmt`** — `#include STRING` for preprocessor directives
- **Expressions**: `expr_immediate` (NUMBER, STRING literals), `expr_ident` (IDENT), `expr_postfix` (expr followed by operator), `expr_infix` (binary expressions), `expr_call` (function calls), `expr_parenthesis`
- **Types**: `int`, `char`, `float`, sized integers (`u8`-`u64`, `s8`-`s64`), `Ref[X]` for references, `String` (alias for `Ref[char]`), and array types

Each rule was an array: `[input..., lookahead, result]`. For example, rule `["expr", "/=", "expr", "/;", "assignment_stmt"]` meant: if the stack contains `expr = expr` and the next token is `;`, reduce to `assignment_stmt`. The `SHIFT` pseudo-result forced the parser to consume a token without reducing — a critical mechanism for handling operator precedence. At [`lang_md.gd`](scenes/lang_md.gd) the `SHIFT` rule served as a lookahead mechanism: a rule like `["expr", "OP", "expr", "/[", "SHIFT"]` prevented premature reduction when array indexing followed an expression, ensuring the parser consumed the `[` token before deciding how to reduce.

The grammar was not abstract — it was *executable*. The parser would iterate through these rules at every step, finding the first match and applying it. This design, while simple, was surprisingly effective.

### The LR(1) Parser

Commit [`f69a819`](https://github.com/) introduced the parser, paired with a parse tree visualization window ([`win_parse.gd`](scenes/win_parse.gd), [`win_parse.tscn`](scenes/win_parse.tscn)).

The parser, defined in [`parser_md.gd`](scenes/parser_md.gd), was a classic LR(1) shift-reduce design:

> *"LR(1) shift-reduce parser, always applies the first valid rule"* — [`parser_md.gd`](scenes/parser_md.gd:39)

The algorithm, visible at [`parser_md.gd`](scenes/parser_md.gd:40-86), was elegant in its simplicity:

1. Push tokens onto a stack
2. For each token (the "lookahead"), check all grammar rules to see if the top of the stack matches the rule's input pattern
3. If a match is found and the rule's expected lookahead matches the current token (or is `*` for wildcard), apply the rule: pop the matched tokens and push the result
4. Continue reducing until no more rules apply (stabilized)
5. Shift the next token onto the stack and repeat
6. At the end, the single remaining item on the stack is the AST

The comment at [`parser_md.gd`](scenes/parser_md.gd:96-100) revealed the rule-matching logic:
```gdscript
func rule_matches(stack, tok_lookahead, rule):
    var rule_lookahead = rule[-2];
    var rule_input = rule.slice(0,-2);
    if len(stack) < len(rule_input): return false;
```

Debug messages flooded the console. Commit [`a6138d4`](https://github.com/) — "parse debug msgs" — added visibility into the parsing process. Commit [`3d310d4`](https://github.com/) declared *"parsing is decent now"*, with 42 new grammar rules and a 12K-line log file attesting to the debugging effort.

The journey from raw tokens to a parse tree was not trivial. The `list_types` dictionary at [`parser_md.gd`](scenes/parser_md.gd:12-15) — mapping `stmt_list` to `stmt` and `expr_list` to `expr` — handled the linearization of AST nodes into flat lists, a pragmatic solution for the analyzer that would consume these trees.

### The Analyzer: From Syntax to Semantics

With parsing functional, the developer turned to the hardest part of the compiler frontend: understanding what the code *means*.

Commit [`15d7980`](https://github.com/) — "wip analyzer" — introduced the first semantic analysis pass. The compiler orchestration file was rewritten (+90/-89), and an IR visualization window ([`win_ir.gd`](scenes/win_ir.gd), [`win_ir.tscn`](scenes/win_ir.tscn)) was created.

Commit [`a18cead`](https://github.com/) declared *"analysis works"* — `comp_compile_md.gd` expanded by 289 lines. But the real restructuring came in commit [`8e0faed`](https://github.com/), where the analyzer was extracted into its own file: [`analyzer_md.gd`](scenes/analyzer_md.gd).

The analyzer ([`analyzer_md.gd`](scenes/analyzer_md.gd)) performed several critical functions:

**Operator Mapping** — The `op_map` dictionary ([`analyzer_md.gd`](scenes/analyzer_md.gd:18-43)) spanned 22 operators, translating every MiniDerp operator into an IR operation:
```
+ → ADD,    - → SUB,    * → MUL,     / → DIV,     % → MOD
[ → INDEX,  > → GREATER, < → LESS,   == → EQUAL,   != → NOT_EQUAL
&& → AND,   || → OR,    ! → NOT
& → B_AND,  | → B_OR,   ^ → B_XOR,   >> → B_SHIFT_RIGHT,  << → B_SHIFT_LEFT,  ~ → B_NOT
++ → INC,   -- → DEC
```
In addition to the main map, `prefix_ops` identified unary prefix operators (`NOT`) and `postfix_ops` identified postfix operators (`INC`, `DEC`), enabling the analyzer to distinguish between binary `expr + expr` and unary `!expr`.

**Scope Tracking** — The analyzer maintained a symbol table (`sym_table` at line 56) and a control flow stack (`control_flow_stack` at line 55) for handling `break` and `continue` within loops. Each scope in the IR corresponded to a lexical scope in the source code. The `analyze()` entry point called `analyze_one()` on the root AST node, then ran `fixup_cb_lbls()` to match function name labels with their corresponding code block labels. Before analysis began, `prepare_sym_table()` initialized the symbol table with built-in types and functions.

**IR Serialization** — After the analysis pass completed, the IR was passed to the next stage by writing to disk: `IR.to_file("IR.txt")`. The debugging window ([`win_ir.gd`](scenes/win_ir.gd)) then read this file and rendered the IR structure — with its `code_blocks{}` and `scopes{}` dictionaries — as a live, hierarchical display.

**Code Block Fixup** — The `fixup_cb_lbls()` function ([`analyzer_md.gd`](scenes/analyzer_md.gd:99)) ensured that function names matched their code block labels — a critical linkage between the IR and the generated assembly.

**Flow Control** — If/else chains and while loops required generating appropriate labels and conditional/non-conditional jump instructions. Commit [`5d2bf78`](https://github.com/) — "improved flow control and if-else" — added 70 lines of analyzer logic and 47 lines of IR support for proper control flow compilation.

The analyzer walked the AST recursively (`analyze_one()` at line 76), building IR commands as it went. When it encountered a variable declaration, it added a symbol to the table. When it found a function definition, it created a new scope and code block. When it processed an expression, it emitted IR commands into the current code block.

The comment "[`analyzer_md.gd`](scenes/analyzer_md.gd:16)" reveals the `ast_bypass_list`: `["start", "stmt_list", "stmt"]` — these AST nodes were structural containers, not semantic constructs, so the analyzer skipped them during traversal, diving directly into their children.

### The IR Layer

The intermediate representation ([`ir_md.gd`](scenes/ir_md.gd)) was the bridge between the high-level analyzer and the low-level code generator. It defined:

- **IR Values** — typed handles for variables, temporaries, immediates, functions, and labels. Each value carried metadata: its type, user name, IR name, value, and storage location.
- **Code Blocks** — containers for sequences of IR commands, linked to scopes and functions.
- **Scopes** — lexical scopes mapping variable names to IR values.
- **IR Commands** — operations like `ADD`, `SUB`, `CALL`, `JUMP`, `LABEL` that operated on IR values.

The `clear_IR()` function ([`ir_md.gd`](scenes/ir_md.gd:17-27)) initialized the IR with a global scope and a global code block:
```gdscript
IR = {
    "code_blocks":{},
    "scopes":{},
};
```

The factory functions — `new_val()`, `new_val_temp()`, `new_val_var()`, `new_val_immediate()`, `new_val_func()`, `new_val_lbl()` — created typed IR values that the analyzer would populate and the code generator would consume.

Commit [`0c7647d`](https://github.com/) — "done playing with IR, lol" — was a landmark. The humorous commit message belied a massive expansion: `ir_md.gd` grew by 140 lines, the analyzer by 154 lines, and the language definition by 113 lines. The IR was no longer a toy; it was a working intermediate representation capable of representing real programs.

### Micro-YAML: Serializing the IR

Between the analyzer and code generator phases, the IR needed to be serialized — saved to disk and reloaded. Rather than using a standard format like JSON or YAML, the developer built a custom serialization format called Micro-YAML ([`uYaml.gd`](scenes/uYaml.gd)).

The module's comment ([`uYaml.gd`](scenes/uYaml.gd:21) captures the spirit: *"What's the point? No point, I was bored"*. And yet, the format was functional, handling nested dictionaries, arrays, and strings with a readable indentation-based syntax. The IR was serialized to `IR.txt` using this format, providing a human-readable view of the compiler's internal state — and a debugging window ([`win_ir.gd`](scenes/win_ir.gd)) rendered it on screen.

### The Pipeline Emerges

By commit [`5d2bf78`](https://github.com/), the MiniDerp compiler frontend was complete. The pipeline:

```
Source Code → Tokenizer → Parser → Analyzer → IR → (serialized to uYaml)
```

Each stage had its own debug visualization: the token viewer, the parse stack viewer, and the IR viewer. The developer could open any MiniDerp file, click "compile," and watch the transformation from raw text to structured intermediate representation.

But the IR was just a plan. It described what the program should do, but it didn't generate any code that the ZVM could execute. That was the next challenge — and it would prove to be the hardest technical challenge of the entire project.

---

## Chapter 4: Bridging Worlds — The IR and Code Generator

> *Commits `ecbd8f7` → `784a049`*

---

### The Backend Begins

The frontend was beautiful. The tokenizer parsed, the parser reduced, the analyzer mapped, and the IR glowed on screen in its custom YAML-like format. But none of it *ran*. The IR was a ghost — a description of computation without a body.

What the compiler needed was a backend: a code generator that could translate IR operations into ZDerp assembly instructions that the ZVM could execute. This was the bridge between the high-level world of MiniDerp and the low-level reality of registers, memory addresses, and stack frames.

Commit [`ecbd8f7`](https://github.com/) — "wip micro-YAML" — created the first two pieces of this bridge: [`uYaml.gd`](scenes/uYaml.gd) (155 lines) for serializing the IR between pipeline stages, and [`codegen_md.gd`](scenes/codegen_md.gd) — initially just 57 lines.

Fifty-seven lines. Compared to what it would become, this was barely a sketch. The code generator had a `generate()` function and little else. But it was a start.

### The Code Generator Explodes

Commit [`fa3525c`](https://github.com/) — "wip code generator" — was the explosion. The code generator went from 57 to 412+ lines in a single commit. The [`codegen_md.gd`](scenes/codegen_md.gd) file was now one of the largest in the project.

The code generator's architecture, visible in the constants and state at [`codegen_md.gd`](scenes/codegen_md.gd:8-75), was a masterclass in pragmatic compiler design:

**Register Allocation** — The ZVM had four general-purpose registers: `EAX`, `EBX`, `ECX`, `EDX` (defined as `const regs` at line 15). The code generator tracked which registers were in use (`regs_in_use` at line 68) and allocated them as needed for expression evaluation.

**Operation Mapping** — The `op_map` dictionary ([`codegen_md.gd`](scenes/codegen_md.gd:19-54)) translated IR operations into sequences of ZDerp assembly instructions. For example, `EQUAL` became:
```
cmp %a, %b;
mov %a, CTRL;
band %a, CMP_Z;
bnot %a;
bnot %a;
```
This sequence compared two values, extracted the zero flag from the control register, and normalized it to a boolean — all without branching.

**Stack Frame Management** — The `cur_stack_size` variable (line 66) tracked the number of bytes used for local variables in the current function's stack frame. The code generator emitted `ENTER` and `LEAVE` instructions to set up and tear down these frames.

**Code Block Linking** — Functions were represented as `CodeBlock` objects in the IR. The code generator maintained a stack of these blocks (`cb_stack` at line 70), linking call instructions to their target blocks and resolving forward references.

The module referenced both the ISA definition (`lang_zvm.gd` via `ISA` at line 6) and the serialization format (`uYaml` at line 5), bridging the two worlds of the compiler.

### The Assembler Refactored

The existing assembler ([`comp_asm_zd.gd`](scenes/comp_asm_zd.gd)) had grown organically from the early days of the project. It worked, but it was becoming a bottleneck. Error reporting was minimal — print statements scattered throughout the code. Structured error handling was nonexistent.

Commit [`91b55b7`](https://github.com/) — "refactored the assembler and improved error reporting" — was a 432-line rewrite. The assembler gained:

- A proper error reporter integration, forwarding errors with source locations
- Structured error messages instead of raw print statements
- Cleaner separation of assembly phases: parsing, encoding, and patching

A new file appeared — [`globals.gd`](globals.gd) — a shared global state module that would grow to host utility functions used across the entire project: `duplicate_val`, `unescape_string`, `trim_spaces`, comparison helpers (`has()`), and type compatibility checks.

### The Struggle: Local Variables and Stack Frames

The most difficult part of the code generator was local variable handling. The IR described variables with storage positions — offsets in the stack frame — but translating these into correct ZDerp assembly was a nightmare of off-by-one errors and frame layout confusion.

Commit [`f2ae93b`](https://github.com/) — "better local var handling at codegen" — added 96 lines of improved variable management. But the very next commit told the real story.

Commit [`b7bb908`](https://github.com/) — "wip codegen, handle.storage.pos still bork" — the developer admitted defeat in the commit message itself. The `storage.pos` field, which described where a variable lived in the stack frame, was "bork" (broken). The code generator grew by 111 lines, but the fix remained elusive.

This was the grind of compiler development: not the glamorous work of designing elegant IRs or clever algorithms, but the tedious battle against stack frame offsets. Every local variable needed a position. Every function call needed frame setup and teardown. Every nested scope needed correct offset calculations. One wrong byte and the entire program crashed.

### Codegen's Fucked

The low point arrived with commit [`c67b2d8`](https://github.com/). The commit message was three words: *"codegen's fucked"*.

362 lines were added to the code generator. Something had gone terribly wrong. The type system integration, the register allocation, the stack frame management — they had collapsed into an unusable state. An export preset was added ([`export_presets.cfg`](export_presets.cfg)), perhaps in a moment of desperate optimism that this would somehow compile to a standalone build.

The next commit — [`18f2880`](https://github.com/) — was titled simply "fixed a crash". Recovery. The regression was identified and patched. The code generator limped back to life.

### The Debug Panel Gets Cool Visuals

While the code generator struggled, the debug panel flourished. Commit [`9df489c`](https://github.com/) — "cool debugger visuals wip" — added 152 lines to [`debug_panel.gd`](debug_panel.gd). The scene file grew by 94 lines.

The debugger was becoming the developer's primary window into the running system:

- **Register displays** — live updates of all 14 ZVM registers as the CPU executed
- **Step/run controls** — single-step, run, pause, and reset buttons with icon buttons
- **IP tracking** — the Instruction Pointer was highlighted in the memory view with color-coded backgrounds, showing the current execution position
- **Color-coded memory** — shadow memory types rendered in distinct colors: yellow for data, green for code, red for unresolved references, purple for frame temporaries

Commit [`c771566`](https://github.com/) — "super duper debugger stuff" — almost doubled the debug panel with 298 lines of additions. Step/unstep operations worked in high-level debug mode. The debugger was no longer an accessory; it was the central tool for understanding program execution.

Commit [`34d2239`](https://github.com/) added improved go/stop controls and frequency control for execution speed. An [`indicator.gd`](scenes/indicator.gd) visual indicator was introduced. The developer could now control execution speed, step through code, and watch registers change in real time.

### The Pipeline Completes

Through the struggle, the code generator grew. Commit [`3b469dd`](https://github.com/) added 216 lines. Commit [`fde749a`](https://github.com/) added 111 lines. Commit [`7d293c1`](https://github.com/) — "refactored for better type safety" — was a 377-line rewrite that introduced five new class files: [`class_AssyBlock.gd`](class_AssyBlock.gd), [`class_CodeBlock.gd`](class_CodeBlock.gd), [`class_IR_cmd.gd`](class_IR_cmd.gd), [`class_IR_value.gd`](class_IR_value.gd), and [`class_LocationMap.gd`](class_LocationMap.gd). The old `comp_compile_zd.gd` was deleted — a relic of an earlier era.

The code generator's architecture at this point, visible in the constants, was a marvel of practical engineering. The `op_map` grew to handle every MiniDerp operation. The register allocator managed four registers (`EAX`, `EBX`, `ECX`, `EDX`) with tracking and spilling. The `cmd_size` constant (line 16, value 8) reflected the fixed 8-byte instruction encoding of the ZVM. Shadow memory writing (`WRITE_SHADOW = true` at line 11) marked every emitted byte with metadata for the debugger.

Commit [`21a780b`](https://github.com/) achieved "miniderp printf compiles with new type stuff" — formatted output was working. A [`class_LoopCounter`](class_LoopCounter.gd) was introduced for performance optimization, preventing infinite loops in the analysis phase. The type system and the code generator were finally working together.

Commit [`f7b0226`](https://github.com/) asked the tentative question: *"miniderp compiles?"* The question mark said everything. The pipeline produced output, but did it produce *correct* output? Could the generated assembly actually run?

### Hello World

And then, the milestone that made every frustration worthwhile.

Commit [`784a049`](https://github.com/) — *"miniderp hello world achieved! also perf_limiter"*.

The emotional arc from "codegen's fucked" to this moment was steep. The developer had stared at broken stack frame offsets, tangled register allocations, and type system integration failures for commit after commit. The IR described programs perfectly — but the assembly it generated was silent, crashing, or nonsensical. Each failed execution was another reminder that the bridge between high-level semantics and low-level bytes was still incomplete. The question mark in commit [`f7b0226`](scenes/codegen_md.gd) — *"miniderp compiles?"* — captured the uncertainty perfectly: the pipeline produced output, but did it produce *correct* output?

Now, with commit [`784a049`](scenes/codegen_md.gd), the answer was a definitive yes. The first MiniDerp program had been compiled through the entire pipeline — tokenize → parse → analyze → codegen → assemble → upload → execute — and it ran. On the GPU screen, in the 56×36 character display, "Hello World" appeared.

The changes were spread across 11 files, with massive log changes (80K+ insertions, 64K+ deletions) attesting to the testing effort. But the core technical changes told the story of what was needed to cross the finish line:

- [`codegen_md.gd`](scenes/codegen_md.gd) — +62 lines, final adjustments including fixed variable allocation, proper function enter/leave sequences, and correct assembly generation
- [`GPU_cs.gd`](scenes/GPU_cs.gd) — The GPU gained a buffer-based memory model: a `mem:Array[int]` field was added alongside the existing direct-write path, and a `READ_RETURNS_BUFFER = true` constant signaled that reads should come from the buffer rather than the tile display. This change decoupled the GPU's rendering pipeline from its memory interface, allowing the compiled MiniDerp programs to write to memory without corrupting the display.
- [`debug_panel.gd`](debug_panel.gd) — +60 lines, debug UI improvements with a `perf_limiter` system added for throttling UI updates during execution
- [`res/data/hello.md`](res/data/hello.md) — +20 lines, the Hello World MiniDerp source file, a test program written specifically to validate the full pipeline
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +4 lines, minor analyzer tweaks

Two new files appeared — [`PerfLimiter.gd`](PerfLimiter.gd) and [`PerfLimitDirectory.gd`](PerfLimitDirectory.gd) — performance control utilities that would prevent the CPU from running too fast during debugging.

The developer didn't just stop at "Hello World" — they *celebrated*. The commit also introduced two GPU screensaver functions: [`_screensaver_matrix()`](scenes/GPU_cs.gd) and [`_screensaver_nyan()`](scenes/GPU_cs.gd), fired up via a `_rand_scr_pos()` randomizer. These were not features for the compiler — they were the developer's victory lap. Matrix code rain and a Nyan Cat rainbow scrolled across the GPU display, visual proof that the machine — the entire stack, from tokenizer to pixel — was alive and working. The screensavers were the digital equivalent of leaning back, hands behind head, and watching the machine dance.

The entire project had been building toward this moment. The ZVM, the assembler, the frontend compiler pipeline, the code generator, the debugger — all of it converged in a single "Hello World" message on a virtual screen.

MiniDerp was real. And it was *celebrating*.

---

*End of Chapters 3–4. The narrative continues with high-level debugging, the type system, and the evolution of the MiniDerp ecosystem.*
