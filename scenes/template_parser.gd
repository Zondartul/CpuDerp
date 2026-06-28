# ============================================================================
# template_parser.gd
# ============================================================================
# Parses `.tg` template files into an Inflated Template Graph (ITG).
#
# Usage:
#   var graph = TemplateParser.parse(tg_file_text)
#   # or with caching:
#   var graph = TemplateParser.load_or_parse("res://templates/codegen_templates.tg")
# ============================================================================

class_name TemplateParser
extends RefCounted

const ITG = preload("res://scenes/inflated_template_graph.gd")

# Cache file path — the .tres file written alongside the .tg file.
const CACHE_SUFFIX: String = "_cache.tres"
const TG_SUFFIX: String = ".tg"


# ============================================================================
# Public API
# ============================================================================

# Parse a complete .tg file text into an InflatedGraph.
static func parse(text: String) -> InflatedGraph:
	var graph = InflatedGraph.new()
	var lines = text.split("\n")
	var i = 0
	while i < lines.size():
		var raw = lines[i]
		var line = raw.strip_edges()
		if line.begins_with("@template"):
			var result = parse_template(lines, i)
			if result.size() >= 2 and result[0] != null:
				graph.templates[result[0].name] = result[0]
				i += result[1]
			else:
				i += 1
		elif line.is_empty() or line.begins_with("#"):
			i += 1
		else:
			i += 1
	return graph


# Load a .tg file with caching.
# If a .tres cache exists and is newer than the .tg, load the cache.
# Otherwise parse the .tg, save the cache, and return the result.
static func load_or_parse(file_path: String) -> InflatedGraph:
	var cache_path = file_path.replace(TG_SUFFIX, CACHE_SUFFIX)
	var tg_path = ProjectSettings.globalize_path(file_path)
	var cache_path_global = ProjectSettings.globalize_path(cache_path)

	# Determine if we need to re-parse by comparing timestamps.
	var needs_parse = true
	var cache_file = FileAccess.open(cache_path_global, FileAccess.READ)
	if cache_file != null:
		var tg_mod_time = _get_modified_time(tg_path)
		var cache_mod_time = _get_modified_time(cache_path_global)
		if cache_mod_time >= tg_mod_time:
			needs_parse = false
		cache_file.close()

	if not needs_parse:
		var loaded = ResourceLoader.load(cache_path)
		if loaded != null and loaded is InflatedGraph:
			return loaded

	# Parse the .tg file.
	var tg_file = FileAccess.open(tg_path, FileAccess.READ)
	if tg_file == null:
		push_error("TemplateParser: cannot open template file: " + file_path)
		return InflatedGraph.new()

	var text = tg_file.get_as_text()
	tg_file.close()

	var graph = parse(text)

	# Save cache.
	var result = ResourceSaver.save(graph, cache_path)
	if result != OK:
		push_warning("TemplateParser: failed to save cache: " + cache_path)

	return graph


# ============================================================================
# Template Block Parsing
# ============================================================================

