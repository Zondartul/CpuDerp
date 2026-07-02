# CpuDerp: A Development Narrative

## Chapter 5: Source-Level Enlightenment — High-Level Debugging

> *Commits `19fffe4` → `7dde647`*

---

### The Next Frontier

MiniDerp Hello World had printed across the GPU screen. The pipeline worked — tokenizer, parser, analyzer, IR, code generator, assembler, upload, execution. But the developer stared at that glowing "[Hello World!]" message and saw the problem immediately: when the program ran, there was no way to know *what it was doing* at the MiniDerp source level.

The assembler debugger showed registers, memory addresses, and instruction pointers. It was a fine tool for assembly programming. But MiniDerp was a high-level language. Variables had names, not stack offsets. Functions had signatures, not entry-point addresses. If the compiler was going to be useful for real development, it needed source-level debugging.

This was the longest phase of the project — 29 commits of grueling infrastructure work. The developer would need to implement backwards execution, build a location-tracking system, create typed data classes, restructure error reporting, and wire everything through the debug panel. The goal was simple to state and monstrously hard to achieve: when you step through MiniDerp code, the source line you're on should be highlighted on screen.

### Running in Reverse

Commit [`19fffe4`](https://github.com/) — "implemented backwards stepping; also better perf_limiter" — tackled the hardest prerequisite first. To debug at the source level, you need to be able to pause at any point, step forward, and step backward. Backward stepping on a custom VM meant the CPU needed to execute in reverse — decrementing the instruction pointer, undoing register changes, rolling back memory writes.

Two new files appeared to manage execution control:

[`PerfLimiter.gd`](PerfLimiter.gd) — a 76-line class that implemented a token-bucket rate limiter for controlling CPU execution speed. Each component of the debug display (registers, stack, locals, IP highlight) could have its own performance budget, preventing the debugger from melting under its own update frequency. The [`PerfLimiter`](PerfLimiter.gd:10) constructor took a period and max credit:
```gdscript
func _init(period:float, new_max_credit=null):
    cost = period;
    credit = 0.0;
    enabled = true;
```

[`PerfLimitDirectory.gd`](PerfLimitDirectory.gd) — a 30-line directory that organized multiple limiters into groups, allowing the debug panel to batch-enable or disable performance categories by tab or mode.

The debug panel ([`debug_panel.gd`](debug_panel.gd)) grew by 198 lines. A new "start" button appeared — represented by [`control_start_blue.png`](res/icons/control_start_blue.png) — that ran the CPU *backwards*. The developer could now pause execution and reverse time, watching registers unwind to their previous states.

### The Great Professionalization

The next commit was a watershed moment for the codebase. Commit [`256fcb1`](https://github.com/) — "more type hints, error callouts from analyzer" — was a 33-file, 1,295-line refactoring that transformed the project from ad-hoc dictionaries into a properly typed class hierarchy.

Seven new class files were created as standalone Godot autoloads:

- [`class_ErrorReporter.gd`](class_ErrorReporter.gd) — 45 lines. A structured error reporting system with context support. The [`ErrorReporter`](class_ErrorReporter.gd:2) attached to the editor via an `Editor` export and accepted a `proxy` object (expected to provide `error_code` and `user_error`). Its [`error()`](class_ErrorReporter.gd:20) method pushed to `push_error`, suppressed cascading errors if `error_code` was already set, then dispatched to one of three context-aware pointing methods. The [`point_out_error()`](class_ErrorReporter.gd:35) method printed a full GNU-style error message — `"error at line N:\ntext\n^\nmsg"` — with a caret pointing at the error column. [`point_out_error_tok()`](class_ErrorReporter.gd:43) and [`point_out_error_iter()`](class_ErrorReporter.gd:53) handled `Token` and `Iter` context types respectively. The class emitted a [`sig_highlight_line`](class_ErrorReporter.gd:7) signal that the editor could use to highlight erroneous source lines.

- [`class_Token.gd`](class_Token.gd) — 19 lines. A [`RefCounted`](class_Token.gd:1) with `class_name Token`. Properties: [`tok_class:String`](class_Token.gd:4), [`text:String`](class_Token.gd:5), [`loc:LocationRange`](class_Token.gd:6). The constructor accepted a dictionary, iterated its keys, and asserted each key existed in `self` — with the comment `# weirdly motivational`. A [`duplicate()`](class_Token.gd:14) method used `G.duplicate_shallow` to clone tokens efficiently.

- [`class_AST.gd`](class_AST.gd) — 15 lines. This class [`extends Token`](class_AST.gd:1), meaning every AST node IS a token with source location baked in. It added a [`children:Array[AST]`](class_AST.gd:4) property. The constructor accepted either a `Dictionary` (using `G.dictionary_init`) or a `Token` — if given a `Token`, it shallow-copied fields from it. This design cemented the AST hierarchy: every node carries its own source location plus an ordered list of typed child nodes.

- [`class_Chunk.gd`](class_Chunk.gd) — 25 lines. A [`RefCounted`](class_Chunk.gd:1) with `class_name Chunk`. Properties: [`code:Array[int]`](class_Chunk.gd:4) (compiled bytecode), [`shadow:Array[int]`](class_Chunk.gd:5) (for relocation tracking), [`labels:Dictionary`](class_Chunk.gd:6), [`refs:Dictionary`](class_Chunk.gd:7) (unresolved references), [`label_toks:Dictionary`](class_Chunk.gd:8), [`error:bool`](class_Chunk.gd:9). Methods: [`to_bool()`](class_Chunk.gd:17) returned `not error`, [`duplicate()`](class_Chunk.gd:19) used `G.duplicate_deep` for full copying, and [`static null_val()`](class_Chunk.gd:24) returned a Chunk with `error:true` — a sentinel for failed assembly.

- [`class_Cmd_arg.gd`](class_Cmd_arg.gd) — 11 lines. Previously an inner class inside [`comp_asm_zd.gd`](scenes/comp_asm_zd.gd), now extracted as its own file. Properties: [`is_present:bool`](class_Cmd_arg.gd:4), [`reg_name:String`](class_Cmd_arg.gd:5), [`reg_idx:int`](class_Cmd_arg.gd:6), [`offset:int`](class_Cmd_arg.gd:7), [`is_deref:bool`](class_Cmd_arg.gd:8), [`is_imm:bool`](class_Cmd_arg.gd:9), [`is_32bit:bool`](class_Cmd_arg.gd:10), [`is_unresolved:bool`](class_Cmd_arg.gd:11) — covering every addressing mode the assembler supported.

- [`class_Cmd_flags.gd`](class_Cmd_flags.gd) — 26 lines. Properties: [`deref_reg1`](class_Cmd_flags.gd:4), [`deref_reg2`](class_Cmd_flags.gd:5), [`reg1_im`](class_Cmd_flags.gd:6), [`reg2_im`](class_Cmd_flags.gd:7), [`is_32bit`](class_Cmd_flags.gd:8), [`spec_flags`](class_Cmd_flags.gd:9). The [`to_byte()`](class_Cmd_flags.gd:11) method packed flags into a single byte: bits 0-1 encoded deref, bit 2 was `reg1_im`, bit 3 was `is_32bit`, bits 4-6 carried `spec_flags`. [`set_arg1()`](class_Cmd_flags.gd:18) and [`set_arg2()`](class_Cmd_flags.gd:22) copied properties from [`Cmd_arg`](class_Cmd_arg.gd) objects; [`set_arg2()`](class_Cmd_flags.gd:22) additionally took an [`ErrorReporter`](class_ErrorReporter.gd) parameter and raised `ERR_04` if both operands were immediates.

- [`class_Iter.gd`](class_Iter.gd) — 12 lines. A [`RefCounted`](class_Iter.gd:1) with `class_name Iter`. Properties: [`tokens:Array`](class_Iter.gd:4), [`pos:int`](class_Iter.gd:5). The constructor took both parameters. The [`duplicate()`](class_Iter.gd:11) method returned a new [`Iter`](class_Iter.gd) referencing the same tokens array — a shallow reference by design, meaning a duplicated iterator shared the underlying token list but tracked its own position independently.

### Error Codes: The Autoloaded Singleton

[`error_list.gd`](error_list.gd) — previously a 29-line file, now expanded — was created as an autoloaded singleton. It declared error code constants that could be referenced from anywhere in the project. The singleton was registered as `E` (a single-letter global name, a Godot convention for autoloads):

- `ERR_01` through `ERR_14` — assembler errors: unlinked references, invalid ops, byte overflow, bad addressing modes.
- `ERR_21` through `ERR_59` — analyzer errors: undefined identifiers, type mismatches, arity violations, invalid operators, array index type checks.

The error list grew alongside the type system. New additions in commit [`256fcb1`](https://github.com/) included three analyzer errors that revealed the project's growing sophistication:

- [`ERR_29`](error_list.gd:28) — `Identifier not found: [%s]`. This was fundamental: the analyzer now tracked every declared identifier and could report when code referenced something that didn't exist. Previously, a misspelled variable name would silently produce garbage; now it stopped the compiler with a clear message.

- [`ERR_30`](error_list.gd:29) — `'Continue' statement outside of a loop`. Control flow analysis had joined the compiler. The analyzer could now verify that `continue` statements only appeared inside `while` or `for` bodies, catching a common structured-programming mistake before the bytecode ran.

- [`ERR_31`](error_list.gd:30) — `Operator '%s' is not allowed here.` The analyzer was learning operator precedence and context rules — certain operators made no sense in certain positions, and the type checker could now reject them.

The constants at [`error_list.gd`](error_list.gd:4-17) mapped errors to human-readable templates:
```gdscript
const ERR_02 = "Error 02: Unlinked references remain (count %d)";
const ERR_29 = "Error 29: Identifier not found: [%s]";
const ERR_36 = "Error 36: function [%s] expected %d arguments, got %d";
```

The analyzer (+212 lines) and assembler (+238 lines) both grew significantly as they were wired into the error reporting system. Every error could now carry a source location, making debugging much more productive.

### The Parser Stands Alone

Also in commit [`256fcb1`](https://github.com/), the parser was extracted from the monolithic [`comp_compile_md.gd`](scenes/comp_compile_md.gd) into its own file: [`parser_md.gd`](scenes/parser_md.gd) — 106 lines.

The parser was an LR(1) shift-reduce engine, applying grammar rules from [`lang_md.gd`](scenes/lang_md.gd) against a token stack. The extraction was a sign of architectural maturity: each compiler phase now had its own file. The pipeline was becoming a proper layered architecture.

### The Central Obsession: Location Tracking

The hardest engineering challenge of this phase — consuming over 10 commits — was location tracking. The problem: every IR command and every assembly instruction needed to know which MiniDerp source line it came from. When the CPU stopped at address `0x1A3F`, the debugger needed to map that back to `hello.md:line 14`.

Two classes formed the foundation:

[`class_Location.gd`](class_Location.gd) — a [`RefCounted`](class_Location.gd:1) with fields for `filename`, `line` (the actual source line text), `line_idx` (zero-based line number), `col` (column offset), and a unique `uid` for ordering. The [`less_than()`](class_Location.gd:31) method enabled comparison sorting. The [`_to_string()`](class_Location.gd:34) method produced readable output: `@filename:line:col`. The [`from_string()`](class_Location.gd:46) static method deserialized locations from a regex-based format, enabling persistence across pipeline stages.

[`class_LocationRange.gd`](class_LocationRange.gd) — a pairing of two [`Location`](class_LocationRange.gd:4-5) objects: `begin` and `end`. A location range represented a span of source code — a token, an expression, a statement. The [`is_valid()`](class_LocationRange.gd:18) method checked that both begin and end were valid. The [`_to_string()`](class_LocationRange.gd:34) method produced a compact representation: `@file:10:5~10:12`.

Commit [`1c965fc`](https://github.com/) — "wip locations" — introduced these classes and wired them into the tokenizer, parser, analyzer, IR, and code generator. [`class_Token.gd`](class_Token.gd) gained location fields. The tokenizer ([`md_tokenizer.gd`](scenes/md_tokenizer.gd)) began tracking line and column numbers. The analyzer ([`analyzer_md.gd`](scenes/analyzer_md.gd)) propagated locations from tokens to AST nodes to IR commands.

Commit [`48caca0`](https://github.com/) — "wip location debug" — enhanced the location infrastructure further. The IR ([`ir_md.gd`](scenes/ir_md.gd)) grew by 72 lines of location-aware logic. The code generator ([`codegen_md.gd`](scenes/codegen_md.gd)) gained 32 lines of location mapping. [`globals.gd`](globals.gd) grew by 38 lines of helper functions for location manipulation.

Commit [`bb0ea53`](https://github.com/) — "wip better locations" — added 116 lines to the debug panel ([`debug_panel.gd`](debug_panel.gd)) for improved location display.

Commit [`8baa478`](https://github.com/) — "wip locations - expanded location map (ELM)" — introduced the Expanded Location Map, a comprehensive data structure that mapped assembly addresses to their corresponding [`LocationRange`](class_Location.gd) objects. The debug panel grew by 166 lines. The ELM was the key to source-level highlighting: given an instruction pointer address, the debugger could now look up which source line produced it.

### Type Safety Refactoring

Commit [`7d293c1`](https://github.com/) — "refactored for better type safety" — was a landmark restructuring. Five new class files were created:

- [`class_AssyBlock.gd`](class_AssyBlock.gd) — 10 lines. Assembly code blocks with an embedded [`LocationMap`](class_AssyBlock.gd:5). Each block carried [`code:String`](class_AssyBlock.gd:4) (the generated assembly text), a [`loc_map:LocationMap`](class_AssyBlock.gd:5), and [`write_pos:int`](class_AssyBlock.gd:6) tracking where the next instruction would be placed. The assy block was the typed replacement for what was previously a raw string buffer.

- [`class_CodeBlock.gd`](class_CodeBlock.gd) — 14 lines. This was the most architecturally interesting addition: it [`extends IR_Value`](class_CodeBlock.gd:1), meaning code blocks ARE values. With properties [`code:Array[IR_Cmd]`](class_CodeBlock.gd:4), [`lbl_from`](class_CodeBlock.gd:7), [`lbl_to`](class_CodeBlock.gd:8), and [`val_type`](class_CodeBlock.gd:11) set to `"code"` in the constructor, this class encoded the insight that executable code could be passed around like any other value — the foundation for function pointers and indirect calls.

- [`class_IR_cmd.gd`](class_IR_cmd.gd) — 28 lines. IR commands became proper objects with [`words:Array[String]`](class_IR_cmd.gd:4) (the instruction tokens) and [`loc:LocationRange`](class_IR_cmd.gd:5). The class had commented-out `_get`/`_set`/`pop_back`/`push_back` methods that previously acted as array proxies over `words` — these were disabled during the typed refactor, since direct array access was now preferred over the proxy pattern.

- [`class_IR_value.gd`](class_IR_value.gd) — 5 lines. IR values — variables, temporaries, immediates — got their own class. This was the base class that [`CodeBlock`](class_CodeBlock.gd) extended, establishing the type hierarchy for all values in the IR.

- [`class_LocationMap.gd`](class_LocationMap.gd) — 10 lines. A bidirectional map between instruction pointers and [`LocationRange`](class_LocationRange.gd) objects. The [`LocationMap`](class_LocationMap.gd:5-6) had two dictionaries: `begin` and `end` — both keyed by instruction pointer, mapping to arrays of [`LocationRange`](class_LocationRange.gd) objects that began or ended at that address.

The code generator ([`codegen_md.gd`](scenes/codegen_md.gd)) received a 377-line rewrite — its largest single change — to use these typed classes throughout. The old [`comp_compile_zd.gd`](scenes/comp_compile_zd.gd) was deleted entirely. The codebase had crossed a threshold: dictionaries were no longer acceptable for core data structures.

Alongside the class hierarchy, the codegen introduced an `op_map` — a dictionary mapping IR operations to assembly instruction templates. These were defined as plain strings:
```gdscript
"ADD":"add %a, %b;\n",
"SUB":"sub %a, %b;\n",
```
More complex operations expanded to multiple instructions. The `GREATER` op, for example, translated to:
```gdscript
"GREATER":"cmp %a, %b; mov %a, CTRL; band %a, CMP_G; bnot %a; bnot %a;\n"
```
This was the code generator learning to be a proper macro-expander rather than emit ad-hoc instruction sequences at each call site.

Every typed variable in the codegen received a full type annotation: [`assy_block_stack:Array[AssyBlock]`](class_AssyBlock.gd:2), [`cur_assy_block:AssyBlock`](class_AssyBlock.gd:2), [`referenced_cbs:Array[CodeBlock]`](class_CodeBlock.gd:2), [`cur_block:CodeBlock`](class_CodeBlock.gd:2), [`cb_stack:Array[CodeBlock]`](class_CodeBlock.gd:2). The Godot type-checker could now verify every assignment — a far cry from the untyped dictionary era.

### The Debug Highlight: "Sort of Works"

Commit [`7cea3b8`](https://github.com/) — "wip hl debug highlight" — began the work of making source lines glow during debugging. The debug panel ([`debug_panel.gd`](debug_panel.gd)) grew by 67 lines. The editor file ([`editor/editor_file.gd`](editor/editor_file.gd)) gained 19 lines for line highlighting.

Commit [`a3e63f4`](https://github.com/) — "HL highlight sort of works" — was the first visible result. The code generator ([`codegen_md.gd`](scenes/codegen_md.gd)) grew by 67 lines of location-aware code emission. The build system ([`comp_build.gd`](scenes/comp_build.gd)) gained 28 lines to wire the ELM through the pipeline.

But "sort of works" was not "works." The highlighting was imprecise. Lines flickered. The wrong source line sometimes lit up. The ELM mappings had gaps.

Commit [`8d68202`](https://github.com/) — "debugger window [step] and [unstep] now work in HL mode" — fixed the stepping logic in the debug panel ([`debug_panel.gd`](debug_panel.gd), +84/-31). Now the developer could step forward through MiniDerp source lines and step backward in reverse, with the debug panel tracking the current high-level position.

### Local Variables in the Debug View

Commit [`6642d5d`](https://github.com/) — "wip high level debug" — began adding local variable display to the debug panel. The analyzer ([`analyzer_md.gd`](scenes/analyzer_md.gd)) gained 30 lines of variable tracking. The code generator ([`codegen_md.gd`](scenes/codegen_md.gd)) grew by 23 lines to emit variable metadata alongside the generated assembly.

Commit [`8f2d368`](https://github.com/) — "added HL local debug view" — completed the feature. The debug panel ([`debug_panel.gd`](debug_panel.gd)) grew by 61 lines, adding a local variable display that showed variable names, types, and current values at runtime. The developer could now pause execution and inspect `i`, `str`, `c` — the actual source-level variables — not just memory addresses.

### The Flicker Fix

Commit [`4206d91`](https://github.com/) — "fixed debug locals flicker" — was a two-line change in [`debug_panel.gd`](debug_panel.gd). After 28 commits of location tracking, ELM construction, typed refactoring, and debug view building, the final bug was a rendering flicker fixed by adding two lines.

The commit captured the paradox of engineering: the hardest problems sometimes have the simplest solutions, but reaching those two lines requires climbing a mountain of infrastructure.

### The Final Fix

Commit [`7dde647`](https://github.com/) — "fixed high-level debug" — was the culmination. High-level debugging worked reliably. The [`class_AST.gd`](class_AST.gd) grew by 38 lines of location-awareness improvements. The location classes received final refinements. The debug panel ([`debug_panel.gd`](debug_panel.gd)) gained 21 lines of polish. The tokenizer ([`word_boundary_tokenizer.gd`](scenes/word_boundary_tokenizer.gd)) grew by 33 lines for better location tracking across multi-line constructs.

The debugger window ([`win_ed_dbg.gd`](scenes/win_ed_dbg.gd)) — first introduced in commit [`70bc02d`](https://github.com/) as the editor-debugger integration — now showed the current MiniDerp source line highlighted in real time during execution. Step forward. Step backward. Watch variables change. The source-level debugger was no longer a prototype; it was a tool.

---

## Chapter 6: Civilizing the Code — Types and Refactoring

> *Commits `e8e17fa` → `18f2880`*

---

### Growing Up

MiniDerp had been a duck-typed language from birth. Variables were declared with `var x = 5` and the compiler inferred their nature from context. This was fine for a prototype. But as programs grew beyond Hello World — as the developer began writing a test operating system ([`testOS/main.md`](res/data/testOS/main.md)) — the limitations became clear. Without type annotations, the analyzer couldn't catch mistakes. Without a type system, the code generator couldn't optimize memory layout. Without type checking, a single `var x = "hello"` at the wrong place could corrupt the stack.

The project needed to grow up. MiniDerp needed types.

### The Type System Is Born

Commit [`e8e17fa`](https://github.com/) — "wip types" — created [`class_Type.gd`](class_Type.gd). Initially 23 lines, the [`Type`](class_Type.gd:2) class was a [`RefCounted`](class_Type.gd:1) object with three fundamental fields:

- `name` — the user-visible type name: `"int"`, `"char"`, `"Ref"`, `"Array"`, `"String"`
- `of` — an array of child [`Type`](class_Type.gd:6) objects, representing generic parameters: `Ref[char]`, `Array[int]`
- `size` — the number of bytes an instance occupies in memory

The [`get_full_name()`](class_Type.gd:13) method composed the full type name recursively. `Ref[char]` became the string `"Ref[char]"`. `Array[Array[int]]` would produce `"Array[Array[int]]"`. The [`from_string()`](class_Type.gd:25) static method parsed type strings back into objects, using a custom brace-parsing utility called [`list_and_brace_separator()`](class_Type.gd:45) that handled nested generics with a brace-counting state machine. The [`from_string_helper()`](class_Type.gd:33) inner method walked the parsed array tree, building [`Type`](class_Type.gd) objects with their generic children recursively.

The type system defined a hierarchy of sizes in [`primitive_sizes`](class_Type.gd:107-119):
- `u8`, `s8`, `char` — 1 byte
- `u16`, `s16` — 2 bytes
- `u32`, `s32`, `float` — 4 bytes
- `u64`, `s64`, `int`, `double` — 8 bytes

Pointer types like `Ref`, `Array`, and `String` were all 4 bytes ([`pointer_size`](class_Type.gd:105) = 4) — the ZVM's native address width.

#### Type Aliases and the Type Stack

The analyzer ([`analyzer_md.gd`](scenes/analyzer_md.gd)) grew two companion structures to make the type system operational. The first was [`type_aliases`](scenes/analyzer_md.gd:44) — a dictionary mapping syntactic sugar names to their resolved types:

```gdscript
const type_aliases = {
    "String":"Ref[char]",
    "char":"u8"
};
```

This let the developer write `str:String` in source code, while the type checker immediately resolved it to `Ref[char]` — a pointer to a character buffer. The `char → u8` alias meant character variables were just bytes with a friendly name, not a separate type with its own rules.

The second structure was [`type_stack`](scenes/analyzer_md.gd:59) — an empty array that served as a stack for tracking types through expression evaluation. When the analyzer walked an AST node, it could push a [`Type`](class_Type.gd) onto the stack, evaluate child expressions, and pop the result. This is the standard pattern for type-checking in expression-oriented languages: the type of `a + b` is determined by pushing the type of `a`, pushing the type of `b`, and popping both to compute the result type. In MiniDerp's case, the stack was also used by [`analyze_type_expr()`](scenes/analyzer_md.gd:476) which pushed the resolved [`Type`](class_Type.gd) after parsing a type expression like `Ref[char]`.

#### Grammar Extension: Type Expressions in the Parser

The language definition in [`lang_md.gd`](scenes/lang_md.gd) was extended with eight new grammar rules to support type expressions:

- `TYPE` → `type_expr` — A bare type name is a valid type expression.
- `TYPE[type_expr]` → `type_expr` — Parameterized types like `Ref[char]`.
- `TYPE[type_expr_list]` → `type_expr` — Multi-parameter generics.
- `IDENT : type_expr` → `expr_typed_ident` — The typed identifier syntax, the most important new rule. A colon after an identifier declared its type: `c:char`, `str:String`, `adr_scr:Ref[char]`.

The grammar at [`lang_md.gd`](scenes/lang_md.gd:106-137) shows the full type-expression rule set, including comma-separated type lists for future multi-parameter generics. This was the parser learning a new dialect.

### Type Annotations in the Wild

The analyzer ([`analyzer_md.gd`](scenes/analyzer_md.gd)) grew by 156 lines of type-checking logic. The language definition ([`lang_md.gd`](scenes/lang_md.gd)) gained 32 lines of type-related grammar rules. A new test file appeared: [`hello_typed.md`](res/data/hello_typed.md).

The test file showed the type system in action:
```gdscript
func print(str:String, r:u8, g:u8, b:u8);
func putch(c:char, r:u8, g:char, b:u8);
var adr_scr:Ref[char] = 67536;
var scr_I:int = 0;
```

Variables now carried type annotations after a colon. Functions declared their parameter types. The analyzer could verify that `str:String` was being passed to a parameter expecting `String`, and that `r:u8` didn't receive a value larger than 255. The `Ref[char]` type on `adr_scr` declared that this variable pointed to a character buffer — the screen memory — and the code generator could emit correct indexed access instructions.

The error list grew three new entries to support type checking:
```gdscript
const ERR_53 = "Error 33: Can't assign value of type [%s] to variable of type [%s]";
const ERR_55 = "Error 35: Can't do operator %s between %s and %s";
const ERR_58 = "Error 38: Array index must be one of integer types";
```

### Type Hints Compile

Commit [`1546a09`](https://github.com/) — "Miniderp compiles with type hints" — was a milestone. The [`class_Type.gd`](class_Type.gd) expanded by 109 lines, adding the full type resolution logic. The analyzer grew by 64 lines of type-aware code. The code generator ([`codegen_md.gd`](scenes/codegen_md.gd)) gained 16 lines to consider type sizes when allocating storage. The IR ([`ir_md.gd`](scenes/ir_md.gd)) gained type fields on values.

The type system was now wired through the entire compiler pipeline:
- **Tokenizer** — recognized type keywords (`int`, `char`, `u8`, `Ref`, etc.)
- **Parser** — parsed type annotations using the colon syntax
- **Analyzer** — resolved type references, checked compatibility, reported type errors
- **IR** — carried type information on every value
- **Code Generator** — used type sizes for stack layout, emitted type-appropriate instructions

### Performance: The Loop Counter

Commit [`21a780b`](https://github.com/) — "miniderp printf compiles with new type stuff; performance improvement" — continued the type integration. printf could now use typed variables. But more interesting was a new file: [`class_LoopCounter.gd`](class_LoopCounter.gd).

The [`LoopCounter`](class_LoopCounter.gd:2) was a simple guard against infinite loops in the compiler's analysis phase. Its [`step()`](class_LoopCounter.gd:9) method incremented a counter and asserted if it exceeded the maximum:
```gdscript
func step():
    n_loops += 1;
    if(n_loops > max_loops):
        assert(false, "infinite loop detected");
```

The [`max_loops`](class_LoopCounter.gd:4) default was 999 — a generous upper bound that would catch genuine infinite loops without interrupting legitimate analysis. This was the compiler learning to protect itself from its own bugs.

### Codegen's Fucked

And then came the crisis.

Commit [`c67b2d8`](https://github.com/) — "codegen's fucked" — was a gut punch. The commit message was three words of raw frustration. 362 lines were added to [`codegen_md.gd`](scenes/codegen_md.gd). The type system integration had broken something fundamental.

The changes touched 14 files. The code generator grew massively but was non-functional. An [`export_presets.cfg`](export_presets.cfg) file appeared — 67 lines of standalone build configuration — suggesting the developer was contemplating cutting losses and shipping whatever worked. A new test file — [`printf_test3.md`](res/data/printf_test3.md) at 204 lines — was also added, a large formatted-print test that exercised the type system across multiple code paths.

#### The `op_map` Restructuring

The most visible change inside the codegen was a restructuring of the [`op_map`](scenes/codegen_md.gd). Previously, each IR operation mapped to a single string template:

```gdscript
"ADD":"add %a, %b;\n",
"GREATER":"cmp %a, %b; mov %a, CTRL; band %a, CMP_G; bnot %a; bnot %a;\n",
```

Now each value was an array of strings, one line per instruction:

```gdscript
"ADD":["add %a, %b;\n"],
"GREATER":["cmp %a, %b;\n", "mov %a, CTRL;\n", "band %a, CMP_G;\n", "bnot %a;\n", "bnot %a;\n"],
```

This wasn't cosmetic. The array-of-lines format allowed the code generator to insert location markers between individual instructions, mapping each assembly line back to its source expression. The old string-blob approach couldn't do that — a multi-instruction expansion like GREATER would produce five assembly lines but only one location tag.

A new [`imm_map`](scenes/codegen_md.gd) was also added, mapping comparison flags like `CMP_G`, `CMP_L`, `CMP_E` to themselves — a lookup table for immediate values that could appear in assembly templates.

#### The Value Index

A system-wide numbering scheme was introduced: [`val_idx`](scenes/codegen_md.gd) and [`bump_val_idx()`](scenes/codegen_md.gd). Throughout the [`deserialize()`](scenes/codegen_md.gd) function — which translated the deserialized IR into the code generator's internal representation — `bump_val_idx()` was called for every scope, every code block, and every symbol. This assigned a unique numeric identity to every IR value in the program. The value index was the missing link between the type system and the code generator: without it, the codegen couldn't distinguish between two variables of the same type at different scopes.

#### Debug Mode Engaged

[`ADD_DEBUG_TRACE`](scenes/codegen_md.gd) was changed from `false` to `true`. This single-line change turned on verbose logging across the code generation pipeline — every instruction emitted, every location mapped, every stack frame allocated was printed to the output console. The developer was debugging the type system integration in real time, watching the compiler fail and trying to understand why.

#### Timeline Context

The commit date tells a crucial story: [`e8e17fa`](https://github.com/) — the type system's birth — was dated **October 29, 2025**, while [`c67b2d8`](https://github.com/) — the codegen crisis — was dated **October 31, 2025**. The type system was born two days before the codegen broke. This wasn't a coincidence: the type system was designed and committed first, and the code generator was struggling to *keep up* with the newly-typed IR. The IR now carried typed value references; the code generator had to allocate registers with type-appropriate sizes, emit correct memory access instructions for 8-bit vs 32-bit values, and track type information through the assembly output. The old ad-hoc codegen wasn't designed for any of this.

The crisis was inevitable. The recovery — two commits later in [`18f2880`](https://github.com/) — wasn't guaranteed. The developer had two choices: revert the type system work and go back to a working compiler, or push through the bugs and fix them.

### Fixed a Crash

Commit [`18f2880`](https://github.com/) — "fixed a crash" — was the recovery.

The crash was diagnosed. The analyzer ([`analyzer_md.gd`](scenes/analyzer_md.gd)) gained 8 lines of fixes. The code generator ([`codegen_md.gd`](scenes/codegen_md.gd)) gained 6 lines. The main scene ([`main.tscn`](scenes/main.tscn)) underwent a 152-line update. [`class_CodeBlock.gd`](class_CodeBlock.gd) grew by 1 line. The project settings ([`project.godot`](project.godot)) were updated.

But the most telling addition was a new test file: [`res/data/testOS/main.md`](res/data/testOS/main.md) — 60 lines of MiniDerp code that would become the seed of a test operating system.

The testOS was a shell — a command-line interface running on the ZVM, accepting keyboard input, processing commands, printing output. It was the most complex MiniDerp program yet written, exercising every feature of the language: typed variables, function calls, while loops, if/else chains, string indexing, character I/O. The testOS would expand to 251 lines by the end of the project, becoming the primary stress test for the compiler.

### The Aftermath

The type system survived. The code generator was stabilized. The crash was fixed. But the scars remained — visible in [`export_presets.cfg`](export_presets.cfg), a reminder that the developer had contemplated packaging whatever worked and moving on.

The commit messages told the story in miniature:

- *"wip types"* — the hopeful beginning
- *"Miniderp compiles with type hints"* — the milestone
- *"codegen's fucked"* — the crisis
- *"fixed a crash"* — the recovery

This was the project growing up. Type systems are not free. They demand changes across every layer of the compiler — the grammar, the parser, the analyzer, the IR, the code generator. They introduce bugs that don't appear with duck typing. They force the developer to think about memory layout, register allocation, and instruction encoding in ways that dynamic languages never require.

But they also catch mistakes. The `ERR_53` error code — "Can't assign value of type [%s] to variable of type [%s]" — would save the developer countless hours of debugging corrupted memory. The [`ERR_58`](error_list.gd:43) — "Array index must be one of integer types" — would prevent indexing bugs before they manifested as crashes.

MiniDerp was no longer a toy language. It had types. It had a type checker. It had a compiler that could report errors with source locations. And it had a test operating system — a 251-line shell — proving that the entire system could build real software.

The project had crossed from experimental prototype to working development platform. The crashes were temporary. The type system was forever.

---

*End of Chapters 5–6. The narrative continues with feature implementation, arrays, and the evolution of the MiniDerp ecosystem.*
