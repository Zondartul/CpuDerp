# ============================================================================
# codegen_master.gd — Pipeline Orchestrator
# ============================================================================
#
# The top-level orchestrator that wires Pass 1 (ABI scanner) + Pass 2
# (template expander) together and manages the old↔new migration dispatcher.
#
# Acts as a drop-in replacement for codegen_md.gd in comp_compile_md.gd.
#
# Migration strategy (plan §7):
#   - migrated_ops tracks which IR commands have been migrated to the new
#     template-driven pipeline (e.g. {"MOV": true, "OP": true}).
#   - Unmigrated commands are still dispatched through the old codegen_md.gd.
#   - Both paths produce assembly text that is concatenated and post-processed
#     by GlobalsEmitter.
# ============================================================================

class_name CodegenMaster
extends Node

# ---------------------------------------------------------------------------
# Dependencies (preloaded constants)
# ---------------------------------------------------------------------------
const CodegenMd       = preload("res://scenes/codegen_md.gd")
const Parser           = preload("res://scenes/template_parser.gd")
const ABIScanner       = preload("res://scenes/abi_scanner.gd")
const TemplateExpander  = preload("res://scenes/tmpl_expand.gd")
const GlobalsEmitter   = preload("res://scenes/globals_emit.gd")
const CodegenResult    = preload("res://scenes/codegen_result.gd")

# ---------------------------------------------------------------------------
# Signals (mirror codegen_md for drop-in compatibility)
# ---------------------------------------------------------------------------
signal locations_ready(loc_map: Dictionary)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
# Tracks which IR commands have been migrated to the new pipeline.
# All 13 IR commands now migrated (Sprints 1-5).
var migrated_ops: Dictionary = {
	"MOV": true,
	"OP": true,
	"IF": true,
	"ELSE_IF": true,
	"ELSE": true,
	"WHILE": true,
	"CALL": true,
	"CALL_INDIRECT": true,
	"RETURN": true,
	"ENTER": true,
	"LEAVE": true,
	"ALLOC": true,
	"MOV_ARR": true,
}

# Cached Inflated Template Graph — loaded once in _ready()
var graph

# Reference to the current editor file (set externally by the editor)
var cur_efile

# The old-codegen instance used for unmigrated commands.
# Created lazily on first generate() call to keep _ready() lightweight.
var _old_codegen


# ===========================================================================
# Lifecycle
# ===========================================================================

func _ready() -> void:
	# Load / parse the Inflated Template Graph from the .tg file.
	# The template_parser caches the result as a .tres file for fast
	# subsequent loads (see template_parser.gd: load_or_parse).
	graph = Parser.load_or_parse("res://templates/codegen_templates.tg")


# ===========================================================================
# Public API — drop-in replacement for codegen_md.gd
# ===========================================================================

# ---------------------------------------------------------------------------
# parse_file — drop-in compatible wrapper
# ---------------------------------------------------------------------------
# Reads the IR file, deserializes it, generates assembly, and returns the
# final assembly text (the same signature as codegen_md.parse_file()).
#
# Parameters:
#   input: Dictionary with at least:
#     .filename  — path to the serialised IR .txt file
#     .tokens    — (optional) token array passed through from the compiler
#     .ast       — (optional) AST passed through from the parser / analyzer
#     .IR        — (optional) pre-built IR dictionary if already analysed
#
# Returns:
#   String — the generated assembly text (or empty on error).
# ---------------------------------------------------------------------------
func parse_file(input: Dictionary) -> String:
	var result = generate(input)
	if result == null or not result.is_success:
		push_error("CodegenMaster: codegen failed: " + (result.error_message if result else "null"))
		return ""

	locations_ready.emit(result.loc_map if result.loc_map else {})
	return result.text


