# Implementation Plan: Array Declarations and Literal Array Construction

## Overview

Two features for CpuDerp / MiniDerp:

1. **Part A**: `var arr = [10]` — declares an array of N zero-initialized elements
2. **Part B**: `x = [a, b, c]` — constructs an array literal from element values

Both reuse existing `[`/`]` tokens (no tokenizer changes). The parser's LR(1) algorithm naturally disambiguates `a[i]` (infix indexing) from `[10]` (prefix array literal) by stack context.

---

## Files That Need Changes (6 files)

| File | What to Change |
|------|----------------|
| `scenes/lang_md.gd` | Add 4 grammar rules for `expr_array_literal` |
| `scenes/analyzer_md.gd` | New `analyze_expr_array_literal` handler; modify `analyze_decl_assignment` to detect array-size pattern |
| `scenes/ir_md.gd` | Add `"array_size"` to serialization props list in `serialize_vals` |
| `scenes/codegen_md.gd` | Add `"array_size"` to `inflate_vals` props; add `ALLOC`/`ARRAY` handlers; modify `allocate_value` for multi-word array sizes |
| `scenes/error_list.gd` | Add ERR_33 for invalid array size |
| `docs/miniderp_syntax.md` | Document array syntax |

## Files That Need NO Changes (4 files)

| File | Reason |
|------|--------|
| `scenes/word_boundary_tokenizer.gd` | `[`/`]` already in `ch_punct`, tokenized as PUNCT correctly |
| `scenes/md_tokenizer.gd` | No new tokens needed |
| `scenes/parser_md.gd` | LR(1) engine handles new rules automatically |
| `scenes/comp_asm_zd.gd` | No new assembly instructions |

---

## Part A: `var arr = [10]` — Array Declaration with Size

### A1: Grammar Rules (lang_md.gd)

Add after line ~110 (end of existing rules):

```gdscript
# Array literal expressions (prefix [)
["/[", "expr", "/]",   "*", "expr_array_literal"],
["/[", "expr_list", "/]", "*", "expr_array_literal"],
["/[", "/]",           "*", "expr_array_literal"],    # empty: var arr = []
["expr_array_literal", "*", "expr"],                   # participate in expressions
```

### A2: Parsing Disambiguation

LR(1) naturally distinguishes based on what's on the stack before `[`:

| Input | Stack before `[` | Rule that matches | Result |
|-------|-------------------|-------------------|--------|
| `a[10]` | `... expr` | `expr /[ expr /]` → `expr_infix` | Indexing |
| `[10]` | `... var =` or `... =` | `/[ expr /]` → `expr_array_literal` | Array literal |

For `a[10]`, the infix rule matches because `expr` is already on the stack before `[` is shifted. For `[10]`, no `expr` precedes `[`, so only the prefix rule can match.

### A3: Declaration vs Assignment Distinction

In the analyzer, `var arr = [10]` goes through `analyze_decl_assignment` → detects the RHS is `expr_array_literal` with a single NUMBER child → treats NUMBER as size, not element.

In the analyzer, `x = [10]` goes through `analyze_assignment_stmt` → RHS is `expr_array_literal` → always treated as array construction (single-element array literal).

Detection logic: In `analyze_decl_assignment`, after creating the variable IR handle and calling `analyze_one(stmt_ass)`, check if the RHS expression result indicates an array literal with a single number literal. If so, read that number as the size, set `var_handle.array_size = N`, and emit `ALLOC` (size in bytes) rather than `ARRAY`.

### A4: IR Representation

No new `val_type`. Extend existing `"variable"` by adding an `array_size` field:

```gdscript
var_handle = IR.new_val_var(var_name)
var_handle.array_size = N   # number of elements
var_handle.data_type = "array_int"
```

Serialization in `ir_md.gd` `serialize_vals()` (line 214): add `"array_size"` to the props list.

Deserialization in `codegen_md.gd` `inflate_vals()` (line 106): add `"array_size"` to the props list.

### A5: New IR Command — `ALLOC`

```
ALLOC size_in_bytes variable
```

The analyzer emits:
```gdscript
var size = N * 4  # 4 bytes per element (32-bit word)
var size_imm = IR.new_val_immediate(str(size), "int")
IR.save_variable(size_imm)
IR.emit_IR(["ALLOC", size_imm, var_handle], loc)
```

The codegen handles `ALLOC`:
- **Global scope**: emit `db 0` × (N*4) times in the data section
- **Local (stack) scope**: in `allocate_value`, when `array_size` is set, allocate `array_size * 4` bytes instead of 4

Modifications to `allocate_value` (codegen_md.gd:631):
```gdscript
# If the variable has an array_size, allocate more space
var data_size = 4
if "array_size" in handle and handle.array_size:
	data_size = int(handle.array_size) * 4
# ... rest of existing allocation logic using data_size
```

