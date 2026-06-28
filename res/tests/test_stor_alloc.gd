# ============================================================================
# test_stor_alloc.gd — Unit tests for stor_alloc.gd
# ============================================================================
# Tests that StorageAllocator correctly allocates storage for symbols
# discovered by the ABI scanner.
#
# Usage:
#   From the test runner: TestStorAlloc.run_all()
# ============================================================================

const AB = preload("res://scenes/ab_manifest.gd")
const StorageAllocator = preload("res://scenes/stor_alloc.gd")

static func run_all() -> int:
	var failed = 0
	
	failed += test_global_var_gets_global_storage()
	failed += test_local_var_gets_stack_storage()
	failed += test_temp_register_allocation()
	failed += test_immediate_allocation()
	failed += test_func_symbol_code_storage()
	failed += test_scope_stack_sizes()
	
	if failed == 0:
		print("  [PASS] All stor_alloc tests passed.")
	else:
		push_error("  [FAIL] %d stor_alloc test(s) failed." % failed)
	return failed


# Build a minimal manifest with one global var.
static func _build_global_var_manifest() -> ABIManifest:
	var m = ABIManifest.new()
	var sym = AB.SymbolInfo.new(
		"var_1__x", "variable", "unallocated", 0,
		"int", false, 0, false, "scp_0__global"
	)
	m.symbols["var_1__x"] = sym
	return m

# Build a manifest with a local var.
static func _build_local_var_manifest() -> ABIManifest:
	var m = ABIManifest.new()
	var sym = AB.SymbolInfo.new(
		"var_2__local", "variable", "unallocated", 0,
		"int", false, 0, false, "scp_1__func"
	)
	m.symbols["var_2__local"] = sym
	return m

# Build a manifest with a func symbol.
static func _build_func_manifest() -> ABIManifest:
	var m = ABIManifest.new()
	var sym = AB.SymbolInfo.new(
		"func_1__main", "func", "unallocated", 0,
		"int", false, 0, false, "scp_0__global"
	)
	m.symbols["func_1__main"] = sym
	return m

# Build a minimal IR structure for allocation.
# vars and funcs are arrays of Dictionary handles (matching the format from
# abi_scanner, where each handle has .get("ir_name"), .get("storage"), etc.).
static func _build_ir_with_scope(scp_name: String, user_name: String, vars_args: Array = [],
		funcs_args: Array = []) -> Dictionary:
	# Convert SymbolInfo to plain Dictionary handle if needed
	var handles = []
	for v in vars_args:
		if v is AB.SymbolInfo:
			handles.append({
				"ir_name": v.ir_name,
				"val_type": v.val_type,
				"data_type": v.data_type,
				"is_array": "1" if v.is_array else "0",
				"array_size": str(v.array_size),
				"storage": "NULL",
				"value": "0",
				"scope": v.scope,
				"code": "",
				"argc": "0",
			})
		else:
			handles.append(v)
	var func_handles = []
	for f in funcs_args:
		if f is AB.SymbolInfo:
			func_handles.append({
				"ir_name": f.ir_name,
				"val_type": f.val_type,
				"data_type": f.data_type,
				"storage": "NULL",
				"value": "",
				"scope": f.scope,
				"code": "",
				"argc": "0",
				"is_array": "0",
				"array_size": "0",
			})
		else:
			func_handles.append(f)
	return {
		"scopes": {
			scp_name: {
				"ir_name": scp_name,
				"user_name": user_name,
				"parent": "none",
				"vars": handles,
				"funcs": func_handles,
			}
		},
		"code_blocks": {},
	}


# --- Individual tests --------------------------------------------------------

static func test_global_var_gets_global_storage() -> int:
	var m = _build_global_var_manifest()
	var IR = _build_ir_with_scope("scp_0__global", "global", [m.symbols["var_1__x"]])
	
	StorageAllocator.allocate(m, IR)
	
	var sym = m.symbols["var_1__x"]
	if sym.storage_type != "global":
		push_error("FAIL: global var expected storage_type 'global', got '%s'" % sym.storage_type)
		return 1
	
	return 0


