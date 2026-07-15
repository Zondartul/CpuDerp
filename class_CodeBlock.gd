extends IR_Value; #RefCounted
class_name CodeBlock;

var code:Array[IR_Cmd] = [];
var if_block_continued:bool = false;
var if_block_lbl_end:String = "";
var lbl_from:String = "";
var lbl_to:String = "";

func _init(dict=null):
	#val_type = "code";
	if dict:
		for key in dict:
			assert(key in self);
			set(key, dict[key]);

func emit_IR(cmd:Array, loc:LocationRange)->void:
	#IR.commands.append(cmd);
	var cmd_translated:Array[String] = [];
	assert(cmd[0] is String);
	for i in range(len(cmd)):
		cmd_translated.append_array(serialize_ir_arg(cmd[i]));
	#cmd_translated.append_array(serialize_ir_arg(loc));
	#code.append(cmd_translated);
	code.append(IR_Cmd.new(cmd_translated,loc));

func serialize_ir_arg(arg)->Array[String]:
	if arg is String: return [arg];
	elif arg is Dictionary:
		assert(("ir_name" in arg) and (arg.ir_name is String));
		return [arg.ir_name];
	elif arg is Array:
		var res:Array[String] = [];
		res.append("[");
		for sub_arg in arg:
			res.append_array(serialize_ir_arg(sub_arg));
		res.append("]");
		return res;
	elif arg is LocationRange:
		return [G.escape_string(arg.to_string_full())];
	else:
		push_error("can't serialize IR argument ["+str(arg)+"]");
		return [];