# ---------------------------------------------------------------------------
# generate — the main pipeline orchestrator
# ---------------------------------------------------------------------------
# Step 1:  Create a temporary old-codegen instance and deserialize the IR
#          (reuses the existing serialization format — no changes required).
# Step 2:  Run ABIScanner.discover(IR, graph) to produce the ABIManifest.
# Step 3:  Separate commands into migrated vs unmigrated based on
#          migrated_ops.
# Step 4:  Run TemplateExpander.expand(migrated_cmds, ...) for migrated.
# Step 5:  Run old codegen's generate_remaining() for unmigrated commands
#          (with a fresh instance to prevent state corruption — architect
#          fix A.6).
# Step 6:  Combine assembly text + location maps from both paths.
# Step 7:  Append GlobalsEmitter.emit_globals(manifest).
#
# Returns:
#   CodegenResult — success with combined assembly + location map, or
#                   failure with error message.
# ---------------------------------------------------------------------------
func generate(input: Dictionary) -> CodegenResult:
	# ---- Step 1: Deserialize IR using old codegen ----
	var old = CodegenMd.new()
	_old_codegen = old
	var ir_text: String

	if input.has("IR") and typeof(input.IR) == TYPE_DICTIONARY and not input.IR.is_empty():
		old.IR = input.IR
		ir_text = ""
	else:
		var fp = FileAccess.open(input.filename, FileAccess.READ)
		if fp == null:
			return CodegenResult.failure("CodegenMaster: cannot open IR file [" + input.filename + "]")
		ir_text = fp.get_as_text()
		fp.close()
		old.reset()
		old.deserialize(ir_text)

	if old.IR.is_empty():
		return CodegenResult.failure("CodegenMaster: deserialized IR is empty")

	# ---- Step 2: Pass 1 — ABI Discovery ----
	var manifest = ABIScanner.discover(old.IR, graph)

	# ---- Step 3: Flatten code blocks into linear emit order ----
	# Use manifest.reachable_cbs if available, otherwise use all code block keys.
	var cb_order = manifest.reachable_cbs
	if cb_order.is_empty():
		cb_order = old.IR.get("code_blocks", {}).keys()
	var flat_commands = _flatten_commands(old.IR.code_blocks, cb_order)

	# ---- Step 4: Separate migrated vs unmigrated from the flat list ----
	var migrated: Array = []
	var unmigrated: Array = []
	for cmd in flat_commands:
		var op_name = cmd.words[0] if cmd.words.size() > 0 else ""
		if op_name.is_empty():
			continue
		# Synthetic label commands are always handled by the new pipeline
		if op_name == "__LBL_FROM__" or op_name == "__LBL_TO__":
			migrated.append(cmd)
		elif is_op_migrated(op_name):
			migrated.append(cmd)
		else:
			unmigrated.append(cmd)

	# ---- Step 5: Pass 2 — Template expansion for migrated commands ----
	var migrated_result = _expand_migrated(migrated, old.IR.code_blocks, manifest)

	# ---- Step 6: Old codegen for unmigrated commands ----
	var unmigrated_text = _generate_unmigrated(unmigrated, old, ir_text)

	# ---- Step 7: Combine assembly text ----
	var combined_text = ""
	if migrated_result != null and migrated_result.is_success:
		combined_text += migrated_result.text
	combined_text += unmigrated_text

	# ---- Step 8: Append globals data section ----
	combined_text += GlobalsEmitter.emit_globals(manifest)

	var combined_loc_map = null
	if migrated_result != null and migrated_result.loc_map != null:
		combined_loc_map = migrated_result.loc_map

	return CodegenResult.success(combined_text, combined_loc_map)


# ===========================================================================
# Migration-status queries
# ===========================================================================

# Returns true if an IR command op-name has a migrated template.
func is_op_migrated(op_name: String) -> bool:
	return migrated_ops.has(op_name) and migrated_ops[op_name] == true


# Marks an op as migrated (for incremental migration, called by tests).
func migrate_op(op_name: String) -> void:
	migrated_ops[op_name] = true


# ===========================================================================
# Command separation (plan §7 — flat_commands simplified)
# ===========================================================================

