extends IR_Value
class_name IR_array

var array_size:int;

func _init(IR:IRKind, _size:int=0):
	ir_name = IR.make_unique_IR_name("arr");
	array_size=_size;
#func new_arr(size)->Dictionary:
	#var ir_name = "arr_"+str(len(all_syms)+1)+"__"+str(size);
	#var handle = {"ir_name":ir_name, "val_type":"array", "value":str(size), "data_type":"error", "storage":"NULL", "is_array":1, "array_size":size};
	#all_syms[ir_name] = handle;
	#return handle;
