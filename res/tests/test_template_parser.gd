# ============================================================================
# test_template_parser.gd — Unit tests for template_parser.gd
# ============================================================================
# Tests that TemplateParser.parse() correctly reads codegen_templates.tg
# and produces the correct InflatedGraph.
#
# Usage:
#   From the test runner: TestTemplateParser.run_all()
# ============================================================================

const TemplateParser = preload("res://scenes/template_parser.gd")
const ITG = preload("res://scenes/inflated_template_graph.gd")

static func run_all() -> int:
	var failed = 0
	
	failed += test_parse_returns_inflated_graph()
	failed += test_all_13_templates_parsed()
	failed += test_mov_template_slots()
	failed += test_op_has_12_variants()
	failed += test_call_template_variadic_args()
	failed += test_while_template_has_labels()
	failed += test_if_template_has_new_imm()
	failed += test_enter_template_has_immediate_slot()
	failed += test_leave_template_has_no_slots()
	failed += test_return_template_has_optional_slot()
	failed += test_cache_load_or_parse()
	
	if failed == 0:
		print("  [PASS] All template_parser tests passed.")
	else:
		push_error("  [FAIL] %d template_parser test(s) failed." % failed)
	return failed


# Parse the actual codegen_templates.tg file and return the graph.
static func _parse_tg() -> InflatedGraph:
	var path = ProjectSettings.globalize_path("res://templates/codegen_templates.tg")
	var fp = FileAccess.open(path, FileAccess.READ)
	if fp == null:
		push_error("Cannot open codegen_templates.tg")
		return null
	var text = fp.get_as_text()
	fp.close()
	return TemplateParser.parse(text)


# --- Individual tests --------------------------------------------------------

static func test_parse_returns_inflated_graph() -> int:
	var graph = _parse_tg()
	if graph == null:
		push_error("FAIL: parse() returned null")
		return 1
	if not (graph is InflatedGraph):
		push_error("FAIL: parse() did not return InflatedGraph, got %s" % typeof(graph))
		return 1
	return 0


static func test_all_13_templates_parsed() -> int:
	var graph = _parse_tg()
	if graph == null:
		return 1
	
	var expected = [
		"MOV", "OP", "IF", "ELSE_IF", "ELSE", "WHILE",
		"CALL", "CALL_INDIRECT", "RETURN", "ENTER", "LEAVE",
		"ALLOC", "MOV_ARR"
	]
	
	var missing = []
	for name in expected:
		if not graph.templates.has(name):
			missing.append(name)
	
	if missing.size() > 0:
		push_error("FAIL: Missing templates: %s" % ", ".join(missing))
		return 1
	
	# Also check no unexpected templates
	if graph.templates.size() != expected.size():
		push_error("FAIL: Expected %d templates, got %d" % [expected.size(), graph.templates.size()])
		return 1
	
	return 0


static func test_mov_template_slots() -> int:
	var graph = _parse_tg()
	if graph == null:
		return 1
	
	var mov = graph.templates.get("MOV")
	if mov == null:
		push_error("FAIL: MOV template not found")
		return 1
	
	if mov.slots.size() != 2:
		push_error("FAIL: MOV expected 2 slots, got %d" % mov.slots.size())
		return 1
	
	# Check first slot: dest:store
	var slot0 = mov.slots[0]
	if slot0.name != "dest":
		push_error("FAIL: MOV slot[0] name expected 'dest', got '%s'" % slot0.name)
		return 1
	
	# Check second slot: src:load
	var slot1 = mov.slots[1]
	if slot1.name != "src":
		push_error("FAIL: MOV slot[1] name expected 'src', got '%s'" % slot1.name)
		return 1
	
	# Check body has at least a binding and an emit line
	if mov.body.size() < 2:
		push_error("FAIL: MOV body expected >=2 nodes, got %d" % mov.body.size())
		return 1
	
	return 0


