extends RefCounted
class_name Type

var name:String; ## user-name, e.g. Vector
var full_name:String:get=get_full_name; ## e.g. Vector[Blah]
var of:Array; ## if it's a meta-type or a container
var size:int:get=get_size; ## how many bytes of memory does an instance occupy?

# special types
@warning_ignore("unused_private_class_variable")
static var _error = Type.new("ERROR"); # poison value - something broke
@warning_ignore("unused_private_class_variable")
static var _none = Type.new("NONE"); # no type specified
@warning_ignore("unused_private_class_variable")
static var _param = Type.new("PARAM"); # template parameter (usually a number)
# normal types
@warning_ignore("unused_private_class_variable")
static var _null = Type.new("null"); # nulled value (expected something, got null)
@warning_ignore("unused_private_class_variable")
static var _void = Type.new("void"); # explicitly does not have a value

func _init(cfg=null):
	if cfg is Dictionary:
		G.dictionary_init(self, cfg);
	elif cfg is String:
		name=cfg;

func get_full_name()->String:
	var S:String = name;
	if len(of):
		S += "[";
		var first:bool = true;
		for ch in of:
			if first: first = false; 
			else: S += ", ";
			if ch is Type:
				S += ch.get_full_name();
			else:
				S += str(ch);
		S += "]";
	return S;

static func from_string(S:String):
	if (S == null) or (S == "NULL"): return null;
	var T:Type = Type.new();
	var parse:Array[String] = list_and_brace_separator(S, "[", "]", ",");
	assert(parse != null);
	T = from_string_helper(parse);
	return T;

static func from_string_helper(parse:Array):
	if parse == null: return null;
	if len(parse) == 0: return null;
	var T:Type = Type.new();
	T.name = (parse[0] as String).strip_edges(true,true);
	if len(parse) >= 2:
		for ch in parse[1]:
			var T2:Type = from_string_helper(ch);
			assert(G.has(T2));
			T.of.append(T2);
	return T;

static func list_and_brace_separator(
	text:String, brace_open:String, 
	brace_close:String, delim:String)->Array[String]:
	var parse:Array[String] = [];
	var word:String = "";
	var brace_count:int = 0;
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
				var sub_list:Array[String] = labs_reduce_list(word, brace_open, brace_close, delim);
				parse.append(sub_list);
				word = "";
		else:
			word += ch;
	if word != "": parse.append(word);
	return parse;
	
static func labs_reduce_list(
	text:String, brace_open:String, 
	brace_close:String, delim:String)->Array[String]:
	var parse:Array[String] = [];
	var words:Array[String] = [];
	var word:String = "";
	var brace_count:int = 0;
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
		var sub_parse:Array[String] = list_and_brace_separator(word_to_parse, brace_open, brace_close, delim);
		assert(sub_parse != null);
		parse.append(sub_parse);
	return parse;

## --------- Miniderp-specific stuff --------

func get_deref_type()->Variant:
	if name in ["Ref", "Array"]:
		if len(of) > 0:
			assert(len(of) > 0);
			var base:Variant = of[0];
			if base is Type:
				return base;
			else:
				return _none;
		else:
			return _none;
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
	"NONE", "int", "char", "u8", "s8", "u16", "s16", "u32", "s32", "u64", "s64",
];
const pointer_types = ["Ref", "Array", "String"]

func get_size()->int:
	if name in pointer_types:
		return pointer_size;
	if name in primitive_sizes:
		return primitive_sizes[name];
	return 1;
	#assert(false, "Unknown type size for type %s" % full_name);

func is_integer()->bool: return bool(full_name in integer_types);
