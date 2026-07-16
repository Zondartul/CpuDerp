extends IR_Value
class_name IR_Var

var user_name:String;
var data_type:Type;

func _init(IR:IRKind, _user_name:String="", _data_type:Type=null):
	ir_name = IR.make_unique_IR_name("var");
	IR.all_syms[ir_name] = self;
	user_name=_user_name;
	data_type = _data_type;
#	assert(ir_name != "var_4", "debug_trap");
