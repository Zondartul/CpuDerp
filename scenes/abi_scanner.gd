# =============================================================================
# abi_scanner.gd — Pass 1 Symbol Discovery Scanner
# =============================================================================
#
# Scans the IR program through the lens of the Inflated Template Graph (ITG)
# to discover every symbol, temporary, label, immediate, and code block
# reference before any emit begins.
#
# Usage:
#   var manifest = ABIScanner.discover(IR, graph)
#
# Steps:
#   1. Walk all IR scopes → collect symbol declarations
#   2. Walk all code blocks, match each IR command to its template
#   3. For each matched template, walk the body to discover:
#      - @temp allocations
#      - @label declarations
#      - @new_imm constants
#      - @ref_cb reachable code blocks
#      - @needs_deref markers
#   4. Call StorageAllocator to allocate storage
# =============================================================================

class_name ABIScanner
extends RefCounted

const ITG = preload("res://scenes/inflated_template_graph.gd")
const AB = preload("res://scenes/ab_manifest.gd")
const StorageAllocator = preload("res://scenes/stor_alloc.gd")


# ---------------------------------------------------------------------------
# ScanContext — per-template scanning state
# ---------------------------------------------------------------------------
class _ScanContext:
	var manifest: ABIManifest
	var cmd                      # IR_Cmd
	var bindings: Dictionary     # slot_name → word value (resolved)
	var label_counter: int

	func _init(
		p_manifest: ABIManifest,
		p_cmd,
		p_bindings: Dictionary,
		p_label_counter: int = 0
	):
		manifest = p_manifest
		cmd = p_cmd
		bindings = p_bindings
		label_counter = p_label_counter


# ===========================================================================
# Public entry point
# ===========================================================================

static func discover(IR: Dictionary, graph: InflatedGraph) -> ABIManifest:
	var manifest = ABIManifest.new()

	# Step 1: Collect all declared symbols from IR scopes
	for scp_name in IR.scopes:
		var scope = IR.scopes[scp_name]
		for var_handle in scope.get("vars", []):
			_add_symbol(manifest, var_handle, scp_name)
		for func_handle in scope.get("funcs", []):
			_add_symbol(manifest, func_handle, scp_name)

	# Step 2 & 3: Walk all code blocks, match commands, discover template bodies
	for cb_name in IR.code_blocks:
		var cb = IR.code_blocks[cb_name]
		if cb_name not in manifest.reachable_cbs:
			manifest.reachable_cbs.append(cb_name)
		for cmd in cb.get("code", []):
			var tmpl_name = cmd.words[0]
			var tmpl = graph.templates.get(tmpl_name)
			if tmpl == null:
				push_error("ABIScanner: No template for [%s]" % tmpl_name)
				continue
			# Pre-compute slot bindings from the template's @bind nodes
			var bindings = _build_bindings(tmpl, cmd)
			var ctx = _ScanContext.new(manifest, cmd, bindings, 0)
			_scan_template_nodes(tmpl.body, ctx)

	# Step 4: Allocate storage for all discovered symbols, temps, and imms
	StorageAllocator.allocate(manifest, IR)
	StorageAllocator.allocate_temps(manifest)
	StorageAllocator.allocate_imms(manifest)

	return manifest


# ===========================================================================
# Step 1 helpers — symbol registration
# ===========================================================================

# Registers one IR variable/function handle into the manifest.
static func _add_symbol(manifest: ABIManifest, handle: Dictionary, scp_name: String) -> void:
	var ir_name: String = handle.get("ir_name", "")
	if ir_name.is_empty() or ir_name in manifest.symbols:
		return

	var val_type: String = handle.get("val_type", "variable")
	var data_type: String = handle.get("data_type", "int")
	var is_array: bool = (int(handle.get("is_array", 0)) != 0)
	var array_size: int = int(handle.get("array_size", 0))
	var storage_str: String = handle.get("storage", "NULL")

	# Determine initial storage type from the original string.
	# "NULL" and "arg" will be resolved by the allocator.
	var storage_type: String
	match storage_str:
		"NULL":
			storage_type = "unallocated"
		"arg":
			storage_type = "unallocated"
		"extern":
			storage_type = "extern"
		_:
			# Already resolved (shouldn't happen in fresh IR, but be safe)
			storage_type = storage_str

	var sym = AB.SymbolInfo.new(
		ir_name,
		val_type,
		storage_type,
		0,
		data_type,
		is_array,
		array_size,
		false,        # needs_deref (default false)
		scp_name
	)

	manifest.symbols[ir_name] = sym


# ===========================================================================
# Step 2 helpers — binding resolution
# ===========================================================================

# Walks a template's body to find all @bind nodes and builds a
# slot_name → word_value dictionary from the IR command.
static func _build_bindings(tmpl: ITG.TemplateDef, cmd) -> Dictionary:
	var bindings = {}
	for node in tmpl.body:
		if node is ITG.BindingNode:
			var word_val = _resolve_binding(node.binding_expression, cmd)
			if word_val != null:
				bindings[node.slot_name] = word_val
		elif node is ITG.VariantSwitchNode:
			# Also scan variant sub-bodies for bindings (some templates
			# have @bind inside specific variants).
			for variant_name in node.variants:
				for sub_node in node.variants[variant_name]:
					if sub_node is ITG.BindingNode:
						var word_val = _resolve_binding(sub_node.binding_expression, cmd)
						if word_val != null:
							bindings[sub_node.slot_name] = word_val
	return bindings