# Parse one @template block starting at lines[start].
# Returns [TemplateDef, consumed_lines].
static func parse_template(lines: Array, start: int) -> Array:
	var header = lines[start].strip_edges()

	var parse_result = _parse_header(header)
	if parse_result.size() < 2:
		push_error("TemplateParser: invalid @template header at line %d: %s" % [start + 1, header])
		return [null, 1]

	var name: String = parse_result[0]
	var slots: Array = parse_result[1]  # Array[SlotDef]
	var param_variants: Array[String] = []

	var body: Array = []  # Array[ITGNode]
	var i = start + 1

	# Track all known slot/temp/label/imm names for emit-line role resolution.
	var known_names: Dictionary = {}
	for s in slots:
		known_names[s.name] = true

	# Variant switch tracking.
	var variant_switch_node: ITG.VariantSwitchNode = null
	# When inside a variant, current_variant_body accumulates nodes.
	var current_variant_body: Array = []
	# The list of variant names for the current @variant line (may be multiple).
	var current_variant_names: Array[String] = []

	while i < lines.size():
		var raw = lines[i]
		var line = raw.strip_edges()

		# End of template.
		if line == "@end":
			if variant_switch_node != null:
				# Finalize the last variant case.
				for vn in current_variant_names:
					variant_switch_node.variants[vn] = current_variant_body.duplicate(true)
				body.append(variant_switch_node)
			break

		# --- Variant switch handling ---
		if line.begins_with("@variant"):
			# Finalize previous variant case if we're already collecting.
			if variant_switch_node != null and not current_variant_names.is_empty():
				for vn in current_variant_names:
					variant_switch_node.variants[vn] = current_variant_body.duplicate(true)
				current_variant_body.clear()

			# Create the variant switch node on first encounter.
			if variant_switch_node == null:
				# Determine which slot the variants switch on.
				var variant_slot = _detect_variant_slot(slots, line)
				variant_switch_node = ITG.VariantSwitchNode.new(variant_slot)
				param_variants.append(variant_slot)

			# Parse variant names from line.
			current_variant_names = _parse_variant_names(line)
			current_variant_body.clear()
			i += 1
			continue

		# If we're inside a variant block, accumulate into the current variant body.
		if variant_switch_node != null:
			var node = _parse_simple_body_line(line, slots, known_names)
			if node != null:
				current_variant_body.append(node)
			i += 1
			continue

		# --- Block constructs (for, if) ---
		if line.begins_with("for "):
			var result = _parse_for_block(lines, i, slots, known_names)
			if result.size() >= 2 and result[0] != null:
				body.append(result[0])
				i += result[1]
			else:
				i += 1
			continue

		if line.begins_with("if "):
			var result = _parse_if_block(lines, i, slots, known_names)
			if result.size() >= 2 and result[0] != null:
				body.append(result[0])
				i += result[1]
			else:
				i += 1
			continue

		# --- Simple body lines ---
		var node = _parse_simple_body_line(line, slots, known_names)
		if node != null:
			body.append(node)

		i += 1

	var def = ITG.TemplateDef.new(name, slots, body, param_variants)
	var consumed = i - start + 1
	return [def, consumed]


# ============================================================================
# Header Parsing
# ============================================================================

# Parse "@template NAME(slot_defs):" → [name, Array[SlotDef]]
static func _parse_header(header: String) -> Array:
	# Remove "@template " prefix.
	var content = header.substr("@template".length()).strip_edges()
	if content.is_empty():
		return []

	# Remove trailing ":" if present.
	if content.ends_with(":"):
		content = content.substr(0, content.length() - 1).strip_edges()

	# Find the opening paren of the slot definitions.
	var paren_pos = content.find("(")
	if paren_pos == -1:
		return [content.strip_edges(), []]

	var name = content.substr(0, paren_pos).strip_edges()
	var slots_str = content.substr(paren_pos + 1)
	# Remove closing paren.
	if slots_str.ends_with(")"):
		slots_str = slots_str.substr(0, slots_str.length() - 1)

	var slots: Array = []  # Array[SlotDef]
	if not slots_str.strip_edges().is_empty():
		var parts = _split_slot_defs(slots_str)
		for part in parts:
			var slot = _parse_slot_def(part.strip_edges())
			if slot != null:
				slots.append(slot)

	return [name, slots]


# Split slot definitions separated by commas (respecting nested parens).
static func _split_slot_defs(slots_str: String) -> Array:
	var result: Array = []
	var depth = 0
	var current = ""
	for i in range(slots_str.length()):
		var ch = slots_str[i]
		if ch == "," and depth == 0:
			result.append(current)
			current = ""
		else:
			if ch == "(":
				depth += 1
			elif ch == ")":
				depth -= 1
			current += ch
	if not current.strip_edges().is_empty():
		result.append(current)
	return result


# Parse one slot definition like "dest:store" or "src:load".
static func _parse_slot_def(part: String) -> ITG.SlotDef:
	var colon_pos = part.find(":")
	if colon_pos == -1:
		push_error("TemplateParser: invalid slot definition: " + part)
		return null

	var name = part.substr(0, colon_pos).strip_edges()
	var type_str = part.substr(colon_pos + 1).strip_edges()
	var type = _parse_slot_type(type_str)
	return ITG.SlotDef.new(name, type, "")


