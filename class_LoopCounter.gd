extends RefCounted
class_name LoopCounter;
var n_loops:int=0;
var max_loops:int=0;

func _init(new_max_loops:int=999):
	max_loops = new_max_loops;

func step()->void:
	n_loops += 1;
	if(n_loops > max_loops):
		assert(false, "infinite loop detected");
