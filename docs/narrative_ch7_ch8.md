# CpuDerp: A Development Narrative

## Chapter 7: The Feature Sprint — Crossing Off the TODO List

> *Commits `2ca5f3a` → `f1c3917`*

---

### The Planning Session

The type system was stable. The code generator had survived its crisis. The debug panel could highlight source lines, step backward through execution, and display local variables with their types. MiniDerp was no longer a prototype — it was a working compiler for a working language, running on a working virtual machine.

But the developer knew exactly what wasn't working. The knowledge lived in their head: a mental TODO list of sharp edges and missing features. The `!=` operator produced garbage output. `x[I] == y[I]` parsed as `(x[I] == y)[I]`. There was no way to write a single-quote character literal, no `#include` directive for modular code, no compound assignment operators, no arity checking on function calls, no indirect calls, no arrays.

Eight problems. The developer needed to fix all of them.

But before writing code, they wrote documents. Commit [`2ca5f3a`](https://github.com/) — bearing the modest message "wip" — was anything but a work-in-progress. It was a detonation of documentation. Fifteen files changed, 3,507 lines added. The developer was stepping back from the keyboard, surveying their kingdom, and making a battle plan.

The core documents were laid out in the new [`docs/`](docs/) directory. [`docs/todo.md`](docs/todo.md) — 12 lines — was the shortest document and the most important. It was a raw, unadorned checklist:

```md
- '\n' // character literals
- var arr = [10] // array declaration
- x = [a,b,c]; // array construction
- #include // needs to be implemented
- += // infix ops need to be implemented
- != doesn't compile?
- x[I] == y[I] parses as (x[I] == y)[I] // broken precedence!
- function arity not checked
- calling a variable as function doesn't compile: f() syntax
```

Each line was a bug or a missing feature. Each line had a corresponding plan file in the new [`plans/`](plans/) directory. The developer was done with ad-hoc hacking; every change from this point forward would be deliberate.

[`docs/todo_implementation.md`](docs/todo_implementation.md) — 485 lines — was the master implementation plan. It documented the entire compiler pipeline phase by phase, file by file. It described how the tokenizer fed the parser, how the parser built ASTs, how the analyzer resolved symbols, how the IR was constructed, how the code generator emitted ZDerp assembly. It was a developer's reference manual, written for the person who would be reading this code six months from now.

[`docs/miniderp_syntax.md`](docs/miniderp_syntax.md) — 242 lines — formally defined the MiniDerp language with all 22 implemented syntax constructs. Variables, functions, control flow, operators, types — every construct was documented with examples and implementation status. The syntax reference showed a language that had grown organically but was now being cataloged:

- Variable declarations: `var name;` and `var name = expr;`
- Extern declarations: `extern var y;` and `extern func putch(c);`
- Function definitions with typed parameters: `func print(str:String, r:u8, g:u8, b:u8) { ... }`
- While loops with break/continue
- If/elif/else chains
- Compound assignment: `x += 2;`
- Array indexing: `adr_scr[scr_I]`
- Character literals: `'\n'`

And then there were the plans. Eight plan files, each addressing a specific deficiency:

- [`plans/implementation_not_equal.md`](plans/implementation_not_equal.md) — 191 lines. Root cause analysis of the `!=` operator bug. The tokenizer's [`assign_ops`](scenes/md_tokenizer.gd:11) constant at line 8 (in the original) listed `"!="` as an assignment operator, which caused the token reclassifier to skip it. The fix: remove `"!="` from `assign_ops`.

- [`plans/implementation_precedence.md`](plans/implementation_precedence.md) — 177 lines. The `x[I] == y[I]` parsing bug was a grammar problem. The shift-reduce engine needed SHIFT lookahead rules to force array indexing to bind tighter than equality comparison.

- [`plans/implementation_character_literals.md`](plans/implementation_character_literals.md) — 113 lines. Single-quoted characters like `'a'` and escape sequences like `'\n'` required changes to three different systems: the generic word-boundary tokenizer, the MiniDerp-specific tokenizer, and the keyboard handler for non-ASCII filtering.

- [`plans/implementation_include.md`](plans/implementation_include.md) — 159 lines. The `#include` directive needed preprocessor support in the tokenizer, with recursive file resolution relative to the including file's path.

- [`plans/implementation_compound_operators.md`](plans/implementation_compound_operators.md) — 155 lines. `+=`, `-=`, `*=`, `/=`, `%=` needed grammar rules in [`lang_md.gd`](scenes/lang_md.gd) and expansion logic in the analyzer.

- [`plans/implementation_arity.md`](plans/implementation_arity.md) — 298 lines. Function calls needed argument-count validation. The analyzer would need to track `argc` on function declarations and compare against call sites.

- [`plans/implementation_indirect_calls.md`](plans/implementation_indirect_calls.md) — 190 lines. Calling a variable as a function — `f()` where `f` is a variable holding a function reference — required changes to the analyzer's type resolution and the code generator's call emission.

- [`plans/implementation_array.md`](plans/implementation_array.md) — 260 lines. Array literal grammar rules (`[expr]`, `[expr_list]`, `[]`), analyzer type resolution for array types, and code generation for array element access with pointer arithmetic.

The developer also added a test file — [`res/data/test_arr_if.md`](res/data/test_arr_if.md) — 19 lines of array-and-if test code. And expanded the test operating system [`res/data/testOS/main.md`](res/data/testOS/main.md) by 106 lines, already preparing for the integration testing that would validate every new feature.

This was the moment the project stopped being a hack and started being an engineering effort. The TODO list was written down. The plans were drafted. The developer had surveyed the codebase, identified every gap, and written a roadmap for filling them.

Now came the execution.

### The Sprint Begins

What followed was the most concentrated burst of feature development in the project's history. Eight features in seven commits, each one targeted, planned, and executed.

**The June 21st Sprint.** Four of those features landed in a single day — June 21st, 2026. Commit [`2b28284`](https://github.com/) brought compound assignment operators (`+=`, `-=`, `*=`, `/=`, `%=`). Commit [`2401d5f`](https://github.com/) delivered character literals with full escape-sequence support. Commit [`083faf5`](https://github.com/) implemented the `#include` preprocessor directive. Commit [`f1c3917`](https://github.com/) began the most complex addition yet: array literal syntax. Four commits, four features, one day — the project's most productive 24 hours. The developer had planned, documented, and then executed with machine-gun precision.

---

**Commit [`5606e3a`](https://github.com/) — "fixed !="**

The simplest fix in the sprint. The `!=` operator had two bugs. First, the tokenizer's [`assign_ops`](scenes/md_tokenizer.gd:11) constant mistakenly classified `!=` as an assignment operator:
```gdscript
const assign_ops = ["=", "+=", "-=", "*=", "/=", "%="];
```
The original list included `"!="`. When the token reclassifier ran, it saw `!=` in the `assign_ops` list and skipped it, leaving the token classified as generic `PUNCT` instead of `OP`. The fix: remove `"!="` from `assign_ops`.

Second, the code generator ([`codegen_md.gd`](scenes/codegen_md.gd)) needed to emit the correct comparison instruction. The ZVM's comparison flags included `CMP_L` (less), `CMP_G` (greater), and `CMP_Z` (zero). Not-equal meant "neither less nor greater" — the combined flag `CMP_NZ` defined in [`lang_zvm.gd`](lang_zvm.gd:39):
```gdscript
"CMP_NZ": BIT_CMP_L | BIT_CMP_G,
```

A single line in the code generator's comparison table mapped `!=` to `CMP_NZ`. A one-char change in [`md_tokenizer.gd`](scenes/md_tokenizer.gd) fixed the token classification. A test file — [`res/data/test_not_eq.md`](res/data/test_not_eq.md) — verified both branches of `!=` and `==`:

```c
var x = 1;
var y = 2;
if ( x != y ){
    c = 1;
}else{
    c = 2;
}
```

The fix was tiny. The planning document that preceded it was 191 lines. This was the new workflow: plan first, then execute the precise, minimal change.

---

**Commit [`e65e359`](https://github.com/) — "fixed precedence of x[I]"**

The bug report in [`docs/todo.md`](docs/todo.md) said it plainly: `x[I] == y[I]` was parsing as `(x[I] == y)[I]`. Array indexing was binding too loosely, letting the equality operator capture the index expression.

The fix was two lines in [`lang_md.gd`](scenes/lang_md.gd), the grammar definition file. The developer added SHIFT lookahead rules at lines 113-114:

```gdscript
["expr", "OP", "expr",				"/[", "SHIFT"],
["expr", "OP", "expr", 				"/(", "SHIFT"],
```

These rules told the shift-reduce parser: when you see an expression, an operator, and another expression followed by `[` or `(`, do NOT reduce to an infix expression yet. Shift the `[` onto the stack and let the array index expression bind first. The `/` prefix in `"/["` meant the rule matched when the *lookahead* token was `[` — it was a peek-ahead rule that forced higher precedence for indexing and function calls.

Two lines. One character each. The entire precedence system of the language hinged on them.

---

**Commit [`2401d5f`](https://github.com/) — "character literals work now"**

Character literals were the most cross-cutting feature in the sprint. Single-quoted characters like `'a'` and escape sequences like `'\n'` required changes across four subsystems.

The generic word-boundary tokenizer gained a `CHAR` token class: a single quote `'` triggered a transition to `CHAR` mode, and a second `'` triggered `ENDCHAR` — mirroring the `STRING`/`ENDSTRING` pattern that already existed for double-quoted strings. The leading `'` was stripped from the token text, preserving only the character content inside.

The MiniDerp tokenizer ([`md_tokenizer.gd`](scenes/md_tokenizer.gd)) grew by 34 lines. A new function, [`resolve_char_tokens()`](scenes/md_tokenizer.gd), was added: for each `CHAR` token, it called `c_unescape()` to resolve escape sequences (`\n` → newline, `\t` → tab, `\'` → literal quote), converted the result to an ASCII buffer, validated that only a single byte remained, and replaced the token text with the decimal ASCII value. Multi-byte and empty character literals reported error `E.ERR_33`. The `ENDCHAR` token was filtered out alongside `ENDSTRING` and `SPACE` during cleanup. A new `CHAR` color entry appeared in [`token_colors`](scenes/md_tokenizer.gd:27):
```gdscript
"CHAR": Color(1.0, 1.0, 0.0, 1.0),
```
The yellow color was deliberate — it matched `NUMBER`, signaling that characters were treated as integer values in the type system.

The keyboard handler ([`scenes/KB.gd`](scenes/KB.gd)) was completely rewritten. The old input logic was replaced with a new [`get_special_ASCII()`](scenes/KB.gd) function that used a `match` on `event.keycode` to translate special keys directly to their ASCII values: Enter→10, Backspace→8, Tab→9, Escape→27, Delete→127, Space→32. Multi-byte UTF-8 characters that could not fit in a single byte were explicitly filtered out. The handler also gained `last_captured` state tracking and a [`sig_keypress(character, byte)`](scenes/KB.gd) signal for clean integration with the terminal.

The analyzer ([`analyzer_md.gd`](scenes/analyzer_md.gd)) and language definition ([`lang_md.gd`](scenes/lang_md.gd)) were updated with `CHAR` token support, and the `"CHAR"` keyword was added to the grammar. The syntax documentation ([`docs/miniderp_syntax.md`](docs/miniderp_syntax.md)) was updated with 6 lines showing character literal usage.

Twelve files changed. But now the developer could write `var c = 'A'` and have it compile. And with the rewritten keyboard handler, pressing Enter in the terminal sent ASCII 10, Backspace sent ASCII 8 — the system spoke the same byte-code language as the compiler.

---

**Commit [`083faf5`](https://github.com/) — "implemented #include"**

Modular programming came to MiniDerp. The `#include` directive was implemented as a preprocessor step in [`md_tokenizer.gd`](scenes/md_tokenizer.gd), growing by 36 lines.

The mechanism was implemented through three new functions. [`process_includes(text)`](scenes/md_tokenizer.gd) was the orchestrator: it repeatedly searched for `#include` directives using `text.find("#include")`, extracted the filename with [`get_word_at()`](scenes/md_tokenizer.gd), read the file with [`include_file()`](scenes/md_tokenizer.gd), and replaced the `#include` line with the file contents through text substitution. It continued searching the result for nested includes, enabling transitive dependencies.

[`get_word_at(text, I)`](scenes/md_tokenizer.gd) handled filename extraction: it skipped whitespace after the `#include` keyword, reported `E.ERR_34` if the line ended immediately, and read the filename token — typically a quoted string like `"lib/screen.md"`.

[`include_file(filepath)`](scenes/md_tokenizer.gd) managed file resolution: it resolved filenames relative to [`cur_path`](scenes/md_tokenizer.gd), the base directory of the current source file. It stripped surrounding quotes and leading slashes, used [`path_join()`](scenes/md_tokenizer.gd) for safe path resolution, read the file via Godot's `FileAccess`, and reported `E.ERR_35` if the file was not found. A critical detail: the tokenizer's `reset()` function was commented out so that `cur_path` persisted across tokenization calls — once set, the include path remained valid for all subsequent `#include` directives in the compilation session.

The commit also added [`res/data/testOS/lib/screen.md`](res/data/testOS/lib/screen.md) — 54 lines of MiniDerp library code. The screen library provided the building blocks for terminal I/O:

```c
func print(str);
func putch(c);
func scr_push_byte(b);
func set_col(R,G,B);
func println(str);
func newline();
```

The library declared global variables for the screen buffer address (`adr_scr = 67536`), the cursor position (`scr_I = 0`), the current color (`col_R = 255, col_G = 255, col_B = 255`), and the screen width (`scr_width = 56`). Functions like [`println`](res/data/testOS/lib/screen.md:15) and [`newline`](res/data/testOS/lib/screen.md:20) provided reusable abstractions.

The test operating system — [`testOS/main.md`](res/data/testOS/main.md) — now began with `#include "lib/screen.md"`. The developer was building a standard library.

---

**Commit [`2b28284`](https://github.com/) — "implemented compound assignment +="**

Five compound assignment operators arrived in one commit: `+=`, `-=`, `*=`, `/=`, `%=`.

The grammar rules in [`lang_md.gd`](scenes/lang_md.gd) gained 7 lines defining the `comp_asn_op` nonterminal:

```gdscript
["/+=", 	"*", "comp_asn_op"],
["/-=", 	"*", "comp_asn_op"],
["/*=", 	"*", "comp_asn_op"],
["//=", 	"*", "comp_asn_op"],
["/%=", 	"*", "comp_asn_op"],
```

A new statement type, `comp_assignment_stmt`, was added at line 49:

```gdscript
["expr", "comp_asn_op", "expr", "/;", "comp_assignment_stmt"],
```

The analyzer ([`analyzer_md.gd`](scenes/analyzer_md.gd)) grew by 55 lines to handle the new statement type. First, the analyzer was refactored: [`analyze_assignment_stmt`](scenes/analyzer_md.gd) had its LHS extraction logic factored out into a shared [`analyze_lhs()`](scenes/analyzer_md.gd) helper that handled both bare `IDENT` and array-indexed `expr` cases. A new [`analyze_comp_assignment_stmt()`](scenes/analyzer_md.gd) then performed the desugaring: it stripped the trailing `=` from the operator text (turning `+=` into `+`), looked up the base operator in [`op_map`](scenes/analyzer_md.gd), emitted the binary operation IR, then emitted a `MOV` to store the result back into the LHS. The effect was that `x += 5` became two IR commands: `OP ADD x, 5, tmp` followed by `MOV x, tmp`. The existing code generator already knew how to handle both operations separately.

The test operating system ([`res/data/testOS/main.md`](res/data/testOS/main.md)) grew by 6 lines to exercise the new operators. Six lines of test code for five language features — efficient verification.

---

**Commit [`428b3f5`](https://github.com/) — "added arity check"**

Before this commit, you could call a function with any number of arguments and the compiler would happily generate broken code. [`func print(str)`](res/data/testOS/lib/screen.md:1) could be called as `print("a", "b", "c")` and the analyzer wouldn't blink.

The fix was arity checking. The analyzer ([`analyzer_md.gd`](scenes/analyzer_md.gd)) gained 35 lines to track `argc` (argument count) on every function declaration. When a function call was analyzed, the analyzer compared the call's argument count against the declaration's. Mismatches were reported using two new error codes added to [`error_list.gd`](error_list.gd):

```gdscript
const ERR_35 = "Error 35: function [%s] expected %d arguments, got %d";
const ERR_36 = "Error 36: function [%s] expected %d arguments, got %d";
```

The IR ([`ir_md.gd`](scenes/ir_md.gd)) grew by 4 lines to carry argument counts in function call IR commands. The code generator ([`codegen_md.gd`](scenes/codegen_md.gd)) gained 2 lines to pass the count through.

The change was small but its impact was large. Every function call in every MiniDerp program was now validated. A whole class of runtime crashes — calling functions with wrong argument counts — was eliminated at compile time.

---

**Commit [`560c81a`](https://github.com/) — "indirect calls supported now"**

Indirect calls were the most sophisticated feature in the sprint. The ability to call a variable as a function — `f()` where `f` is a variable holding a function reference — required the compiler to resolve function references at runtime.

The analyzer ([`analyzer_md.gd`](scenes/analyzer_md.gd)) gained 8 lines of type resolution logic. When the parser produced a call node like `expr_call` with an identifier that wasn't a declared function name, the analyzer checked whether the identifier was a variable of a callable type.

The code generator ([`codegen_md.gd`](scenes/codegen_md.gd)) gained 24 lines to emit the indirect call sequence. Instead of `CALL label`, the generated assembly loaded the function address from the variable, then performed an indirect `CALL [reg]`. The register held the address of the function to call — a function pointer in all but syntax.

The test operating system ([`res/data/testOS/main.md`](res/data/testOS/main.md)) grew by 3 lines to test the feature. Indirect calls enabled higher-order patterns: callbacks, dispatch tables, and dynamic behavior that wasn't possible before.

---

**Commit [`f1c3917`](https://github.com/) — "wip array"**

The final commit of the sprint began the array feature — the most complex addition yet.

Array literal grammar rules were added to [`lang_md.gd`](scenes/lang_md.gd) at lines 128-130:

```gdscript
["/[", "expr", "/]",   			"*", "expr_array_literal"],
["/[", "expr_list", "/]",		"*", "expr_array_literal"],
["/[", "/]",					"*", "expr_array_literal"],
```

Three forms: `[expr]` for single-element arrays, `[expr_list]` for multi-element arrays with comma-separated expressions, and `[]` for empty arrays.

Array indexing was extracted into its own grammar rule, [`expr_index`](scenes/lang_md.gd):
```gdscript
["expr", "/[", "expr", "/]", "*", "expr_index"]
```
This was then promoted into the expression hierarchy: `["expr_index", "*", "expr_infix"]` — array indexing became a first-class expression with the same precedence as infix operations. Variable declarations also gained array-size syntax: `["/var", "expr_index", "/;", "var_decl_stmt"]` enabled the `var arr[10]` declaration form.

The analyzer ([`analyzer_md.gd`](scenes/analyzer_md.gd)) gained 45 lines of array type resolution. A new [`analyze_expr_array_literal()`](scenes/analyzer_md.gd) handled all three literal forms: for `[expr]` and `[expr_list]` it emitted `ALLOC` (specifying total size) and `MOV_ARR` (copying each element) IR instructions; for `[]` it allocated an empty array. Array variable declarations set `var_handle.is_array = true` and `var_handle.array_size = arr_size` by walking the `expr_index` tree to extract the declared size.

A supporting change hardened [`user_error()`](scenes/analyzer_md.gd): it now set `error_code`, called `push_error`, and executed `assert(false)` for immediate debugging feedback. And [`analyze_expr()`](scenes/analyzer_md.gd) was updated to detect errors early — returning immediately on failure — and to dispatch `expr_array_literal` to the new handler.

The code generator ([`codegen_md.gd`](scenes/codegen_md.gd)) gained 19 lines of array emission. The IR ([`ir_md.gd`](scenes/ir_md.gd)) gained 4 lines for `ALLOC` and `MOV_ARR` IR commands. The assembler ([`comp_asm_zd.gd`](scenes/comp_asm_zd.gd)) gained 33 lines of array data handling. A new error code appeared:

```gdscript
const ERR_58 = "Error 38: Array index must be one of integer types";
```

But the commit message said "wip" — work in progress. Arrays were not done. They were begun.

---

### The Summation

Seven commits. Eight features. The sprint was remarkable not for its size — many individual commits in earlier phases were larger — but for its precision. Each change was targeted. Each feature was planned before it was coded. Each commit message was clear and declarative: "fixed !=", "fixed precedence", "character literals work now", "implemented #include", "implemented compound assignment +=", "added arity check", "indirect calls supported now."

The TODO list had seven items crossed off:

- [x] `!=` doesn't compile
- [x] `x[I] == y[I]` parses as `(x[I] == y)[I]` // broken precedence
- [x] `'\n'` // character literals
- [x] `#include` // needs to be implemented
- [x] `+=` // infix ops need to be implemented
- [x] function arity not checked
- [x] calling a variable as function doesn't compile: `f()` syntax

One item remained: arrays. But arrays were different. Arrays touched every layer of the compiler — the grammar, the parser, the analyzer, the IR, the code generator, the assembler, the runtime. Arrays needed new data structures, new instruction sequences, new memory layouts. Arrays were not a quick fix; they were a deep engineering project.

The sprint was over. The deep work was about to begin.

---

## Chapter 8: Deep Waters — Arrays, Shadow Stacks, and Beyond

> *Commits `1b2dc74` → `833801`*

---

### The Array Problem

Arrays are the gateway drug to complexity in language implementation. A language without arrays is a language of scalars — variables hold single values, functions return single values, memory is flat and simple. A language with arrays suddenly demands pointer arithmetic, indexed addressing, bounds awareness, and layout calculations.

MiniDerp now had array literal syntax: `var arr = [1, 2, 3]`. The grammar could parse it. The analyzer could type-check it. But the code generator's handling was incomplete. Arrays on the ZVM required the compiler to:

1. Calculate the total size of the array at compile time
2. Allocate space on the stack or in the data segment
3. Emit initialization code for each element
4. Generate correct indexed access instructions for reads and writes
5. Handle nested arrays (arrays of arrays)
6. Manage array references passed to functions

The "wip" commit at the end of Phase 7 had laid the foundation. Now the developer had to make arrays actually work.

---

### The Contraption

Commit [`1b2dc74`](https://github.com/) — "wip" — was cryptic. A new scene file appeared: [`contraption/panel_contraption.tscn`](contraption/panel_contraption.tscn). "Contraption" was an unusual word in the project — most files had descriptive, functional names. A contraption was something experimental, a gadget, a tool built to solve a specific problem that might not have a name yet.

The 92-line scene was likely a UI element for array visualization or debugging — a panel that could display array contents during execution, showing elements in sequence with their indices and values. The existing memory viewer showed raw bytes at addresses. A contraption could show *arrays* — logical data structures with named elements and types.

Or it could have been something else entirely. The commit message just said "wip." The contraption remained unnamed and unexplained, a loose thread in the project's fabric.

---

### Refining the Plan

Commit [`427b03f`](https://github.com/) — "wip arrays" — continued the array implementation. The code generator ([`codegen_md.gd`](scenes/codegen_md.gd)) gained 28 lines and lost 12 — a net increase driven by array-specific code emission. The analyzer ([`analyzer_md.gd`](scenes/analyzer_md.gd)) grew by 13 lines of array type handling. The assembler ([`comp_asm_zd.gd`](scenes/comp_asm_zd.gd)) gained 33 lines for array data directives.

But the most revealing change was to the plan document. [`plans/implementation_array.md`](plans/implementation_array.md) was modified by +80/-19 lines — a major update reflecting the developer's deepening understanding of the array problem. The plan was a living document, revised as reality imposed its constraints.

A new test file appeared: [`res/data/test_arr2.md`](res/data/test_arr2.md) — 16 lines of focused array testing:

```c
func main();
var x = 1001;
var arr1[10];
var y = 1002;
main();

func main(){
    var x2 = 1003;
    arr1[0] = 1014;
    arr1[1] = 1015;
    x = 1006;
    var arr2 = [1027, 1028, 1029];
    var y2 = 1007;
    while(1){}
}
```

The test exercised both declaration syntaxes — `var arr1[10]` (fixed-size array declaration) and `var arr2 = [1027, 1028, 1029]` (array literal construction). It mixed global and local variables with array accesses. The infinite `while(1){}` loop at the end was a debugging anchor — it let the developer inspect memory after all the array operations had executed.

---

### The Great Plans

Commit [`da685db`](https://github.com/) — "some plans" — produced two massive documents.

[`plans/implementation_debug_panel_pointers.md`](plans/implementation_debug_panel_pointers.md) — 549 lines — was a detailed design for pointer visualization in the debug panel. The memory viewer could show raw bytes, but it couldn't follow pointers. This plan described how to add dereference capabilities: clicking on a memory address that contained a pointer would jump to the pointed-to location. The debugger would become interactive, letting the developer navigate the heap and stack visually.

[`plans/implementation_parser_dfa.md`](plans/implementation_parser_dfa.md) — 1,013 lines — was the largest plan document in the entire project. It described a complete rewrite of the shift-reduce parser as a DFA-based (Deterministic Finite Automaton) parser. The current parser was hand-coded with explicit grammar rules in [`lang_md.gd`](scenes/lang_md.gd). A DFA parser would be generated from a formal grammar specification, producing faster and more reliable parsing.

1,013 lines of planning. The developer was thinking big — rewriting the core of the compiler frontend. The DFA parser plan was evidence that the project was pushing against the limits of its own architecture. The hand-coded parser had served well through 87 commits, but it was reaching the edge of what hand-rolled parsing could handle.

---

### Diagnosing Arrays

Commit [`4277052`](https://github.com/) — "wip" — added a 346-line diagnostic document: [`docs/diagnosis_array_literal.md`](docs/diagnosis_array_literal.md).

This was something new in the project. Previous debugging had been done in code — fix the bug, commit the fix, move on. But array literal compilation was proving stubborn. The developer sat down and wrote a formal diagnosis document, tracing the full pipeline for `var x = [1,2,3]`:

```
decl_assignment_stmt
├── var
├── assignment_stmt
│   ├── expr
│   │   └── expr_ident
│   │       └── IDENT("x")
│   ├── =
│   └── expr
│       └── expr_array_literal
│           ├── [
│           ├── expr_list
│           │   ├── expr → expr_immediate → NUMBER(1)
│           │   ├── expr → expr_immediate → NUMBER(2)
│           │   └── expr → expr_immediate → NUMBER(3)
│           └── ]
```

The document listed symptoms, hypotheses, and expected behaviors for each compiler phase. The developer was methodically working through the problem, writing down each step. This was debugging as scientific method: observe, hypothesize, test, repeat.

---

### The Shadow Stack

The most architecturally significant addition in this phase was shadow stack instrumentation. Commits [`6ebdc5a`](https://github.com/) and [`fe29c69`](https://github.com/) added a system for marking every stack memory cell with metadata about its role in the call frame.

The ZVM's ISA definition ([`lang_zvm.gd`](lang_zvm.gd)) gained six new shadow constants at lines 150-155:

```gdscript
const SHADOW_FRAME_PREV_EBP = 9;
const SHADOW_FRAME_PREV_IP = 10;
const SHADOW_FRAME_ARGUMENT = 11;
const SHADOW_FRAME_VAR = 12;
const SHADOW_FRAME_TEMP = 13;
const SHADOW_FRAME_PADDING = 14;
```

These joined the existing shadow types — `SHADOW_UNUSED`, `SHADOW_DATA`, `SHADOW_CMD_HEAD`, `SHADOW_CMD_TAIL`, `SHADOW_CMD_UNRESOLVED`, `SHADOW_CMD_RESOLVED`, `SHADOW_DATA_UNRESOLVED`, `SHADOW_DATA_RESOLVED`, `SHADOW_PADDING` — forming a comprehensive taxonomy of 15 shadow constants. A new [`SHADOW_TO_STRING`](lang_zvm.gd) dictionary mapped every constant to a human-readable label for debug display.

The code generator ([`codegen_md.gd`](scenes/codegen_md.gd)) grew by 121 lines in the first commit and 59 lines in the second. A new constant [`WRITE_SHADOW = true`](scenes/codegen_md.gd) controlled shadow emission, with [`SHADOW_CODE_ADR = 30000`](scenes/codegen_md.gd) and [`SHADOW_STACK_ADR = 50000`](scenes/codegen_md.gd) serving as base addresses for the two shadow memory regions — separate from the real code and stack, so shadow metadata never interfered with program execution. Each shadow update consumed `shadow_update_size = cmd_size * 50 = 400` bytes. A subtle but important change: the `INDEX` op was modified from `add %a, %b` to `mul %b, 4; add %a, %b` — multiplying the index by 4 to perform byte-addressed 32-bit cell access. And [`alloc_temporary()`](scenes/codegen_md.gd) was fixed to append temp handles to `cur_scope.vars`, ensuring temporaries appeared in the local variable list.

Every stack operation was instrumented:

- **Function entry**: The saved base pointer (`PREV_EBP`) and return address (`PREV_IP`) were marked with their shadow types
- **Argument pushes**: Each function argument was marked as `SHADOW_FRAME_ARGUMENT`
- **Local variable allocation**: Each local variable slot was marked as `SHADOW_FRAME_VAR`
- **Temporary slots**: Compiler-generated temporaries were marked as `SHADOW_FRAME_TEMP`
- **Alignment padding**: Any padding bytes inserted for alignment were marked as `SHADOW_FRAME_PADDING`

The memory viewer ([`scenes/Memory.gd`](scenes/Memory.gd)) grew by 55 lines across the two commits to render these new shadow types with distinct colors. A new [`interp_numbers()`](scenes/Memory.gd) function added a numeric column showing 4-byte groups decoded as u32 integers — letting the developer read raw memory as actual values. The [`shadow_colors`](scenes/Memory.gd) dictionary was expanded with six new color entries: RED for `PREV_EBP`, CYAN for `PREV_ESP`, ORANGE for arguments, YELLOW for variables, PURPLE for temporaries, and DARK_BLUE for padding. Each region of the stack became visually identifiable — the saved frame pointer in red, the argument list in orange, local variables in yellow, compiler temporaries in purple, and alignment padding in dark blue. The developer could look at the memory view and see the entire stack frame structure at a glance:

```
| Address | Value    | Shadow Type          |
|---------|----------|----------------------|
| 0xFFA0  | 0xFFC0   | FRAME_PREV_EBP      |  ← saved base pointer
| 0xFFA4  | 0x1234   | FRAME_PREV_IP       |  ← return address
| 0xFFA8  | 0x0042   | FRAME_ARGUMENT      |  ← function argument
| 0xFFAC  | 0x0000   | FRAME_VAR           |  ← local variable
| 0xFFB0  | 0x0000   | FRAME_TEMP          |  ← temporary
```

The shadow stack transformed the debugger from a raw memory inspector into a structured call-frame visualizer. The developer could now step through function calls and see the stack frames build and unwind with their roles clearly labeled.

---

### Arrays Mostly Work

Commit [`d59611f`](https://github.com/) — "arrays mostly work" — was a milestone.

The code generator ([`codegen_md.gd`](scenes/codegen_md.gd)) gained 24 lines of array-related fixes. The debug panel ([`debug_panel.gd`](debug_panel.gd)) gained 6 lines for array display in the local variables view.

But the real evidence was in the test operating system. [`res/data/testOS/main.md`](res/data/testOS/main.md) exploded from roughly 100 lines to 154 lines — a major expansion that exercised arrays heavily:

```c
var buff[80];
var buffI = 0;
```

The testOS now declared a character buffer array, using it to store keyboard input, process commands, and pass strings between functions. Array indexing was used throughout:

```c
buff[buffI] = c;
buffI++;
```

The operating system was no longer a toy. It had a command buffer, string processing functions like [`str_eq`](res/data/testOS/main.md:8) and [`str_len`](res/data/testOS/main.md:9) and [`str_rev`](res/data/testOS/main.md:10), number printing via [`printnum`](res/data/testOS/main.md:13), and a command loop that read keyboard input and dispatched actions.

"Mostly" worked, not "completely" worked. The commit message was honest. Some array edge cases remained broken — nested array access, array return values, multi-dimensional arrays. But the core feature was functional. The developer could write, compile, and run programs that used arrays.

---

### The Final State

Two commits closed out the project history.

Commit [`950b1cb`](https://github.com/) — "merged" — was a merge commit with no net code changes. A branch had been integrated, but the diff was empty. Perhaps it was a workflow cleanup, perhaps a branch that had already been cherry-picked.

Commit [`833801`](https://github.com/) — "small fixes, something still broken on compile" — was the final entry in the commit log. The message was characteristic: honest, direct, unpolished.

The changes touched five core files:

- [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — +6/-1 lines of small codegen fixes
- [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — +14/-1 lines of analyzer adjustments
- [`scenes/ir_md.gd`](scenes/ir_md.gd) — +2/-1 lines of IR tweaks
- [`class_CodeBlock.gd`](class_CodeBlock.gd) — +1/-1 line of class refinement
- [`error_list.gd`](error_list.gd) — +1/-1 line of error message updates

Small changes across the compiler stack. The kind of changes you make when you're hunting a bug that you can't quite find. The "something still broken on compile" admission — not "fixed compile error" but "still broken" — captured the developer's relationship with the project. The work was never finished. There was always one more bug, one more feature, one more thing that didn't quite work.

---

### The State of the Machine

As the commit log falls silent, let us survey what has been built.

**The Virtual Computer** runs inside the Godot engine, but it is no less real for being virtual. The ZVM has:

- A 64K address space with byte-addressable memory ([`RAM_64k.gd`](scenes/RAM_64k.gd))
- A 32-bit CPU with 14 registers (EAX, EBX, ECX, EDX, IP, ESP, ESZ, ESS, EBP, IVT, IVS, IRQ, CTRL) defined in [`lang_zvm.gd`](lang_zvm.gd:4-11)
- A 34-opcode instruction set spanning control, memory, ALU arithmetic, ALU logic, and bitwise operations ([`lang_zvm.gd`](lang_zvm.gd:81-127))
- A fetch-decode-execute loop in [`CPU_vm.gd`](scenes/CPU_vm.gd) that can run forward and backward
- An interrupt system with an interrupt vector table
- Comparison flags (CMP_L, CMP_G, CMP_Z, CMP_NZ) for conditional execution
- Shadow memory tracking every byte's role and access pattern

**The Two-Language Compiler Pipeline** transforms high-level MiniDerp source into executable ZDerp assembly:

- **Tokenizer** ([`md_tokenizer.gd`](scenes/md_tokenizer.gd)) — Converts source text into tokens, handling keywords, operators, string literals, character literals, comments, and preprocessor directives
- **Parser** ([`parser_md.gd`](scenes/parser_md.gd)) — Shift-reduce LR parser applying 176 grammar rules from [`lang_md.gd`](scenes/lang_md.gd)
- **Analyzer** ([`analyzer_md.gd`](scenes/analyzer_md.gd)) — Semantic analysis with symbol resolution, type checking, arity validation, error reporting via 58 error codes
- **IR** ([`ir_md.gd`](scenes/ir_md.gd)) — Intermediate representation with typed values, commands, and code blocks
- **Code Generator** ([`codegen_md.gd`](scenes/codegen_md.gd)) — Translates IR to ZDerp assembly with shadow stack instrumentation
- **Assembler** ([`comp_asm_zd.gd`](scenes/comp_asm_zd.gd)) — Assembles ZDerp source to machine code with reference resolution and patching

**The Visual Debugger** ([`debug_panel.gd`](debug_panel.gd), ~1,000+ lines) provides:

- Source-level stepping with line highlighting in MiniDerp code
- Register state display (all 14 registers)
- Memory viewer with shadow-type color coding
- Stack frame visualization showing arguments, locals, temporaries, and saved frame pointers
- Forward and backward execution at controllable speed
- High-level local variable inspection with type and value display

**The Editor and IDE** ([`Editor.gd`](scenes/Editor.gd), [`comp_file.gd`](scenes/comp_file.gd), [`comp_search.gd`](scenes/comp_search.gd)) provides:

- Multi-tab editing with syntax highlighting for both MiniDerp and ZDerp
- File management (open, save, close)
- Text search across open files
- Build console with status messages and error reporting
- Language auto-detection from file extension

**The MiniDerp Language** supports 22 defined syntax constructs:

- Declarations: variable, function, extern, typed, array
- Assignment: simple, compound (+=, -=, *=, /=, %=)
- Control flow: while, if/elif/else, break, continue, return
- Expressions: arithmetic, comparison, logical, bitwise, indexing, calls (direct and indirect), literals (number, string, character, array)
- Preprocessor: #include for modular code
- Type system: int, char, float, double, u8/u16/u32/u64, s8/s16/s32/s64, Ref, String

**The Test Operating System** ([`res/data/testOS/main.md`](res/data/testOS/main.md), 251 lines) is the project's crowning test case — a command-line shell with keyboard input, screen output, string processing, number formatting, and command dispatch, all running on the custom ZVM.

**The Documentation Suite** includes:

- 3 documentation files in [`docs/`](docs/): TODO list, implementation master plan, syntax reference
- 11 plan files in [`plans/`](plans/): detailed implementation plans for 8 completed features, plus 3 forward-looking plans for debug panel pointers, DFA parser, and array refinements
- 1 diagnosis document ([`docs/diagnosis_array_literal.md`](docs/diagnosis_array_literal.md)): formal bug analysis
- 3 narrative chapters covering the entire development story

---

### An Open Ending

The commit log ends with a broken compile. The TODO list still has unchecked items: arrays need completion, the debug panel could show pointers, the parser could be rewritten as a DFA. The project is not finished — it is *active*.

The contraption sits in the scenes directory, waiting. The 1,013-line DFA parser plan waits to be implemented. The array diagnosis document lists symptoms that may or may not have been fixed. The "something still broken" message is the project's last word — for now.

This is the nature of projects like CpuDerp. They are never complete. They are abandoned, revisited, refactored, rebooted. The developer who wrote "codegen's fucked" and then fixed it, who planned eight features and implemented them in seven commits, who built a virtual computer inside a game engine and a two-language compiler to program it — that developer will be back.

The CPU will run again. The shadows will deepen. The contraption will reveal its purpose.

The commit log is silent, but the machine hums.

---

*End of Chapters 7–8. The CpuDerp development narrative continues beyond the recorded commit history.*
