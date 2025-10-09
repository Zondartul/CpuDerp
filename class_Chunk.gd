extends RefCounted
class_name Chunk

var code:Array[int];
var shadow:Array[int];
var labels:Dictionary;
var refs:Dictionary;
var label_toks:Dictionary;
var error:bool;

func _init(dict=null):
	if dict:
		for key in dict:
			assert(key in self);
			set(key, dict[key]);

func to_bool()->bool: return not error;

func duplicate()->Chunk:
	var chunk2:Chunk = Chunk.new();
	G.duplicate_deep(self, chunk2);
	return chunk2;
	
static func null_val():
	return Chunk.new({"error":true});
