# ============================================================================
# TemplateExpander — Pass 2 imperative template expander
# ============================================================================
#
# Walks the Inflated Template Graph (ITG) body for each IR command,
# resolves slot references against the ABIManifest, and produces assembly
# text via the EmitBuffer.
#
# Handles:
#   - EMIT_LINE nodes            → delegate to AsmEmitter
#   - FOREACH nodes              → iterate variadic lists, recurse body
#   - VARIANT_SWITCH nodes       → dispatch on slot value
#   - CALLBACK nodes             → @emit_cb, @reverse, @ref_cb, @needs_deref
#   - LABEL_DEF nodes            → emit pre-generated labels
#   - TEMP_ALLOC / IMM_DEF nodes → pass (already handled in Pass 1)
#   - IF_CONDITIONAL nodes       → conditional emission based on slot presence
#   - BINDING nodes              → resolved before emit_node_list
#
# Context variables: {%if_block_lbl_end} is set by IF/ELSE_IF expansion
# so that ELSE_IF/ELSE can jump to the parent IF's end label.
#
# Implements the algorithm from plan section 6.3.
# ============================================================================

class_name TemplateExpander
extends RefCounted

const AsmEmitter   = preload("res://scenes/asm_emit.gd")
const ITG          = preload("res://scenes/inflated_template_graph.gd")
const ABIManifest  = preload("res://scenes/ab_manifest.gd")
const CodegenResult = preload("res://scenes/codegen_result.gd")


# ============================================================================
# Public API
# ============================================================================

static func expand(
	commands: Array,
	code_blocks: Dictionary,
	graph,
	manifest
) -> CodegenResult:
	var buf = CodegenResult.EmitBuffer.new()
	var visited = {}
	var context = {}  # Template-level context variables ({%name})

	for cmd in commands:
		var op_name = cmd.words[0] if cmd.words.size() > 0 else ""

		if op_name == "__LBL_FROM__":
			var cb_name = cmd.words[1] if cmd.words.size() > 1 else ""
			var lbl_name = cmd.words[2] if cmd.words.size() > 2 else ""
			buf.append("# Begin code block %s\n" % cb_name, null)
			buf.append(":%s:\n" % lbl_name, null)
			continue

		if op_name == "__LBL_TO__":
			var cb_name = cmd.words[1] if cmd.words.size() > 1 else ""
			var lbl_name = cmd.words[2] if cmd.words.size() > 2 else ""
			buf.append(":%s:\n" % lbl_name, null)
			buf.append("# End code block %s\n" % cb_name, null)
			continue

		var tmpl = graph.templates.get(op_name)
		if tmpl == null:
			return CodegenResult.failure(
				"TemplateExpander: no template for IR command [%s]" % op_name
			)

		var bindings = _build_bindings_from_body(tmpl, cmd.words)

		# Context variable injection for IF/ELSE_IF chains
		if op_name == "IF" or op_name == "ELSE_IF":
			var lbl_end = manifest.labels.get("lbl_end")
			if lbl_end != null:
				context["%if_block_lbl_end"] = lbl_end
				bindings["%if_block_lbl_end"] = lbl_end

		emit_node_list(tmpl.body, cmd, bindings, manifest, buf, visited, code_blocks, graph, context)

	AsmEmitter.fixup_enter_leave(buf, manifest)
	var loc_map = buf.build_location_map()
	return CodegenResult.success(buf.to_text(), loc_map)


# ============================================================================
# emit_node_list
# ============================================================================
static func emit_node_list(
	nodes: Array,
	cmd,
	bindings: Dictionary,
	manifest,
	buf,
	visited: Dictionary,
	code_blocks: Dictionary,
	graph,
	context: Dictionary
) -> void:
	for node in nodes:
		match node.type:
			ITG.ITGNode.NodeType.EMIT_LINE:
				var line_bindings = bindings.duplicate()
				for key in context:
					line_bindings[key] = context[key]
				AsmEmitter.emit_line(
					node.text_pattern, node.slot_refs,
					line_bindings, manifest, buf, cmd.loc
				)

			ITG.ITGNode.NodeType.FOREACH:
				_handle_foreach(node, cmd, bindings, manifest, buf, visited, code_blocks, graph, context)

			ITG.ITGNode.NodeType.VARIANT_SWITCH:
				_handle_variant_switch(node, cmd, bindings, manifest, buf, visited, code_blocks, graph, context)

			ITG.ITGNode.NodeType.CALLBACK:
				_handle_callback(node, cmd, bindings, manifest, buf, visited, code_blocks, graph, context)

			ITG.ITGNode.NodeType.LABEL_DEF:
				_handle_label_def(node, manifest, buf)

			ITG.ITGNode.NodeType.TEMP_ALLOC:
				pass

			ITG.ITGNode.NodeType.IMM_DEF:
				pass

			ITG.ITGNode.NodeType.BINDING:
				pass

			ITG.ITGNode.NodeType.IF_CONDITIONAL:
				_handle_if_conditional(node, cmd, bindings, manifest, buf, visited, code_blocks, graph, context)

			_:
				push_error("TemplateExpander: unknown ITGNode type [%d]" % node.type)


# ============================================================================
# Internal Handlers
# ============================================================================

