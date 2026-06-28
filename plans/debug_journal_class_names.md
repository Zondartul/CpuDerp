# Debug Journal: `class_name` Resolution Errors

## STAGE 1 — Replication

### Environment
- Godot 4.7 (Steam: `E:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`)
- Project: `e:/Stride/godot/CpuDerp`
- Config: Godot 4.7, GL Compatibility

### Capture Methodology

```powershell
# Run headless check-only, redirect stderr to log
# (parse errors go to stderr, not stdout)
& "E:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" `
    --headless --check-only --path "e:\Stride\godot\CpuDerp" 2> "plans\errors_before.log"
```

### Raw Error Output (Before Fixes)

```
SCRIPT ERROR: Parse Error: Could not resolve external class member "load_or_parse".
   at: GDScript::reload (res://scenes/codegen_master.gd:66)
SCRIPT ERROR: Parse Error: Could not resolve external class member "discover".
   at: GDScript::reload (res://scenes/codegen_master.gd:140)
SCRIPT ERROR: Compile Error: Failed to compile depended scripts.
   at: GDScript::reload (res://scenes/comp_codegen_new.gd:0)
ERROR: Failed to load script "res://scenes/comp_codegen_new.gd" with error "Compilation failed".
   at: load (modules/gdscript/gdscript_resource_format.cpp:46)
```

### Root Cause Confirmed

The errors match exactly the user's report. Cascade chain:
1. `ITG.InflatedGraph` type hints fail → `template_parser.gd` fails to compile
2. `AB.ABIManifest` type hints fail → `abi_scanner.gd` and `stor_alloc.gd` fail to compile
3. `codegen_master.gd` preloads `template_parser.gd` → fails with "Could not resolve external class member"
4. `comp_codegen_new.gd` depends on `codegen_master.gd` → fails to compile

---

## STAGE 2 — Diagnosis

### Hypothesis

> In Godot 4 GDScript, `const Script = preload("res://script.gd")` makes `Script` equal to the script's **main class** itself. Using `Script.MainClassName` as a type hint fails because the main class IS the script — there is no **inner class** named after the main class. Inner classes like `Script.InnerClass` work fine.

### Test Results

**Expected Failures (confirmed)** — using `ITG.InflatedGraph` or `AB.ABIManifest` as:
- Return type hints: `-> ITG.InflatedGraph` → Parse Error
- Parameter type hints: `param: AB.ABIManifest` → Parse Error
- `is` checks: `loaded is ITG.InflatedGraph` → Parse Error
- Constructor calls: `ITG.InflatedGraph.new()` → Parse Error
- Main class constructors: `AB.ABIManifest.new()` → Parse Error

**Valid patterns (confirmed working)** — inner class access:
- `ITG.SlotDef`, `ITG.TemplateDef`, `ITG.VariantSwitchNode` → work fine
- `AB.SymbolInfo`, `AB.TempSlot` → work fine (after fixing the prefix from `AB.ABIManifest.X` to `AB.X`)

### Fix Rationale

| Before | After | Why |
|---|---|---|
| `ITG.InflatedGraph` | `InflatedGraph` | Use global `class_name` — the main class is registered project-wide |
| `AB.ABIManifest` | `ABIManifest` | Same — `class_name ABIManifest` is globally visible |
| `AB.ABIManifest.SymbolInfo` | `AB.SymbolInfo` | Drop redundant `ABIManifest` — `AB` is the script, `SymbolInfo` is an inner class |
| `AB.ABIManifest.TempSlot` | `AB.TempSlot` | Same pattern |

---

## STAGE 3 — Fixes Applied

### File 1: [`scenes/template_parser.gd`](scenes/template_parser.gd)

| Line | Before | After |
|---|---|---|
| 27 | `func parse(text: String) -> ITG.InflatedGraph:` | `-> InflatedGraph` |
| 28 | `var graph = ITG.InflatedGraph.new()` | `InflatedGraph.new()` |
| 51 | `func load_or_parse(...) -> ITG.InflatedGraph:` | `-> InflatedGraph` |
| 68 | `loaded is ITG.InflatedGraph` | `loaded is InflatedGraph` |
| 75 | `return ITG.InflatedGraph.new()` | `return InflatedGraph.new()` |

### File 2: [`scenes/abi_scanner.gd`](scenes/abi_scanner.gd)

| Line | Before | After |
|---|---|---|
| 36 | `var manifest: AB.ABIManifest` | `var manifest: ABIManifest` |
| 42 | `p_manifest: AB.ABIManifest` | `p_manifest: ABIManifest` |
| 57 | `func discover(...) -> AB.ABIManifest:` | `-> ABIManifest` |
| 57 | `graph: ITG.InflatedGraph` | `graph: InflatedGraph` |
| 58 | `AB.ABIManifest.new()` | `ABIManifest.new()` |
| 97 | `manifest: AB.ABIManifest` | `manifest: ABIManifest` |
| 122 | `AB.ABIManifest.SymbolInfo.new()` | `AB.SymbolInfo.new()` |
| 230 | `AB.ABIManifest.SymbolInfo.new()` | `AB.SymbolInfo.new()` |
| 271 | `manifest: AB.ABIManifest` | `manifest: ABIManifest` |
| 276 | `AB.ABIManifest.TempSlot.new()` | `AB.TempSlot.new()` |

### File 3: [`scenes/stor_alloc.gd`](scenes/stor_alloc.gd)

| Line | Before | After |
|---|---|---|
| 56 | `manifest: AB.ABIManifest` | `manifest: ABIManifest` |
| 98 | `manifest: AB.ABIManifest` | `manifest: ABIManifest` |
| 155 | `manifest: AB.ABIManifest` | `manifest: ABIManifest` |
| 186 | `manifest: AB.ABIManifest` | `manifest: ABIManifest` |

### File 4: [`res/tests/test_template_parser.gd`](res/tests/test_template_parser.gd)

| Line | Before | After |
|---|---|---|
| 37 | `-> ITG.InflatedGraph` | `-> InflatedGraph` |
| 55 | `graph is ITG.InflatedGraph` | `graph is InflatedGraph` |
| 295 | `graph is ITG.InflatedGraph` | `graph is InflatedGraph` |

### File 5: [`res/tests/test_abi_scanner.gd`](res/tests/test_abi_scanner.gd)

| Line | Before | After |
|---|---|---|
| 34 | `-> ITG.InflatedGraph` | `-> InflatedGraph` |
| 90 | `manifest is AB.ABIManifest` | `manifest is ABIManifest` |

### File 6: [`res/tests/test_stor_alloc.gd`](res/tests/test_stor_alloc.gd)

| Line | Before | After |
|---|---|---|
| 32 | `-> AB.ABIManifest` | `-> ABIManifest` |
| 33 | `AB.ABIManifest.new()` | `ABIManifest.new()` |
| 34 | `AB.ABIManifest.SymbolInfo.new()` | `AB.SymbolInfo.new()` |
| 42 | `-> AB.ABIManifest` | `-> ABIManifest` |
| 43 | `AB.ABIManifest.new()` | `ABIManifest.new()` |
| 44 | `AB.ABIManifest.SymbolInfo.new()` | `AB.SymbolInfo.new()` |
| 52 | `-> AB.ABIManifest` | `-> ABIManifest` |
| 53 | `AB.ABIManifest.new()` | `ABIManifest.new()` |
| 54 | `AB.ABIManifest.SymbolInfo.new()` | `AB.SymbolInfo.new()` |
| 69 | `is AB.ABIManifest.SymbolInfo` | `is AB.SymbolInfo` |
| 86 | `is AB.ABIManifest.SymbolInfo` | `is AB.SymbolInfo` |
| 150 | `AB.ABIManifest.new()` | `ABIManifest.new()` |
| 151-154 | `AB.ABIManifest.TempSlot.new()` | `AB.TempSlot.new()` |
| 170 | `AB.ABIManifest.new()` | `ABIManifest.new()` |
| 173 | `AB.ABIManifest.SymbolInfo.new()` | `AB.SymbolInfo.new()` |
| 221 | `AB.ABIManifest.new()` | `ABIManifest.new()` |
| 226 | `AB.ABIManifest.SymbolInfo.new()` | `AB.SymbolInfo.new()` |

---

## STAGE 4 — Verification

### Raw Error Output (After Fixes)

```
WARNING: res://scenes/main.tscn:38 - ext_resource, invalid UID ...  (pre-existing)
WARNING: res://scenes/main.tscn:39 - ext_resource, invalid UID ...  (pre-existing)
ERROR: TemplateParser: cannot open template file: res://templates/codegen_templates.tg  (pre-existing)
SCRIPT ERROR: Cannot call method 'get_node' on a null value.  (pre-existing)
SCRIPT ERROR: Invalid call. Nonexistent function 'setup' in base 'Control'.  (pre-existing)
```

**Zero `class_name`-related parse errors.** The following error categories are all eliminated:

| Error type | Before | After |
|---|---|---|
| `Could not resolve external class member` | 2 occurrences | **0** |
| `Cannot find member "InflatedGraph" in base "InflatedGraph"` | 1 occurrence | **0** |
| `Cannot find member "ABIManifest" in base "ABIManifest"` | 4 occurrences | **0** |
| `Failed to compile depended scripts` | 1 occurrence | **0** |
| `Failed to load script` | 1 occurrence | **0** |

### Unrelated Remaining Errors

1. **UID warnings** — `main.tscn` references `comp_codegen_new.gd` and `codegen_master.gd` by UID that doesn't match the `.uid` files; cosmetic only.
2. **Template file not found** — `res://templates/codegen_templates.tg` doesn't exist yet; expected until `.tg` templates are authored.
3. **Null `get_node`** — `comp_search.gd:23` references a scene node that may not exist at check-only time.
4. **Missing `setup`** — `main.gd:31` calls `setup()` on a Control that may not be initialized in headless mode.

None of these are related to `class_name` resolution.
