extends IR_Var
class_name IR_Imm

var value:Variant=null;
var type:Type;
var is_assy_constant:bool=false; ## is this constant known by name to the assembler?

func _init(IR:IRKind, _value:Variant=null, _type:Type=null):
	ir_name = IR.make_unique_IR_name("imm");
	IR.all_syms[ir_name] = self;
	value = _value;
	type = _type;
#
#func new_imm(val)->Dictionary:
	#var ir_name = "imm_"+str(val_idx)+"__"+str(val); val_idx += 1;
	#assert(ir_name not in all_syms, "ir sym uid count broken");
	#var handle = {"ir_name":ir_name, "val_type":"immediate", "value":str(val), "data_type":"error", "data_size":4, "storage":"NULL"};
	#if val is int:
		#handle["data_type"] = "int";
	#elif val is String:
		#handle["data_type"] = "String";
	#all_syms[ir_name] = handle;
	#return handle;
