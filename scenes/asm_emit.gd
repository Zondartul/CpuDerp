# ============================================================================
# AsmEmitter — Assembly line emitter and fixup handler for Pass 2
# ============================================================================
#
# Responsible for:
#   1. Resolving {slot_name} references in emitted text patterns via
#      RegResolver and producing the final assembly text.
#   2. Fixing up __ENTER_{scp} / __LEAVE_{scp} placeholders with actual
#      push / pop code based on the per-scope stack sizes known after Pass 1.
#   3. Appending resolved lines to an EmitBuffer with location tracking.
#
# Mirrors the logic of codegen_md.gd: emit(), fixup_enter_leave() and the
# $name / ^name / @name reference resolution embedded in emit().
# ============================================================================

class_name AsmEmitter
extends RefCounted

const RegResolver   = preload("res://scenes/reg_resolve.gd")
const ITG           = preload("res://scenes/inflated_template_graph.gd")
const ABIManifest   = preload("res://scenes/ab_manifest.gd")
const CodegenResult = preload("res://scenes/codegen_result.gd")


# ---------------------------------------------------------------------------
# emit_line
# ---------------------------------------------------------------------------
# Resolves all {slot_name} references in text_pattern using the SlotRef
# role list, then appends the resolved line to the EmitBuffer.
#
# Parameters:
#   text_pattern — the raw template line, e.g. "mov {dest}, {src};"
#   slot_refs    — Array[SlotRef] extracted by the template parser
#   bindings     — Dictionary slot_name → resolved-string
#   manifest     — ABIManifest from Pass 1
#   buf          — EmitBuffer to append to
#   loc          — LocationRange from the IR command (for source mapping)
# ---------------------------------------------------------------------------
static func emit_line(
	text_pattern: String,
	slot_refs: Array,
	bindings: Dictionary,
	manifest: ABIManifest,
	buf: CodegenResult.EmitBuffer,
	loc = null
) -> void:
	var resolved = resolve_line_pattern(text_pattern, slot_refs, bindings, manifest)

	# Append with optional location tracking
	if loc != null and loc.begin != null:
		buf.append(resolved + "\n", loc)
	else:
		buf.append(resolved + "\n")


# ---------------------------------------------------------------------------
# resolve_line_pattern
# ---------------------------------------------------------------------------
# Performs the actual {slot_name} → text substitution for all slot_refs
# found in the pattern.  Each SlotRef's role determines how the slot value
# is resolved.
#
# Returns the pattern string with all {slot_name} placeholders replaced.
# ---------------------------------------------------------------------------
static func resolve_line_pattern(
	pattern: String,
	slot_refs: Array,
	bindings: Dictionary,
	manifest: ABIManifest
) -> String:
	var result = pattern

	for ref in slot_refs:
		var replacement = _resolve_slot_ref(ref, bindings, manifest)
		result = result.replace("{%s}" % ref.slot_name, replacement)

	return result


# ---------------------------------------------------------------------------
# _resolve_slot_ref — resolve a single SlotRef to its assembly text
# ---------------------------------------------------------------------------
static func _resolve_slot_ref(ref, bindings: Dictionary, manifest: ABIManifest) -> String:
	match ref.role:
		ITG.SlotRef.Role.LOAD_REF:
			var name = bindings.get(ref.slot_name, "")
			if name.is_empty():
				push_error("AsmEmitter: LOAD_REF slot [%s] has no binding" % ref.slot_name)
				return ""
			return RegResolver.resolve_value(name, manifest, "load")

		ITG.SlotRef.Role.STORE_REF:
			var name = bindings.get(ref.slot_name, "")
			if name.is_empty():
				push_error("AsmEmitter: STORE_REF slot [%s] has no binding" % ref.slot_name)
				return ""
			return RegResolver.resolve_value(name, manifest, "store")

		ITG.SlotRef.Role.ADDR_REF:
			var name = bindings.get(ref.slot_name, "")
			if name.is_empty():
				push_error("AsmEmitter: ADDR_REF slot [%s] has no binding" % ref.slot_name)
				return ""
			return RegResolver.resolve_value(name, manifest, "address")

		ITG.SlotRef.Role.LABEL_REF:
			var lbl = manifest.labels.get(ref.slot_name)
			if lbl == null:
				push_error("AsmEmitter: LABEL_REF [%s] not found in manifest.labels" % ref.slot_name)
				return ref.slot_name
			return lbl

		ITG.SlotRef.Role.VALUE_REF:
			# Verbatim word value from the IR command (e.g. "ADD", "SUB")
			return bindings.get(ref.slot_name, "")

		ITG.SlotRef.Role.TEMP_REF:
			return RegResolver.resolve_temp(ref.slot_name, manifest)

		ITG.SlotRef.Role.IMM_REF:
			# Immediate constant — its symbol's ir_name is the label reference
			# to the data-section entry.
			var sym = manifest.symbols.get(ref.slot_name)
			if sym == null:
				push_error("AsmEmitter: IMM_REF [%s] not found in manifest.symbols" % ref.slot_name)
				return ""
			return sym.ir_name

		ITG.SlotRef.Role.CONTEXT_REF:
			return _resolve_context_ref(ref.slot_name, bindings, manifest)

		ITG.SlotRef.Role.COMPUTED_REF:
			return _resolve_computed_ref(ref.slot_name, bindings)

		_:
			push_error("AsmEmitter: unknown SlotRef role [%d]" % ref.role)
			return ""


