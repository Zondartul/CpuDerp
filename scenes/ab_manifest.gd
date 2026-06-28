class_name ABIManifest
extends RefCounted

# All known symbols (variables, functions, temporaries, immediates)
# ir_name → SymbolInfo
var symbols: Dictionary = {}

# Pre-generated label names for @label declarations
# meta_name → generated_label_string
var labels: Dictionary = {}

# All temps discovered during template scan (pre-allocated in Pass 1)
var temps: Array[TempSlot] = []

# Optional debug trace flag
var trace_enabled: bool = false

# Per-scope stack data: scp_name → bytes needed
var scope_stack_sizes: Dictionary = {}

# Code blocks reachable through @ref_cb or in IR
var reachable_cbs: Array[String] = []

# Template-to-slot-ref mapping (for discovery iteration)
# template_name → Array[SlotRef]
var template_slot_refs: Dictionary = {}


# ---------------------------------------------------------------------------
# SymbolInfo — describes one symbol discovered and allocated during Pass 1
# ---------------------------------------------------------------------------
class SymbolInfo:
	var ir_name: String
	var val_type: String       # "variable", "temporary", "immediate", "func", "code", "label"
	var storage_type: String   # "global", "stack", "register", "immediate", "code", "extern"
	var storage_pos: int       # stack offset or register index
	var data_type: String      # "int", "string", "func_ptr"
	var is_array: bool
	var array_size: int
	var needs_deref: bool
	var scope: String          # which scope this belongs to

	func _init(
		p_ir_name: String,
		p_val_type: String = "variable",
		p_storage_type: String = "stack",
		p_storage_pos: int = 0,
		p_data_type: String = "int",
		p_is_array: bool = false,
		p_array_size: int = 0,
		p_needs_deref: bool = false,
		p_scope: String = ""
	):
		ir_name = p_ir_name
		val_type = p_val_type
		storage_type = p_storage_type
		storage_pos = p_storage_pos
		data_type = p_data_type
		is_array = p_is_array
		array_size = p_array_size
		needs_deref = p_needs_deref
		scope = p_scope


# ---------------------------------------------------------------------------
# TempSlot — a pre-allocated temporary value slot
# ---------------------------------------------------------------------------
class TempSlot:
	var name: String               # "tmp_a"
	var preferred_register: String # "EAX" or "" (stack spill)
	var stack_pos: int             # EBP offset if spilled

	func _init(p_name: String, p_preferred_register: String = "", p_stack_pos: int = 0):
		name = p_name
		preferred_register = p_preferred_register
		stack_pos = p_stack_pos
