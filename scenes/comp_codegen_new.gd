# ============================================================================
# comp_codegen_new.gd — Scene-tree wrapper for CodegenMaster
# ============================================================================
#
# A thin wrapper that places CodegenMaster into the scene tree as a child
# of comp_compile_md.gd, enabling drop-in replacement of the old codegen.
#
# The wrapper:
#   - Auto-loads the CodegenMaster pipeline
#   - Delegates parse_file() → CodegenMaster.generate()
#   - Delegates fixup_symtable() to the old codegen child (if present) for
#     backward compatibility with the editor's symbol-table fixup step
#   - Manages the old-codegen child (codegen_md) underneath so it remains
#     available for unmigrated commands
#
# Usage in comp_compile_md.gd:
#   @onready var codegen = $comp_codegen_new
#   input["assy"] = codegen.parse_file(input)
#   codegen.fixup_symtable(analyzer.sym_table)
# ============================================================================

extends Node

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------
const CodegenMaster = preload("res://scenes/codegen_master.gd")
const CodegenMd = preload("res://scenes/codegen_md.gd")

# ---------------------------------------------------------------------------
# Child references
# ---------------------------------------------------------------------------
@onready var master: CodegenMaster = $codegen_master

# The old codegen node — present as a child for unmigrated commands.
# Created automatically in _ready().
var _old_codegen_node


# ===========================================================================
# Lifecycle
# ===========================================================================

func _ready() -> void:
	# Ensure we have a CodegenMaster child.
	if master == null:
		master = CodegenMaster.new()
		master.name = "codegen_master"
		add_child(master)

	# Look for an existing old-codegen node (codegen_md) that may have been
	# added in the scene editor.  If one exists, keep it for backward
	# compatibility; otherwise create a minimal wrapper.
	_old_codegen_node = find_child("codegen_md", true, false)
	if _old_codegen_node == null:
		# The old codegen is used internally by CodegenMaster for unmigrated
		# commands, but we keep a reference here for fixup_symtable().
		pass


# ===========================================================================
# Public API — drop-in for the old codegen reference
# ===========================================================================

# Returns the CodegenMaster instance for direct access.
func get_master() -> CodegenMaster:
	return master


# ---------------------------------------------------------------------------
# parse_file — drop-in replacement for codegen_md.parse_file()
# ---------------------------------------------------------------------------
# Reads the serialised IR file, runs the combined pipeline
# (Pass 1 + Pass 2 + old-codegen fallback), and returns the final assembly
# text.
# ---------------------------------------------------------------------------
func parse_file(input: Dictionary) -> String:
	return master.parse_file(input)


# ---------------------------------------------------------------------------
# generate — access to the richer CodegenResult API
# ---------------------------------------------------------------------------
func generate(input: Dictionary):
	return master.generate(input)


# ---------------------------------------------------------------------------
# fixup_symtable — backward-compatible symbol-table fixup
# ---------------------------------------------------------------------------
# After codegen completes, the compiler calls this to patch storage
# positions into the analyzer's symbol table for the debugger.
#
# CodegenMaster.create() instantiates an internal old-codegen instance
# (CodegenMd) and stores it as master._old_codegen.  We call fixup_symtable
# on that instance to propagate storage positions into the analyzer's
# symbol table.
# ---------------------------------------------------------------------------
func fixup_symtable(sym_table: Dictionary) -> void:
	if master == null:
		return

	# Access the stored old-codegen instance.  The master sets
	# _old_codegen = CodegenMd.new() during generate().
	var old = master._old_codegen
	if old == null:
		# If generate() hasn't been called yet, create a throw-away instance.
		old = CodegenMd.new()
	if old.has_method("fixup_symtable"):
		old.fixup_symtable(sym_table)


# ---------------------------------------------------------------------------
# reset
# ---------------------------------------------------------------------------
func reset() -> void:
	if master != null:
		master.reset()
