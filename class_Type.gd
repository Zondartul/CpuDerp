extends RefCounted
class_name Type

var name:String; ## user-name, e.g. Vector
var full_name:String:get=get_full_name; ## e.g. Vector[Blah]
var of:Array[Type]; ## if it's a meta-type or a container
var size:int; ## how many bytes of memory does an instance occupy?

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