# ---------------------------------------------------------------------------
# _separate_commands
# ---------------------------------------------------------------------------
# Walks all reachable code blocks and separates each IR_Cmd into either the
# migrated list or the unmigrated list.
#
# Parameters:
#   IR — the deserialised IR dictionary (from codegen_md.deserialize)
#
# Returns:
#   { "migrated": Array[IR_Cmd], "unmigrated": Array[IR_Cmd] }
# ---------------------------------------------------------------------------
func _separate_commands(IR: Dictionary) -> Dictionary:
	var migrated: Array = []
	var unmigrated: Array = []

	# Walk code blocks in a deterministic order (sorted by key).
	var cb_names = IR.get("code_blocks", {}).keys()
	cb_names.sort()

	for cb_name in cb_names:
		var cb = IR.code_blocks[cb_name]
		var code = cb.get("code", [])
		for cmd in code:
			var op_name = cmd.words[0] if cmd.words.size() > 0 else ""
			if op_name.is_empty():
				continue
			if is_op_migrated(op_name):
				migrated.append(cmd)
			else:
				unmigrated.append(cmd)

	return {
		"migrated": migrated,
		"unmigrated": unmigrated,
	}


# ===========================================================================
# Flat-command helpers (plan §7 — architect fix A.5)
# ===========================================================================

# ---------------------------------------------------------------------------
# _flatten_commands
# ---------------------------------------------------------------------------
# Flattens the nested IR.code_blocks into a linear emit-order list.
#
# Processes manifest.reachable_cbs (or all code blocks if the manifest is
# not yet built) in order.  For each code block, it emits:
#   1. The label-start marker (lbl_from)
#   2. The code block's commands
#   3. The label-end marker (lbl_to)
#
# This is required by architect fix A.5 and provides a canonical emit order
# that both Pass 2 and the old codegen can agree on.
#
# Parameters:
#   code_blocks — Dictionary of CodeBlock instances from the deserialised IR.
#   order       — Array[String] of code block names in emit order
#                 (typically manifest.reachable_cbs).
#
# Returns:
#   Array of IR_Cmd commands in linear emit order (includes label-marker
#   synthetic commands).
# ---------------------------------------------------------------------------
func _flatten_commands(code_blocks: Dictionary, order: Array) -> Array:
	var flat: Array = []

	for cb_name in order:
		var cb = code_blocks.get(cb_name)
		if cb == null:
			continue

		# Emit a synthetic "label" marker for the block's lbl_from.
		# This is a lightweight sentinel that the template expander / old
		# codegen can recognise as a label boundary.
		flat.append(_make_synthetic_cmd("__LBL_FROM__", [cb_name, cb.lbl_from]))

		# Emit the code block's actual commands.
		var code = cb.get("code", [])
		for cmd in code:
			flat.append(cmd)

		# Emit the label-to marker.
		flat.append(_make_synthetic_cmd("__LBL_TO__", [cb_name, cb.lbl_to]))

	return flat


# Creates a minimal synthetic IR_Cmd for label markers.
static func _make_synthetic_cmd(op: String, words: Array):
	var cmd = IR_Cmd.new({"loc": null})
	cmd.words.assign(words)
	return cmd


# ===========================================================================
# Internal: migrated-command expansion
# ===========================================================================

# Runs TemplateExpander.expand() on the migrated command list.
# Returns a CodegenResult (may be a success with empty text if no migrated
# commands exist).
func _expand_migrated(migrated_cmds: Array, code_blocks: Dictionary, manifest) -> CodegenResult:
	if migrated_cmds.is_empty():
		return CodegenResult.success("")

	return TemplateExpander.expand(migrated_cmds, code_blocks, graph, manifest)


# ===========================================================================
# Internal: unmigrated-command generation
# ===========================================================================

