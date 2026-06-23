# Diagnostic Report: Array Literal Construction Bug

## 1. Full Pipeline Trace — `var x = [1,2,3]`

### Tokenization & Parsing

The source `var x = [1,2,3]` is tokenized and parsed via the shift-reduce grammar in `lang_md.gd`:

```
/var /IDENT( "x" ) /= /[ /NUMBER( "1" ) /, /NUMBER( "2" ) /, /NUMBER( "3" ) /] /;
```

The parser produces this AST structure:
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

### Analysis (analyzer_md.gd)

The analyzer processes `decl_assignment_stmt`:

1. **`analyze_decl_assignment`** (line 362):
   - Creates `var_handle` for `x` (ir_name: `var_42__x`)
   - Calls `IR.save_variable(var_handle)` → adds to `cur_scope.vars`
   - Calls `analyze_one(stmt_ass)` → processes the `x = [1,2,3]` assignment

2. **`analyze_assignment_stmt`** (line 415):
   - `analyze_lhs(ast.children[0])` → returns `var_42__x` handle
   - `analyze_expr(ast.children[2])` → processes `[1,2,3]`

3. **`analyze_expr_array_literal`** (line 277):
   - Creates `tmp_43` (ir_name: `tmp_43`, val_type: `temporary`)
   - `IR.save_variable(tmp_43)` → adds `tmp_43` to `cur_scope.vars`
   - Creates immediate values for 1, 2, 3: `imm_44`, `imm_45`, `imm_46`
   - **Emits IR**: `["ALLOC", "3", "tmp_43"]`
   - **Emits IR**: `["MOV_ARR", "tmp_43", ["[", "imm_44", "imm_45", "imm_46", "]"]]`
   - Pushes `tmp_43` onto expr_stack

4. Back in `analyze_assignment_stmt`:
   - **Emits IR**: `["MOV", "var_42__x", "tmp_43"]`

**Final IR emitted:**
```
ALLOC 3 tmp_43
MOV_ARR tmp_43 [ imm_44 imm_45 imm_46 ]
MOV var_42__x tmp_43
```

### Code Generation (codegen_md.gd)

#### Step A: Variable Allocation (allocate_vars, line 642)

`allocate_vars` iterates `cur_scope.vars` before code generation begins. The scope initially contains:
- `var_42__x` (from `var x` declaration)
- `tmp_43` (from analysis of the RHS)

**Variable layout after `allocate_vars`:**
| Variable | storage.pos | EBP-relative address |
|----------|-------------|---------------------|
| `var_42__x` | -3 | `EBP[-3]` |
| `tmp_43` | -7 | `EBP[-7]` |

`local_vars_write_pos` = -11 after these two allocations (each allocated 4 bytes).

#### Step B: generate_cmd_alloc (line 726)

For IR: `ALLOC 3 tmp_43`

```gdscript
var arr_storage = new_arr("3");  # ir_name = "arr_1__3"
allocate_value(arr_storage, cur_scope);  # allocates on stack
cur_scope.vars.append(arr_storage);
emit("mov ^tmp_43, @arr_1__3");
```

`new_arr("3")` (line 343) creates:
```gdscript
{"ir_name":"arr_1__3", "val_type":"array", "value":"3", "data_type":"error", "storage":"NULL"}
```
**Note: No `is_array` or `array_size` fields!**

In `allocate_value` (line 667), `data_size = 4` because `"is_array" not in handle`.  
So the array storage gets: `pos = -11`, then `local_vars_write_pos -= 4` → -15.

The `emit` stores `arr_1__3`'s address (`EBP[-11]`) into `tmp_43`.

#### Step C: generate_cmd_mov_arr (line 734)

For IR: `MOV_ARR tmp_43 [ imm_44 imm_45 imm_46 ]`

