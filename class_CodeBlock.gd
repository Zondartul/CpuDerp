extends IR_Value; #RefCounted
class_name CodeBlock;

var code:Array[IR_Cmd] = [];
var if_block_continued:bool = false;
var lbl_from:String = "";
var lbl_to:String = "";

func _init(dict=null):
	val_type = "code";
	if dict:
		for key in dict:
			assert(key in self);
			set(key, dict[key]);
