extends Node

const class_Iter = preload("res://class_Iter.gd");
const class_Token = preload("res://class_Token.gd");
const class_Chunk = preload("res://class_Chunk.gd");
const class_ErrorReporter = preload("res://class_ErrorReporter.gd");
const class_Cmd_args = preload("res://class_Cmd_arg.gd");
const class_Cmd_flags = preload("res://class_Cmd_flags.gd");
const class_AST = preload("res://class_AST.gd");

## Creates an independent copy of the value
func duplicate_val(obj)->Variant:
	if (obj is Object):
		if "duplicate" in obj:
			return obj.duplicate();
	return obj;

const duplication_blacklist = ["RefCounted", "script", "Built-in script"];
## Creates a deep copy of an object by duplicating each property
func duplicate_deep(src, dest)->void:
	for key in src.get_property_list():
		if key.name in duplication_blacklist: continue;
		#print("duplicate "+str(key));
		var old_val = src.get(key.name);
		var new_val = duplicate_val(old_val);
		dest.set(key.name, new_val);
## creats a shallow copy of an object by duplicating each property
func duplicate_shallow(src, dest)->void:
	for key in src.get_property_list():
		if key.name in duplication_blacklist: continue;
		dest.set(key.name, src.get(key.name));

#-------- Comparison logic ---------------
func has(obj):
	if obj is Array:
		return not obj.is_empty();
	if obj is Dictionary:
		return not obj.is_empty();
	if obj and (obj is Object) and ("to_bool" in obj):
		return obj.to_bool();
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
