# ============================================================================
# run_iter2_test.gd — Iteration 2 Test Runner (scene-based headless)
# ============================================================================
# Tests the full compiler pipeline through both old and new codegen paths:
#   1. Reads test_iter2.md
#   2. Tokenizer → Parser → Analyzer → Codegen (old)
#   3. Tokenizer → Parser → Analyzer → CodegenMaster (new, template-based)
#   4. Reports errors, saves assembly output
# ============================================================================
extends Node


var _test_file = "res://data/test_iter2.md"
var _log_file = "res://data/test_iter2_results.txt"

# Expected assembly patterns (substring checks)
var _expected_patterns_old = [
	"enter",       # function prologue
	"leave",       # function epilogue
	"mov",         # variable assignment
	"add",         # arithmetic
]

var _expected_patterns_new = [
	":main",       # function label
	"enter",       # prologue
	"mov",         # MOV via template
	"add",         # OP via template
]

var _results := ""
var _all_passed := true
var _sep := ""


func _ready() -> void:
	_sep = "=".repeat(70)
	_rlog(_sep)
	_rlog("  CpuDerp - Iteration 2 Test Suite (Headless)")
	_rlog("  Timestamp: " + Time.get_datetime_string_from_system())
	_rlog(_sep)
	_rlog("")
	
	await get_tree().process_frame
	_run_all_tests()


# ===========================================================================
# Helper: add a scene-tree child
# ===========================================================================

func _make_component(script_path: String) -> Node:
	var comp = load(script_path).new()
	add_child(comp)
	return comp


# ===========================================================================
# Main test entry point
# ===========================================================================

func _run_all_tests() -> void:
	_rlog("  Building compiler pipeline...")
	
	# --- Error reporters ---
	var tok_erep = load("res://class_ErrorReporter.gd").new()
	var par_erep = load("res://class_ErrorReporter.gd").new()
	var ana_erep = load("res://class_ErrorReporter.gd").new()
	
	# --- Tokenizer ---
	var tok = _make_component("res://scenes/md_tokenizer.gd")
	tok_erep.proxy = tok
	tok.erep = tok_erep
	tok.reset()
	
	# --- Parser ---
	var parser = _make_component("res://scenes/parser_md.gd")
	par_erep.proxy = parser
	parser.erep = par_erep
	parser.reset()
	
	# --- IR (shared) ---
	var ir = _make_component("res://scenes/ir_md.gd")
	
	# --- Analyzer ---
	var analyzer = _make_component("res://scenes/analyzer_md.gd")
	ana_erep.proxy = analyzer
	analyzer.IR = ir
	analyzer.erep = ana_erep
	analyzer.reset()
	
	# --- Old Codegen ---
	var old_codegen = _make_component("res://scenes/codegen_md.gd")
	
	# --- New Codegen Master ---
	var new_codegen = _make_component("res://scenes/codegen_master.gd")
	
	_rlog("  [SETUP] All compiler components loaded and ready.")
	_rlog("")
	
	# Read source with path fallback
	var source_text = _read_source(_test_file)
	if source_text.is_empty():
		var alt_path = "res://res/data/test_iter2.md"
		_rlog("  [INFO] Trying alternate path: " + alt_path)
		source_text = _read_source(alt_path)
	if source_text.is_empty():
		var alt_path2 = "res://data/test_iter2.md"
		_rlog("  [INFO] Trying alternate path: " + alt_path2)
		source_text = _read_source(alt_path2)
	if source_text.is_empty():
		_rlog("  [FATAL] Cannot open test file (tried multiple paths)")
		_all_passed = false
		_finish()
		return
	
	_rlog("")
	_rlog("  Source file: test_iter2.md")
	_rlog("  Source code:")
	var li = 0
	for line in source_text.split("\n"):
		li += 1
		_rlog("    " + str(li).pad_zeros(3) + " | " + line)
	_rlog("")
	
	# Build input dict shared across pipeline steps
	var input = {"text": source_text, "filename": "test_iter2.md"}
	
	# =======================================================================
	# STEP 1 — Tokenize
	# =======================================================================
	_rlog("  ═══ Step 1: Tokenize ═══")
	tok.reset()
	tok.error_code = ""
	tok.cur_path = ProjectSettings.globalize_path("res://data/")
	tok.cur_filename = "test_iter2.md"
	var tokens = tok.tokenize(input)
	if tok.error_code != "" or tokens.is_empty():
		_rlog("  [FAIL] Tokenization: '" + tok.error_code + "'")
		_all_passed = false
		_finish()
		return
	_rlog("  [PASS] " + str(tokens.size()) + " tokens produced")
	for i in range(mini(tokens.size(), 25)):
		_rlog("    [" + str(i) + "] " + str(tokens[i]))
	if tokens.size() > 25:
		_rlog("    ... (" + str(tokens.size() - 25) + " more)")
	input.tokens = tokens
	
	# =======================================================================
	# STEP 2 — Parse
	# =======================================================================
	_rlog("")
	_rlog("  ═══ Step 2: Parse ═══")
	parser.reset()
	parser.error_code = ""
	var ast = parser.parse(input)
	if parser.error_code != "" or ast == null:
		_rlog("  [FAIL] Parsing: '" + parser.error_code + "'")
		_all_passed = false
		_finish()
		return
	var ast_desc = "null"
	if ast is Array and ast.size() > 0:
		ast_desc = str(ast[0].tok_class) + " (" + str(ast.size()) + " nodes)"
	elif ast is Array:
		ast_desc = "empty array"
	_rlog("  [PASS] AST root: " + ast_desc)
	input.ast = ast
	
	# =======================================================================
	# STEP 3 — Analyze (IR generation)
	# =======================================================================
	_rlog("")
	_rlog("  ═══ Step 3: Analyze (IR gen) ═══")
	analyzer.reset()
	analyzer.error_code = ""
	var ir_result = analyzer.analyze(input)
	if analyzer.error_code != "" or ir_result == null:
		_rlog("  [FAIL] Analysis: '" + analyzer.error_code + "'")
		_all_passed = false
		_finish()
		return
	_rlog("  [PASS] IR generated")
	
	# Dump IR structure
	if ir_result:
		var scope_count = ir_result.IR.scopes.size() if ir_result.IR and ir_result.IR.has("scopes") else 0
		var cb_count = ir_result.IR.code_blocks.size() if ir_result.IR and ir_result.IR.has("code_blocks") else 0
		_rlog("    Scopes: " + str(scope_count) + ", CodeBlocks: " + str(cb_count))
	input.IR = ir_result
	input.filename = "IR.txt"
	
	# =======================================================================
	# STEP 4a — Codegen via OLD codegen
	# =======================================================================
	_rlog("")
	_rlog("  ═══ Step 4a: Codegen (OLD codegen_md.gd) ═══")
	var assy_old = old_codegen.parse_file(input)
	if assy_old.is_empty():
		_rlog("  [FAIL] Old codegen produced empty output")
		_all_passed = false
	else:
		var asm_lines_old = assy_old.split("\n")
		_rlog("  [PASS] " + str(assy_old.length()) + " chars, " + str(asm_lines_old.size()) + " lines")
		
		# Check expected patterns
		_check_expected_patterns("OLD codegen", assy_old, _expected_patterns_old)
		
		# Dump first 40 lines
		_dump_assembly("OLD", assy_old, 40)
		
		# Save
		_save_output("a_iter2_old.zd", assy_old)
	
	# =======================================================================
	# STEP 4b — Codegen via NEW CodegenMaster (template-based)
	# =======================================================================
	_rlog("")
	_rlog("  ═══ Step 4b: Codegen (NEW CodegenMaster) ═══")
	
	# Reset analyzer IR state for a clean second pass
	ir.clear_IR()
	analyzer.reset()
	analyzer.error_code = ""
	var ir_result2 = analyzer.analyze(input)
	if analyzer.error_code != "" or ir_result2 == null:
		_rlog("  [FAIL] Analysis (pass 2): '" + analyzer.error_code + "'")
		_all_passed = false
		_finish()
		return
	
	# Use the new pipeline (CodegenMaster directly)
	var new_input = input.duplicate(true)
	new_input.IR = ir_result2.IR if ir_result2 else ir_result2
	
	var assy_new = new_codegen.parse_file(new_input)
	if assy_new.is_empty():
		_rlog("  [FAIL] New codegen (CodegenMaster) produced empty output")
		_all_passed = false
	else:
		var asm_lines_new = assy_new.split("\n")
		_rlog("  [PASS] " + str(assy_new.length()) + " chars, " + str(asm_lines_new.size()) + " lines")
		
		# Check expected patterns
		_check_expected_patterns("NEW codegen", assy_new, _expected_patterns_new)
		
		# Dump first 40 lines
		_dump_assembly("NEW", assy_new, 40)
		
		# Save
		_save_output("a_iter2_new.zd", assy_new)
	
	# =======================================================================
	# Done
	# =======================================================================
	_finish()


