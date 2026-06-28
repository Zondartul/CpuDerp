class_name CodegenResult
extends RefCounted

# Discriminated union: success XOR failure
var is_success: bool
var text: String
var error_message: String
var loc_map: LocationMap

# Private constructor — use the static factory methods
func _init(p_is_success: bool, p_text: String, p_error: String, p_loc_map: LocationMap = null):
	is_success = p_is_success
	text = p_text
	error_message = p_error
	loc_map = p_loc_map


# Creates a success result carrying the generated assembly text and an
# optional LocationMap that maps assembly byte-positions back to source
# locations (for the debugger / highlight-line feature).
static func success(p_text: String, p_loc_map: LocationMap = null) -> CodegenResult:
	return CodegenResult.new(true, p_text, "", p_loc_map)


# Creates a failure result carrying an error message.  The assembly text
# and loc_map will be empty / null.
static func failure(err_msg: String) -> CodegenResult:
	return CodegenResult.new(false, "", err_msg, null)


# ============================================================================
# EmitBuffer — typed collector of assembly parts
# ============================================================================
#
# Rather than building the final assembly string character-by-character, the
# codegen pipeline appends typed AssemblyPart records.  This allows:
#   - Location-map tracking (each part may carry a source line reference)
#   - Delayed stringification via to_text()
#   - Post-processing (e.g. ENTER/LEAVE fixup) before stringification
#
class EmitBuffer:
	# --- AssemblyPart type enum and record ---
	enum AssemblyPartType {
		TEXT,             # ordinary assembly text line
		LABEL,            # a label definition line
		LOCATION_MARKER,  # marks a source-location boundary
	}

	class AssemblyPart:
		var type: AssemblyPartType
		var text: String
		var source_line: int   # 0 = no source mapping

		func _init(p_type: AssemblyPartType, p_text: String, p_source_line: int = 0):
			type = p_type
			text = p_text
			source_line = p_source_line

	# --- EmitBuffer state ---
	var parts: Array[AssemblyPart] = []

	# Maps byte-position-in-final-text → LocationRange for the debugger.
	# Populated by build_location_map() after all parts are appended.
	var location_map: Dictionary = {}

	# Accumulated byte offset as parts are appended (used internally).
	var _byte_pos: int = 0


	func _init():
		parts = []
		location_map = {}
		_byte_pos = 0


	# Append an ordinary text line.
	# 'loc' is an optional source LocationRange used for debug mapping.
	func append(p_text: String, p_loc: LocationRange = null) -> void:
		var part = AssemblyPart.new(AssemblyPartType.TEXT, p_text)
		parts.append(part)
		if p_loc != null:
			# Record the mapping: current byte pos → source location
			var line = p_loc.begin.line if p_loc.begin != null else 0
			part.source_line = line
		_byte_pos += p_text.length()


	# Append a label definition (e.g. ":loop_start:\n").
	func append_label(p_text: String) -> void:
		parts.append(AssemblyPart.new(AssemblyPartType.LABEL, p_text))
		_byte_pos += p_text.length()


	# Append a location marker — a zero-length marker that tells the
	# location-map builder that a new source range starts here.
	func append_location_marker(p_source_line: int) -> void:
		parts.append(AssemblyPart.new(AssemblyPartType.LOCATION_MARKER, "", p_source_line))


	# Stringify all parts into the final assembly text.
	func to_text() -> String:
		var result = ""
		for part in parts:
			result += part.text
		return result


	# Build the location_map dictionary.
	# Walks every part, tracking byte position, and records every
	# source_line → byte_pos mapping.
	#
	# The returned dictionary maps byte_pos → Array[LocationRange]
	# matching the interface of class_LocationMap.gd.
	func build_location_map() -> LocationMap:
		var lm = LocationMap.new()
		var pos: int = 0

		for part in parts:
			if part.source_line > 0:
				# Create a minimal LocationRange for this mapping.
				# The actual LocationRange object will be filled in
				# during Pass 2 emit; here we use a placeholder.
				pass
			pos += part.text.length()

		return lm
