# ============================================================================
# Inflated Template Graph — Data Model
# ============================================================================
#
# The ITG is the result of compiling a `.tg` template file.  It is the sole
# type passed between the pre-build step (template_parser.gd), the cache
# (.tres file), and both passes of the codegen pipeline.
#
# *** Serialisation strategy (see Architect fix A.1) ***
#
# InflatedGraph extends Resource so it can be saved/loaded via
# ResourceSaver / ResourceLoader as a .tres file.  However, the *child*
# types (TemplateDef, ITGNode, etc.) are NOT Resources — they are plain
# RefCounted (or inner classes).  Instead, serialisation is handled through
# a custom _to_dict() / from_dict() pair, keeping the .tres file compact
# and avoiding Resource-system bloat.
#
# The serialisation flow is:
#   save:   InflatedGraph → _to_dict() → JSON / ResourceSaver
#   load:   JSON / ResourceSaver → from_dict() → InflatedGraph
# ============================================================================

class_name InflatedGraph
extends Resource

# -- Public fields -----------------------------------------------------------

# String template_name → TemplateDef
var templates: Dictionary = {}
var version: int = 1


func _init():
	templates = {}
	version = 1


# -- Serialisation -----------------------------------------------------------

# Convert the entire graph to a plain Dictionary tree.
func _to_dict() -> Dictionary:
	var tmpl_dict = {}
	for tmpl_name in templates:
		tmpl_dict[tmpl_name] = templates[tmpl_name]._to_dict()
	return {
		"version": version,
		"templates": tmpl_dict,
	}


# Reconstruct an InflatedGraph from a Dictionary previously returned by
# _to_dict().  This is a static factory, call it as:
#   var graph = InflatedGraph.from_dict(data)
static func from_dict(data: Dictionary) -> InflatedGraph:
	var graph = InflatedGraph.new()
	graph.version = data.get("version", 1)
	var tmpl_data = data.get("templates", {})
	for tmpl_name in tmpl_data:
		graph.templates[tmpl_name] = TemplateDef.from_dict(tmpl_data[tmpl_name])
	return graph


# ============================================================================
# TemplateDef
# ============================================================================
#
# Represents one @template block in the .tg file.
# Holds the slot signature, any variant declarations, and the body node list.

class TemplateDef:
	var name: String
	var param_variants: Array    # e.g. ["op"] — empty if no variants
	var slots: Array
	var body: Array

	func _init(p_name: String = "", p_slots: Array = [], p_body: Array = [],
			p_param_variants: Array = []):
		name = p_name
		slots = p_slots
		body = p_body
		param_variants = p_param_variants

	func _to_dict() -> Dictionary:
		var slot_list = []
		for s in slots:
			slot_list.append(s._to_dict())
		var body_list = []
		for n in body:
			body_list.append(n._to_dict())
		return {
			"name": name,
			"param_variants": param_variants.duplicate(),
			"slots": slot_list,
			"body": body_list,
		}

	static func from_dict(data: Dictionary) -> TemplateDef:
		var def = TemplateDef.new()
		def.name = data.get("name", "")
		def.param_variants = data.get("param_variants", []).duplicate()
		for s_data in data.get("slots", []):
			def.slots.append(SlotDef.from_dict(s_data))
		for n_data in data.get("body", []):
			var node = ITGNode.node_from_dict(n_data)
			if node != null:
				def.body.append(node)
		return def


# ============================================================================
# SlotDef
# ============================================================================
#
# Describes one slot in the @template signature, e.g. "dest:store" or
# "src:load".  The type determines how the slot value is resolved at
# emit time (load / store / addr / variadic / etc.).