# ===========================================================================
# Helpers
# ===========================================================================

func _read_source(file_path: String) -> String:
	var text = ""
	var fp = FileAccess.open(file_path, FileAccess.READ)
	if fp == null:
		fp = FileAccess.open(ProjectSettings.globalize_path(file_path), FileAccess.READ)
	if fp:
		text = fp.get_as_text()
		fp.close()
	return text


func _check_expected_patterns(label: String, assy: String, patterns: Array) -> void:
	var lower = assy.to_lower()
	for pat in patterns:
		if lower.find(pat) >= 0:
			_rlog("    [OK] Contains expected pattern: '" + pat + "'")
		else:
			_rlog("    [WARN] Missing expected pattern: '" + pat + "'")


func _dump_assembly(label: String, assy: String, max_lines: int) -> void:
	var asm_lines = assy.split("\n")
	var ai = 0
	for line in asm_lines:
		ai += 1
		if ai <= max_lines:
			_rlog("    " + str(ai).pad_zeros(4) + " | " + line)
		elif ai == max_lines + 1:
			_rlog("    ... (" + str(asm_lines.size() - max_lines) + " more)")
			break


func _save_output(filename: String, text: String) -> void:
	var out_path = ProjectSettings.globalize_path("res://data/" + filename)
	var fp = FileAccess.open(out_path, FileAccess.WRITE)
	if fp:
		fp.store_string(text)
		fp.close()
		_rlog("  Saved: " + filename)


func _finish() -> void:
	_rlog("")
	_rlog(_sep)
	if _all_passed:
		_rlog("  [PASS] ALL TESTS COMPLETED")
	else:
		_rlog("  [FAIL] SOME TESTS FAILED")
	_rlog(_sep)
	
	var fp = FileAccess.open(_log_file, FileAccess.WRITE)
	if fp:
		fp.store_string(_results)
		fp.close()
		print("Results saved to: " + _log_file)
	print(_results)
	get_tree().quit(0 if _all_passed else 1)


func _rlog(msg: String) -> void:
	_results += msg + "\n"
	print(msg)
