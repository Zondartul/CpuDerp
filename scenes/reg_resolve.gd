# ============================================================================
# RegResolver — Register / Stack resolver for Pass 2 codegen
# ============================================================================
#
# Resolves temp and value names to concrete assembly-text strings using the
# pre-allocated ABIManifest from Pass 1.  Registers are PRE-ALLOCATED during
# Pass 1 (stor_alloc.gd), so this file is a simple stateless resolver —
# no allocation decision is made here.
#
# Replicates the $name / ^name / @name logic from codegen_md.gd's
# load_value(), store_val(), and address_value() functions.
# ============================================================================

class_name RegResolver
extends RefCounted

const ABIManifest = preload("res://scenes/ab_manifest.gd")


# ---------------------------------------------------------------------------
# resolve_temp
# ---------------------------------------------------------------------------
# Given a temporary name (e.g. "tmp_a"), returns the register name if the
# temp was assigned one, or a stack spill reference otherwise.
static func resolve_temp(temp_name: String, manifest: ABIManifest) -> String:
	for temp in manifest.temps:
		if temp.name == temp_name:
			if temp.preferred_register != "":
				return temp.preferred_register
			else:
				return "[EBP+%d]" % temp.stack_pos

	push_error("RegResolver: temp [%s] not found in manifest" % temp_name)
	return ""


# ---------------------------------------------------------------------------
# resolve_value
# ---------------------------------------------------------------------------
# Resolve a value name to its assembly-text representation based on the
# requested access mode.
#
#   mode = "load"    → "*var_x", "EBP[-4]", or immediate literal
#   mode = "store"   → writable target  "*var_x" or "EBP[-4]"
#   mode = "address" → address of value "var_x" or "EBP+12"
#
static func resolve_value(value_name: String, manifest: ABIManifest, mode: String) -> String:
	var sym = manifest.symbols.get(value_name)
	if sym == null:
		push_error("RegResolver: symbol [%s] not found in manifest" % value_name)
		return ""

	match mode:
		"load":
			return _resolve_load(sym)
		"store":
			return _resolve_store(sym)
		"address":
			return _resolve_address(sym)
		_:
			push_error("RegResolver: unknown resolve mode [%s]" % mode)
			return ""


# ---------------------------------------------------------------------------
# Internal helpers — mirror the logic of load_value / store_val / address_value
# from codegen_md.gd lines 550–626.
# ---------------------------------------------------------------------------

# Replicates codegen_md.gd: load_value()
static func _resolve_load(sym) -> String:
	# Immediate values are returned as literals (or label-references for strings).
	if sym.val_type == "immediate":
		if sym.data_type == "string":
			# String immediates are emitted in the data section; return the label.
			return sym.ir_name
		else:
			# Integer immediate — return the literal value as text.
			return str(sym.storage_pos)

	# Variables, functions, temporaries, etc.
	match sym.storage_type:
		"global":
			return "*%s" % sym.ir_name
		"stack":
			return "EBP[%d]" % sym.storage_pos
		"extern":
			return "*%s" % sym.ir_name
		_:
			push_error("RegResolver: unknown storage type [%s] for load" % sym.storage_type)
			return ""


# Replicates codegen_md.gd: store_val()
static func _resolve_store(sym) -> String:
	match sym.storage_type:
		"global":
			return "*%s" % sym.ir_name
		"stack":
			assert(sym.storage_pos != 0)
			return "EBP[%d]" % sym.storage_pos
		_:
			push_error("RegResolver: unknown storage type [%s] for store" % sym.storage_type)
			return ""


# Replicates codegen_md.gd: address_value()
static func _resolve_address(sym) -> String:
	match sym.storage_type:
		"global":
			return sym.ir_name
		"stack":
			var res = "EBP+%d" % sym.storage_pos
			res = res.replace("+-", "-")
			return res
		"code":
			return sym.ir_name
		"extern":
			return sym.ir_name
		_:
			push_error("RegResolver: unknown storage type [%s] for address" % sym.storage_type)
			return ""
