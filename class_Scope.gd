extends Node
class_name Scope
var ir_name:String;
var user_name:String;
var parent:Scope;
var vars:Array[IR_Var];
var funcs:Array[IR_func];

var local_vars_count:int=0
var local_vars_write_pos:int=0; #= to_local_pos(0);
var args_count:int = 0;
var args_write_pos:int=0;

func _init(cfg:Dictionary):
	G.dictionary_init(self,cfg);

func get_func(fun_name:String)->IR_func:
	var seek_scope:Scope = self; #cur_scope;
	var lc:LoopCounter = LoopCounter.new();
	while true:
		lc.step();
		for fun in seek_scope.funcs:
			if fun.user_name == fun_name:
				return fun;
		if seek_scope.parent:# and seek_scope.parent != "none":
			seek_scope = seek_scope.parent; #IR.scopes[seek_scope.parent];
		else:
			break;
	assert(false, "func not found");
	return null;