---

## Part B: `x = [a, b, c]` — Array Literal Construction

### B1: Grammar (same rules as Part A, handled by different analyzer path)

The grammar rules from Part A (`/[ expr /]` and `/[ expr_list /]`) handle all construction patterns. The analyzer distinguishes by context:
- In `analyze_decl_assignment`: allocation (size)
- In `analyze_assignment_stmt` or any expression context: construction

### B2: New IR Command — `ARRAY`

```
ARRAY [elem1 elem2 ... elemN] result
```

Elements are wrapped in `[...]` brackets (same convention as `CALL` args in `ir_md.gd` `serialize_ir_arg`).

### B3: New Analyzer Function — `analyze_expr_array_literal`

Add to `analyze_expr` in the match block:

```gdscript
"expr_array_literal": analyze_expr_array_literal(ch);
```

New function:
```gdscript
func analyze_expr_array_literal(ast):
	assert(ast.tok_class == "expr_array_literal")
	var elements = []

	if len(ast.children) == 0:
		pass  # empty array: []
	elif len(ast.children) == 1 and ast.children[0].tok_class == "expr":
		# Single element: [10] or [x]
		analyze_expr(ast.children[0])
		elements.append(expr_stack.pop_back())
	elif len(ast.children) == 1 and ast.children[0].tok_class == "expr_list":
		# Multiple elements: [a, b, c]
		for child in ast.children[0].children:
			assert(child.tok_class == "expr")
			analyze_expr(child)
			elements.push_front(expr_stack.pop_back())
		elements.reverse()
	else:
		internal_error("Unexpected expr_array_literal structure")
		return

	var res = IR.new_val_temp()
	IR.save_variable(res)
	IR.emit_IR(["ARRAY", elements, res], ast.get_location())
	expr_stack.push_back(res)
```

### B4: Codegen for ARRAY

New handler in `generate_cmd`:

```gdscript
"ARRAY": generate_cmd_array(cmd);
```

`generate_cmd_array`:
1. Extract elements from between `[`...`]` in the IR command words
2. Count N elements
3. Allocate N*4 bytes on the stack (or globally)
4. For each element `j`, emit a store: element value at `base + j*4`
5. The result variable stores the base address (pointer to first element)

This produces assembly like:
```asm
sub ESP, 12        ; for 3 elements
mov EBP[-12], $a   ; element 0
mov EBP[-8], $b    ; element 1
mov EBP[-4], $c    ; element 2
mov ^result, EBP-12 ; result points to base
```

---

## Edge Cases

| Case | Behavior |
|------|----------|
| `var arr = [0]` | Zero-length array (valid) |
| `var arr = [-5]` | Error: negative size |
| `var arr = [10, 20]` | Error: declaration expects single number size |
| `var arr = [x]` (variable) | Error: declaration expects number literal for size |
| `var arr = [];` | Zero-length array (valid) |
| `x = []` | Construct empty array (zero-length allocation, pointer = null or valid base) |
| `x = [a]` | Single-element literal |
| `x = [a, b][i]` | Index into literal result (ARRAY produces temp with base address; INDEX works on it) |
| `f([a, b, c])` | Literal as function argument |
| Nested `[[1, 2], [3, 4]]` | Not supported (arrays of arrays need type system) |

---

## Implementation Order (Recommended)

1. **Grammar** (lang_md.gd): Add 4 rules for `expr_array_literal`
2. **IR serialization** (ir_md.gd, codegen_md.gd): Add `array_size` to prop lists
3. **Analyzer** (analyzer_md.gd):
   - Add `analyze_expr_array_literal` → emits `ARRAY` IR
   - Modify `analyze_decl_assignment` → detect single-number pattern, emit `ALLOC` IR
4. **Codegen** (codegen_md.gd):
   - Add `ALLOC` handler
   - Add `ARRAY` handler
   - Modify `allocate_value` for multi-word array sizes
5. **Error codes** (error_list.gd): Add ERR_33
6. **Test**: Run existing tests, test Part A and Part B

---

## Test Cases

### Part A: `var arr = [N]`

```miniderp
func main() {
	var arr = [10];
	arr[0] = 5;
	arr[9] = 42;
	var x = arr[0];  # 5
	# arr[10] = 1;   # out-of-bounds (VM behavior)
}
```

### Part B: `x = [a, b, c]`

```miniderp
func main() {
	var a = 1; var b = 2; var c = 3;
	var lit = [a, b, c];
	var x = lit[0] + lit[1] + lit[2];  # 6
	var single = [42];
	var empty = [];
}
```

### Mixed

```miniderp
func main() {
	var dest = [3];
	var src = [10, 20, 30];
	dest[0] = src[0];
	dest[1] = src[1];
	dest[2] = src[2];
}
```
