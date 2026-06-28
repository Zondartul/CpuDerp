# ============================================================================
# GlobalsEmitter — Global data section emitter for Pass 2 codegen
# ============================================================================
#
# Walks the ABIManifest's symbols and emits DB / ALLOC directives for all
# symbols with storage_type == "global".  This mirrors the logic of the
# current codegen_md.gd: generate_globals() function (line 202).
#
# Emitted in this order:
#   - Global variables (non-array) → ":name: db 0;\n"
#   - Global arrays → ":name: alloc N;\n"
#   - Global temporaries → ":name: db 0;\n"
#   - String immediates → ":name: db \"...\", 0;\n"
# ============================================================================

class_name GlobalsEmitter
extends RefCounted


# ---------------------------------------------------------------------------
# emit_globals
# ---------------------------------------------------------------------------
# Walks manifest.symbols and produces the data-section assembly text for
# every global symbol.  Returns the complete data-section text.
#
# Parameters:
#   manifest — ABIManifest containing all allocated symbols
#
# Returns:
#   String — assembly text for the data section (may be empty)
# ---------------------------------------------------------------------------
static func emit_globals(manifest) -> String:
	var text = ""

	for key in manifest.symbols:
		var sym = manifest.symbols[key]

		# Only emit symbols with global storage
		if sym.storage_type != "global":
			continue

		match sym.val_type:
			"variable":
				if sym.is_array:
					text += ":%s: alloc %s;\n" % [sym.ir_name, str(4 * sym.array_size)]
				else:
					text += ":%s: db 0;\n" % sym.ir_name

			"temporary":
				text += ":%s: db 0;\n" % sym.ir_name

			"immediate":
				if sym.data_type == "string":
					var S = _format_db_string(sym)
					text += ":%s: db %s;\n" % [sym.ir_name, S]
				# Integer immediates are emitted as literal values in-line,
				# not stored in the data section, so we skip them here.

			# Functions, code blocks, labels, etc. are not data-section items.
			_:
				# skip
				pass

	return text


# ---------------------------------------------------------------------------
# _format_db_string
# ---------------------------------------------------------------------------
# Formats a string value for use in a DB directive.
# Mirrors codegen_md.gd: format_db_string() at line 222.
# ---------------------------------------------------------------------------
static func _format_db_string(sym) -> String:
	# The string value may be stored as a dynamic 'value' property (duck-typing
	# compatible with both old and new SymbolInfo representations).
	var S = ""
	if "value" in sym:
		S = str(sym.value)
	else:
		S = str(sym.storage_pos)
	# Wrap in quotes with null terminator
	return "\"%s\", 0" % S
