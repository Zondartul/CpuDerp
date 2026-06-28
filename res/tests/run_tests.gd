# ============================================================================
# run_tests.gd — Test Runner for CpuDerp Codegen Refactor
# ============================================================================
#
# Usage in Godot editor:
#   RunTests.run_all()
#   RunTests.run_suite("template_parser")
#   RunTests.run_suite("abi_scanner")
#
# NOTE: This test runner is designed to be run from within the Godot editor
# (e.g., via the editor console with `RunTests.run_all()`) because it relies
# on class_name resolution which is not available in --headless --script mode.
#
# In --headless --script mode, you can still use the --check-only flag to
# verify syntax:
#   godot --headless --check-only --path <project>
# ============================================================================

# Test suite preloads
# Note: These use res://res/ path because the project's res/ directory is
# nested inside the Godot resource root.
const TestTemplateParser   = preload("res://res/tests/test_template_parser.gd")
const TestABIScanner       = preload("res://res/tests/test_abi_scanner.gd")
const TestStorAlloc        = preload("res://res/tests/test_stor_alloc.gd")
const TestCodegenIntegration = preload("res://res/tests/test_codegen_integration.gd")
const TestGoldenRegression = preload("res://res/tests/test_golden_regression.gd")

static func run_all() -> void:
	print("\n" + "".repeat(60))
	print("  CpuDerp Codegen Refactor — Test Suite")
	print("".repeat(60))
	print("")

	var total_failed = 0
	var suites_run = 0

	# Run each suite
	total_failed += _run_suite("Template Parser",     TestTemplateParser,     "test_template_parser")
	total_failed += _run_suite("ABI Scanner",          TestABIScanner,         "test_abi_scanner")
	total_failed += _run_suite("Storage Allocator",    TestStorAlloc,          "test_stor_alloc")
	total_failed += _run_suite("Codegen Integration",  TestCodegenIntegration, "test_codegen_integration")
	total_failed += _run_suite("Golden Regression",    TestGoldenRegression,   "test_golden_regression")

	# Summary
	print("")
	print("".repeat(60))
	if total_failed == 0:
		print("  ✅ ALL TESTS PASSED — %d suites, 0 failures" % suites_run)
	else:
		push_error("  ❌ %d TEST(S) FAILED across %d suites" % [total_failed, suites_run])
	print("".repeat(60))


static func _run_suite(name: String, suite, suite_key: String) -> int:
	if suite == null:
		push_error("Suite [%s] could not be loaded — tests skipped." % name)
		return 0

	if not suite.has_method("run_all"):
		push_error("Suite [%s] has no run_all() — tests skipped." % name)
		return 0

	print("  --- %s ---" % name)
	var failed = suite.run_all()
	if failed == 0:
		print("")
	return failed


# Run a single suite by name (case-insensitive prefix match).
static func run_suite(name: String) -> void:
	var suites = {
		"template_parser":     TestTemplateParser,
		"abi_scanner":         TestABIScanner,
		"stor_alloc":          TestStorAlloc,
		"codegen_integration": TestCodegenIntegration,
		"golden_regression":   TestGoldenRegression,
	}
	var lower = name.to_lower()
	for key in suites:
		if key.begins_with(lower) or lower.begins_with(key):
			_run_suite(key, suites[key], key)
			return
	push_error("No test suite matching [%s]. Options: %s" % [name, suites.keys()])