# Map type string to SlotType enum.
static func _parse_slot_type(type_str: String) -> int:
	match type_str:
		"load":
			return ITG.SlotDef.SlotType.LOAD
		"store":
			return ITG.SlotDef.SlotType.STORE
		"addr":
			return ITG.SlotDef.SlotType.ADDR
		"variadic":
			return ITG.SlotDef.SlotType.VARIADIC
		"codeblock":
			return ITG.SlotDef.SlotType.CODEBLOCK
		"label":
			return ITG.SlotDef.SlotType.LABEL
		"optional":
			return ITG.SlotDef.SlotType.OPTIONAL
		"immediate":
			return ITG.SlotDef.SlotType.IMMEDIATE
		_:
			push_error("TemplateParser: unknown slot type: " + type_str)
			return ITG.SlotDef.SlotType.LOAD


# ============================================================================
# Simple Body Line Parsing (non-block directives)
# ============================================================================

# Parse a single body line that is NOT a block construct (@variant, for, if).
# Returns an ITGNode or null (for end markers, blank lines, comments).
static func _parse_simple_body_line(line: String, slots: Array, known_names: Dictionary) -> ITG.ITGNode:
	if line.is_empty() or line.begins_with("#"):
		return null

	if line.begins_with("@bind"):
		return _parse_bind(line)

	if line.begins_with("@temp"):
		return _parse_temp_allocation(line)

	if line.begins_with("@label"):
		return _parse_label_def(line)

	if line.begins_with("@new_imm"):
		return _parse_imm_def(line)

	if line.begins_with("@emit_cb"):
		return _parse_callback("emit_cb", line)

	if line.begins_with("@ref_cb"):
		return _parse_callback("ref_cb", line)

	if line.begins_with("@needs_deref"):
		return _parse_callback("needs_deref", line)

	if line.begins_with("@reverse"):
		return _parse_callback("reverse", line)

	if line.begins_with("endfor") or line.begins_with("endif"):
		# End markers — should not be reached in this path.
		return null

	# Default: emit line.
	return _parse_emit_line(line, slots, known_names)


# Parse "@bind slot_name = expression"
static func _parse_bind(line: String) -> ITG.BindingNode:
	# Remove "@bind " prefix.
	var content = line.substr("@bind".length()).strip_edges()
	var eq_pos = content.find("=")
	if eq_pos == -1:
		push_error("TemplateParser: invalid @bind: " + line)
		return null

	var slot_name = content.substr(0, eq_pos).strip_edges()
	var expr = content.substr(eq_pos + 1).strip_edges()
	return ITG.BindingNode.new(slot_name, expr)


# Parse "@temp name1, name2"
static func _parse_temp_allocation(line: String) -> ITG.TempAllocNode:
	var content = line.substr("@temp".length()).strip_edges()
	var names = _split_comma_list(content)
	return ITG.TempAllocNode.new(names)


# Parse "@label name1, name2"
static func _parse_label_def(line: String) -> ITG.LabelDefNode:
	var content = line.substr("@label".length()).strip_edges()
	var names = _split_comma_list(content)
	return ITG.LabelDefNode.new(names)


# Parse "@new_imm(value) → name" or "@new_imm(value) -> name"
static func _parse_imm_def(line: String) -> ITG.ImmDefNode:
	var content = line.substr("@new_imm".length()).strip_edges()

	# Extract value from parens: (value)
	var paren_open = content.find("(")
	var paren_close = content.find(")")
	if paren_open == -1 or paren_close == -1 or paren_close <= paren_open:
		push_error("TemplateParser: invalid @new_imm: " + line)
		return null

	var value_str = content.substr(paren_open + 1, paren_close - paren_open - 1).strip_edges()
	var value = value_str.to_int()

	# Extract name after arrow: → name or -> name
	var after_paren = content.substr(paren_close + 1).strip_edges()
	var name = ""
	# Check for unicode arrow → or ascii ->
	if after_paren.begins_with("→"):
		name = after_paren.substr(1).strip_edges()
	elif after_paren.begins_with("->"):
		name = after_paren.substr(2).strip_edges()
	else:
		push_error("TemplateParser: @new_imm missing arrow: " + line)
		return null

	return ITG.ImmDefNode.new(name, value)


