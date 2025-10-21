extends Node

# constants
const uYaml = preload("res://scenes/uYaml.gd");
# state
var IR = null;
var cur_scope = null;
var cur_code_block = null;
var val_idx = 0;

func reset():
	IR = null;
	cur_scope = null;
	cur_code_block = null;
	val_idx = 0;

func clear_IR():
	reset();
	IR = {
		"code_blocks":{},
		"scopes":{},
	};
	var global_scope = new_scope("global", "none");
	cur_scope = global_scope;
	var global_code_block = new_code_block();
	cur_code_block = global_code_block;#IR.code_blocks[0];

func is_cur_scope_global():
	return cur_scope.user_name == "global";

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
	"data_type":null, 		# what is the data type of the underlying object?
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
	val.data_type = type;
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
		cmd_translated.append_array(serialize_ir_arg(cmd[i]));
	cur_code_block.code.append(cmd_translated);

func serialize_ir_arg(arg):
	if arg is String: return [arg];
	elif arg is Dictionary:
		assert(("ir_name" in arg) and (arg.ir_name is String));
		return [arg.ir_name];
	elif arg is Array:
		var res = [];
		res.append("[");
		for sub_arg in arg:
			res.append_array(serialize_ir_arg(sub_arg));
		res.append("]");
		return res;
	else:
		push_error("can't serialize IR argument ["+str(arg)+"]");
		return [];


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
	var cb = {"ir_name":make_unique_IR_name("cb"), "code":[], "lbl_from":make_unique_IR_name("lbl_from"), "lbl_to":make_unique_IR_name("lbl_to")};
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

func serialize_full()->String:
	var sIR = {};
	G.duplicate_deep(IR, sIR); #IR.duplicate();
	for key in sIR.scopes:
		var scope = sIR.scopes[key];
		serialize_vals(scope.vars);
		if not len(scope.vars): scope.erase("vars");
		serialize_vals(scope.funcs);
		if not len(scope.funcs): scope.erase("funcs");
	for key in sIR.code_blocks:
		var cb = sIR.code_blocks[key];
		if cb.code.is_empty(): cb.erase("code");
	return uYaml.serialize(sIR);

func serialize_vals(arr):
	for i in range(len(arr)):
			var old_var = arr[i];
			var new_var = [];
			for key2 in ["ir_name", "val_type", "user_name", "data_type", "storage", "value", "scope", "code"]:
				if (key2 in old_var) and (old_var[key2] != null):
					var val = old_var[key2];
					val = escape_string(val);
					new_var.append(val);
				else:
					new_var.append("NULL");
			arr[i] = new_var;

func escape_string(text):
	var new_str = "";
	for ch:String in text:
		if ch in "qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM1234567890.+-_":
			new_str += ch;
		else:
			var buff = ch.to_ascii_buffer();
			assert(len(buff) == 1);
			ch = "%" + "%03d" % buff[0];
			new_str += ch;
	return new_str;

func unescape_string(text):
	var new_str:String = "";
	var esc_step:int = 0;
	var num_str:String = "";
	for ch in text:
		match esc_step:
			0:
				if(ch == "%"):
					esc_step = 1;
				else:
					new_str += ch;
			1:	num_str += ch; esc_step += 1;
			2:	num_str += ch; esc_step += 1;
			3:	
				num_str += ch;
				assert(num_str.is_valid_int());
				var num = num_str.to_int();
				num_str = "";
				var new_ch = PackedByteArray([num]).get_string_from_ascii();
				new_str += new_ch;
				esc_step = 0;
	print("unescape str: in [%s], out [%s]" % [text, new_str]);
	return new_str;

func to_file(filename):
	var fp = FileAccess.open(filename, FileAccess.ModeFlags.WRITE);
	if not fp: push_error("can't write file: "+filename); return;
	var text = serialize_full();
	fp.store_line(text);
	fp.close();
