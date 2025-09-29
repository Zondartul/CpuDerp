extends Node
# This is a parser-reader for my custom serialization format that looks vaguelly like YAML.
# dict:
#  key1_1: blah
#  key1_2: 
#   lvl2_1:
#    blah bluh bloh
#    fa foo
#
# Is equivalent to (GDScript)...
#
# {"dict":{
#           "key1_1": [ "blah" ],
#			"key_1_2": { "lvl2_1": [
#				["blah", "bluh", "bloh"],  
#				["fa", "foo"],
#			] },
#		  } 
# }
# (all leaf values are strings btw)
# What's the point? No point, I was bored

#--------- SERIALIZATION ------------------

func serialize(obj)->String:
	if is_serializible(obj):
		return serialize_helper(obj, 0);
	else:
		push_error("object is not serializible");
		return "";

func serialize_helper(obj, indent:int)->String:
	var text = "";
	var is_first = true;
	if obj is String:
		text += obj;
	if obj is Dictionary:
		for key in obj:
			var val = obj[key];
			if is_first: is_first = false; 
			else: text += "\n";
			text += " ".repeat(indent) + key + ": ";
			if is_one_liner(val):
				text += serialize_helper(val, 0);
			else:
				text += "\n";
				text += serialize_helper(val, indent+1);
	if obj is Array:
		for val in obj:
			if val is String:
				if is_first: is_first = false;
				else: text += " ";
				text += val;
			if val is Array:
				assert(is_one_liner(val));
				if is_first: is_first = false;
				else: text += "\n";
				text += serialize_helper(val, indent+1);
	return text;
			
func is_one_liner(obj):
	if obj is String: return true;
	if obj is Array:
		for ch in obj:
			if ch is not String: return false;
		return true;
	return false;

func is_serializible(obj): return is_serializible_helper(obj, 0);

func is_serializible_helper(obj, in_array):
	const spec_symbols = " :#\n";
	if obj is String:
		if len(obj) == 0: return false; # no empty strings
		if obj[0] == "#": return true; #comment marker
		for s in spec_symbols:
			if s in obj: return false;
		return true;
	if obj is Array and in_array < 2:
		if len(obj) == 0: return false;
		for ch in obj:
			if not is_serializible_helper(ch, in_array+1): return false;
		return true;
	if obj is Dictionary and not in_array:
		if len(obj) == 0: return false;
		for key in obj:
			if not (key is String and is_serializible_helper(key,0)): return false;
			var val = obj[key];
			if not is_serializible_helper(val,0): return false;
		return true;
	return false;

#------- DESERIALIZATION ----------------------

var IR = {};

func deserialize(text):
	var obj = {};
	deserialize_helper(text, obj);
	return obj;

const AS_2D_APPEND = 2;
const AS_1D_SET = 1;

func deserialize_helper(text, obj):
	var lines = text.split("\n",false);
	var path = [];
	for line in lines:
		if len(line) == 0: continue;
		if line[0] == "#": continue;
		var indent = find_first_not_of(line, " ");
		path.resize(indent);
		line = line.substr(indent);
		var colon_pos = line.find(":");
		if colon_pos == -1:
			# array-like object
			var words = line.split(" ", false);
			#print("parse arr: ["+str(words)+"]");
			dict_path_insert(obj, path, words, AS_2D_APPEND);
		else:
			# key-value object
			var key = line.substr(0, colon_pos);
			var val = line.substr(colon_pos+1);
			#print("parse kv: ["+key+"] : ["+val+"]");
			path.append(key);
			var words = val.split(" ",false);
			if len(words):
				dict_path_insert(obj, path, words, AS_1D_SET);
	#print("parsed dict: ");
	#print(obj);

func dict_path_insert(obj:Dictionary, path:Array, words:Array, mode:int):
	if len(path) == 1:
		obj[path[0]] = words;
	else:
		var rhead = path.back();
		var rtail = path.slice(0,-1);
		var node = obj;
		for key in rtail:
			if key not in node: node[key] = {};
			node = node[key];
		if mode == AS_1D_SET:
			node[rhead] = words;
		if mode == AS_2D_APPEND:
			if rhead not in node: node[rhead] = [];
			node[rhead].append(words);

func find_first_not_of(text:String, needle:String):
	var idx = 0;
	for ch in text: 
		if ch in needle:
			idx += 1; 
		else: 
			return idx;
	return -1;
