# Implementation Plan: Character Literals (`'a'`, `'\n'`)

## Design Decision

Char literals are treated as **integer immediates** (ASCII byte values). A char like `'a'` resolves to 97 and flows through the entire pipeline as an integer — no new IR types, no new codegen data paths.

---

## Files to Modify

### 1. `scenes/word_boundary_tokenizer.gd`

- **`tok_ch_class()`**: Add `if ch == "'": return "CHAR"` before the ERROR fallback.
- **`should_split_on_transition()`**: Add CHAR rules mirroring STRING:
  - `old_tok_class == "CHAR" and new_tok_class == "CHAR"` → `return true` (split on opening/closing quote)
  - `old_tok_class == "CHAR"` → `return false` (keep accumulating content between quotes)
- **End-of-char split**: On CHAR→CHAR transition, set `new_tok_class = "ENDCHAR"` and strip the leading quote from `cur_tok`, following the identical STRING pattern already in the code.

### 2. `scenes/md_tokenizer.gd`

- **`filter_tokens()`**: Add `"ENDCHAR"` to the filtered list alongside `"SPACE"` and `"ENDSTRING"`.
- **`token_colors`**: Add `"CHAR": Color(1.0, 1.0, 0.0, 1.0)` — reuse the NUMBER color since chars resolve to integers.
- **New function `resolve_char_tokens(tokens)`**: A post-processing step that walks all tokens and converts CHAR tokens to NUMBER tokens with the resolved ASCII value as text. Called after `reclassify_tokens()` and before `filter_tokens()` in the `tokenize()` pipeline.
  - Validates that CHAR text is exactly 1 character long after escape resolution
  - Resolves escape sequences: `\n`→10, `\t`→9, `\r`→13, `\0`→0, `\\`→92, `\'`→39, `\"`→34
  - On validation failure, reports errors (empty char `''`, multi-char `'ab'`, unknown escape `'\x'`)

**Escape resolution algorithm (inside `resolve_char_tokens`)**:
```
if raw_text.length() == 1:
    return ord(raw_text)          # plain char like 'a' → 97
elif raw_text.length() == 2 and raw_text[0] == "\\":
    return lookup_escape(raw_text[1])  # escape like '\n' → 10
else:
    error("invalid char literal")
```

### 3. `scenes/lang_md.gd`

- Add one grammar rule to the `rules` array:
  ```gdscript
  ["CHAR", "*", "expr_immediate"],
  ```
  This goes alongside the existing `["NUMBER", "*", "expr_immediate"]` and `["STRING", "*", "expr_immediate"]` rules at line 89-90.

### 4. `scenes/analyzer_md.gd`

- In `analyze_expr_immediate()` (around line 391), add a CHAR case:
  ```gdscript
  if tok.tok_class == "CHAR":
      value = str(ord(tok.text))
      type = "int"
  ```
  This produces an integer immediate IR value identical to what NUMBER literals produce. No other analyzer changes needed.

### 5. `scenes/error_list.gd` (optional)

- Add an error constant for invalid char literals, e.g.:
  ```gdscript
  const ERR_33 = "Error 33: Invalid character literal: [%s]";
  ```

### 6. `docs/miniderp_syntax.md`

- Document char literal syntax under "6. Expressions"
- List supported escape sequences

---

## Files NOT Changed

- **`scenes/ir_md.gd`**: No changes. Char immediates use `new_val_immediate(ascii_value, "int")` — existing infrastructure.
- **`scenes/codegen_md.gd`**: No changes. Integer immediates already flow through the existing allocation and code generation paths. Must verify but expect zero modifications.
- **`scenes/comp_asm_zd.gd`**: No changes. The assembler's `emit_db_items` already handles NUMBER tokens for `db` directives.

---

## Test Plan

**Valid inputs**:
- `'a'` → 97, `'A'` → 65, `'0'` → 48, `' '` → 32
- `'\n'` → 10, `'\t'` → 9, `'\r'` → 13, `'\0'` → 0
- `'\\'` → 92, `'\''` → 39, `'\"'` → 34

**Usage in expressions**:
- `var c = 'a';` — declaration with char init
- `x = 'a';` — assignment
- `if (c == 'a') {}` — comparison
- `putch('x');` — function argument
- `return 'A';` — return value

**Error cases**:
- `''` — empty char literal
- `'ab'` — multi-char literal
- `'\x'` — unknown escape sequence
- Unterminated/open quote patterns

---

## Pipeline Flow Diagram

```
Source: `x = 'a';`
  ↓ word_boundary_tokenizer: tok_ch_class() returns CHAR for '
  ↓                          CHAR token created with text="a" (quotes stripped)
  ↓ md_tokenizer: resolve_char_tokens() → ord('a') = 97, converts to NUMBER token "97"
  ↓                filters out ENDCHAR tokens
  ↓ lang_md: grammar rule ["CHAR", "*", "expr_immediate"]
  ↓           (but after conversion to NUMBER, it hits ["NUMBER", "*", "expr_immediate"])
  ↓ parser: reduces NUMBER → expr_immediate → expr
  ↓ analyzer: analyze_expr_immediate → new_val_immediate("97", "int")
  ↓ codegen: existing int immediate path → assembly
```
