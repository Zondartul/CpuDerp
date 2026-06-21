# Implementation Plan: Compound Assignment Operators (`+=`, `-=`, `*=`, `/=`, `%=`)

## Overview

Implement `x += 5;` as syntactic sugar for `x = x + 5;`. The approach is **analyzer-level desugaring with grammar rules for dispatch** — the parser recognizes each compound operator via distinct grammar rules, and the analyzer emits IR for the equivalent read-modify-write sequence.

## Design Decision

**Analyzer-level desugaring** with mandatory grammar rules:

- **Grammar rules** are REQUIRED because the parser's `token_match()` at [`scenes/parser_md.gd:111`](scenes/parser_md.gd:111) does exact text comparison for `/`-prefixed rules. Rule `["expr", "/=", ...]` checks `tok.text == "="` and therefore FAILS for `+=` (text is `"+="`). Each compound operator needs its own rule.
- **Desugaring** happens in the analyzer: when `+=` is encountered in `analyze_assignment_stmt()`, emit `OP ADD lhs, rhs, tmp` + `MOV lhs, tmp` instead of just `MOV lhs, rhs`.
- **No codegen changes** — desugared IR uses existing `MOV` and `OP` codegen paths.

## Files to Modify

### 1. `scenes/md_tokenizer.gd` — Add 3 recombinations

The `recombinations` array (line 10-14) already has `["+", "="]` and `["-", "="]` for `+=` and `-=`. Missing entries for `*=`, `/=`, `%=`:

```gdscript
const recombinations = [
    ["#", "/*"], ["+", "+"], ["-", "-"], ["+", "="], ["-", "="],
    ["!", "="], ["=", "="],
    ["*", "="], ["/", "="], ["%", "="],      # NEW
    ["/WORD", "/NUMBER"], ["/NUMBER", ".", "/NUMBER"],
];
```

Without these, `x *= 5` tokenizes as `[x] [OP:*] [PUNCT:=] [5]` — two separate tokens that the grammar cannot match as a single compound operator.

### 2. `scenes/lang_md.gd` — Add 5 grammar rules

Replace the single assignment rule with 6 rules (one plain `=`, five compound):

```gdscript
#-- assignment_stmt (compound operators desugared in analyzer)
["expr", "/=", "expr",  ";", "assignment_stmt"],
["expr", "/+=", "expr", ";", "assignment_stmt"],
["expr", "/-=", "expr", ";", "assignment_stmt"],
["expr", "/*=", "expr", ";", "assignment_stmt"],
["expr", "//=", "expr", ";", "assignment_stmt"],
["expr", "/%=", "expr", ";", "assignment_stmt"],
```

**Why this works**: The parser's `token_match()` for `/+=` checks `ref.substr(1)` = `"+="` against `tok.text == "+="` — exact match for the `+=` PUNCT token. Each rule is mutually exclusive since each matches a different operator text. All produce `assignment_stmt` as the result, with the specific operator preserved in AST children.

### 3. `scenes/analyzer_md.gd` — Core desugaring logic

**Add** `compound_op_map` constant (near the existing `op_map` at line 18):

```gdscript
const compound_op_map = {
    "+=":"ADD",
    "-=":"SUB",
    "*=":"MUL",
    "/=":"DIV",
    "%=":"MOD",
};
```

**Modify** `analyze_assignment_stmt()` (line 365-389):

Current flow:
1. Evaluate LHS (variable handle or expression)
2. Evaluate RHS expression
3. Emit `MOV LHS, RHS`
4. Push RHS onto expr_stack

New flow:
```gdscript
func analyze_assignment_stmt(ast):
    ...
    var op_tok = ast.children[1];
    var op_text = op_tok.text;
    
    # LHS evaluation (unchanged)
    ...
    
    # RHS evaluation (unchanged)
    analyze_expr(rhs_expr);
    var RHS = expr_stack.pop_back();
    
    if op_text == "=":
        IR.emit_IR(["MOV", LHS, RHS], ast.get_location());
        expr_stack.push_back(RHS);
    elif op_text in compound_op_map:
        var ir_op = compound_op_map[op_text];
        var tmp = IR.new_val_temp();
        IR.save_variable(tmp);
        IR.emit_IR(["OP", ir_op, LHS, RHS, tmp], ast.get_location());
        IR.emit_IR(["MOV", LHS, tmp], ast.get_location());
        expr_stack.push_back(tmp);
    else:
        erep.error(E.ERR_31 % op_text);
```

