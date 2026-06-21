# Implementation Plan: Calling a Variable as a Function

## Bug Summary

Trying to call a variable as if it were a function (e.g., `f()` where `f` is a variable, not a function name) doesn't compile. The grammar correctly accepts any `expr` as a callee in `expr_call`, but the semantic analyzer and codegen paths assume the callee is always a function handle.

## Root Cause (from memory of reading the code)

1. **Grammar is fine**: [`scenes/lang_md.gd:106-108`](scenes/lang_md.gd:106) — `["expr", "/(", "/)", "*", "expr_call"]` accepts any `expr`, including `expr_ident`. Parsing works correctly.

2. **Analyzer ambiguity**: [`scenes/analyzer_md.gd:417`](scenes/analyzer_md.gd:417) — `analyze_expr_ident()` looks up an identifier first via `IR.get_var()`, then falls back to `IR.get_func()`. When a variable with that name exists, the **variable handle** (val_type="variable") is pushed onto the expression stack. When a function with that name exists (but no variable), a **function handle** (val_type="func") is pushed.

3. **Crash point**: [`scenes/analyzer_md.gd:226`](scenes/analyzer_md.gd:226) — `analyze_expr_call()` pops the callee from the expression stack and blindly emits `["CALL", fun, args, res]`, regardless of whether `fun` is a variable or function handle.

4. **Codegen crash**: [`scenes/codegen_md.gd:432`](scenes/codegen_md.gd:432) — `generate_cmd_call()` accesses `fun_handle.code` to get the code block label. A variable handle has no `code` field, so this crashes.

5. **VM supports it**: [`scenes/CPU_vm.gd:401`](scenes/CPU_vm.gd:401) — `cmd_call()` uses `fetch_dest()`, which resolves register values. `call eax;` works correctly by jumping to whatever address is in EAX. **No VM changes needed.**

6. **Assembler supports it**: [`scenes/comp_asm_zd.gd:450`](scenes/comp_asm_zd.gd:450) — `parse_command()` handles registers as arguments. `call eax;` is valid assembly. **No assembler changes needed.**

## Recommended Approach: Phased Full Indirect Calls

Three incremental phases, each independently testable.

---

## Phase 1: Function Names as First-Class Values

### Problem
When `analyze_expr_ident()` resolves an identifier to a function, it pushes the raw function handle onto the expression stack. This handle has no `storage` field and no `value` field, so codegen's `load_value()` hits a `push_error("unknown storage type")` if anyone tries to use it as a value.

### Fix: [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — `analyze_expr_ident()` at line 417

After `get_func()` finds a function handle, instead of pushing the raw func handle, create a **new immediate value** whose `value` is the function's label/IR name and `data_type` is `"func_ptr"`:

```
# Pseudocode in analyze_expr_ident():
var var_handle = IR.get_var(var_name);
if not var_handle:
    var_handle = IR.get_func(var_name);
    if var_handle:
        # Emit function address as an immediate value
        var imm = IR.new_val_immediate(var_handle.ir_name, "func_ptr");
        imm["code_label"] = var_handle.code;  # reference to the code block
        expr_stack.push_back(imm);
        return;
```

This makes `myFunc` in `var f = myFunc;` resolve to an immediate value containing the function's label, which can be stored into a variable.

### Fix: [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — `load_value()` at line 514

Handle `data_type == "func_ptr"` by returning the function's IR name (which is the code label):

```
if handle.data_type == "func_ptr":
    res = handle.ir_name;  # resolves to the code label
```

### Test Phase 1
```miniderp
myFunc: print 42; return;
main: var f = myFunc; return;
```
Should compile without errors. The variable `f` now holds the address of `myFunc`.

---

## Phase 2: Indirect Call IR + Codegen

### Fix: [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — `analyze_expr_call()` at line 226

After popping the callee from `expr_stack`, check its `val_type`:

- If `val_type == "func"` or `data_type == "func_ptr"`: emit `["CALL", fun, args, res]` (direct, existing path)
- If `val_type == "variable"`: emit `["CALL_INDIRECT", fun, args, res]` (new path)
- Otherwise: emit an error ("cannot call expression of type X")

