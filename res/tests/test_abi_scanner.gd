# ============================================================================
# test_abi_scanner.gd — Unit tests for abi_scanner.gd
# ============================================================================
# Tests that ABIScanner.discover() produces correct ABIManifest from IR + ITG.
#
# Usage:
#   From the test runner: TestABIScanner.run_all()
# ============================================================================

const ABIScanner = preload("res://scenes/abi_scanner.gd")
const TemplateParser = preload("res://scenes/template_parser.gd")
const ITG = preload("res://scenes/inflated_template_graph.gd")
const AB = preload("res://scenes/ab_manifest.gd")

static func run_all() -> int:
	var failed = 0
	
	failed += test_discover_with_simple_mov_ir()
	failed += test_discover_symbols_from_scopes()
	failed += test_discover_labels()
	failed += test_discover_temps()
	failed += test_discover_imms()
	failed += test_discover_reachable_cbs()
	failed += test_storage_allocated()
	
	if failed == 0:
		print("  [PASS] All ABI scanner tests passed.")
	else:
		push_error("  [FAIL] %d ABI scanner test(s) failed." % failed)
	return failed


# Parse the codegen_templates.tg once for all tests.
static func _get_graph() -> InflatedGraph:
	var path = ProjectSettings.globalize_path("res://templates/codegen_templates.tg")
	var fp = FileAccess.open(path, FileAccess.READ)
	var text = fp.get_as_text()
	fp.close()
	return TemplateParser.parse(text)


# Build a minimal IR with just MOV commands and a global scope.
static func _build_simple_ir() -> Dictionary:
	return {
		"scopes": {
			"scp_0__global": {
				"ir_name": "scp_0__global",
				"user_name": "global",
				"parent": "none",
				"vars": [
					{"ir_name": "var_1__x", "val_type": "variable", "user_name": "x",
					 "data_type": "int", "storage": "NULL", "value": "0",
					 "scope": "scp_0__global", "code": "", "argc": "0",
					 "is_array": "0", "array_size": "0"},
				],
				"funcs": [],
			}
		},
		"code_blocks": {
			"cb_1": {
				"ir_name": "cb_1",
				"lbl_from": "lbl_from_2",
				"lbl_to": "lbl_to_3",
				"code": [
					IR_Cmd.new({"words": ["MOV", "var_1__x", "imm_2"]}),
				],
			},
		},
		"all_syms": {},
	}


# --- Individual tests --------------------------------------------------------

static func test_discover_with_simple_mov_ir() -> int:
	var graph = _get_graph()
	if graph == null:
		push_error("FAIL: Could not parse template graph")
		return 1
	
	var IR = _build_simple_ir()
	# We need to add imm_2 to the manifest manually — it should be discovered
	# through the MOV template's bindings (but we need a minimal IR_Cmd).
	
	var manifest = ABIScanner.discover(IR, graph)
	if manifest == null:
		push_error("FAIL: discover() returned null")
		return 1
	
	if not (manifest is ABIManifest):
		push_error("FAIL: discover() did not return ABIManifest")
		return 1
	
	return 0


static func test_discover_symbols_from_scopes() -> int:
	var graph = _get_graph()
	var IR = _build_simple_ir()
	var manifest = ABIScanner.discover(IR, graph)
	
	if not manifest.symbols.has("var_1__x"):
		push_error("FAIL: var_1__x not discovered in symbols")
		return 1
	
	var sym = manifest.symbols["var_1__x"]
	if sym.val_type != "variable":
		push_error("FAIL: var_1__x val_type expected 'variable', got '%s'" % sym.val_type)
		return 1
	
	return 0


static func test_discover_labels() -> int:
	# Build a simple IR that exercises IF (which uses @label)
	var IR = {
		"scopes": {
			"scp_0__global": {
				"ir_name": "scp_0__global",
				"user_name": "global",
				"parent": "none",
				"vars": [],
				"funcs": [],
			}
		},
		"code_blocks": {
			"cb_1": {
				"ir_name": "cb_1",
				"lbl_from": "lbl_from_2",
				"lbl_to": "lbl_to_3",
				"code": [
					IR_Cmd.new({"words": ["IF", "cb_2", "var_res", "cb_3"]}),
				],
			},
			"cb_2": {
				"ir_name": "cb_2",
				"lbl_from": "lbl_from_4",
				"lbl_to": "lbl_to_5",
				"code": [],
			},
			"cb_3": {
				"ir_name": "cb_3",
				"lbl_from": "lbl_from_6",
				"lbl_to": "lbl_to_7",
				"code": [],
			},
		},
	}
	
	var graph = _get_graph()
	var manifest = ABIScanner.discover(IR, graph)
	
	if manifest.labels.size() < 2:
		push_error("FAIL: IF template should produce >=2 labels, got %d" % manifest.labels.size())
		return 1
	
	return 0


