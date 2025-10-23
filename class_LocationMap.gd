extends RefCounted
class_name LocationMap

## map. key is IP. value is Array[LocationRange] of all LRs that begin or end here.
var begin:Dictionary;
var end:Dictionary;

func _init():
	begin = {};
	end = {};
