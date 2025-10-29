extends Node

const class_Iter = preload("res://class_Iter.gd");
const class_Location = preload("res://class_Location.gd");
const class_LocationRange = preload("res://class_Location.gd");
const class_Token = preload("res://class_Token.gd");
const class_Chunk = preload("res://class_Chunk.gd");
const class_ErrorReporter = preload("res://class_ErrorReporter.gd");
const class_Cmd_args = preload("res://class_Cmd_arg.gd");
const class_Cmd_flags = preload("res://class_Cmd_flags.gd");
const class_AST = preload("res://class_AST.gd");
const class_LocationMap = preload("res://class_LocationMap.gd");
const class_IR_Value = preload("res://class_IR_value.gd");
const class_IR_Cmd = preload("res://class_IR_cmd.gd");
const class_CodeBlock = preload("res://class_CodeBlock.gd");
const class_AssyBlock = preload("res://class_AssyBlock.gd");


## Creates an independent copy of the value
func duplicate_val(obj)->Variant:
	if (obj is Object):
		if "duplicate" in obj:
			return obj.duplicate();
	elif (obj is Dictionary):
		var res = {};
		duplicate_deep(obj, res);
		return res;
	elif (obj is Array):
		return obj.duplicate();
	return obj;

const duplication_blacklist = ["RefCounted", "script", "Built-in script"];
## Creates a deep copy of an object by duplicating each property
func duplicate_deep(src, dest)->void:
	if src is Object:
		assert(dest is Object);
		for key in src.get_property_list():
			if key.name in duplication_blacklist: continue;
			#print("duplicate "+str(key));
			var old_val = src.get(key.name);
			var new_val = duplicate_val(old_val);
			assert(is_type_compatible(key.type, typeof(new_val)), "Can't assign property because of type mismatch");
			dest.set(key.name, new_val);
	elif src is Dictionary:
		assert(dest is Dictionary);
		for key in src:
			var val = src[key];
			dest[key] = duplicate_val(val);
	elif src is Array:
		assert(dest is Array);
		var res = duplicate_val(src);
		dest.assign(res);
## creats a shallow copy of an object by duplicating each property
func duplicate_shallow(src, dest)->void:
	for key in src.get_property_list():
		if key.name in duplication_blacklist: continue;
		dest.set(key.name, src.get(key.name));

func is_type_compatible(type_A:int, type_B:int)->bool:
	return type_A == type_B;

func dictionary_init(obj:Object, dict:Dictionary):
	var prop_list = obj.get_property_list();
	for key in prop_list:
		if key.name in dict:
			var val = dict[key.name];
			assert(is_type_compatible(key.type, typeof(val)), "Can't assign property because of type mismatch");
			obj.set(key.name, val);
		
#-------- Comparison logic ---------------
func has(obj):
	if obj is Array:
		return not obj.is_empty();
	if obj is Dictionary:
		return not obj.is_empty();
	if obj and (obj is Object) and ("to_bool" in obj):
		return obj.to_bool();
	if obj is LocationRange:
		return (has(obj.begin) and has(obj.end));
	if obj is Location:
		return obj.line_idx != -1;
	return not not obj;

# --------- util ------------
## returns an index of "idx from the end".
func rev_idx(arr:Array, idx:int):
	return len(arr)-1-idx;

## returns N'th array element or null if there isn't one.
func maybe_idx(arr:Array, idx:int):
	if (idx >= 0) and (idx < len(arr)): return arr[idx];
	else: return null;

#------ string stuff

## removes space characters from the beginning and the end of a string
func trim_spaces(line:String)->String:
	var idx_first = first_non_space(line)
	var idx_last = last_non_space(line)
	var nsp_len = idx_last - idx_first+1;
	line = line.substr(idx_first, nsp_len);
	return line;

## returns the index of the first character in a string that is not some space character
func first_non_space(line:String)->int:
	var idx = 0;
	for ch in line:
		if ch in " \n\r\t":
			idx = idx+1;
		else:
			return idx;
	return -1;

## returns the index of the last character in a string that is not some space character
func last_non_space(line:String)->int:
	var idx = first_non_space(line.reverse())
	if idx == -1: return -1;
	else: return line.length() - idx - 1;

## finds first instance of any character from 'needles' in the string 'text'
func find_first_of(text:String, needles:String, from:int=0)->int:
	for i in range(from, len(text)):
		var ch = text[i];
		if ch in needles:
			return i;
	return len(text);

## returns an array with the positions of all occurences of needle in haystack
func str_find_all_instances(needle:String, haystack:String)->Array:
	var res = [];
	var pos = 0;
	while true:
		var iter = haystack.find(needle, pos);
		if(iter != -1):
			res.append(iter);
			pos = iter+1;
		else: break;
	return res;

## converts a string index to a row/column pair.
func str_to_row_col(pos:int, text:String)->Array:
	return str_to_row_col_arr([pos], text)[0];

## returns an array of [row, column] entries for each entry in the [positions] array
func str_to_row_col_arr(positions:Array, text:String)->Array:
	var res = [];
	var newlines = str_find_all_instances("\n", text);
	for pos in positions:
		var line_idx = 0;
		var last_pos = 0;
		for line_pos in newlines:
			if line_pos > pos:
				pos -= last_pos;
				pos -= 1; # off by one error
				break;
			else:
				last_pos = line_pos;
				line_idx += 1;
		res.append([line_idx, pos]);
	assert(len(res) == len(positions));
	return res;

func comparison(A:Object, B:Object, prop_list:Array)->bool:
	for prop in prop_list:
		var val_A = A.get(prop);
		var val_B = B.get(prop);
		if val_A < val_B: return true;
		elif val_A > val_B: return false;
	return false;

func first_in_dict(dict:Dictionary)->Variant:
	if len(dict.keys()):
		return dict[dict.keys()[0]];
	return null;
	
#-------

func unescape_string(text:String)->String:
	var new_str:String = "";
	var esc_step:int = 0;
	var num_str:String = "";
	for ch in text:
		match esc_step:
			0:
				if(ch == "%"):
					esc_step = 1;
				else:
					new_str += ch;
			1:	num_str += ch; esc_step += 1;
			2:	num_str += ch; esc_step += 1;
			3:	
				num_str += ch;
				assert(num_str.is_valid_int());
				var num = num_str.to_int();
				num_str = "";
				var new_ch = PackedByteArray([num]).get_string_from_ascii();
				new_str += new_ch;
				esc_step = 0;
	#print("unescape str: in [%s], out [%s]" % [text, new_str]);
	return new_str;

func escape_string(text):
	var new_str = "";
	for ch:String in text:
		if ch in "qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM1234567890.+-_":
			new_str += ch;
		else:
			var buff = ch.to_ascii_buffer();
			assert(len(buff) == 1);
			ch = "%" + "%03d" % buff[0];
			new_str += ch;
	return new_str;

## performs a "newline" function for ItemList widgets
func complete_line(item_list:ItemList):
	var n = item_list.max_columns-1 - ((item_list.item_count-1) % item_list.max_columns);
	for i in range(n): item_list.add_item(" ");
