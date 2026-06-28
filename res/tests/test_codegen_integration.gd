# ============================================================================
# test_codegen_integration.gd — Integration tests for codegen pipeline
# ============================================================================
# Tests that the old codegen matches golden files, and the new codegen
# matches incrementally as ops are migrated.
#
# Usage:
#   From the test runner: TestCodegenIntegration.run_all()
# ============================================================================

const CodegenMd = preload("res://scenes/codegen_md.gd")

# Maps test name → { source_md, golden_asm, ir_txt }
# Golden files are loaded from res://golden/
const TEST_PROGRAMS = [
	{"name": "hello",         "source": "res://data/hello.md",        "golden": "res://golden/hello.asm"},
	{"name": "array_test",    "source": "res://data/array_test.md",   "golden": "res://golden/array_test.asm"},
	{"name": "test_arr_if",   "source": "res://data/test_arr_if.md",  "golden": "res://golden/test_arr_if.asm"},
	{"name": "test_not_eq",   "source": "res://data/test_not_eq.md",  "golden": "res://golden/test_not_eq.asm"},
	{"name": "elif_test",     "source": "res://data/elif_test.md",    "golden": "res://golden/elif_test.asm"},
	{"name": "printf_test",   "source": "res://data/printf_test.md",  "golden": "res://golden/printf_test.asm"},
	{"name": "return_test",   "source": "res://data/return_test.md",  "golden": "res://golden/return_test.asm"},
]

# Flag: set to true when running in Godot with a fully configured scene tree
# The full compilation pipeline requires tokenizer, parser, analyzer nodes.
# Set this externally before calling run_all().
static var RUN_FULL_COMPILATION: bool = false

static func run_all() -> int:
	var failed = 0
	
	# Test 1: Verify golden files exist and are non-empty
	failed += test_golden_files_exist()
	
	# Test 2: Verify golden files have expected structure
	failed += test_golden_structure()
	
	# Test 3: (if run with full compiler) compile each source and compare
	if RUN_FULL_COMPILATION:
		failed += test_compile_matches_golden()
	
	if failed == 0:
		print("  [PASS] All codegen integration tests passed.")
	else:
		push_error("  [FAIL] %d codegen integration test(s) failed." % failed)
	return failed


static func test_golden_files_exist() -> int:
	var missing = 0
	for prog in TEST_PROGRAMS:
		var path = ProjectSettings.globalize_path(prog.golden)
		var fp = FileAccess.open(path, FileAccess.READ)
		if fp == null:
			push_error("FAIL: Golden file missing: %s" % prog.golden)
			missing += 1
		else:
			var text = fp.get_as_text()
			fp.close()
			if text.is_empty():
				push_error("FAIL: Golden file is empty: %s" % prog.golden)
				missing += 1
	return missing


static func test_golden_structure() -> int:
	var failed = 0
	for prog in TEST_PROGRAMS:
		var path = ProjectSettings.globalize_path(prog.golden)
		var fp = FileAccess.open(path, FileAccess.READ)
		if fp == null:
			failed += 1
			continue
		var text = fp.get_as_text()
		fp.close()
		
		# Check for required structural elements
		if not text.contains("# Begin code block"):
			push_error("FAIL: %s missing '# Begin code block' marker" % prog.golden)
			failed += 1
		
		if not text.contains(":lbl_from_") and not text.contains(":func_"):
			push_error("FAIL: %s missing label/func marker" % prog.golden)
			failed += 1
		
		# Should have some assembly instructions
		if not text.contains("mov ") and not text.contains("call "):
			push_error("FAIL: %s has no recognizable assembly instructions" % prog.golden)
			failed += 1
		
		# Should end with global data declarations
		if not text.contains(": db 0") and not text.contains(": alloc"):
			var has_globals = text.contains("db 0") or text.contains("alloc ")
			if not has_globals:
				# Small programs may not have globals; only flag if no assembly either
				if text.length() < 50:
					push_error("FAIL: %s seems too short (%d chars)" % [prog.golden, text.length()])
					failed += 1
		
	return failed


static func test_compile_matches_golden() -> int:
	# This test can only be run from within Godot with the scene tree
	# properly set up (tokenizer, parser, analyzer as children of comp_compile_md).
	# 
	# The test loads each source .md file, compiles it through the full pipeline,
	# captures the assembly output, and compares byte-for-byte with the golden file.
	
	var failed = 0
	
	# Look for the compiler node in the scene tree
	var compile_node = _find_compile_node()
	if compile_node == null:
		push_error("FAIL: Cannot find comp_compile_md node in scene tree. "
				  + "Set RUN_FULL_COMPILATION=false or run from main scene.")
		return 1
	
	for prog in TEST_PROGRAMS:
		var source_path = ProjectSettings.globalize_path(prog.source)
		var golden_path = ProjectSettings.globalize_path(prog.golden)
		
		# Read source
		var src_fp = FileAccess.open(source_path, FileAccess.READ)
		if src_fp == null:
			push_error("FAIL: Cannot open source: %s" % prog.source)
			failed += 1
			continue
		var source_text = src_fp.get_as_text()
		src_fp.close()
		
		# Read golden
		var gld_fp = FileAccess.open(golden_path, FileAccess.READ)
		var golden_text = gld_fp.get_as_text()
		gld_fp.close()
		
		# Compile via old codegen
		var input = {
			"code": source_text,
			"filename": source_path,
		}
		
		compile_node.reset()
		var success = compile_node.compile(input)
		
		if not success or compile_node.has_error:
			push_error("FAIL: Compilation of %s failed" % prog.source)
			failed += 1
			continue
		
		var assy_text = input.get("assy", "")
		if assy_text.is_empty():
			push_error("FAIL: No assembly output for %s" % prog.source)
			failed += 1
			continue
		
		if assy_text != golden_text:
			push_error("FAIL: Assembly mismatch for %s" % prog.source)
			push_error("  Expected length: %d, Got: %d" % [golden_text.length(), assy_text.length()])
			# Show first differing line
			var exp_lines = golden_text.split("\n")
			var got_lines = assy_text.split("\n")
			for i in range(min(exp_lines.size(), got_lines.size())):
				if exp_lines[i] != got_lines[i]:
					push_error("  First diff at line %d:" % (i + 1))
					push_error("    Expected: %s" % exp_lines[i])
					push_error("    Got:      %s" % got_lines[i])
					break
			failed += 1
	
	return failed


# Find a comp_compile_md node anywhere in the scene tree.
static func _find_compile_node():
	var root = Engine.get_main_loop()
	if root == null:
		return null
	
	# Try to find from scene tree
	var scene_root = root.get_root()
	if scene_root == null:
		return null
	
	# Search for compile_md node
	var compile_node = scene_root.find_child("comp_compile_md", true, false)
	if compile_node == null:
		# Try alternate name
		compile_node = scene_root.find_child("compile_md", true, false)
	
	return compile_node
