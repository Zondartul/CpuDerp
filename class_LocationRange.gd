extends RefCounted
class_name LocationRange

var begin:Location;
var end:Location;

func _init(dict=null):
	if dict:
		for key in dict:
			assert(key in self);
			set(key, dict[key]);
			
func duplicate()->LocationRange:
	var loc2 = LocationRange.new();
	G.duplicate_deep(self, loc2);
	return loc2;

func is_valid():
	if not (begin != null):
		print("LocationRange: begin is null");
		return false;
	if not (begin.is_valid()):
		print("LocationRange: begin invalid");
		return false;
	if not (end != null):
		print("LocationRange: end is null");
		return false;
	if not (end.is_valid()):
		print("LocationRange: end invalid");
		return false;
	return true;
#	return begin.is_valid() and end.is_valid();

func _to_string()->String:
	if is_valid():
		return "%s~%s" % [begin._to_string(), end.to_string_short()];
	else:
		return "<error>";

func to_string_full()->String:
	if is_valid():
		return "%s~%s" % [begin.to_string_full(), end.to_string_full()];
	else:
		return "<error>"

## returns a comparable value
func dist()->float:
	assert(is_valid());
	var line_diff = end.line_idx - begin.line_idx;
	var col_diff = end.col - begin.col;
	return line_diff + col_diff / 1000.0;

static func from_loc_len(loc:Location, length:int)->LocationRange:
	var loc2 = loc.duplicate();
	loc2.col += length;
	return LocationRange.new({"begin":loc.duplicate(), "end":loc2});

static func from_string(S:String)->LocationRange:
	var idx = S.find("~");
	var s_from = S.substr(0, idx);
	var s_to = S.substr(idx+1);
	var loc_from = Location.from_string(s_from);
	var loc_to = Location.from_string(s_to);
	var res = LocationRange.new({"begin":loc_from, "end":loc_to});
	#print("LocationRange.from_string(%s) result: %s" % [S, res.to_string_full()])
	return res;