# Parse @directive(arg) style callbacks.
static func _parse_callback(callback_name: String, line: String) -> ITG.CallbackNode:
	# Remove the @ prefix and directive name.
	var directive = "@" + callback_name
	var content = line.substr(directive.length()).strip_edges()

	# Extract args from parens: (arg1, arg2)
	var args: Array[String] = []
	if content.begins_with("("):
		var paren_close = content.find(")")
		if paren_close != -1:
			var args_str = content.substr(1, paren_close - 1)
			args = _split_comma_list(args_str)

	return ITG.CallbackNode.new(callback_name, args)


# ============================================================================
# EMIT_LINE Parsing
# ============================================================================

# Parse an assembly emit line containing {slot} references.
# The text_pattern is the raw line; slot_refs are extracted from {} patterns.
static func _parse_emit_line(line: String, slots: Array, known_names: Dictionary) -> ITG.EmitLineNode:
	var text_pattern = line
	var slot_refs: Array = []  # Array[SlotRef]

	# Find all {name} patterns in the line.
	var regex = RegEx.new()
	regex.compile("\\{([^}]+)\\}")

	var matches = regex.search_all(line)
	for match in matches:
		var full_match = match.get_string()   # e.g. "{dest}"
		var inner = match.get_string(1)       # e.g. "dest"
		var role = _resolve_slot_role(inner, slots, known_names)
		slot_refs.append(ITG.SlotRef.new(inner, role))

	return ITG.EmitLineNode.new(text_pattern, slot_refs)


# Determine the SlotRef.Role for a given {name} reference.
static func _resolve_slot_role(name: String, slots: Array, known_names: Dictionary) -> int:
	# Context references: {%name}
	if name.begins_with("%"):
		return ITG.SlotRef.Role.CONTEXT_REF

	# Computed references: {len(name)} or {len(args)}
	if name.begins_with("len(") and name.ends_with(")"):
		return ITG.SlotRef.Role.COMPUTED_REF

	# Look up in slot definitions.
	#
	# Semantics:
	#   A slot typed "store" (e.g. dest:store) means "the command stores its
	#   result into this operand".  When referenced as {dest} in an emit line
	#   like "mov {dest}, {src};", the destination needs a WRITABLE target,
	#   which is the store-mode resolution → STORE_REF.
	#
	#   A slot typed "load" (e.g. src:load) means "the command loads a value
	#   from this operand".  When referenced as {src}, it needs a READABLE
	#   value, which is the load-mode resolution → LOAD_REF.
	for slot in slots:
		if slot.name == name:
			match slot.type:
				ITG.SlotDef.SlotType.LOAD:
					return ITG.SlotRef.Role.LOAD_REF
				ITG.SlotDef.SlotType.STORE:
					return ITG.SlotRef.Role.STORE_REF
				ITG.SlotDef.SlotType.ADDR:
					return ITG.SlotRef.Role.ADDR_REF
				ITG.SlotDef.SlotType.LABEL:
					return ITG.SlotRef.Role.LABEL_REF
				ITG.SlotDef.SlotType.VARIADIC:
					return ITG.SlotRef.Role.VALUE_REF
				ITG.SlotDef.SlotType.CODEBLOCK:
					return ITG.SlotRef.Role.VALUE_REF
				ITG.SlotDef.SlotType.OPTIONAL:
					return ITG.SlotRef.Role.VALUE_REF
				ITG.SlotDef.SlotType.IMMEDIATE:
					return ITG.SlotRef.Role.VALUE_REF
			break

	# Check for temp and imm prefixes FIRST — these are identified by naming
	# convention, not by known_names membership, because @temp / @new_imm
	# declarations may appear after the emit line in the template body, and
	# the known_names set is populated from slot definitions only.
	if name.begins_with("tmp_"):
		return ITG.SlotRef.Role.TEMP_REF
	if name.begins_with("imm_"):
		return ITG.SlotRef.Role.IMM_REF

	# Check known names (labels, for-element variables, etc.).
	if known_names.has(name):
		return ITG.SlotRef.Role.VALUE_REF

	# Default fallback.
	return ITG.SlotRef.Role.VALUE_REF


# ============================================================================
# Variant Parsing
# ============================================================================

# Parse variant names from "@variant ADD, SUB, MUL, DIV, MOD:"
static func _parse_variant_names(line: String) -> Array[String]:
	var content = line.substr("@variant".length()).strip_edges()
	if content.ends_with(":"):
		content = content.substr(0, content.length() - 1).strip_edges()
	# Split by comma.
	var names = _split_comma_list(content)
	return names