```gdscript
tmp = alloc_register()  # gets EAX
emit("mov EAX, $tmp_43")       # EAX = value of tmp_43 = EBP-11 (the array base address)
emit("mov *EAX, $imm_44")      # write 1 to address EBP-11
emit("add EAX, 4")             # EAX = EBP-7
emit("mov *EAX, $imm_45")      # write 2 to address EBP-7 ← OVERWRITES tmp_43!
emit("add EAX, 4")             # EAX = EBP-3
emit("mov *EAX, $imm_46")      # write 3 to address EBP-3 ← OVERWRITES x!
```

#### Step D: generate_cmd_mov (line 284)

For IR: `MOV var_42__x tmp_43`

```gdscript
emit("mov ^var_42__x, $tmp_43")
```

This loads from `tmp_43` (EBP[-7]) — which was **overwritten** with value 2 in Step C — and stores into `var_42__x` (EBP[-3]) — which was **overwritten** with value 3 in Step C.

**Result:** `x` gets the value 2 (not the pointer!). And `x`'s own storage slot (EBP[-3]) previously held value 3 from the overflow.

#### Step E: fixup_enter_leave (line 754)

```gdscript
stack_bytes = scope.local_vars_write_pos  # = -15
S.replace("__ENTER_...", "sub ESP, %d" % -stack_bytes)  # sub ESP, 15
S.replace("__LEAVE_...", "sub ESP, %d" % stack_bytes)   # sub ESP, -15 → sub ESP, -15
```

The frame only reserves 15 bytes for all locals. But the array (starting at EBP-11) writes:
- 4 bytes at EBP-11 (element 0 — within frame)
- 4 bytes at EBP-7 (element 1 — within frame, but overwrites tmp)
- 4 bytes at EBP-3 (element 2 — within frame, but overwrites x)

No out-of-bounds crash in this specific case, but the data integrity is destroyed.

---

## 2. Stack Frame Diagram

```
                     HIGH ADDRESSES (toward 0xFFFF)
  ┌─────────────────────────────────────────────────────┐
  │                     ...                             │
  ├─────────────────────────────────────────────────────┤
  │  Caller's frame                                     │
  ├─────────────────────────────────────────────────────┤
  │  Return address              (pushed by CALL)       │  ← EBP + 8
  ├─────────────────────────────────────────────────────┤
  │  Saved EBP                   (pushed by _call)      │  ← EBP + 4
  ├─────────────────────────────────────────────────────┤
  │  ───── EBP ─────                                   │  ← EBP
  ├─────────────────────────────────────────────────────┤
  │  var_42__x   storage.pos = -3  (EBP[-3])           │  ← EBP - 3  ← array element 2 is written here!
  ├─────────────────────────────────────────────────────┤
  │  tmp_43      storage.pos = -7  (EBP[-7])           │  ← EBP - 7  ← array element 1 is written here!
  ├─────────────────────────────────────────────────────┤
  │  arr_1__3    storage.pos = -11 (EBP[-11])          │  ← EBP - 11 ← array element 0 is written here  
  │                 [only 4 bytes allocated!]           │              (element 0 = 1, correct)
  ├─────────────────────────────────────────────────────┤
  │  [unallocated stack space]                          │  ← EBP - 15 (new ESP after `sub ESP, 15`)
  │                                                     │
  ▼                                                     │
                     LOW ADDRESSES (toward 0)
  ─── ESP after `sub ESP, 15` ──────────────────────────
```

**What each element overwrites:**
| Element | Written to | Overwrites |
|---------|-----------|------------|
| `[0]` = 1 | `EBP[-11]` | arr_1__3 storage (the intended array base) |
| `[1]` = 2 | `EBP[-7]` | **tmp_43** — the pointer to the array! |
| `[2]` = 3 | `EBP[-3]` | **var_42__x** — the variable `x` itself! |

---

## 3. Bug Identification

### Primary Bug: `new_arr()` does not set array sizing metadata

**File:** [`scenes/codegen_md.gd`](scenes/codegen_md.gd:343)

```gdscript
func new_arr(size)->Dictionary:
    var ir_name = "arr_"+str(len(all_syms)+1)+"__"+str(size);
    var handle = {"ir_name":ir_name, "val_type":"array", "value":str(size), "data_type":"error", "storage":"NULL"};
    all_syms[ir_name] = handle;
    return handle;
```

