extends Node
class_name Scope
var ir_name:String;
var user_name:String;
var parent:Scope;
var vars:Array[IR_Var];
var funcs:Array[IR_func];

func _init(cfg:Dictionary):
	G.dictionary_init(self,cfg);