# Determine which slot the @variant directives switch on.
# Currently detects the first "immediate" slot; defaults to "op".
static func _detect_variant_slot(slots: Array, _variant_line: String) -> String:
	for slot in slots:
		if slot.type == ITG.SlotDef.SlotType.IMMEDIATE:
			return slot.name
	return "op"


# ============================================================================
# For Block Parsing
# ============================================================================

# Parse "for element in list: ... endfor"
# Returns [ForEachNode, consumed_lines].
static func _parse_for_block(lines: Array, start: int, slots: Array, known_names: Dictionary) -> Array:
	var header = lines[start].strip_edges()

	# Parse "for element_name in list_name:"
	var content = header.substr("for".length()).strip_edges()
	if content.ends_with(":"):
		content = content.substr(0, content.length() - 1).strip_edges()

	var in_pos = content.find(" in ")
	if in_pos == -1:
		push_error("TemplateParser: invalid for header: " + header)
		return [null, 1]

	var element_name = content.substr(0, in_pos).strip_edges()
	var list_name = content.substr(in_pos + 4).strip_edges()

	var body: Array = []  # Array[ITGNode]
	var i = start + 1
	var depth = 1  # Track nesting (though GDScript templates shouldn't nest for).

	while i < lines.size():
		var line = lines[i].strip_edges()
		if line == "endfor":
			depth -= 1
			if depth <= 0:
				break
		elif line.begins_with("for "):
			depth += 1
		elif line.begins_with("if "):
			# Nested if inside for — delegate to if parser.
			var result = _parse_if_block(lines, i, slots, known_names)
			if result.size() >= 2 and result[0] != null:
				body.append(result[0])
				i += result[1] - 1  # -1 because we'll i += 1 below
			i += 1
			continue
		elif line == "endif" or line == "endfor":
			pass  # handled above
		else:
			var node = _parse_simple_body_line(line, slots, known_names)
			if node != null:
				body.append(node)
		i += 1

	var node = ITG.ForEachNode.new(list_name, element_name, body)
	return [node, i - start + 1]


# ============================================================================
# If Block Parsing
# ============================================================================

# Parse "if {slot}: ... endif"
# Returns [IfConditionalNode, consumed_lines].
static func _parse_if_block(lines: Array, start: int, slots: Array, known_names: Dictionary) -> Array:
	var header = lines[start].strip_edges()

	# Parse "if {slot_name}:" — extract the slot name from braces.
	var content = header.substr("if".length()).strip_edges()
	if content.ends_with(":"):
		content = content.substr(0, content.length() - 1).strip_edges()

	# Extract slot name from {slot_name}.
	var slot_name = content
	var regex = RegEx.new()
	regex.compile("\\{([^}]+)\\}")
	var match = regex.search(content)
	if match:
		slot_name = match.get_string(1)
	# If no braces, treat the whole text as the slot name.

	var body: Array = []  # Array[ITGNode]
	var i = start + 1
	var depth = 1

	while i < lines.size():
		var line = lines[i].strip_edges()
		if line == "endif":
			depth -= 1
			if depth <= 0:
				break
		elif line.begins_with("if "):
			depth += 1
		elif line.begins_with("for "):
			var result = _parse_for_block(lines, i, slots, known_names)
			if result.size() >= 2 and result[0] != null:
				body.append(result[0])
				i += result[1] - 1
			i += 1
			continue
		elif line == "endfor":
			pass
		else:
			var node = _parse_simple_body_line(line, slots, known_names)
			if node != null:
				body.append(node)
		i += 1

	var node = ITG.IfConditionalNode.new(slot_name, body)
	return [node, i - start + 1]


# ============================================================================
# Utility
# ============================================================================

# Split a comma-separated list, trimming whitespace.
static func _split_comma_list(text: String) -> Array[String]:
	var result: Array[String] = []
	var parts = text.split(",")
	for part in parts:
		var trimmed = part.strip_edges()
		if not trimmed.is_empty():
			result.append(trimmed)
	return result


# Get the last-modified timestamp of a file path.
static func _get_modified_time(path: String) -> int:
	return FileAccess.get_modified_time(path)