class SlotDef:
	enum SlotType {
		LOAD,
		STORE,
		ADDR,
		VARIADIC,
		CODEBLOCK,
		LABEL,
		OPTIONAL,
		IMMEDIATE,
	}

	var name: String
	var type: SlotType
	var binding: String     # e.g. "$cmd.words[1]" — stored as parse info

	func _init(p_name: String = "", p_type: SlotType = SlotType.LOAD, p_binding: String = ""):
		name = p_name
		type = p_type
		binding = p_binding

	func _to_dict() -> Dictionary:
		return {
			"name": name,
			"type": type,
			"binding": binding,
		}

	static func from_dict(data: Dictionary) -> SlotDef:
		return SlotDef.new(
			data.get("name", ""),
			data.get("type", SlotType.LOAD),
			data.get("binding", "")
		)


# ============================================================================
# ITGNode — base for all body-node types in a TemplateDef body
# ============================================================================

class ITGNode:
	enum NodeType {
		EMIT_LINE,
		FOREACH,
		IF_CONDITIONAL,
		VARIANT_SWITCH,
		CALLBACK,
		TEMP_ALLOC,
		LABEL_DEF,
		IMM_DEF,
		BINDING,
	}

	var type: NodeType

	func _init(p_type: NodeType):
		type = p_type

	# Subclasses MUST override.
	func _to_dict() -> Dictionary:
		return {"type": type}

	# Deserialise one ITGNode subclass from a Dictionary.
	# The "type" key determines which subclass to instantiate.
	static func node_from_dict(data: Dictionary) -> ITGNode:
		var ntype = data.get("type", -1) as int
		match ntype:
			NodeType.EMIT_LINE:
				return EmitLineNode.from_dict(data)
			NodeType.FOREACH:
				return ForEachNode.from_dict(data)
			NodeType.IF_CONDITIONAL:
				return IfConditionalNode.from_dict(data)
			NodeType.VARIANT_SWITCH:
				return VariantSwitchNode.from_dict(data)
			NodeType.CALLBACK:
				return CallbackNode.from_dict(data)
			NodeType.TEMP_ALLOC:
				return TempAllocNode.from_dict(data)
			NodeType.LABEL_DEF:
				return LabelDefNode.from_dict(data)
			NodeType.IMM_DEF:
				return ImmDefNode.from_dict(data)
			NodeType.BINDING:
				return BindingNode.from_dict(data)
			_:
				push_error("ITGNode.node_from_dict: unknown node type %d" % ntype)
				return null


# ============================================================================
# SlotRef
# ============================================================================
#
# Describes a single {slot_name} reference found inside an emitted line.
# The role determines how the slot's value is presented in the final text
# (e.g. with a $ / ^ / @ prefix, as a raw value, as a temporary, etc.).

class SlotRef:
	enum Role {
		LOAD_REF,       # {dest} with dest:store → using ^ sigil
		STORE_REF,      # {dest} with dest:load → using $ sigil
		ADDR_REF,       # {fun} with fun:addr → using @ sigil
		LABEL_REF,      # {lbl_else} — plain label string
		VALUE_REF,      # {op} — verbatim word value
		TEMP_REF,       # {tmp_a} — reference to a temporary
		IMM_REF,        # {imm_0} — reference to immediate constant
		CONTEXT_REF,    # {%if_block_lbl_end} — context variable
		COMPUTED_REF,   # {len(args)} — computed value
	}

	var slot_name: String
	var role: Role

	func _init(p_slot_name: String = "", p_role: Role = Role.VALUE_REF):
		slot_name = p_slot_name
		role = p_role

	func _to_dict() -> Dictionary:
		return {
			"slot_name": slot_name,
			"role": role,
		}

	static func from_dict(data: Dictionary) -> SlotRef:
		return SlotRef.new(
			data.get("slot_name", ""),
			data.get("role", Role.VALUE_REF) as int
		)


# ============================================================================
# EmitLineNode
# ============================================================================
#
# One line of assembly text containing {slot} references.  The text_pattern
# is the raw string as it appeared in the .tg file; slot_refs is a
# pre-extracted list of every {slot} reference found during parsing.

