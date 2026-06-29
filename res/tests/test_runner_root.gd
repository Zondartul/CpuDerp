# ============================================================================
# test_runner_root.gd — Iteration 1 test runner
# ============================================================================
extends Node


const TESTS = [
	{"name": "test_iter1a", "desc": "Simple variable and arithmetic",     "file": "res://res/data/test_iter1a.md"},
	{"name": "test_iter1b", "desc": "Function call",                     "file": "res://res/data/test_iter1b.md"},
	{"name": "test_iter1c", "desc": "Arrays",                            "file": "res://res/data/test_iter1c.md"},
	{"name": "test_iter1d", "desc": "Control flow (if/else)",            "file": "res://res/data/test_iter1d.md"},
]

const LOG_FILE = "res://res/data/test_iter1_results.txt"

var _results := ""
var _all_passed := true
var _sep := ""


func _ready() -> void:
	_sep = "=".repeat(70)
	_rlog(_sep)
	_rlog("  CpuDerp - Iteration 1 Test Suite")
	_rlog("  Timestamp: " + Time.get_datetime_string_from_system())
	_rlog(_sep)
	_rlog("")
	
	await get_tree().process_frame
	_run_all_tests()


func _run_all_tests() -> void:
	var tok = _make_tok()
	var parser = _make_parser()
	var analyzer = _make_analyzer()
	var codegen = _make_codegen()
	
	if tok == null or parser == null or analyzer == null or codegen == null:
		_rlog("FATAL: Could not build compiler components")
		_all_passed = false
		_finish()
		return
	
	_rlog("  [SETUP] All components ready.")
	_rlog("")
	
	for t in TESTS:
		_run_single_test(tok, parser, analyzer, codegen, t)
	
	_finish()


func _make_tok():
	var tok = load("res://scenes/md_tokenizer.gd").new()
	add_child(tok)
	var erep = load("res://class_ErrorReporter.gd").new()
	erep.proxy = tok
	tok.erep = erep
	tok.reset()
	return tok


func _make_parser():
	var parser = load("res://scenes/parser_md.gd").new()
	add_child(parser)
	var erep = load("res://class_ErrorReporter.gd").new()
	erep.proxy = parser
	parser.erep = erep
	parser.reset()
	return parser


func _make_analyzer():
	var ir = load("res://scenes/ir_md.gd").new()
	add_child(ir)
	var analyzer = load("res://scenes/analyzer_md.gd").new()
	add_child(analyzer)
	var erep = load("res://class_ErrorReporter.gd").new()
	erep.proxy = analyzer
	analyzer.IR = ir
	analyzer.erep = erep
	analyzer.reset()
	return analyzer


func _make_codegen():
	var cg = load("res://scenes/codegen_md.gd").new()
	add_child(cg)
	return cg


func _run_single_test(tok, parser, analyzer, codegen, test_def: Dictionary) -> void:
	var name = test_def.name
	var desc = test_def.desc
	var file_path = test_def.file
	
	_rlog("")
	_rlog("-".repeat(70))
	_rlog("  TEST: " + name + " - " + desc)
	_rlog("  File: " + file_path)
	_rlog("-".repeat(70))
	
	# Read source - try multiple paths
	var source_text = ""
	var paths_to_try = [
		file_path,
		ProjectSettings.globalize_path(file_path),
		"res://data/" + file_path.get_file(),
		"res://res/data/" + file_path.get_file(),
	]
	
	for p in paths_to_try:
		var fp = FileAccess.open(p, FileAccess.READ)
		if fp:
			source_text = fp.get_as_text()
			fp.close()
			_rlog("  [INFO] Opened via: " + p)
			break
	
	if source_text.is_empty():
		_rlog("  [ERROR] Cannot open: " + file_path)
		_all_passed = false
		return
	
	_rlog("")
	_rlog("  Source code:")
	var li = 0
	for line in source_text.split("\n"):
		li += 1
		_rlog("    " + str(li).pad_zeros(3) + " | " + line)
	_rlog("")
	
	var input = {"text": source_text, "filename": file_path}
	
	# Step 1: Tokenize
	_rlog("  --- Step 1: Tokenize ---")
	tok.reset()
	tok.error_code = ""
	tok.cur_path = file_path.get_base_dir()
	tok.cur_filename = file_path
	var tokens = tok.tokenize(input)
	if tok.error_code != "" or tokens.is_empty():
		_rlog("  [FAIL] Tokenization: '" + tok.error_code + "'")
		_all_passed = false
		return
	_rlog("  [PASS] " + str(tokens.size()) + " tokens")
	for i in range(mini(tokens.size(), 20)):
		_rlog("    [" + str(i) + "] " + str(tokens[i]))
	if tokens.size() > 20:
		_rlog("    ... (" + str(tokens.size() - 20) + " more)")
	input.tokens = tokens
	
	# Step 2: Parse
	_rlog("  --- Step 2: Parse ---")
	parser.reset()
	parser.error_code = ""
	var ast = parser.parse(input)
	if parser.error_code != "" or ast == null or ast.is_empty():
		_rlog("  [FAIL] Parsing: '" + parser.error_code + "'")
		_all_passed = false
		return
	var ast_s = "empty" if ast.size() == 0 else str(ast[0].tok_class) + " (" + str(ast.size()) + " nodes)"
	_rlog("  [PASS] AST: " + ast_s)
	input.ast = ast
	
	# Step 3: Analyze
	_rlog("  --- Step 3: Analyze (IR gen) ---")
	analyzer.reset()
	analyzer.error_code = ""
	var ir_result = analyzer.analyze(input)
	if analyzer.error_code != "" or ir_result == null:
		_rlog("  [FAIL] Analysis: '" + analyzer.error_code + "'")
		_all_passed = false
		return
	_rlog("  [PASS] IR generated")
	input.IR = ir_result
	input.filename = "IR.txt"
	
	# Step 4: Codegen
	_rlog("  --- Step 4: Codegen ---")
	var assy = codegen.parse_file(input)
	if assy.is_empty():
		_rlog("  [FAIL] Codegen empty output")
		_all_passed = false
		return
	_rlog("  [PASS] " + str(assy.length()) + " chars assembly")
	
	var asm_lines = assy.split("\n")
	_rlog("  Assembly (" + str(asm_lines.size()) + " lines):")
	var ai = 0
	for line in asm_lines:
		ai += 1
		if ai <= 50:
			_rlog("    " + str(ai).pad_zeros(4) + " | " + line)
		elif ai == 51:
			_rlog("    ... (" + str(asm_lines.size() - 50) + " more)")
			break
	
	var out_path = ProjectSettings.globalize_path("res://res/data/a_test_" + name + ".zd")
	var out_fp = FileAccess.open(out_path, FileAccess.WRITE)
	if out_fp:
		out_fp.store_string(assy)
		out_fp.close()
		_rlog("  Saved: a_test_" + name + ".zd")
	
	_rlog("  [SUCCESS]")


func _finish() -> void:
	_rlog("")
	_rlog(_sep)
	if _all_passed:
		_rlog("  [PASS] ALL TESTS COMPLETED")
	else:
		_rlog("  [FAIL] SOME TESTS FAILED")
	_rlog(_sep)
	
	var fp = FileAccess.open(LOG_FILE, FileAccess.WRITE)
	if fp:
		fp.store_string(_results)
		fp.close()
		print("Results saved: " + LOG_FILE)
	print(_results)
	get_tree().quit(0 if _all_passed else 1)


func _rlog(msg: String) -> void:
	_results += msg + "\n"
	print(msg)
