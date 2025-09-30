extends Node

var IR = null;
var cur_scope = null;
var cur_code_block = null;
const uYaml = preload("res://scenes/uYaml.gd");

func clear_IR():
	IR = {
		"code_blocks":{},
		"scopes":{},
	};
	var global_scope = new_scope("global", "none");
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
func new_val(): return {
	"val_type":null, 	# what sort of object does this handle represent?
	"ir_name":null, 	# what is a unique name of this handle?
	"user_name":null, 	# how does the source code refer to the underlying object?
	"type":null, 		# what is the data type of the underlying object?
	"value":null,		# what is the actual value of the underlying object?
	"storage":null		# where is the object located?
	};

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

func new_val_none():
	var val = new_val();
	val.val_type = "none";
	val.ir_name = "none";
	return val;

func new_val_func(fun_name, fun_scope, fun_code):
	var val = new_val();
	val.val_type = "func";
	val.ir_name = make_unique_IR_name("func", fun_name);
	val.user_name = fun_name;
	val["scope"] = fun_scope.ir_name;
	val["code"] = fun_code.ir_name;
	return val;

func new_val_lbl(lbl_name=null):
	var val = new_val();
	val.val_type = "label";
	val.ir_name = make_unique_IR_name("lbl", lbl_name);
	val.user_name = lbl_name;
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

func save_function(fun_handle):
	cur_scope.funcs.append(fun_handle);

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

func push_scope(scope=null):
	var old_sc = cur_scope;
	if not scope:
		scope = new_scope(null,cur_scope.ir_name);
	cur_scope = scope;
	return old_sc;

func pop_scope(old_scope):
	var popped_scope = cur_scope;
	cur_scope = old_scope;
	return popped_scope;
	
func new_scope(scp_name, scp_parent:String=""):
	if not scp_name: scp_name = "NULL";
	var scp = {
				"ir_name":make_unique_IR_name("scp",scp_name),
				"user_name":scp_name,
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
		if seek_scope.parent and seek_scope.parent != "none":
			seek_scope = IR.scopes[seek_scope.parent];
		else:
			break;
	return null;

func get_func(fun_name:String):
	var seek_scope = cur_scope;
	while true:
		for fun in seek_scope.funcs:
			if fun.user_name == fun_name:
				return fun;
		if seek_scope.parent and seek_scope.parent != "none":
			seek_scope = IR.scopes[seek_scope.parent];
		else:
			break;
	return null;

#func serialize_full():
	#var text = "";
	#text += serialize_code_blocks() + "\n";
	#text += serialize_scopes() + "\n";
	#return text;
#
#func remove_last_newline(text): 
	#return text.substr(0,len(text)-1);
#
#func serialize_code_blocks():
	#var text = "code:\n";
	#for key in IR.code_blocks:
		#var cb = IR.code_blocks[key];
		#text += serialize_code_block(cb) + "\n";
	#text = remove_last_newline(text);
	#return text;
#
#func serialize_code_block(cb):
	#var text:String = " "+cb.ir_name+":\n";
	#for cmd in cb.code:
		#text += "  " + serialize_cmd(cmd) + "\n";
	#text = remove_last_newline(text);
	#return text;
#
#func serialize_cmd(cmd):
	#var text = "";
	#for arg:String in cmd:
		#text += arg + " ";
	#return text;
#
#func serialize_scopes():
	#var text = "scopes:\n";
	#for key in IR.scopes:
		#var sc = IR.scopes[key];
		#text += serialize_scope(sc) + "\n";
	#text = remove_last_newline(text);
	#return text;
#
#func serialize_scope(sc):
	#var text = " "+sc.ir_name + ":\n";
	#text += "# ir_name: val_type, user_name, data_type, storage, value, scope, code\n";
	#text += "  vars:\n";
	#for val in sc.vars:
		#text += "   "+serialize_val(val)+"\n";
	#text += "  funcs:\n";
	#for val in sc.funcs:
		#text += "   "+serialize_val(val)+"\n";
	#text = remove_last_newline(text);
	#return text;
#
#func serialize_val(val):
	#var text = val.ir_name+": ";
	#for key in ["val_type", "user_name", "data_type", "storage", "value", "scope", "code"]:
		#if (key in val) and (val[key] != null):
			#text += val[key] + " ";
		#else:
			#text += "NULL ";
	#return text;
		
func serialize_full()->String:
	var sIR = IR.duplicate();
	for key in sIR.scopes:
		var scope = sIR.scopes[key];
		serialize_vals(scope.vars);
		if not len(scope.vars): scope.erase("vars");
		serialize_vals(scope.funcs);
		if not len(scope.funcs): scope.erase("funcs");
	return uYaml.serialize(sIR);

func serialize_vals(arr):
	for i in range(len(arr)):
			var old_var = arr[i];
			var new_var = [];
			for key2 in ["ir_name", "val_type", "user_name", "data_type", "storage", "value", "scope", "code"]:
				if (key2 in old_var) and (old_var[key2] != null):
					new_var.append(old_var[key2]);
				else:
					new_var.append("NULL");
			arr[i] = new_var;

func to_file(filename):
	var fp = FileAccess.open(filename, FileAccess.ModeFlags.WRITE);
	if not fp: push_error("can't write file: "+filename); return;
	var text = serialize_full();
	fp.store_line(text);
	fp.close();
