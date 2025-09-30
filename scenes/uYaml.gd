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

static func serialize(obj)->String:
	var state = {};
	if is_serializible(obj, state):
		return serialize_helper(obj, 0);
	else:
		push_error("object is not serializible ("+decode_ser_err(state.err)+", path: "+"".join(state.path)+")");
		return "";

static func decode_ser_err(ser_err_code):
	const msgs = {
		101:"empty_string",
		102:"special_symbol_in_string",
		103:"empty_array",
		104:"in_array",
		105:"empty_dict",
		106:"as_key_in_dict",
		107:"as_val_in_dict",
		108:"not_a_string_or_dict_or_array",
		109:"null_value",
		110:"array_too_deep",
		111:"dict",
		112:"not_a_string",
		113:"not_a_string_or_array",
	};
	var text = "";
	for code in ser_err_code:
		text += msgs[code]+".";
	return text;

static func serialize_helper(obj, indent:int)->String:
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
				text += " ".repeat(indent)+serialize_helper(val, indent);
	return text;
			
static func is_one_liner(obj):
	if obj is String: return true;
	if obj is Array:
		for ch in obj:
			if ch is not String: return false;
		return true;
	return false;


# is_serializible(obj, state) - returns true if object can be serialized. 
# provides diagnostic as to what's wrong.
static func is_serializible(obj, state:Dictionary): 
	state["in_array"] = 0;
	state["in_dict"] = 0;
	state["err"] = [];
	state["path"] = [];
	return is_serializible_helper(obj, state);

static func is_serializible_helper(obj, state):
	const spec_symbols = " :#\n";
	if obj == null: state.err.append(109); return false; #no nulls
	if obj is String:
		if len(obj) == 0: state.err.append(101); return false; # no empty strings
		if obj[0] == "#": return true; #comment marker
		for s in spec_symbols:
			if s in obj: state.err.append(102); return false;
		return true;
	if obj is Array:
		if state.in_array >= 2: state.err.append(110); return false;
		if len(obj) == 0: state.err.append(103); return false;
		state.in_array += 1;
		var i = 0;
		for ch in obj:
			state.path.push_back("["+str(i)+"]");
			if not is_serializible_helper(ch, state): state.err.append(104); return false;
			state.path.pop_back();
			i += 1;
		state.in_array -= 1;
		return true;
	if obj is Dictionary:
		if state.in_array: state.err.append(111); return false;
		if len(obj) == 0: state.err.append(105); return false;
		state.in_dict += 1;
		for key in obj:
			if not (key is String and is_serializible_helper(key,state)): state.err.append(106); return false;
			state.path.push_back("."+key);
			var val = obj[key];
			if not is_serializible_helper(val,state): state.err.append(107); return false;
			state.path.pop_back();
		state.in_dict -= 1;
		return true;
	# wrong object type
	if state.in_array == 0: state.err.append(108);
	if state.in_array == 1: state.err.append(113);
	if state.in_array >= 2: state.err.append(112);
	return false;

#------- DESERIALIZATION ----------------------

static func deserialize(text):
	var obj = {};
	deserialize_helper(text, obj);
	return obj;

const AS_2D_APPEND = 2;
const AS_1D_SET = 1;

static func deserialize_helper(text, obj):
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

static func dict_path_insert(obj:Dictionary, path:Array, words:Array, mode:int):
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
			if len(words) == 1:
				node[rhead] = words[0];
			else:
				node[rhead] = words;
		if mode == AS_2D_APPEND:
			if rhead not in node: node[rhead] = [];
			node[rhead].append(words);

static func find_first_not_of(text:String, needle:String):
	var idx = 0;
	for ch in text: 
		if ch in needle:
			idx += 1; 
		else: 
			return idx;
	return -1;