# ---------------------------------------------------------------------------
# _generate_unmigrated
# ---------------------------------------------------------------------------
# Runs the old codegen on only the unmigrated commands.
#
# Strategy:
#   1. Create a fresh old-codegen instance (prevents state corruption per
#      architect fix A.6).
#   2. Deserialise the IR (same as before).
#   3. Strip every migrated IR_Cmd from each code block's "code" array.
#   4. Call the old codegen's generate() loop BUT without its final
#      generate_globals() call (since GlobalsEmitter handles that).
#
# Parameters:
#   unmigrated_cmds — Array[IR_Cmd] of commands that still use the old
#                     codegen path (may be empty).
#   old              — the original CodegenMd instance used for deserialisation
#                      (we clone its state rather than re-reading the file).
#   ir_text          — the raw IR text (for creating a fresh codegen if
#                      needed; may be empty if IR was passed directly).
#
# Returns:
#   String — assembly body text for the unmigrated commands only (no
#            globals section; no ENTER/LEAVE fixup — the fixup happens
#            inside the old codegen).
# ---------------------------------------------------------------------------
func _generate_unmigrated(unmigrated_cmds: Array, old_original, ir_text: String) -> String:
	if unmigrated_cmds.is_empty():
		return ""

	# Build a set of migrated op-names for quick lookup.
	var migrated_set: Dictionary = {}
	for key in migrated_ops:
		if migrated_ops[key]:
			migrated_set[key] = true

	# ---- Step 1: Create a fresh old-codegen instance ----
	var old = CodegenMd.new()

	# ---- Step 2: Deserialise the IR ----
	if not ir_text.is_empty():
		old.reset()
		old.deserialize(ir_text)
	else:
		# IR was provided directly — deep-copy the relevant state.
		old.IR = old_original.IR.duplicate(true)
		old.all_syms = old_original.all_syms.duplicate(true)

	# ---- Step 3: Strip migrated commands from every code block ----
	for cb_name in old.IR.get("code_blocks", {}):
		var cb = old.IR.code_blocks[cb_name]
		if not cb.has("code"):
			continue
		var kept: Array = []
		for cmd in cb.code:
			var op_name = cmd.words[0] if cmd.words.size() > 0 else ""
			if not migrated_set.has(op_name):
				kept.append(cmd)
		cb.code = kept

	# ---- Step 4: Run the old codegen's emit loop (minus globals) ----
	return _run_old_emit(old)


# ---------------------------------------------------------------------------
# _run_old_emit
# ---------------------------------------------------------------------------
# Runs the old codegen's allocation + emit loop but skips its final
# generate_globals() call.  Produces only the assembly body text.
#
# This mirrors the logic from codegen_md.gd lines 148-177:
#   - allocate_vars()
#   - Walk referenced_cbs → emit_cb()
#   - fixup_enter_leave()
#   - SKIP generate_globals()
#
# We operate directly on the old codegen's internal state (IR, all_syms).
# ---------------------------------------------------------------------------
func _run_old_emit(old) -> String:
	# Guard: ensure there is at least one code block.
	var cb_names = old.IR.get("code_blocks", {})
	if cb_names.is_empty():
		return ""

	# Allocate storage for all symbols.
	old.allocate_vars()

	# Prime the referenced_cbs list with the first code block (matches the
	# behaviour of old codegen: line 148-149).
	var cb_global = _first_dict_value(cb_names)
	if cb_global == null:
		return ""

	old.referenced_cbs = []
	old.referenced_cbs.append(cb_global)

	# Initialise the emit state.
	old.cur_assy_block = _new_assy_block()
	var emitted_cbs: Array = []

	# Walk referenced_cbs in FIFO order, emitting each code block once.
	while not old.referenced_cbs.is_empty():
		var cb = old.referenced_cbs.pop_front()
		if cb in emitted_cbs:
			continue
		emitted_cbs.append(cb)
		old.emit_cb(cb.ir_name, "codegen_master.generate.unmigrated")

	# Fixup ENTER/LEAVE placeholders now that all code blocks have been
	# emitted and stack sizes are known.
	old.fixup_enter_leave(old.cur_assy_block)

	return old.cur_assy_block.code


# ===========================================================================
# Helper utilities
# ===========================================================================

# Returns the first value in a Dictionary (analogous to G.first_in_dict
# used in the old codegen).
static func _first_dict_value(d: Dictionary):
	for key in d:
		return d[key]
	return null


# Creates a minimal AssyBlock for the old codegen's emit loop.
static func _new_assy_block():
	var block = AssyBlock.new()
	return block


# ===========================================================================
# Backward-compatible reset
# ===========================================================================

# Resets the master's state.  Does NOT clear migrated_ops (since those
# are a configuration choice, not per-compilation state).
func reset() -> void:
	_old_codegen = null
