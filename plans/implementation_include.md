# Implementation Plan: `#include` Directive

## Overview

The `#include "filename"` directive should insert the contents of the referenced file into the current compilation unit. Currently parsed into the AST as `preproc_stmt`, but `analyze_preproc_stmt()` is a no-op (`pass`).

**Core decision**: Handle include resolution at the **tokenizer level** via text insertion **before** line-by-line tokenization. The parser and analyzer never see `#include` directives — they are expanded away in preprocessing.

---

## Pipeline Flow

```
Source text:                           process_includes()           basic_tokenize()
  #include "foo.txt"          ──→      expanded text        ──→    tokens
  var x = 5;                           // contents of foo.txt
                                        var x = 5;
```

The tokenizer's `preproc()` function already handles comment removal per-line. Adding `#include` resolution as a pre-tokenization step is a natural extension.

---

## Design Decisions

### 1. When Inclusion Happens

In `md_tokenizer.gd`, the `tokenize()` function:

```
1. text = process_includes(text, cur_path)    ← NEW
2. tokens = basic_tokenize(text)
3. recombine_tokens(tokens)
4. reclassify_tokens(tokens)
5. filter_tokens(tokens)
```

`process_includes()` scans for lines matching `#include "..."`, loads referenced files, splices in their contents, and recurses into loaded files to resolve their own includes.

### 2. Path Resolution

Priority order:
1. **Relative to including file's directory**: e.g. `cur_path` + filename
2. **Default include directory**: `res://res/data/` as fallback

**Critical fix**: In `comp_build.gd`, the line `n_compiler.cur_path = cur_efile.path` is **commented out** — must be uncommented so the tokenizer knows where the source file lives.

If `cur_path` is empty, fall back to `res://res/data/`.

**Path resolution helper** (new function in `md_tokenizer.gd`):
```gdscript
func resolve_include_path(include_name: String, base_path: String) -> String:
    var base_dir = base_path.get_base_dir()
    var candidate = base_dir.path_join(include_name)
    if FileAccess.file_exists(candidate):
        return candidate
    candidate = "res://res/data/".path_join(include_name)
    if FileAccess.file_exists(candidate):
        return candidate
    return ""
```

### 3. Recursive Includes & Cycle Detection

Add `_included_files: Array[String]` to tokenizer state (reset in `reset()`).

For each include:
1. Resolve to canonical path
2. If already in `_included_files` → skip silently (handles cycles AND duplicate includes)
3. Otherwise add to `_included_files`, load file
4. Recursively `process_includes()` on loaded text with new base path
5. Replace include line with expanded text

This handles: `A→B→A` cycles, `A→B→B` duplicates, `A→B→C` transitive includes.

### 4. Language Mismatch (`.zd` in `.md` files)

No special handling. Textual insertion means zderp assembly included in miniderp will naturally fail at parse time with normal syntax errors. The existing `.zd` library files use zderp's `@include`, not miniderp's `#include` — they remain independent.

### 5. Already-Included Guards

`_included_files` prevents double-inclusion within a single compilation unit. Each `tokenize()` call gets a fresh `_included_files` (reset), so separate compilation units are independent.

### 6. Error Handling

| Scenario | Behavior |
|----------|----------|
| File not found | Set `error_code`, stop compilation: `#include "foo.txt": file not found` |
| Circular include | Silently skipped (already in `_included_files`) |
| Malformed line | `#include: expected "filename"` |
| Commented-out include | Skipped: `process_includes` checks for `//` prefix |

### 7. Scope of Includes

**Textual insertion** — no scope boundaries. Included code shares the same scope as the including file (C preprocessor semantics). Variables/functions declared in included files are accessible from the including file.

### 8. Grammar Rule & Analyzer

The grammar rule in `lang_md.gd:77` (`["/#include", "STRING", "*", "preproc_stmt"]`) and `analyze_preproc_stmt` in `analyzer_md.gd:261` (currently `pass`) are **unchanged**. Since includes are resolved at tokenization, these rules are never triggered during normal compilation. They remain for documentation and potential future preprocessor directives.

---

## Files to Modify

### File 1: `scenes/md_tokenizer.gd` — Core implementation

**State**: Add `var _included_files: Array[String] = []`

**`reset()`**: Add `_included_files = []`

**New `process_includes(text, base_path)` → String**:
1. Split text into lines
2. For each line, detect `#include "..."` pattern (simple string check)
3. Skip lines starting with `//`
4. Extract filename between quotes
5. Resolve full path via `resolve_include_path()`
6. Check `_included_files` — skip if already included
7. Load file with `FileAccess.get_file_as_string()`
8. Recursively process loaded text
9. Replace the include line with expanded text
10. Rejoin and return

**`tokenize()`**: Add `text = process_includes(text, cur_path)` before `basic_tokenize(text)`. Check `error_code` and return early on failure.

### File 2: `scenes/comp_build.gd` — Fix path propagation

Uncomment line 49: `n_compiler.cur_path = cur_efile.path` inside `compile_miniderp()`.

### File 3: `docs/miniderp_syntax.md` — Documentation

Update the Include Directive section with path resolution rules, include guard behavior, and error behavior.

### Files Not Modified

- `scenes/analyzer_md.gd` — `analyze_preproc_stmt` stays as `pass`
- `scenes/lang_md.gd` — grammar rule kept for documentation
- `scenes/comp_compile_md.gd` — pipeline unchanged
- `scenes/parser_md.gd` — never sees include directives

---

## Test Scenarios

| Test | Input | Expected |
|------|-------|----------|
| Basic include | `#include "lib.inc"` with `var x = 5;` | `var x = 5;` is compiled as if inline |
| Missing file | `#include "nope.txt"` | Compiler error: file not found |
| Circular include | A→B→A | Second include silently skipped |
| Duplicate include | A includes B twice | Second skip |
| Relative path | `#include "lib/helper.txt"` | Resolved relative to source directory |
| Commented include | `// #include "x.txt"` | Skipped (treated as comment) |

## Edge Cases

- **`cur_path` unset**: Fall back to `res://res/data/`
- **`#include` inside comments**: `process_includes` checks for `//` prefix, skips
- **Angle bracket includes** (`#include <file>`): Not supported (only `"file"` syntax)
- **Performance**: Small library files only; `_included_files` prevents redundant loading
- **`asm_screen.txt`**: Referenced by test files but doesn't exist — needs creation or test updates
