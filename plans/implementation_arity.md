# Implementation Plan: Function Arity Checking

## Overview

The MiniDerp compiler should check that every function call passes the correct number of arguments. Currently, calling a function with too many or too few arguments silently compiles and produces undefined behavior at runtime.

## Design: How `argc` flows through the compiler

```
func foo(a, b) { ... }          →  IR: func_handle.argc = 2
func bar(x, y, z);              →  IR: func_handle.argc = 3
extern func baz(w);             →  IR: func_handle.argc = 1
func no_params();               →  IR: func_handle.argc = 0

foo(1, 2)                       →  len(args) = 2, matches foo.argc = 2 ✓
foo(1)                          →  len(args) = 1, foo.argc = 2 → ERROR
foo(1, 2, 3)                    →  len(args) = 3, foo.argc = 2 → ERROR
```

### Key decision: `argc = -1` means "unknown"

When a function handle is created via [`new_val_func()`](scenes/ir_md.gd:80), `argc` defaults to `-1`. During arity checking in [`analyze_expr_call()`](scenes/analyzer_md.gd:226), if `fun.argc < 0`, the check is **skipped** — the function's parameter count is unknown. This handles the edge case where a forward declaration without parameter list (e.g. `func foo;` which doesn't actually parse as valid) or a function referenced before its declaration occurs.

In practice, MiniDerp requires a function to be declared or defined before its first call (otherwise [`IR.get_func()`](scenes/ir_md.gd:184) returns null and [`analyze_expr_ident()`](scenes/analyzer_md.gd:417) already fires `ERR_29`). So the `argc` is typically already known at call sites.

### Where the check fires

In [`analyze_expr_call()`](scenes/analyzer_md.gd:226), the flow is:

```
1. Parse func name → push onto expr_stack
2. Pop func handle from expr_stack → this is `fun`
3. Evaluate call arguments → build `args` array
4. [NEW] Check arity: if fun.argc >= 0 and len(args) != fun.argc → ERROR
5. Emit CALL instruction
```

## Files to modify

### 1. [`scenes/ir_md.gd`](scenes/ir_md.gd) — Add `argc` field to function handles

**`new_val_func()`** (line 80-87): Add `val["argc"] = -1` after the existing fields.

```gdscript
func new_val_func(fun_name, fun_scope, fun_code):
    var val = new_val();
    val.val_type = "func";
    val.ir_name = make_unique_IR_name("func", fun_name);
    val.user_name = fun_name;
    val["scope"] = fun_scope.ir_name;
    val["code"] = fun_code.ir_name;
    val["argc"] = -1;          # NEW: -1 = unknown, 0+ = known parameter count
    return val;
```

**`serialize_vals()`** (line 210-221): Add `"argc"` to the property list so it survives IR serialization.

```gdscript
for key2 in ["ir_name", "val_type", "user_name", "data_type", "storage", "value", "scope", "code", "argc"]:
```

### 2. [`scenes/codegen_md.gd`](scenes/codegen_md.gd) — Add `argc` to deserialization

**`inflate_vals()`** (line 105-114): Add `"argc"` to the property list so codegen properly deserializes the field.

```gdscript
const props = ["ir_name", "val_type", "user_name", "data_type", "storage", "value", "scope", "code", "argc"];
```

### 3. [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd) — 4 changes

#### Change 3a: `analyze_func_def_stmt()` — Record argc from arg_names

Around line 554-560, after creating/updating the function handle, set `fun_handle.argc = len(arg_names)`.

```gdscript
var fun_handle = IR.get_func(fun_name);
if fun_handle:
    fun_handle.code = fun_code.ir_name;
    fun_handle.scope = fun_scope.ir_name;
else:
    fun_handle = IR.new_val_func(fun_name, fun_scope, fun_code);
    IR.save_function(fun_handle);
fun_handle.argc = len(arg_names);         # NEW
```

`arg_names` is already populated by the loop at lines 520-529 from parsing `expr_call.children[2]`. For no-arg functions like `func foo() {}`, `arg_names` is empty and `len(arg_names) = 0`, which correctly sets `argc = 0`.

#### Change 3b: `analyze_func_decl_stmt()` — Count params and set argc

Lines 275-290 currently create a function handle without examining parameters. Need to:

1. Count parameters from `expr_call.children[2]` using the same logic as `analyze_func_def_stmt()`
2. Check if function handle already exists via `IR.get_func()` and update it, or create a new one

The AST structure of `expr_call` in `func_decl_stmt`:

| Source | `expr_call.children[2]` | Arg count |
|--------|------------------------|-----------|
| `func foo();` | `text == ")"` | 0 |
| `func foo(a);` | `tok_class == "expr"` | 1 |
| `func foo(a, b);` | `tok_class == "expr_list"` | `len(children)` |

```gdscript
func analyze_func_decl_stmt(ast):
    ...
    var fun_name = tok_ident.text;
    
    # NEW: count parameters
    var argc = 0;
    if expr_call.children[2].text != ")":
        var expr = expr_call.children[2];
        if expr.tok_class == "expr":
            argc = 1;
        elif expr.tok_class == "expr_list":
            argc = len(expr.children);
        else:
            internal_error(E.ERR_28); return;
    
    var fun_handle = IR.get_func(fun_name);
    if fun_handle:
        fun_handle.argc = argc;
    else:
        var fun_scp = IR.new_val_none();
        var fun_cb = IR.new_val_none();
        fun_handle = IR.new_val_func(fun_name, fun_scp, fun_cb);
        fun_handle.argc = argc;
        IR.save_function(fun_handle);
```

