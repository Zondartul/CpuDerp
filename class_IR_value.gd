extends RefCounted
class_name IR_Value;

var ir_name:String;
var storage:Storage;
var needs_deref:bool=false;

static var none = IR_Value.new("none");

func _init(_ir_name=""):
	ir_name=_ir_name;