static func _build_bindings_from_body(tmpl, words: Array) -> Dictionary:
	var bindings = {}
	for node in tmpl.body:
		if node is ITG.BindingNode:
			var value = _evaluate_binding(node.binding_expression, words)
			bindings[node.slot_name] = value
		elif node is ITG.VariantSwitchNode:
			for variant_name in node.variants:
				for sub_node in node.variants[variant_name]:
					if sub_node is ITG.BindingNode:
						var value = _evaluate_binding(sub_node.binding_expression, words)
						bindings[sub_node.slot_name] = value
	return bindings


static func _evaluate_binding(expr: String, words: Array) -> Variant:
	if expr.begins_with("$cmd.words["):
		var inner = expr.substr(11, expr.length() - 12)
		if ".." in inner:
			var parts = inner.split("..")
			var start_idx = int(parts[0].strip_edges())
			var end_part = parts[1].strip_edges()
			var end_idx: int
			if end_part == "-1":
				end_idx = words.size() - 1
			elif end_part == "-2":
				end_idx = words.size() - 2
			else:
				end_idx = int(end_part)
			if start_idx < 0 or start_idx >= words.size():
				return []
			if end_idx < 0 or end_idx >= words.size():
				end_idx = words.size() - 1
			var result = []
			for i in range(start_idx, end_idx + 1):
				result.append(words[i])
			return result
		else:
			var idx_str = inner.replace("?", "").strip_edges()
			var idx = int(idx_str)
			if idx < 0:
				idx = words.size() + idx
			if idx < 0 or idx >= words.size():
				return ""
			return words[idx]
	push_error("TemplateExpander: unknown binding expression [%s]" % expr)
	return ""


static func _handle_foreach(
	node, cmd, bindings: Dictionary, manifest, buf,
	visited, code_blocks, graph, context: Dictionary
) -> void:
	var list_name = node.list_name
	var element_name = node.element_name
	var list_val = bindings.get(list_name, [])
	if not (list_val is Array):
		return

	for elem in list_val:
		var scoped_bindings = bindings.duplicate()
		scoped_bindings[element_name] = elem
		emit_node_list(node.body, cmd, scoped_bindings, manifest, buf, visited, code_blocks, graph, context)


static func _handle_variant_switch(
	node, cmd, bindings: Dictionary, manifest, buf,
	visited, code_blocks, graph, context: Dictionary
) -> void:
	var variant_value = bindings.get(node.slot_name, "")
	if variant_value.is_empty():
		return
	var variant_body = node.variants.get(variant_value)
	if variant_body != null:
		emit_node_list(variant_body, cmd, bindings, manifest, buf, visited, code_blocks, graph, context)


static func _handle_callback(
	node, cmd, bindings: Dictionary, manifest, buf,
	visited, code_blocks, graph, context: Dictionary
) -> void:
	match node.callback_name:
		"emit_cb":
			_handle_emit_cb(node, cmd, bindings, manifest, buf, visited, code_blocks, graph, context)
		"reverse":
			_handle_reverse(node, bindings)
		"ref_cb":
			pass
		"needs_deref":
			pass
		_:
			push_error("TemplateExpander: unknown callback [%s]" % node.callback_name)


static func _handle_emit_cb(
	node, cmd, bindings: Dictionary, manifest, buf,
	visited, code_blocks, graph, context: Dictionary
) -> void:
	var cb_name = bindings.get(node.arg_names[0], "")
	if cb_name.is_empty():
		push_error("TemplateExpander: @emit_cb slot [%s] has no binding" % node.arg_names[0])
		return

	if visited.has(cb_name):
		push_warning("TemplateExpander: skipping already-visited code block [%s]" % cb_name)
		return

	var cb = code_blocks.get(cb_name)
	if cb == null:
		push_error("TemplateExpander: code block [%s] not found" % cb_name)
		return

	var cb_commands = cb.get("code", [])
	if cb_commands.is_empty():
		return

	visited[cb_name] = true

	for cb_cmd in cb_commands:
		var tmpl = graph.templates.get(cb_cmd.words[0])
		if tmpl == null:
			push_error("TemplateExpander: no template for [%s] in @emit_cb" % cb_cmd.words[0])
			continue
		var cb_bindings = _build_bindings_from_body(tmpl, cb_cmd.words)
		emit_node_list(tmpl.body, cb_cmd, cb_bindings, manifest, buf, visited, code_blocks, graph, context)

	visited.erase(cb_name)


static func _handle_reverse(node, bindings: Dictionary) -> void:
	if node.arg_names.is_empty():
		return
	var list_name = node.arg_names[0]
	var list_val = bindings.get(list_name)
	if list_val is Array:
		list_val.reverse()


static func _handle_label_def(node, manifest, buf) -> void:
	for lbl_name in node.label_names:
		var actual = manifest.labels.get(lbl_name)
		if actual == null:
			push_error("TemplateExpander: label [%s] not found in manifest" % lbl_name)
			continue
		buf.append_label(":%s:\n" % actual)


static func _handle_if_conditional(
	node, cmd, bindings: Dictionary, manifest, buf,
	visited, code_blocks, graph, context: Dictionary
) -> void:
	var slot_name = node.slot_name
	var val = bindings.get(slot_name)
	var has_val = val != null and val != ""
	if has_val:
		emit_node_list(node.body, cmd, bindings, manifest, buf, visited, code_blocks, graph, context)