```
# Pseudocode in analyze_expr_call():
var fun = expr_stack.pop_back();
# ... parse args ...
if fun.val_type == "func" or fun.data_type == "func_ptr":
    IR.emit_IR(["CALL", fun, args, res], loc);
elif fun.val_type == "variable":
    IR.emit_IR(["CALL_INDIRECT", fun, args, res], loc);
else:
    erep.error("cannot call expression of type '%s'" % fun.val_type);
```

### Fix: [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — New function `generate_cmd_call_indirect()`

Emits assembly that:
1. Pushes arguments onto the stack (same as direct call)
2. Loads the variable's value (the function address) into EAX
3. Does `call eax;` — the ZVM interprets this as call through register
4. Cleans up the stack
5. Stores the return value

```
func generate_cmd_call_indirect(cmd:IR_Cmd):
    var var_name = cmd.words[1];
    # Parse args (same as direct call)
    # Push args onto stack
    for arg in args:
        emit("push $%s;\n" % arg, ...);
    # Load function address from variable into EAX
    emit("mov eax, $%s;\n" % var_name, ...);
    # Call through register
    emit("call eax;\n", ...);
    # Clean up stack
    emit("add ESP, %s;\n" % pushed_stack_size, ...);
    # Store result
    emit("mov ^%s, eax;\n" % res, ...);
```

### Fix: [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — `generate_cmd()` at line 262

Add dispatch for the new `"CALL_INDIRECT"` command:

```
"CALL": generate_cmd_call(cmd);
"CALL_INDIRECT": generate_cmd_call_indirect(cmd);
```

### Test Phase 2
```miniderp
myFunc: print 42; return;
main:
    var f = myFunc;
    f();   # should print 42
    return;
```

---

## Phase 3: Assignment Tracking & Arity Checking

### Fix: [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — `analyze_decl_assignment()` at line 312

Propagate function pointer metadata when assigning a func_ptr to a variable:

```
# After the assignment analysis:
var_handle.data_type = arg.data_type;  # already exists
if arg.has("code_label") and arg.data_type == "func_ptr":
    var_handle["resolved_func"] = arg.code_label;
```

### Test Phase 3
```miniderp
add: a,b = pop,pop; push a+b; return;
main:
    var f = add;
    f(3, 4);   # should print 7
    print;
    return;
```

---

## Files Modified Summary

| File | Phase | Changes |
|------|-------|---------|
| [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) | 1 | `analyze_expr_ident()` — create func_ptr immediate instead of raw func handle |
| [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) | 2 | `analyze_expr_call()` — detect variable callee, emit `CALL_INDIRECT` |
| [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) | 3 | `analyze_decl_assignment()` — propagate func_ptr metadata |
| [`scenes/codegen_md.gd`](scenes/codegen_md.gd) | 1 | `load_value()` — handle `data_type == "func_ptr"` |
| [`scenes/codegen_md.gd`](scenes/codegen_md.gd) | 2 | New `generate_cmd_call_indirect()` function |
| [`scenes/codegen_md.gd`](scenes/codegen_md.gd) | 2 | `generate_cmd()` — add `CALL_INDIRECT` dispatch |
| [`scenes/CPU_vm.gd`](scenes/CPU_vm.gd) | — | **No change needed** — `cmd_call()` handles register targets |
| [`scenes/comp_asm_zd.gd`](scenes/comp_asm_zd.gd) | — | **No change needed** — `call eax;` is valid syntax |
| [`scenes/ir_md.gd`](scenes/ir_md.gd) | — | **No change needed** — IR commands are just string arrays |
| [`scenes/lang_md.gd`](scenes/lang_md.gd) | — | **No change needed** — grammar already accepts any expr |

## Error Cases

| Source | Expected Behavior |
|--------|-------------------|
| `var x = 5; x();` | Compile error: "cannot call expression of type 'variable'" |
| `42();` | Compile error: "cannot call expression of type 'immediate'" |
| `myFunc();` | Continues to work via existing direct CALL path (unchanged) |

## Limitations (Phase 2 only, not addressed)

- Function pointers as function arguments (e.g., `map(arr, myFunc)`) — requires parameter type handling
- Dynamic dispatch via conditional assignment — works at runtime since the variable value is loaded dynamically
- Returning function pointers from functions — no return type system
- Arity checking for indirect calls — analyzer doesn't know the target function's signature at compile time