The handle produced by `new_arr()` lacks the `is_array` and `array_size` fields that `allocate_value()` checks at line 669:

```gdscript
var data_size = 4;
if "is_array" in handle and int(handle.is_array):
    data_size *= int(handle.array_size);
```

Since `is_array` is absent from the dictionary, the condition is **falsy** and `data_size` remains 4 regardless of the array's element count. For `[1,2,3]` (3 elements), the code allocates only 4 bytes instead of the required 12 bytes.

**What the code currently does:** Allocates 4 bytes on the stack for the array storage slot.

**What it should do:** Allocate `4 * array_size` bytes (12 bytes for 3 elements).

### Secondary Bug Chain (consequences of the primary bug)

| Step | Code Location | What Goes Wrong |
|------|--------------|-----------------|
| `allocate_value(arr_storage)` | [`codegen_md.gd:667`](scenes/codegen_md.gd:667) | Only 4 bytes allocated, not 12 |
| `generate_cmd_mov_arr` writing elements | [`codegen_md.gd:734`](scenes/codegen_md.gd:734) | Element 1 overwrites `tmp_43` at EBP[-7]; element 2 overwrites `var_42__x` at EBP[-3] |
| `MOV var_42__x tmp_43` | [`codegen_md.gd:284`](scenes/codegen_md.gd:284) | Reads corrupted `tmp_43` (now = 2) into `x` |
| `fixup_enter_leave` | [`codegen_md.gd:754`](scenes/codegen_md.gd:754) | Stack frame sized to 15 bytes instead of the needed 23+ bytes |

---

## 4. Root Cause Analysis

The bug is an **oversight in the implementation of array literal support**. The developer correctly:

1. Created the `ALLOC` IR command to allocate space for arrays
2. Created the `MOV_ARR` IR command to copy elements into the array
3. Created the `new_arr()` helper to represent array storage handles
4. Created the `is_array` / `array_size` mechanism in `allocate_value()` to handle multi-word variables

**However**, the developer forgot to populate the `is_array` and `array_size` fields in `new_arr()`. This is likely because:

- The array literals feature was implemented **after** the `is_array`/`array_size` mechanism was designed for statically-declared arrays (`var arr[10]`)
- The `generate_cmd_alloc` and `new_arr` functions were written with the assumption that `allocate_value` would "just know" the array needs more space, without explicitly threading the size metadata through
- Alternatively, the developer may have started with a working implementation but the metadata got lost during refactoring

Evidence that `is_array`/`array_size` was intended to be used: The `allocate_value` function already has the correct logic to handle multi-word allocations — it simply never receives the signal from `new_arr()`.

---

## 5. Impact Assessment

### At Runtime

The program **does NOT crash** (no segfault or stack overflow) because:

1. The 12 bytes written (elements 0, 1, 2) all fall within the stack frame of 15 bytes in this simple case
2. No EBP+positive addresses are hit for a 3-element array (element 2 lands at EBP-3, still within the frame)

However, the program **produces completely wrong results**:

- `x` does not hold a pointer to the array — it holds the **value** `2` (the second element)
- Accessing `x[0]` would use `2` as an address, reading from memory location `2` (near the bottom of the address space), likely interpreting whatever garbage is there
- The `tmp_43` variable is corrupted, which could cause issues in more complex expressions

### For Larger Arrays

With `var x = [1,2,3,4,5]` (5 elements, 20 bytes, only 4 allocated):

- Element 3 at EBP+1: **overwrites the saved EBP** on the stack
- Element 4 at EBP+5: **overwrites the return address**
- The function would likely crash on return (jumping to garbage address) or corrupt the caller's frame

### Severity: HIGH

The bug completely breaks array literal semantics. Any program using `[...]` syntax will either produce garbage results or crash.

---

## 6. Test Inputs

The following test cases would expose the bug:

