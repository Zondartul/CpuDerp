extends Node
class_name IRKind

var code_blocks:Dictionary[String,CodeBlock]
var scopes:Dictionary[String,Scope]
var all_syms:Dictionary[String,IR_Value] = {};
var val_idx:int = 0;

func make_unique_IR_name(type:String, text:Variant=null)->String:
	var val_name:String = type+"_"+str(val_idx);
	if text != null: val_name += "__"+text;
	val_idx+=1;
	return val_name;