static func test_op_has_12_variants() -> int:
	var graph = _parse_tg()
	if graph == null:
		return 1
	
	var op = graph.templates.get("OP")
	if op == null:
		push_error("FAIL: OP template not found")
		return 1
	
	# Check that the body contains a VariantSwitchNode
	var has_variant = false
	var variant_count = 0
	for node in op.body:
		if node is ITG.VariantSwitchNode:
			has_variant = true
			variant_count = node.variants.size()
			break
	
	if not has_variant:
		push_error("FAIL: OP template missing VariantSwitchNode")
		return 1
	
	# Expect 12 variants: INC, DEC, ADD, SUB, MUL, DIV, MOD,
	#                     GREATER, LESS, EQUAL, NOT_EQUAL, INDEX
	var expected_variants = 12
	if variant_count != expected_variants:
		push_error("FAIL: OP expected %d variants, got %d" % [expected_variants, variant_count])
		return 1
	
	return 0


static func test_call_template_variadic_args() -> int:
	var graph = _parse_tg()
	if graph == null:
		return 1
	
	var call = graph.templates.get("CALL")
	if call == null:
		push_error("FAIL: CALL template not found")
		return 1
	
	# Check that one of the slots is variadic
	var has_variadic = false
	for slot in call.slots:
		if slot.type == ITG.SlotDef.SlotType.VARIADIC:
			has_variadic = true
			break
	
	if not has_variadic:
		push_error("FAIL: CALL template has no variadic slot")
		return 1
	
	return 0


static func test_while_template_has_labels() -> int:
	var graph = _parse_tg()
	if graph == null:
		return 1
	
	var wh = graph.templates.get("WHILE")
	if wh == null:
		push_error("FAIL: WHILE template not found")
		return 1
	
	var has_label_def = false
	for node in wh.body:
		if node is ITG.LabelDefNode:
			has_label_def = true
			break
	
	if not has_label_def:
		push_error("FAIL: WHILE template missing label definitions")
		return 1
	
	return 0


static func test_if_template_has_new_imm() -> int:
	var graph = _parse_tg()
	if graph == null:
		return 1
	
	var if_tmpl = graph.templates.get("IF")
	if if_tmpl == null:
		push_error("FAIL: IF template not found")
		return 1
	
	var has_imm_def = false
	for node in if_tmpl.body:
		if node is ITG.ImmDefNode:
			has_imm_def = true
			break
	
	if not has_imm_def:
		push_error("FAIL: IF template missing ImmDefNode for imm_0")
		return 1
	
	return 0


static func test_enter_template_has_immediate_slot() -> int:
	var graph = _parse_tg()
	if graph == null:
		return 1
	
	var enter = graph.templates.get("ENTER")
	if enter == null:
		push_error("FAIL: ENTER template not found")
		return 1
	
	if enter.slots.size() < 1:
		push_error("FAIL: ENTER expected >=1 slots, got %d" % enter.slots.size())
		return 1
	
	# Check that scp slot is type IMMEDIATE
	var slot0 = enter.slots[0]
	if slot0.name != "scp":
		push_error("FAIL: ENTER slot[0] name expected 'scp', got '%s'" % slot0.name)
		return 1
	
	return 0


static func test_leave_template_has_no_slots() -> int:
	var graph = _parse_tg()
	if graph == null:
		return 1
	
	var leave = graph.templates.get("LEAVE")
	if leave == null:
		push_error("FAIL: LEAVE template not found")
		return 1
	
	if leave.slots.size() != 0:
		push_error("FAIL: LEAVE expected 0 slots, got %d" % leave.slots.size())
		return 1
	
	return 0


static func test_return_template_has_optional_slot() -> int:
	var graph = _parse_tg()
	if graph == null:
		return 1
	
	var ret = graph.templates.get("RETURN")
	if ret == null:
		push_error("FAIL: RETURN template not found")
		return 1
	
	var has_optional = false
	for slot in ret.slots:
		if slot.type == ITG.SlotDef.SlotType.OPTIONAL:
			has_optional = true
			break
	
	if not has_optional:
		push_error("FAIL: RETURN template has no optional slot")
		return 1
	
	return 0


static func test_cache_load_or_parse() -> int:
	# Test that load_or_parse works with the actual file
	var graph = TemplateParser.load_or_parse("res://templates/codegen_templates.tg")
	if graph == null:
		push_error("FAIL: load_or_parse() returned null")
		return 1
	if not (graph is InflatedGraph):
		push_error("FAIL: load_or_parse() did not return InflatedGraph")
		return 1
	if graph.templates.size() < 13:
		push_error("FAIL: load_or_parse() produced graph with %d templates (expected >=13)" % graph.templates.size())
		return 1
	return 0