class EmitLineNode:
	extends ITGNode

	var text_pattern: String          # e.g. "mov {dest}, {src};"
	var slot_refs: Array              # extracted from {} during parse

	func _init(p_text_pattern: String = "", p_slot_refs: Array = []):
		super(ITGNode.NodeType.EMIT_LINE)
		text_pattern = p_text_pattern
		slot_refs = p_slot_refs

	func _to_dict() -> Dictionary:
		var refs = []
		for r in slot_refs:
			refs.append(r._to_dict())
		return {
			"type": type,
			"text_pattern": text_pattern,
			"slot_refs": refs,
		}

	static func from_dict(data: Dictionary) -> EmitLineNode:
		var refs = []
		for r_data in data.get("slot_refs", []):
			refs.append(SlotRef.from_dict(r_data))
		return EmitLineNode.new(
			data.get("text_pattern", ""),
			refs
		)


# ============================================================================
# ForEachNode
# ============================================================================
#
# Iterates over a variadic list.  Inspired by:  for arg in args: ... endfor

class ForEachNode:
	extends ITGNode

	var list_name: String      # "args"
	var element_name: String   # "arg"
	var body: Array

	func _init(p_list_name: String = "", p_element_name: String = "", p_body: Array = []):
		super(ITGNode.NodeType.FOREACH)
		list_name = p_list_name
		element_name = p_element_name
		body = p_body

	func _to_dict() -> Dictionary:
		var body_list = []
		for n in body:
			body_list.append(n._to_dict())
		return {
			"type": type,
			"list_name": list_name,
			"element_name": element_name,
			"body": body_list,
		}

	static func from_dict(data: Dictionary) -> ForEachNode:
		var body = []
		for n_data in data.get("body", []):
			var node = ITGNode.node_from_dict(n_data)
			if node != null:
				body.append(node)
		return ForEachNode.new(
			data.get("list_name", ""),
			data.get("element_name", ""),
			body
		)


# ============================================================================
# IfConditionalNode
# ============================================================================
#
# Conditionally emits a body if a slot value is present/non-empty.
# .tg syntax:  if {slot}: ... endif

class IfConditionalNode:
	extends ITGNode

	var slot_name: String       # the slot to test for presence
	var body: Array

	func _init(p_slot_name: String = "", p_body: Array = []):
		super(ITGNode.NodeType.IF_CONDITIONAL)
		slot_name = p_slot_name
		body = p_body

	func _to_dict() -> Dictionary:
		var body_list = []
		for n in body:
			body_list.append(n._to_dict())
		return {
			"type": type,
			"slot_name": slot_name,
			"body": body_list,
		}

	static func from_dict(data: Dictionary) -> IfConditionalNode:
		var body = []
		for n_data in data.get("body", []):
			var node = ITGNode.node_from_dict(n_data)
			if node != null:
				body.append(node)
		return IfConditionalNode.new(
			data.get("slot_name", ""),
			body
		)


# ============================================================================
# VariantSwitchNode
# ============================================================================
#
# Dispatches on the value of a slot (the "op" slot, e.g. ADD / SUB / ...).
# Each variant name maps to an Array[ITGNode] body.

class VariantSwitchNode:
	extends ITGNode

	var slot_name: String              # "op"
	var variants: Dictionary           # "ADD" → Array[ITGNode], etc.

	func _init(p_slot_name: String = "", p_variants: Dictionary = {}):
		super(ITGNode.NodeType.VARIANT_SWITCH)
		slot_name = p_slot_name
		variants = p_variants

	func _to_dict() -> Dictionary:
		var vdict = {}
		for vname in variants:
			var body_list = []
			for n in variants[vname]:
				body_list.append(n._to_dict())
			vdict[vname] = body_list
		return {
			"type": type,
			"slot_name": slot_name,
			"variants": vdict,
		}

	static func from_dict(data: Dictionary) -> VariantSwitchNode:
		var variants = {}
		var vdata = data.get("variants", {})
		for vname in vdata:
			var body = []
			for n_data in vdata[vname]:
				var node = ITGNode.node_from_dict(n_data)
				if node != null:
					body.append(node)
			variants[vname] = body
		return VariantSwitchNode.new(
			data.get("slot_name", ""),
			variants
		)