**Why `compound_op_map` is separate from `op_map`**: Compound operators are never used in `expr_infix` context — they only appear in `assignment_stmt`. The existing `op_map` maps plain infix operators like `+` → `"ADD"`. The `compound_op_map` maps `+=` → `"ADD"` so the same codegen path is reused.

### 4. `scenes/codegen_md.gd` — No changes needed

Reuses existing codegen for:
- **`MOV`** → `generate_cmd_mov()` (line 277): `mov ^dest, $src;`
- **`OP ADD/SUB/MUL/DIV/MOD`** → `generate_cmd_op()` (line 287): loads args, applies op, stores result

### 5. `scenes/ir_md.gd` — No changes needed

`emit_IR()`, `new_val_temp()`, `save_variable()` all exist and work for the new IR commands.

## Pipeline Flow

```
Source: x += 5;
  ↓ Tokenizer (recombine `+` + `=` into `+=`)
[IDENT:x] [PUNCT:+=] [NUMBER:5] [PUNCT:;]
  ↓ Parser (rule: ["expr", "/+=", "expr", ";", "assignment_stmt"])
AST: (assignment_stmt (expr (expr_ident x)) (OP:+=) (expr (expr_immediate 5)))
  ↓ Analyzer (compound_op_map["+="] → "ADD"; emit OP + MOV)
IR:  OP ADD x_var, imm_5, tmp_1
     MOV x_var, tmp_1
  ↓ Codegen (existing OP/MOV paths)
Assembly: mov eax, $x_var;   # load x
          mov ebx, $imm_5;   # load 5
          add eax, ebx;      # x + 5
          mov ^x_var, eax;   # store back
```

## Edge Cases

| Case | Behavior |
|------|----------|
| `x += 5` (simple var) | Works. LHS variable handle obtained via `IR.get_var()`, used for both OP source and MOV dest. |
| `var x += 5` (decl-assign) | Works. `analyze_decl_assignment` calls `analyze_assignment_stmt`. Variable zero-initialized, then `0 + 5 = 5`. |
| `x = y += 5` (chaining) | **Not supported.** Compound assignments don't produce expr values. Results in parse error. |
| `arr[I] += 5` (array index LHS) | **Known limitation.** The `needs_deref` flag on INDEX result causes issues when the result is used as OP source. Workaround: write `arr[I] = arr[I] + 5`. |
| `x $= 5` (unknown operator) | Falls through to `else` branch → error `ERR_31`. |
| `x++` vs `x += 1` | `x++` → `OP INC x none tmp` (postfix). `x += 1` → `OP ADD x, 1, tmp; MOV x, tmp`. Both correctly increment `x`. |

## Test Cases

1. **All 5 operators**: `x += 5; x -= 3; x *= 2; x /= 4; x %= 3;`
2. **Declaration with compound**: `var x += 10;` → `x == 10`
3. **Multiple compounds in sequence**: `x = 10; x += 5; x *= 2;` → `x == 30`
4. **Compound with expression RHS**: `x += y * 2;`
5. **Array index LHS** (known limitation — test for no crash, not correct result)

## Summary

| File | Change |
|------|--------|
| `scenes/md_tokenizer.gd` | Add `["*", "="]`, `["/", "="]`, `["%", "="]` to `recombinations` |
| `scenes/lang_md.gd` | Add 5 grammar rules for compound operators |
| `scenes/analyzer_md.gd` | Add `compound_op_map` + modify `analyze_assignment_stmt()` |
| `scenes/codegen_md.gd` | No change |
| `scenes/ir_md.gd` | No change |
