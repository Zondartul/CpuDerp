extends RefCounted
class_name Location

var filename:String;
var line:String;
var line_idx:int = -1;
var col:int = 0;
var uid:int = 0;
static var counter = 0;

func _init(dict=null):
	if dict:
		for key in dict:
			assert(key in self);
			set(key, dict[key]);
	uid = counter;
	counter += 1;

func duplicate()->Location:
	var loc2 = Location.new();
	G.duplicate_deep(self, loc2);
	return loc2;

func is_valid(): 
	if not (line_idx != -1):
		print("Location: line_idx unset");
		return false;
	return true;
	#return line_idx != -1;

func less_than(other:Location)->bool:
	return G.comparison(self, other, ["filename", "line", "line_idx", "col"]);
	
func _to_string()->String:
	return "@%s:%d:%d" % [filename, line_idx, col];

func to_string_short()->String:
	return "%d:%d" % [line_idx, col];

func to_string_full()->String:
	return "@%s:%d:%d:[%s]" % [filename, line_idx, col, G.escape_string(line)];

static func from_string(S:String)->Location:
	var regex:RegEx = RegEx.new();
	#const rx_pretty = "\\@[^:]*\\:[^:]*\\:[^:]*";
	#const rx_short = "[^:]*\\:[^:]*";
	#const rx_full = "\\@[^:]*\\:[^:]*\\:[^:]*\\:\\[[^:]*\\]";
	const rx_any =  "(\\@([^:]*)\\:)?([^:]*)\\:([^:]*)(\\:\\[([^:]*)\\])?";
	# groups           1 2          3        4      5      6
	var compile_res = regex.compile(rx_any);
	assert(compile_res == OK);
	var res:RegExMatch = regex.search(S);
	assert(res, "unable to deserialize location: %s" % S);
	if res:
		#print("-------- REGEX ----");
		#print(res.strings);
		var new_filename = "";
		if res.get_string(1) != "":
			new_filename = res.get_string(2);
		var new_line_idx = int(res.get_string(3));
		var new_col = int(res.get_string(4));
		var new_line = "";
		if res.get_string(5) != "":
			new_line = res.get_string(6);
			new_line = G.unescape_string(new_line);
		var loc = Location.new({"filename":new_filename, "line":new_line, "line_idx":new_line_idx, "col":new_col});
		return loc;
	else:
		return Location.new();
	#var regex:RegEx = RegEx.new();
	#regex.compile("\\@([^:]*)\\:([^:]*)\\:([^:]*)");
	#var res:RegExMatch = regex.search(S);
	#if res:
		#var loc = Location.new({"filename":res.get_string(1), "line_idx":res.get_string(2), "col":res.get_string(3)});
		#return loc;
	#else:
		#return Location.new();
		