#### Change 3c: `analyze_decl_extern_stmt()` — Count params for extern funcs

Lines 303-309 handle `extern func foo(a, b);`. Apply the same parameter counting and get-or-create pattern.

```gdscript
elif (decl.tok_class == "func_decl_stmt"):
    var expr_call = decl.children[1];
    var tok_ident = expr_call.children[0].children[0].children[0];
    assert(tok_ident.tok_class == "IDENT");
    var fun_name = tok_ident.text;
    
    var argc = 0;
    if expr_call.children[2].text != ")":
        var expr = expr_call.children[2];
        if expr.tok_class == "expr":
            argc = 1;
        elif expr.tok_class == "expr_list":
            argc = len(expr.children);
        else:
            internal_error(E.ERR_28); return;
    
    var fun_handle = IR.get_func(fun_name);
    if fun_handle:
        fun_handle.storage = "extern";
        fun_handle.argc = argc;
    else:
        fun_handle = IR.new_val_func(fun_name, IR.new_val_none(), IR.new_val_none());
        fun_handle.storage = "extern";
        fun_handle.argc = argc;
        IR.save_function(fun_handle);
```

#### Change 3d: `analyze_expr_call()` — Add arity check

Around line 247-250, after building the `args` array and before emitting the CALL instruction, add the check.

```gdscript
# NEW: arity check
if fun.has("argc") and fun.argc >= 0:
    erep.context = ast.children[0];       # point error at function name in call
    if len(args) != fun.argc:
        erep.error(E.ERR_33 % [fun.user_name, fun.argc, len(args)]);
        return;                           # error_code is set, caller will stop

var res = IR.new_val_temp();
IR.save_variable(res);
IR.emit_IR(["CALL", fun, args, res], ast.get_location());
expr_stack.push_back(res);
```

Setting `erep.context` to `ast.children[0]` (the function name expression) ensures `ErrorReporter.error()` underlines the correct source position.

### 4. [`scenes/error_list.gd`](scenes/error_list.gd) — Add ERR_33

```gdscript
const ERR_33 = "Error 33: Function '%s' expects %d argument(s), but got %d";
```

This follows the existing style (e.g. `ERR_29` uses `%s` for identifier name).

## Edge cases

| Case | Behavior |
|------|----------|
| No-arg function `func foo() {}` | `argc = 0`, check catches `foo(1)` as error |
| Forward declaration `func foo(a, b);` | `argc = 2` set at declaration time, available at call sites |
| Forward declaration without params `func foo();` | `argc = 0` (no params in parens) |
| Extern function `extern func foo(x);` | `argc = 1` set by the extern decl handler |
| Recursive call | `argc` already set from the enclosing definition, checked normally |
| Function called before declaration | `IR.get_func()` returns null → existing `ERR_29` fires before arity check |
| Duplicate declaration `func foo(a); func foo(x, y);` | Second call updates `argc` from 1 to 2 (last wins) |
| Variadic functions | Not supported in MiniDerp — no special handling needed |

## Test cases

### TC1: Correct arity (no error)
```miniderp
func add(x, y):
    return x + y;
func main():
    print(add(3, 4));
```
Expected: `7`

### TC2: Too few arguments
```miniderp
func add(x, y):
    return x + y;
func main():
    var result = add(3);
```
Expected: Error 33 — "Function 'add' expects 2 argument(s), but got 1"

### TC3: Too many arguments
```miniderp
func add(x, y):
    return x + y;
func main():
    var result = add(3, 4, 5);
```
Expected: Error 33 — "Function 'add' expects 2 argument(s), but got 3"

### TC4: No-arg function called correctly
```miniderp
func greet():
    print(42);
func main():
    greet();
```
Expected: `42`

### TC5: No-arg function called with arguments
```miniderp
func greet():
    print(42);
func main():
    greet(1);
```
Expected: Error 33 — "Function 'greet' expects 0 argument(s), but got 1"

### TC6: Forward declaration with correct arity
```miniderp
func add(x, y);
func main():
    print(add(3, 4));
func add(x, y):
    return x + y;
```
Expected: `7`

### TC7: Forward declaration with wrong arity
```miniderp
func add(x, y);
func main():
    print(add(3));
```
Expected: Error 33

### TC8: Extern function (correct)
```miniderp
extern func print(x);
func main():
    print(42);
```
Expected: `42`

### TC9: Recursive call (correct)
```miniderp
func factorial(n):
    if n <= 1: return 1;
    else: return n * factorial(n - 1);
func main():
    print(factorial(5));
```
Expected: `120`

### TC10: Regression — existing programs
All programs in `res/data/` should compile and produce same output as before.

## Implementation order

1. [`scenes/ir_md.gd`](scenes/ir_md.gd): Add `argc` to `new_val_func()` and `serialize_vals()`
2. [`scenes/codegen_md.gd`](scenes/codegen_md.gd): Add `argc` to `inflate_vals()`
3. [`scenes/error_list.gd`](scenes/error_list.gd): Add `ERR_33`
4. [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd): Changes 3a–3d
5. Test with the 10 test cases above
6. Regression test existing programs
7. Update [`docs/todo.md`](docs/todo.md) to mark arity checking as done