# Parse a binding expression like "$cmd.words[1]" or "$cmd.words[-1]"
# or "$cmd.words[2..-2]" and return the resolved word value.
# Returns null if the expression can't be parsed.
static func _resolve_binding(expr: String, cmd) -> String:
	# Expected pattern: $cmd.words[N] or $cmd.words[N..M]
	if not expr.begins_with("$cmd.words["):
		return expr  # passthrough for literal values

	var bracket_content = expr.substr("$cmd.words[".length())
	if bracket_content.ends_with("]"):
		bracket_content = bracket_content.substr(0, bracket_content.length() - 1)

	# Handle range expression: N..M
	var dotdot = bracket_content.find("..")
	if dotdot != -1:
		# Take the first element of the range
		var first_part = bracket_content.substr(0, dotdot).strip_edges()
		var idx = int(first_part)
		return _cmd_word_at(cmd, idx)

	# Single index
	var idx = int(bracket_content)
	return _cmd_word_at(cmd, idx)


static func _cmd_word_at(cmd, idx: int) -> String:
	var n = len(cmd.words)
	if idx < 0:
		idx = n + idx
	if idx >= 0 and idx < n:
		return cmd.words[idx]
	return ""


# ===========================================================================
# Step 3 helpers — template body scanning
# ===========================================================================

# Recursively walk an array of ITGNode to discover temps, labels, imms,
# callbacks, and code block references.
static func _scan_template_nodes(nodes: Array, ctx: _ScanContext) -> void:
	for node in nodes:
		match node.type:
			ITG.ITGNode.NodeType.CALLBACK:
				_handle_callback(node, ctx)

			ITG.ITGNode.NodeType.TEMP_ALLOC:
				# Discover @temp declarations
				for t_name in node.temp_names:
					_add_temp(ctx.manifest, t_name)

			ITG.ITGNode.NodeType.LABEL_DEF:
				# Discover @label declarations — generate unique label names
				for lbl_name in node.label_names:
					ctx.label_counter += 1
					var ir_name = "lbl_%d__%s" % [ctx.label_counter, lbl_name]
					ctx.manifest.labels[lbl_name] = ir_name

			ITG.ITGNode.NodeType.IMM_DEF:
				# Discover @new_imm constants
				var imm_ir_name = node.imm_name
				if imm_ir_name not in ctx.manifest.symbols:
					# Store the actual immediate value in storage_pos.
					# This is what reg_resolve.gd reads for integer immediates
					# (see _resolve_load: returns str(sym.storage_pos)).
					var imm_val = node.value
					if typeof(imm_val) == TYPE_STRING:
						imm_val = 0  # Strings live in data section; position 0
					var sym = AB.SymbolInfo.new(
						imm_ir_name,
						"immediate",
						"immediate",
						imm_val,
						"int" if typeof(node.value) == TYPE_INT else "string",
						false,
						0,
						false,
						""
					)
					ctx.manifest.symbols[imm_ir_name] = sym

			ITG.ITGNode.NodeType.VARIANT_SWITCH:
				# Scan all variant bodies (the variant value is in bindings;
				# during Pass 1 we scan ALL variants because we don't know
				# which one will be active at emit time).
				for variant_name in node.variants:
					_scan_template_nodes(node.variants[variant_name], ctx)

			ITG.ITGNode.NodeType.FOREACH:
				# The FOREACH body is always emitted, so scan it always.
				_scan_template_nodes(node.body, ctx)

			ITG.ITGNode.NodeType.IF_CONDITIONAL:
				# The IF body may or may not be emitted, but during Pass 1
				# we conservatively scan it to discover any symbols inside.
				if node.body.size() > 0:
					_scan_template_nodes(node.body, ctx)

			# BINDING and EMIT_LINE are Pass 2 concerns — skip in Pass 1.
			ITG.ITGNode.NodeType.BINDING:
				pass
			ITG.ITGNode.NodeType.EMIT_LINE:
				pass

			_:
				push_warning("ABIScanner: unhandled node type %d" % node.type)


# Add a temporary slot to the manifest.
static func _add_temp(manifest: ABIManifest, t_name: String) -> void:
	# Avoid duplicates
	for existing in manifest.temps:
		if existing.name == t_name:
			return
	manifest.temps.append(AB.TempSlot.new(t_name))


# ===========================================================================
# Callback handling
# ===========================================================================

static func _handle_callback(node: ITG.CallbackNode, ctx: _ScanContext) -> void:
	match node.callback_name:
		"ref_cb":
			# Mark a code block as reachable
			if node.arg_names.size() > 0:
				var cb_name = ctx.bindings.get(node.arg_names[0], "")
				if not cb_name.is_empty() and cb_name not in ctx.manifest.reachable_cbs:
					ctx.manifest.reachable_cbs.append(cb_name)

		"needs_deref":
			# Set the needs_deref flag on a symbol
			if node.arg_names.size() > 0:
				var sym_name = ctx.bindings.get(node.arg_names[0], "")
				if not sym_name.is_empty():
					var sym = ctx.manifest.symbols.get(sym_name)
					if sym != null:
						sym.needs_deref = true

		"reverse":
			# "reverse" is a Pass 2 operation only — no-op in Pass 1
			pass

		"emit_cb":
			# "emit_cb" is a Pass 2 operation only — no-op in Pass 1
			pass

		_:
			push_warning("ABIScanner: unknown callback [%s]" % node.callback_name)
