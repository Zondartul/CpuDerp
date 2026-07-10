extends IR_Value
class_name IR_Var

var user_name:String;
var data_type:Type;
var storage:Storage;

func _init(IR:IRKind, _user_name:String=""):
	ir_name = IR.make_unique_IR_name("var");
	user_name=_user_name;