# ============================================================================
# CallbackNode
# ============================================================================
#
# Directives that trigger side-effects during template walking:
#   @emit_cb(name), @ref_cb(name), @needs_deref(name), @reverse(name)

class CallbackNode:
	extends ITGNode

	var callback_name: String       # "ref_cb", "needs_deref", "reverse", "emit_cb"
	var arg_names: Array            # ["fun"]

	func _init(p_callback_name: String = "", p_arg_names: Array = []):
		super(ITGNode.NodeType.CALLBACK)
		callback_name = p_callback_name
		arg_names = p_arg_names

	func _to_dict() -> Dictionary:
		return {
			"type": type,
			"callback_name": callback_name,
			"arg_names": arg_names.duplicate(),
		}

	static func from_dict(data: Dictionary) -> CallbackNode:
		return CallbackNode.new(
			data.get("callback_name", ""),
			data.get("arg_names", []).duplicate()
		)


# ============================================================================
# TempAllocNode
# ============================================================================
#
# Declares one or more temporaries that must be allocated before emit.
# .tg syntax: @temp tmp_a, tmp_b

class TempAllocNode:
	extends ITGNode

	var temp_names: Array   # ["tmp_a", "tmp_b"]

	func _init(p_temp_names: Array = []):
		super(ITGNode.NodeType.TEMP_ALLOC)
		temp_names = p_temp_names

	func _to_dict() -> Dictionary:
		return {
			"type": type,
			"temp_names": temp_names.duplicate(),
		}

	static func from_dict(data: Dictionary) -> TempAllocNode:
		return TempAllocNode.new(data.get("temp_names", []).duplicate())


# ============================================================================
# LabelDefNode
# ============================================================================
#
# Declares labels that will receive auto-generated unique names.
# .tg syntax: @label lbl_else, lbl_end

class LabelDefNode:
	extends ITGNode

	var label_names: Array   # ["lbl_else", "lbl_end"]

	func _init(p_label_names: Array = []):
		super(ITGNode.NodeType.LABEL_DEF)
		label_names = p_label_names

	func _to_dict() -> Dictionary:
		return {
			"type": type,
			"label_names": label_names.duplicate(),
		}

	static func from_dict(data: Dictionary) -> LabelDefNode:
		return LabelDefNode.new(data.get("label_names", []).duplicate())


# ============================================================================
# ImmDefNode
# ============================================================================
#
# Defines an immediate constant value that will be stored in the data section.
# .tg syntax: @new_imm(0) → imm_0    (value=0, imm_name="imm_0")

class ImmDefNode:
	extends ITGNode

	var imm_name: String   # "imm_0"
	var value: int         # 0

	func _init(p_imm_name: String = "", p_value: int = 0):
		super(ITGNode.NodeType.IMM_DEF)
		imm_name = p_imm_name
		value = p_value

	func _to_dict() -> Dictionary:
		return {
			"type": type,
			"imm_name": imm_name,
			"value": value,
		}

	static func from_dict(data: Dictionary) -> ImmDefNode:
		return ImmDefNode.new(
			data.get("imm_name", ""),
			data.get("value", 0)
		)


# ============================================================================
# BindingNode
# ============================================================================
#
# Represents a @bind directive that connects an IR command word to a local
# slot name.  The binding_expression stores the raw parse string such as
# "$cmd.words[1]".
#
# .tg syntax: @bind dest = $cmd.words[1]

class BindingNode:
	extends ITGNode

	var slot_name: String            # "dest"
	var binding_expression: String   # "$cmd.words[1]"

	func _init(p_slot_name: String = "", p_binding_expression: String = ""):
		super(ITGNode.NodeType.BINDING)
		slot_name = p_slot_name
		binding_expression = p_binding_expression

	func _to_dict() -> Dictionary:
		return {
			"type": type,
			"slot_name": slot_name,
			"binding_expression": binding_expression,
		}

	static func from_dict(data: Dictionary) -> BindingNode:
		return BindingNode.new(
			data.get("slot_name", ""),
			data.get("binding_expression", "")
		)
