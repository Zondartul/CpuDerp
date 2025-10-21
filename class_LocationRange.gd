extends RefCounted
class_name LocationRange

var from:Location;
var to:Location;

func _init(dict=null):
	if dict:
		for key in dict:
			assert(key in self);
			set(key, dict[key]);
			
func duplicate()->LocationRange:
	var loc2 = LocationRange.new();
	G.duplicate_deep(self, loc2);
	return loc2;

func _to_string()->String:
	return "%s~%s" % [from, to];

static func from_loc_len(loc:Location, length:int):
	var loc2 = loc.duplicate();
	loc2.col += length;
	return LocationRange.new({"from":loc.duplicate(), "to":loc2});