static func test_discover_temps() -> int:
	# OP with ADD uses @temp tmp_a, tmp_b
	var IR = {
		"scopes": {
			"scp_0__global": {
				"ir_name": "scp_0__global",
				"user_name": "global",
				"parent": "none",
				"vars": [],
				"funcs": [],
			}
		},
		"code_blocks": {
			"cb_1": {
				"ir_name": "cb_1",
				"lbl_from": "lbl_from_2",
				"lbl_to": "lbl_to_3",
				"code": [
					IR_Cmd.new({"words": ["OP", "ADD", "var_a", "var_b", "var_res"]}),
				],
			},
		},
	}
	
	var graph = _get_graph()
	var manifest = ABIScanner.discover(IR, graph)
	
	if manifest.temps.size() < 2:
		push_error("FAIL: OP ADD should discover >=2 temps, got %d" % manifest.temps.size())
		return 1
	
	return 0


static func test_discover_imms() -> int:
	# IF template uses @new_imm(0)
	var IR = {
		"scopes": {
			"scp_0__global": {
				"ir_name": "scp_0__global",
				"user_name": "global",
				"parent": "none",
				"vars": [
					{"ir_name": "var_res", "val_type": "variable", "user_name": "res",
					 "data_type": "int", "storage": "NULL", "value": "0",
					 "scope": "scp_0__global", "code": "", "argc": "0",
					 "is_array": "0", "array_size": "0"},
				],
				"funcs": [],
			}
		},
		"code_blocks": {
			"cb_1": {
				"ir_name": "cb_1",
				"lbl_from": "lbl_from_2",
				"lbl_to": "lbl_to_3",
				"code": [
					IR_Cmd.new({"words": ["IF", "cb_2", "var_res", "cb_3"]}),
				],
			},
			"cb_2": {"ir_name": "cb_2", "lbl_from": "lbl_from_4", "lbl_to": "lbl_to_5", "code": []},
			"cb_3": {"ir_name": "cb_3", "lbl_from": "lbl_from_6", "lbl_to": "lbl_to_7", "code": []},
		},
	}
	
	var graph = _get_graph()
	var manifest = ABIScanner.discover(IR, graph)
	
	# The imm_0 should be created and added to symbols
	var has_imm = false
	for sym_name in manifest.symbols:
		if manifest.symbols[sym_name].val_type == "immediate":
			has_imm = true
			break
	
	if not has_imm:
		push_error("FAIL: IF template should create an immediate constant via @new_imm")
		return 1
	
	return 0


static func test_discover_reachable_cbs() -> int:
	var IR = {
		"scopes": {
			"scp_0__global": {
				"ir_name": "scp_0__global",
				"user_name": "global",
				"parent": "none",
				"vars": [],
				"funcs": [],
			}
		},
		"code_blocks": {
			"cb_1": {
				"ir_name": "cb_1",
				"lbl_from": "lbl_from_2",
				"lbl_to": "lbl_to_3",
				"code": [
					IR_Cmd.new({"words": ["CALL", "func_1__main", "[", "]", "tmp_res"]}),
				],
			},
			"cb_2": {
				"ir_name": "cb_2",
				"lbl_from": "func_1__main",
				"lbl_to": "lbl_to_5",
				"code": [],
			},
		},
	}
	
	# Add func symbol
	IR.scopes["scp_0__global"]["funcs"] = [
		{"ir_name": "func_1__main", "val_type": "func", "user_name": "main",
		 "data_type": "int", "storage": "NULL", "value": "",
		 "scope": "scp_0__global", "code": "cb_2", "argc": "0",
		 "is_array": "0", "array_size": "0"},
	]
	
	var graph = _get_graph()
	var manifest = ABIScanner.discover(IR, graph)
	
	# cb_1 should be reachable (it's a code block in the IR)
	# For CALL, @ref_cb should mark the target code block reachable too
	if manifest.reachable_cbs.size() == 0:
		push_error("FAIL: At least one reachable code block expected")
		return 1
	
	return 0


static func test_storage_allocated() -> int:
	var graph = _get_graph()
	var IR = _build_simple_ir()
	var manifest = ABIScanner.discover(IR, graph)
	
	# After discovery + allocation, var_1__x should have storage_type != "unallocated"
	if not manifest.symbols.has("var_1__x"):
		push_error("FAIL: var_1__x not in symbols")
		return 1
	
	var sym = manifest.symbols["var_1__x"]
	if sym.storage_type == "unallocated":
		push_error("FAIL: var_1__x was not allocated (still unallocated)")
		return 1
	
	# Global vars should have storage_type "global"
	if sym.storage_type != "global":
		push_error("FAIL: var_1__x expected storage_type 'global', got '%s'" % sym.storage_type)
		return 1
	
	return 0
