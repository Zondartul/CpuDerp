extends RefCounted
class_name AssyBlock

var code:String = "";
var loc_map:LocationMap = LocationMap.new();
var write_pos:int = 0;

#func _init():
	#code = "";
	#loc_map = LocationMap.new();
