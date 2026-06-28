# =============================================================================
# stor_alloc.gd — Storage Allocator for Pass 1
# =============================================================================
#
# Allocates storage for all symbols discovered in Pass 1 (ABIScanner).
# Replicates the existing allocate_vars() / allocate_value() logic from
# codegen_md.gd for golden file compatibility.
#
# Public API:
#   StorageAllocator.allocate(manifest, IR)     — allocate vars in stack frames
#   StorageAllocator.allocate_temps(manifest)   — assign regs / stack for temps
#   StorageAllocator.allocate_imms(manifest)    — finalise immediate entries
# =============================================================================

class_name StorageAllocator
extends RefCounted

const AB = preload("res://scenes/ab_manifest.gd")


# ---------------------------------------------------------------------------
# Position conversion  (replicates codegen_md.gd helpers)
# ---------------------------------------------------------------------------

# Maps logical local-var slot N to a concrete EBP offset.
# Local vars grow DOWN from EBP.
static func _to_local_pos(pos: int) -> int:
	return -3 + pos


# Maps logical argument slot N to a concrete EBP offset.
# Arguments grow UP from EBP (past the return address).
static func _to_arg_pos(pos: int) -> int:
	return 9 + pos


# Returns the byte size a symbol occupies on the stack (default 4 bytes).
static func _get_data_size(handle: Dictionary) -> int:
	var size = 4
	if "is_array" in handle and int(handle.get("is_array", 0)):
		size *= int(handle.get("array_size", 0))
	return size


# ===========================================================================
# allocate() — replicate codegen_md.gd allocate_vars() + allocate_value()
# ===========================================================================
#
# Walks every scope in the IR, finds each variable/function handle, and
# updates the corresponding SymbolInfo in the manifest with the correct
# storage_type and storage_pos.
#
# IMPORTANT: This logic must produce IDENTICAL positions to the existing
# codegen_md.gd for golden file compatibility.

static func allocate(manifest: ABIManifest, IR: Dictionary) -> void:
	for scp_name in IR.scopes:
		var scope = IR.scopes[scp_name]

		# Initialise per-scope counters (mirrors allocate_vars lines 647-650)
		scope["local_vars_count"] = 0
		scope["local_vars_write_pos"] = _to_local_pos(0)
		scope["args_count"] = 0
		scope["args_write_pos"] = _to_arg_pos(0)

		# --- Allocate declared variables ---
		if "vars" in scope:
			for handle in scope.vars:
				_allocate_value(manifest, handle, scope, scp_name)

		# --- Allocate declared functions ---
		if "funcs" in scope:
			for handle in scope.funcs:
				var sym = manifest.symbols.get(handle.get("ir_name", ""))
				if sym == null:
					continue
				if handle.get("storage", "NULL") == "NULL":
					sym.storage_type = "code"
					sym.storage_pos = 0
				elif handle.get("storage") == "extern":
					sym.storage_type = "extern"
					sym.storage_pos = 0
				else:
					push_error("StorageAllocator: unknown func storage [%s]" % handle.get("storage"))

	# Write back per-scope stack sizes into the manifest
	for scp_name in IR.scopes:
		var scope = IR.scopes[scp_name]
		var local_count = scope.get("local_vars_count", 0)
		manifest.scope_stack_sizes[scp_name] = local_count * 4


# ===========================================================================
# _allocate_value() — replicates codegen_md.gd allocate_value()
# ===========================================================================

static func _allocate_value(
	manifest: ABIManifest,
	handle: Dictionary,
	scope: Dictionary,
	scp_name: String
) -> void:
	var data_size = _get_data_size(handle)
	var ir_name: String = handle.get("ir_name", "")
	var sym = manifest.symbols.get(ir_name)
	if sym == null:
		return

	var storage_str: String = handle.get("storage", "NULL")

	match storage_str:
		"NULL":
			# Check scope name — global scope means global storage
			if scope.get("user_name", "") == "global":
				sym.storage_type = "global"
				sym.storage_pos = 0
			else:
				sym.storage_type = "stack"
				var wp = scope.local_vars_write_pos
				sym.storage_pos = wp
				scope.local_vars_write_pos = wp - data_size
				scope.local_vars_count += 1
				assert(sym.storage_pos != 0)

		"extern":
			sym.storage_type = "extern"
			sym.storage_pos = 0

		"arg":
			var wp = scope.args_write_pos
			sym.storage_type = "stack"
			sym.storage_pos = wp
			scope.args_write_pos = wp + data_size
			scope.args_count += 1
			assert(sym.storage_pos != 0)

		_:
			push_error("StorageAllocator: unknown storage type [%s] for [%s]" % [storage_str, ir_name])

	# The old code always sets needs_deref = false after allocation,
	# but we preserve the needs_deref flag that may have been set
	# by @needs_deref during scanning.
	if not sym.needs_deref:
		sym.needs_deref = false


# ===========================================================================
# allocate_temps() — assign registers to temps, fall back to stack spill
# ===========================================================================
#
# Round-robins through EAX, EBX, ECX, EDX.  When all registers are taken,
# spills to a stack position in the first (global) scope's frame.
# In a future phase, smarter spill scoping can be implemented.

static func allocate_temps(manifest: ABIManifest) -> void:
	var regs: Array[String] = ["EAX", "EBX", "ECX", "EDX"]
	var next_reg: int = 0
	var next_spill: int = -4  # first spill position below declared locals

	for temp in manifest.temps:
		if next_reg < len(regs):
			# Assign a register
			temp.preferred_register = regs[next_reg]
			temp.stack_pos = 0
			next_reg += 1
		else:
			# Spill to stack
			temp.preferred_register = ""
			temp.stack_pos = next_spill
			next_spill -= 4


# ===========================================================================
# allocate_imms() — finalise immediate entries in the manifest
# ===========================================================================
#
# Immediates were already registered as symbols during scanning.
# This function ensures they have storage_type = "immediate" and
# records any metadata the emit phase will need.
#
# In the current codegen, immediates appear in the data section via
# generate_globals().  The SymbolInfo entries created during scanning
# already have val_type = "immediate" and storage_type = "immediate",
# so this function is mostly a validation / no-op for now.

static func allocate_imms(manifest: ABIManifest) -> void:
	for ir_name in manifest.symbols:
		var sym = manifest.symbols[ir_name]
		if sym.val_type == "immediate":
			sym.storage_type = "immediate"
			sym.storage_pos = 0
