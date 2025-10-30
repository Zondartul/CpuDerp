extends RefCounted
class_name Type

var name:String; ## user-name, e.g. Vector
var full_name:String:get=get_full_name; ## e.g. Vector[Blah]
var of:Array[Type]; ## if it's a meta-type or a container
var size:int:get=get_size; ## how many bytes of memory does an instance occupy?

func _init(dict=null):
	if dict:
		G.dictionary_init(self, dict);

func get_full_name()->String:
	var S = name;
	if len(of):
		S += "[";
		var first = true;
		for ch in of:
			if first: first = false; 
			else: S += ", ";
			S += ch.get_full_name();
		S += "]";
	return S;

static func from_string(S:String):
	if (S == null) or (S == "NULL"): return null;
	var T:Type = Type.new();
	var parse = list_and_brace_separator(S, "[", "]", ",");
	assert(parse != null);
	T = from_string_helper(parse);
	return T;

static func from_string_helper(parse:Array):
	if parse == null: return null;
	if len(parse) == 0: return null;
	var T = Type.new();
	T.name = (parse[0] as String).strip_edges(true,true);
	if len(parse) >= 2:
		for ch in parse[1]:
			var T2 = from_string_helper(ch);
			assert(T2 != null);
			T.of.append(T2);
	return T;

static func list_and_brace_separator(text:String, brace_open:String, brace_close:String, delim:String):
	var parse = [];
	var word = "";
	var brace_count = 0;
	for ch in text:
		if ch == brace_open:
			if(brace_count == 0):
				## first brace of this text, shift the word
				parse.append(word);
				word = "";
			brace_count += 1;
		elif ch == brace_close:
			brace_count -= 1;
			if(brace_count == 0):
				## last brace of this text, reduce the list
				var sub_list = labs_reduce_list(word, brace_open, brace_close, delim);
				parse.append(sub_list);
				word = "";
		else:
			word += ch;
	if word != "": parse.append(word);
	return parse;
	
static func labs_reduce_list(text:String, brace_open:String, brace_close:String, delim:String):
	var parse = [];
	var words = [];
	var word = "";
	var brace_count = 0;
	for ch in text:
		if ch == brace_open:
			brace_count += 1;
			word += ch;
		elif ch == brace_close:
			brace_count -= 1;
			word += ch;
		elif ch == ",":
			if brace_count == 0:
				words.append(word);
				word = "";
			else:
				word += ch;
		else:
			word += ch;
	if word != "": words.append(word);
	for word_to_parse in words:
		var sub_parse = list_and_brace_separator(word_to_parse, brace_open, brace_close, delim);
		assert(sub_parse != null);
		parse.append(sub_parse);
	return parse;

## --------- Miniderp-specific stuff --------

func get_deref_type():
	if name in ["Ref", "Array"]:
		assert(len(of) > 0);
		return of[0];
	if name == "String":
		return Type.new({"name":"char"});
	return null;

const pointer_size = 4;

const primitive_sizes = {
	"u8":1,
	"s8":1,
	"u16":2,
	"s16":2,
	"u32":4,
	"s32":4,
	"u64":8,
	"s64":8,
	"int":8,
	"char":1,
	"float":4,
	"double":8,
};
const integer_types = [
	"int", "char", "u8", "s8", "u16", "s16", "u32", "s32", "u64", "s64",
];
const pointer_types = ["Ref", "Array", "String"]

func get_size():
	if name in pointer_types:
		return pointer_size;
	if name in primitive_sizes:
		return primitive_sizes[name];
	return 1;
	#assert(false, "Unknown type size for type %s" % full_name);

func is_integer(): return bool(full_name in integer_types);
