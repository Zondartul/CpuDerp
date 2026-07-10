extends RefCounted
class_name IR_Value;

var ir_name:String;

static var none = IR_Value.new("none");

func _init(_ir_name=""):
	ir_name=_ir_name;