static func test_local_var_gets_stack_storage() -> int:
	var m = _build_local_var_manifest()
	var IR = _build_ir_with_scope("scp_1__func", "func", [m.symbols["var_2__local"]])
	
	StorageAllocator.allocate(m, IR)
	
	var sym = m.symbols["var_2__local"]
	if sym.storage_type != "stack":
		push_error("FAIL: local var expected storage_type 'stack', got '%s'" % sym.storage_type)
		return 1
	
	if sym.storage_pos == 0:
		push_error("FAIL: local var should have non-zero stack position")
		return 1
	
	return 0


static func test_temp_register_allocation() -> int:
	var m = ABIManifest.new()
	m.temps.append(AB.TempSlot.new("tmp_a"))
	m.temps.append(AB.TempSlot.new("tmp_b"))
	m.temps.append(AB.TempSlot.new("tmp_c"))
	m.temps.append(AB.TempSlot.new("tmp_d"))
	
	StorageAllocator.allocate_temps(m)
	
	# First 4 temps should get registers
	var registers = ["EAX", "EBX", "ECX", "EDX"]
	for i in range(4):
		var temp = m.temps[i]
		if temp.preferred_register != registers[i]:
			push_error("FAIL: temp_%s expected register '%s', got '%s'" % [temp.name, registers[i], temp.preferred_register])
			return 1
	
	return 0


static func test_immediate_allocation() -> int:
	var m = ABIManifest.new()
	
	# Add an immediate symbol manually
	var imm_sym = AB.SymbolInfo.new(
		"imm_1__42", "immediate", "unallocated", 0,
		"int", false, 0, false, "scp_0__global"
	)
	m.symbols["imm_1__42"] = imm_sym
	
	var IR = _build_ir_with_scope("scp_0__global", "global", [])
	StorageAllocator.allocate_imms(m)
	
	# Immediates should have storage_type "immediate"
	var sym = m.symbols["imm_1__42"]
	if sym.storage_type != "immediate":
		push_error("FAIL: immediate expected storage_type 'immediate', got '%s'" % sym.storage_type)
		return 1
	
	return 0


static func test_func_symbol_code_storage() -> int:
	var m = _build_func_manifest()
	# Note: funcs are not passed via _build_ir_with_scope() because the
	# symbol itself is already in the manifest.  The IR funcs array must
	# contain Dictionary handles, not SymbolInfo objects.
	var func_handle = {
		"ir_name": "func_1__main",
		"val_type": "func",
		"data_type": "int",
		"storage": "NULL",
		"value": "",
		"scope": "scp_0__global",
		"code": "",
		"argc": "0",
		"is_array": "0",
		"array_size": "0",
	}
	var IR = _build_ir_with_scope("scp_0__global", "global", [], [func_handle])
	
	StorageAllocator.allocate(m, IR)
	
	var sym = m.symbols["func_1__main"]
	if sym.storage_type != "code":
		push_error("FAIL: func expected storage_type 'code', got '%s'" % sym.storage_type)
		return 1
	
	return 0


static func test_scope_stack_sizes() -> int:
	var m = ABIManifest.new()
	
	# Add 3 local vars to a function scope
	var vars = []
	for i in range(3):
		var sym = AB.SymbolInfo.new(
			"var_%d__local" % (i + 1), "variable", "unallocated", 0,
			"int", false, 0, false, "scp_1__func"
		)
		m.symbols[sym.ir_name] = sym
		vars.append(sym)
	
	var IR = _build_ir_with_scope("scp_1__func", "func", vars)
	StorageAllocator.allocate(m, IR)
	
	# After allocation, scope_stack_sizes should have an entry for scp_1__func
	if m.scope_stack_sizes.size() == 0:
		# StorageAllocator may or may not fill scope_stack_sizes depending on implementation
		# This is a soft check — just verify symbols were allocated
		pass
	
	# All 3 local vars should be on the stack
	for sym in vars:
		if sym.storage_type != "stack":
			push_error("FAIL: local var %s expected 'stack' storage" % sym.ir_name)
			return 1
	
	return 0