### Test 1: Basic array literal (demonstrates wrong value)
```miniderp
func test() {
    var x = [1, 2, 3];
    print(x[0]);  // expects 1, gets garbage (derefs address 2)
    print(x[1]);  // expects 2, gets garbage
    print(x[2]);  // expects 3, gets garbage
}
```

### Test 2: Array literal in expression (exposes corruption of adjacent vars)
```miniderp
func test() {
    var a = 42;
    var x = [1, 2, 3];
    var b = 99;
    // a or b may be corrupted by array overflow
    print(a);     // expects 42, may get garbage
    print(b);     // expects 99, may get garbage
}
```

### Test 3: Larger array (crashes on return)
```miniderp
func test() {
    var x = [10, 20, 30, 40, 50, 60];
    print(x[0]);  // might crash before even printing
}
// crashes when test() tries to return (saved EBP/return address corrupted)
```

### Test 4: Nested function with array (exposes corruption of caller's frame)
```miniderp
func helper() {
    var arr = [100, 200, 300];
}

func test() {
    var safe = 7;
    helper();
    print(safe);  // expects 7, may get garbage if helper's array corrupted test's frame
}
```

### Test 5: Empty or single-element array (boundary conditions)
```miniderp
func test() {
    var empty = [];      // parser handles this? (grammar rule exists)
    var single = [5];    // only 1 element, may accidentally work
    print(single[0]);    // expects 5
}
```

---

## Appendix: Key Code Locations

| Component | File | Lines | Purpose |
|-----------|------|-------|---------|
| Grammar rule | [`scenes/lang_md.gd`](scenes/lang_md.gd:123) | 123-126 | `expr_array_literal` shift-reduce rules |
| Analyzer | [`scenes/analyzer_md.gd`](scenes/analyzer_md.gd:277) | 277-295 | `analyze_expr_array_literal` — emits ALLOC + MOV_ARR |
| Codegen: `new_arr` | [`scenes/codegen_md.gd`](scenes/codegen_md.gd:343) | 343-347 | **BUG: missing `is_array`/`array_size`** |
| Codegen: `generate_cmd_alloc` | [`scenes/codegen_md.gd`](scenes/codegen_md.gd:726) | 726-732 | Allocates array storage handle |
| Codegen: `generate_cmd_mov_arr` | [`scenes/codegen_md.gd`](scenes/codegen_md.gd:734) | 734-751 | Writes elements sequentially |
| Codegen: `allocate_value` | [`scenes/codegen_md.gd`](scenes/codegen_md.gd:667) | 667-698 | Has correct multi-word logic but never triggered for arrays |
| Codegen: `to_local_pos` | [`scenes/codegen_md.gd`](scenes/codegen_md.gd:701) | 701-702 | Local var offset base = -3 |
| Codegen: `fixup_enter_leave` | [`scenes/codegen_md.gd`](scenes/codegen_md.gd:754) | 754-762 | Frame size from `local_vars_write_pos` |
| CPU: Stack growth | [`scenes/CPU_vm.gd`](scenes/CPU_vm.gd:358) | 358-372 | `push8` writes at ESP, ESP-- |
| CPU: `_call` | [`scenes/CPU_vm.gd`](scenes/CPU_vm.gd:377) | 377-382 | Pushes IP, EBP; EBP = ESP |
| CPU: `_ret` | [`scenes/CPU_vm.gd`](scenes/CPU_vm.gd:384) | 384-387 | ESP = EBP; pops EBP, IP |
| Scope management | [`scenes/ir_md.gd`](scenes/ir_md.gd:163) | 163-174 | Scope creation with vars/funcs lists |
| IR serialization | [`scenes/ir_md.gd`](scenes/ir_md.gd:99) | 99-125 | `emit_IR` and `serialize_ir_arg` |
| Existing array usage in IR | [`IR.txt`](IR.txt:70) | 70-72 | `ALLOC 7 tmp_70` and `MOV_ARR tmp_70 [...]` from `putch` function |
| Array test source | [`res/data/array_test.md`](res/data/array_test.md:1) | 1-13 | Existing array test (indexing only, no literals) |
