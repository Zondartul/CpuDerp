extends RefCounted
class_name Iter

var tokens:Array;
var pos:int;

func _init(new_tokens:Array, new_pos:int):
	tokens = new_tokens;
	pos = new_pos;

func duplicate()->Iter:
	return Iter.new(tokens,pos);