# ---------------------------------------------------------------------------
# _resolve_context_ref
# ---------------------------------------------------------------------------
# Handles template-context slot references like {%if_block_lbl_end},
# {%scope_name}, {%scope_stack_size} etc.
#
# These are special values set by the template expander on the bindings
# dictionary during emit (not from the IR command words).
# ---------------------------------------------------------------------------
static func _resolve_context_ref(slot_name: String, bindings: Dictionary, manifest: ABIManifest) -> String:
	# Standard context keys set by the expander:
	match slot_name:
		"scope_name":
			return bindings.get("%scope_name", "")
		"scope":
			return bindings.get("%scope", "")
		"if_block_lbl_end":
			return bindings.get("%if_block_lbl_end", "")

	# Fallback: if the binding has a key with the % prefix, use it
	var key = "%%%s" % slot_name
	if bindings.has(key):
		return bindings[key]

	# Fallback: check manifest.labels for any context label
	if manifest.labels.has(slot_name):
		return manifest.labels[slot_name]

	push_error("AsmEmitter: unresolved CONTEXT_REF [%s]" % slot_name)
	return ""


# ---------------------------------------------------------------------------
# _resolve_computed_ref
# ---------------------------------------------------------------------------
# Handles computed values like {len(args)} and {len(args) * 4}.
# Supports:
#   len(X)         — returns size of list X
#   len(X) * N     — returns (size of list X) * N
# ---------------------------------------------------------------------------
static func _resolve_computed_ref(slot_name: String, bindings: Dictionary) -> String:
	# Pattern: len(X) * N
	var mult_pos = slot_name.find(" * ")
	if mult_pos != -1:
		var len_part = slot_name.substr(0, mult_pos).strip_edges()
		var multiplier_str = slot_name.substr(mult_pos + 3).strip_edges()
		var len_val = _eval_len_expr(len_part, bindings)
		var multiplier = int(multiplier_str) if multiplier_str.is_valid_int() else 1
		return str(len_val * multiplier)

	# Pattern: len(X)
	if slot_name.begins_with("len(") and slot_name.ends_with(")"):
		return str(_eval_len_expr(slot_name, bindings))

	push_error("AsmEmitter: unknown COMPUTED_REF [%s]" % slot_name)
	return "0"


# Evaluates a len(...) expression and returns the integer count.
static func _eval_len_expr(expr: String, bindings: Dictionary) -> int:
	if expr.begins_with("len(") and expr.ends_with(")"):
		var list_name = expr.substr(4, expr.length() - 5)
		var list_val = bindings.get(list_name, [])
		if list_val is Array:
			return list_val.size()
	return 0


# ---------------------------------------------------------------------------
# fixup_enter_leave
# ---------------------------------------------------------------------------
# Replaces all __ENTER_{scp} and __LEAVE_{scp} placeholders in the
# EmitBuffer with actual sub-ESP instructions based on the per-scope
# stack sizes stored in manifest.scope_stack_sizes.
#
# Currently, the replacement uses the local_vars_write_pos from each scope.
# __ENTER_{scp} → "sub ESP, N"   (where N = -local_vars_write_pos, bytes)
# __LEAVE_{scp}  → "sub ESP, M"   (where M = +local_vars_write_pos, bytes)
#
# Mirrors codegen_md.gd: fixup_enter_leave() at line 754.
# ---------------------------------------------------------------------------
static func fixup_enter_leave(buf: CodegenResult.EmitBuffer, manifest: ABIManifest) -> void:
	# Walk all parts and perform text-level replacement
	for i in range(buf.parts.size()):
		var part = buf.parts[i]
		if part.type == CodegenResult.EmitBuffer.AssemblyPartType.TEXT:
			var text = part.text
			var modified = false

			for scp_name in manifest.scope_stack_sizes:
				var stack_bytes = manifest.scope_stack_sizes[scp_name]

				var enter_marker = "__ENTER_%s" % scp_name
				var leave_marker = "__LEAVE_%s" % scp_name

				if text.find(enter_marker) != -1:
					text = text.replace(enter_marker, "sub ESP, %d" % (-stack_bytes))
					modified = true

				if text.find(leave_marker) != -1:
					text = text.replace(leave_marker, "sub ESP, %d" % stack_bytes)
					modified = true

			if modified:
				# Replace the part's text in-place
				buf.parts[i] = CodegenResult.EmitBuffer.AssemblyPart.new(
					CodegenResult.EmitBuffer.AssemblyPartType.TEXT,
					text,
					part.source_line
				)
