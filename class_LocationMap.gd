extends RefCounted
class_name LocationMap

## map. key is IP. value is Array[LocationRange] of all LRs that begin or end here.
var begin:Dictionary[int,Array];
var end:Dictionary[int,Array];

func _init():
	begin = {};
	end = {};
