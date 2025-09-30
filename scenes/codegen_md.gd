extends Node

const uYaml = preload("res://scenes/uYaml.gd")

var IR = {};
var all_syms = {};

#---------- IR ingestion -------------------

func parse_file(filename)->String:
	var fp = FileAccess.open(filename, FileAccess.READ);
	var text = fp.get_as_text();
	fp.close();
	deserialize(text);
	return generate();

func deserialize(text):
	IR = uYaml.deserialize(text);
	#inflate scopes
	for key in IR.scopes:
		var scope = IR.scopes[key];
		if not "vars" in scope: scope["vars"] = [];
		if not "funcs" in scope: scope["funcs"] = [];
		inflate_vals(scope.vars);
		inflate_vals(scope.funcs);
	#make a total list of vals
	for key in IR.code_blocks: all_syms[key] = IR.code_blocks[key];
	for key in IR.scopes:
		var scope = IR.scopes[key];
		for val in scope.vars: all_syms[val.ir_name] = val;
		for val in scope.funcs: all_syms[val.ir_name] = val;
	print(all_syms.keys());

func inflate_vals(arr):
	const props = ["ir_name", "val_type", "user_name", "data_type", "storage", "value", "scope", "code"];
	for i in range(len(arr)):
		var val = arr[i];
		assert(len(val) == len(props));
		var new_val = {};
		for j in range(len(props)):
			new_val[props[j]] = val[j];
		arr[i] = new_val;

#-------------- Code generation -----------------
var if_block_continued = false;
var if_block_lbl_end = null;

var assy_block_stack = [];
var cur_assy_block = null;
var cur_stack_size = 0; # number of bytes in the current frame used for local variables

const regs = ["EAX", "EBX", "ECX", "EDX"];
var regs_in_use = {};

func generate():
	allocate_vars();
	#for key in IR.code_blocks:
	#	var cb = IR.code_blocks[key];
	#	generate_code_block(cb);
	var cb = generate_code_block(IR.code_blocks[IR.code_blocks.keys()[0]]);
	return cb.code;
	
func generate_code_block(cb):
	assy_block_stack.push_back(cur_assy_block);
	cur_assy_block = {"code":""};
	maybe_emit_func_label(cb.ir_name);
	for i in range(len(cb.code)):
		var cmd = cb.code[i];
		generate_cmd(cmd);
		check_if_block_continued(i, cb.code);
	var res = cur_assy_block;
	cur_assy_block = assy_block_stack.pop_back();
	return res;

func maybe_emit_func_label(ir_name):
	for key in all_syms:
		var sym = all_syms[key];
		if sym.val_type == "function":
			if sym.code == ir_name:
				emit_raw(sym.ir_name);
				break;

func check_if_block_continued(i, code):
	if_block_continued = false;
	if i+1 < len(code):
		var cmd2 = code[i+1];
		if cmd2[0] in ["ELSE_IF", "ELSE"]:
			if_block_continued = true;

func generate_cmd(cmd:Array):
	match cmd[0]:
		"MOV": generate_cmd_mov(cmd);
		"OP": generate_cmd_op(cmd);
		"IF": generate_cmd_if(cmd);
		"ELSE_IF": generate_cmd_else_if(cmd);
		"ELSE": generate_cmd_else(cmd);
		"WHILE": generate_cmd_while(cmd);
		"CALL": generate_cmd_call(cmd);
		"RETURN": generate_cmd_return(cmd);
		_: push_error("codegen: unknown IR command ["+str(cmd[0])+"]");

func generate_cmd_mov(cmd):
	#MOV dest src
	var dest = cmd[1];
	var src = cmd[2];
	emit("mov @%s $%s" % [dest, src]);

const op_map = {
	"ADD":"add %a, %b",
	"SUB":"sub %a, %b",
	"MUL":"mul %a, %b",
	"DIV":"div %a, %b",
	"GREATER":"sub %a, %b; sgn %a",
	"LESS":"sub %a, %b; neg %a; sgn %a",
	"INDEX":"add @%a, %b",
	"DEC":"dec %a",
	"EQUAL":"sub %a, %b; sub %a",
};

