extends Node

var IR = null;
var cur_scope = null;
var cur_code_block = null;

func clear_IR():
	IR = {
		"code_blocks":{},
		"scopes":{},
	};
	var global_scope = new_scope("global",null);
	cur_scope = global_scope;
	var global_code_block = new_code_block();
	cur_code_block = global_code_block;#IR.code_blocks[0];

var val_idx = 0;
func make_unique_IR_name(type, text=null):
	var val_name = type+"_"+str(val_idx);
	if text: val_name += "__"+text;
	val_idx+=1;
	return val_name;
	
# returns a handle to a new IR value
func new_val(): return {"val_type":null, "ir_name":null, "user_name":null, "type":null, "value":null};

func new_val_temp():
	var val = new_val();
	val.val_type = "temporary";
	val.ir_name = make_unique_IR_name("tmp");
	return val;

func new_val_var(val_name):
	var val = new_val();
	val.val_type = "variable";
	val.ir_name = make_unique_IR_name("var", val_name);
	val.user_name = val_name;
	return val;

func new_val_immediate(value, type):
	var val = new_val();
	val.val_type = "immediate";
	val.value = value;
	val.type = type;
	val.ir_name = make_unique_IR_name("imm");
	return val;

func new_val_error():
	var val = new_val();
	val.val_type = "error";
	val.ir_name = "error";
	return val;


func emit_IR(cmd:Array):
	#IR.commands.append(cmd);
	var cmd_translated = [];
	assert(cmd[0] is String);
	for i in range(len(cmd)):
		cmd_translated.append(serialize_ir_arg(cmd[i]));
	cur_code_block.code.append(cmd_translated);

func serialize_ir_arg(arg):
	if arg is String: return arg;
	elif arg is Dictionary:
		assert(("ir_name" in arg) and (arg.ir_name is String));
		return arg.ir_name;
	elif arg is Array:
		var S = "";
		S += "[" + " ";
		for sub_arg in arg:
			S += serialize_ir_arg(sub_arg) + " ";
		S += "]";
		return S;
	else:
		push_error("can't serialize IR argument ["+str(arg)+"]");
		return null;


func save_variable(var_handle):
	cur_scope.vars.append(var_handle);

func push_code_block(new_block=null):
	var old_cb = cur_code_block;
	if not new_block: 
		new_block = new_code_block();
		#IR.code_blocks.append(new_block);
	cur_code_block = new_block;
	return old_cb;

func pop_code_block(old_block):
	var popped_block = cur_code_block;
	cur_code_block = old_block;
	return popped_block;

func new_code_block():
	var cb = {"ir_name":make_unique_IR_name("cb"), "code":[]};
	IR.code_blocks[cb.ir_name] = cb;
	return cb;

func new_scope(scp_name, scp_parent):
	var scp = {
				"ir_name":make_unique_IR_name("scp",scp_name),
				"parent":scp_parent,
				"vars":[],
				"funcs":[],
			};
	IR.scopes[scp.ir_name] = scp;
	return scp;

func get_var(var_name:String):
	var seek_scope = cur_scope;
	while true:
		for variable in seek_scope.vars:
			if variable.user_name == var_name:
				return variable;
		if seek_scope.parent:
			seek_scope = seek_scope.parent;
		else:
			break;
	return null;

func get_func(fun_name:String):
	var seek_scope = cur_scope;
	while true:
		for fun in seek_scope.funcs:
			if fun.user_name == fun_name:
				return fun;
		if seek_scope.parent:
			seek_scope = seek_scope.parent;
		else:
			break;
	return null;
