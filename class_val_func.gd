extends IR_Value
class_name IR_func

var user_name:String;
var scope:Scope;
var code:CodeBlock;

var type_return:Type;
var arg_names:Array[String];
var arg_types:Array[Type];

func _init(IR:IRKind, cfg):
	ir_name = IR.make_unique_IR_name("func");
	if cfg is Dictionary:
		G.dictionary_init(self,cfg);
	