func generate_cmd_op(cmd):
	#OP op arg1 arg2 res
	var op = cmd[1];
	var arg1 = cmd[2];
	var arg2 = cmd[3];
	var res = cmd[4];
	if op not in op_map: push_error("codegen: can't generate op ["+op+"]"); return;
	var op_str:String = op_map[op];
	
	var tmpA = null;
	var tmpB = null;
	var arg1_by_addr = false;
	tmpA = alloc_temporary();
	if op_str.find("@%a"):
		op_str = op_str.replace("@%a", "%a");
		arg1_by_addr = true;
	if arg1_by_addr:
		emit("mov %s, @%s" % [tmpA, arg1]);
	else:
		emit("mov %s, $%s" % [tmpA, arg1]);
	op_str = op_str.replace("%a", tmpA);
	if op_str.find("%b") != -1:
		tmpB = alloc_temporary();
		emit("mov %s, $%s" % [tmpB, arg2]);
		op_str = op_str.replace("%b", tmpB);
	emit(op_str);
	store_val(tmpA, res);
	free_val(tmpA);
	if(tmpB): free_val(tmpB);
	
func new_lbl(lbl_name):
	var ir_name = "lbl_"+str(len(all_syms)+1)+"__"+lbl_name;
	var handle = {"ir_name":ir_name, "val_type":"label"};
	all_syms[ir_name] = handle;
	return handle;

func generate_cmd_if(cmd):
	var cb_cond = cmd[1];
	var res = cmd[2];
	var cb_block = cmd[3];
	var lbl_else = new_lbl("if_else").ir_name;
	var lbl_end = new_lbl("if_end").ir_name;
	emit("$%s\ncmp $%s, 0;\nJZ %s;\n$%s\n%s:\n" % [cb_cond, res, lbl_else, cb_block, lbl_else]);
	if not if_block_continued:
		emit("%s:\n" % [lbl_end]);
		if_block_lbl_end = null;
	else:
		if_block_lbl_end = lbl_end;

func generate_cmd_else_if(cmd):
	var cb_cond = cmd[1];
	var res = cmd[2];
	var cb_block = cmd[3];
	var lbl_else = new_lbl("if_else").ir_name;
	var lbl_end = if_block_lbl_end;
	emit("$%s\ncmp $%s, 0;\nJZ %s;\n$%s\n%s:\n" % [cb_cond, res, lbl_else, cb_block, lbl_else]);
	if not if_block_continued:
		emit("%s:\n" % [lbl_end]);
		if_block_lbl_end = null;

func generate_cmd_else(cmd):
	var cb_block = cmd[1];
	var lbl_end = if_block_lbl_end;
	emit("$%s\n" % [cb_block]);
	emit("%s:\n" % [lbl_end]);
	if_block_lbl_end = null;

func generate_cmd_while(cmd):
	#WHILE cb_cond res cb_block lbl_next lbl_end
	var cb_cond = cmd[1];
	var res = cmd[2];
	var cb_block = cmd[3];
	var lbl_next = cmd[4];
	var lbl_end = cmd[5];
	emit("%s:\n" % lbl_next);		# loop:
	emit("$%s\n" % cb_cond);		#  (expr->cond)
	emit("CMP $%s,0;\n" % res);		#  IF !cond 
	emit("JZ %s;\n" % lbl_end);		#  THEN GOTO "end"
	emit("$%s\n" % cb_block);		#  (code block)
	emit("JMP %s\n" % lbl_next);	#  GOTO "loop"
	emit("%s:\n" % lbl_end);		# end:

func generate_cmd_call(cmd):
	#CALL fun arg(s) res
	var fun = cmd[1];
	var cmd_arg = cmd[2];
	var res = cmd[3];
	var args = [cmd_arg];
	args.reverse();
	var n_args = len(args);
	for arg in args:
		emit("push $%s;" % arg);
	emit("call @%s;\n" % fun);
	emit("add SP, %s;\n" % n_args);
	emit("mov ^%s, eax;\n" % res);

func emit(text:String):
	var allocs = [];
	while true:
		var ref_load = find_reference(text, "$");
		if not ref_load: break;
		var res = load_value(ref_load.val);
		allocs.append(res);
		text = text.substr(0, ref_load.from) + res + text.substr(ref_load.to);
	while true:
		var ref_addr = find_reference(text, "@");
		if not ref_addr: break;
		var res = address_value(ref_addr.val);
		allocs.append(res);
		text = text.substr(0, ref_addr.from) + res + text.substr(ref_addr.to);
	var vars_to_store = [];
	while true:
		var ref_store = find_reference(text, "^");
		if not ref_store: break;
		var res = alloc_temporary();
		allocs.append(res);
		vars_to_store.append([res, ref_store.val]);
		text = text.substr(0, ref_store.from) + res + text.substr(ref_store.to);
	emit_raw(text);
	for pair in vars_to_store:
		store_val(pair[0], pair[1]);
	for val in allocs:
		free_val(val);

