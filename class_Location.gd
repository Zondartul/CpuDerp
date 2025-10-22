extends RefCounted
class_name Location

var filename:String;
var line:String;
var line_idx:int;
var col:int;

func _init(dict=null):
	if dict:
		for key in dict:
			assert(key in self);
			set(key, dict[key]);

func duplicate()->Location:
	var loc2 = Location.new();
	G.duplicate_deep(self, loc2);
	return loc2;

func less_than(other:Location)->bool:
	return G.comparison(self, other, ["filename", "line", "line_idx", "col"]);
	
func _to_string()->String:
	return "@%s:%d:%d" % [filename, line_idx, col];

static func from_string(S:String)->Location:
	var regex:RegEx = RegEx.new();
	regex.compile("\\@([^:]*)\\:([^:]*)\\:([^:]*)");
	var res:RegExMatch = regex.search(S);
	if res:
		var loc = Location.new({"filename":res.get_string(1), "line_idx":res.get_string(2), "col":res.get_string(3)});
		return loc;
	else:
		return Location.new();
		