func find_reference(text:String, marker:String):
	var marker_pos = text.find(marker);
	if(marker_pos == -1): return null;
	var end_pos = find_first_of(text, " ,:;\n", marker_pos);
	var val = text.substr(marker_pos+1, end_pos-(marker_pos+1));
	var res = {"from":marker_pos, "to":end_pos, "val":val};
	return res;

func find_first_of(text:String, needles:String, from:int=0):
	for i in range(from, len(text)):
		var ch = text[i];
		if ch in needles:
			return i;
	return len(text);

func load_value(val:String):
	assert(val in all_syms);
	var handle = all_syms[val];
	var res = "";
	if handle.val_type == "code":
		res = generate_code_block(handle).code;
	elif handle.val_type == "immediate":
		res = handle.value;
	else:
		#res = alloc_register();
		match handle.storage.type:
			"global": 
				res = "*%d" % handle.storage.pos; #emit("mov %s, *%d;\n" % [res, handle.storage.pos]);
			"stack":
				res = "EBP[%d]" % handle.storage.pos; #emit("mov %s, EBP[%d];\n" % [res, handle.storage.pos]);
			"extern":
				res = "*%s" % handle.ir_name;
			_: push_error("codegen: load_value: unknown storage type ["+handle.storage.type+"]");
	return res;

func address_value(val:String):
	assert(val in all_syms);
	var handle = all_syms[val];
	var res = "";
	match handle.storage.type:
		"global":
			res = "%d" % handle.storage.pos; #emit("mov %s, %d;\n" % [reg, handle.storage.pos]);
		"stack":
			res = "EBP+%d" % handle.storage.pos; #emit("mov %s, EBP+%d;\n" % [reg, handle.storage.pos]);
		"code":
			res = "%s" % handle.ir_name;
		"extern":
			res = "%s" % handle.ir_name;
		_: push_error("codegen: address_value: unkown storage type ["+handle.storage.type+"]");
	return res;

func alloc_temporary():
	var res = alloc_register();
	if not res:
		res = "EBP[%d]" % cur_stack_size;
		cur_stack_size += 1;
	return res;

func emit_raw(text:String):
	cur_assy_block.code += text;

func store_val(reg:String, val:String):
	assert(val in all_syms);
	var handle = all_syms[val];
	match handle.storage.type:
		"global":
			emit("mov %d, %s;\n" % [handle.storage.pos, reg]);
		"stack":
			emit("mov EBP[%d], %s;\n" % [handle.storage.pos, reg]);
		_: push_error("codegen: store_value: unkown storage type ["+handle.storage.type+"]");
	return reg;

func free_val(val:String):
	if val in regs:
		regs_in_use[val] = false;
	else:
		pass;

func alloc_register():
	for reg in regs:
		if not reg in regs_in_use: regs_in_use[reg] = false;
		if not regs_in_use[reg]:
			regs_in_use[reg] = true;
			return reg;
	return null;

func allocate_vars():
	for key in IR.scopes:
		var scope = IR.scopes[key];
		var stack_pos = 0; # we will be placing local vars on the stack
		var arg_pos = 0; # args are placed on the stack in the other direction
		if "vars" in scope:
			for handle in scope.vars:
				if handle.storage == "NULL":
					var storage_type = "stack";
					if(scope.user_name == "global"): storage_type = "global";
					handle.storage = {"type":storage_type, "pos":to_local_pos(stack_pos)};
					stack_pos += 1;
				elif handle.storage == "extern":
					handle.storage = {"type":"extern", "pos":0};
				elif handle.storage == "arg":
					handle.storage = {"type":"stack", "pos":to_arg_pos(arg_pos)};
					arg_pos += 1;
				else:
					push_error("codegen: allocate_vars: unknown storage type");
			scope["local_var_stack_size"] = stack_pos;
		if "funcs" in scope:
			for handle in scope.funcs:
				if handle.storage == "NULL":
					handle.storage = {"type":"code", "pos":0};
				elif handle.storage == "extern":
					handle.storage = {"type":"extern", "pos":0};
				else:
					push_error("codegen: allocate_vars: unknown storage type");
	for key in IR.code_blocks:
		var cb = IR.code_blocks[key];
		cb["val_type"] = "code";

# defines a mapping between the input pos and stack pos for local vars of a function
func to_local_pos(pos):
	return pos;

# defines a mapping between the input pos and stack pos for arguments of a function
func to_arg_pos(pos):
	return -(2+pos);

func generate_cmd_return(_cmd):
	emit("ret;\n");
