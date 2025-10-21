extends Node

const uYaml = preload("res://scenes/uYaml.gd")
# constants
const ADD_DEBUG_TRACE = false; # in emitted assembly, specify where it came from.
const ADD_IR_TRACE = true; # print the IR commands that are being generated
const regs = ["EAX", "EBX", "ECX", "EDX"];
# state
var IR = {};
var all_syms = {};
var assy_block_stack = [];
var cur_assy_block = null;
var cur_stack_size = 0; # number of bytes in the current frame used for local variables
var regs_in_use = {};
var referenced_cbs = [];
var cur_block = null
var cb_stack = [];
var entered_scopes = [];
var cur_scope = null;

func reset():
	IR = {};
	all_syms = {};
	assy_block_stack = [];
	cur_assy_block = null;
	cur_stack_size = 0;
	regs_in_use = {};
	referenced_cbs = [];
	cur_block = null;
	cb_stack = [];
	entered_scopes = [];
	cur_scope = null;

#---------- IR ingestion -------------------

func parse_file(filename)->String:
	reset();
	var fp = FileAccess.open(filename, FileAccess.READ);
	var text = fp.get_as_text();
	fp.close();
	deserialize(text);
	return generate();

func deserialize(text):
	IR = uYaml.deserialize(text);
	assert(not IR.is_empty());
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
	#print(all_syms.keys());

func inflate_vals(arr):
	const props = ["ir_name", "val_type", "user_name", "data_type", "storage", "value", "scope", "code"];
	for i in range(len(arr)):
		var val = arr[i];
		assert(len(val) == len(props));
		var new_val = {};
		for j in range(len(props)):
			var S = unescape_string(val[j]);
			new_val[props[j]] = S;
		arr[i] = new_val;

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
	#print("unescape str: in [%s], out [%s]" % [text, new_str]);
	return new_str;

#-------------- Code generation -----------------

func generate():
	allocate_vars();
	#for key in IR.code_blocks:
	#	var cb = IR.code_blocks[key];
	#	generate_code_block(cb);
	var cb_global = IR.code_blocks[IR.code_blocks.keys()[0]];
	referenced_cbs.append(cb_global);
	var emitted_cbs = [];
	#referenced_cbs.push_back(cb_global);
	var scp_global = IR.scopes[IR.scopes.keys()[0]];
	enter_scope(scp_global);
	var assy_full = "";
	while not referenced_cbs.is_empty(): #we're using the dictionary as a Set.
		var cb = referenced_cbs.pop_front();
		if cb in emitted_cbs: continue;
		else: emitted_cbs.append(cb);
		var ab = generate_code_block(cb);
		fixup_enter_leave(ab);
		assy_full += ab.code;
	assy_full += generate_globals();
	return assy_full;

func generate_code_block(cb):
	if cur_block:
		cb_stack.push_back(cur_block);
	cur_block = cb;
	cb["if_block_continued"] = false;
	assy_block_stack.push_back(cur_assy_block);
	cur_assy_block = {"code":""};
	emit_raw("# Begin code block %s\n" % cb.ir_name, "generate_code_block.intro");
	maybe_emit_func_label(cb.ir_name);
	if "code" in cb:
		for i in range(len(cb.code)):
			var cmd = cb.code[i];
			check_if_block_continued(i, cb.code);
			generate_cmd(cmd);
	maybe_emit_func_ret(cb.ir_name);
	emit_raw("# End code block %s\n" % cb.ir_name, "generate_code_block.exit");
	var res = cur_assy_block;
	cur_assy_block = assy_block_stack.pop_back();
	cur_block = cb_stack.pop_back();
	return res;

func generate_globals()->String:
	var text = "";
	for key in all_syms:
		var sym = all_syms[key];
		if sym.val_type == "variable":
			if sym.storage.type == "global":
				text += ":%s: db 0;\n" % sym.ir_name;
		if sym.val_type == "temporary":
			if sym.storage.type == "global":
				text += ":%s: db 0;\n" % sym.ir_name;
		if sym.val_type == "immediate":
			if sym.data_type == "string":
				var S = sym.value;
				S = format_db_string(S);
				text += ":%s: db %s;\n" % [sym.ir_name, S];
	return text;

func format_db_string(S):
	var text = "";
	#if USE_WIDE_STRINGS:
	#	for ch:String in S:
	#		text += "%d,0,0,0, " % ch.to_ascii_buffer()[0];
	#	#text = text.erase(len(text)-2,2);
	#	text += "0,0,0,0";
	#else:
	text = "\"%s\", 0" % S;
	#print("format db string: in ["+S+"], out ["+text+"]");
	return text;

func enter_scope(new_scope):
	if cur_scope:
		entered_scopes.push_back(cur_scope);
	cur_scope = new_scope;
func leave_scope():
	cur_scope = entered_scopes.pop_back();


func maybe_emit_func_label(ir_name:String):
	var calling_func = is_referenced_by_func(ir_name);
	if calling_func:	emit_raw(":%s:\n" % calling_func, "maybe_emit_func_label(%s)" % ir_name);

func maybe_emit_func_ret(ir_name:String):
	var calling_func = is_referenced_by_func(ir_name);
	if calling_func:	emit_raw("ret;\n", "maybe_emit_func_ret(%s)" % ir_name);

func is_referenced_by_func(ir_name:String):
	for key in all_syms:
		var sym = all_syms[key];
		if sym.val_type == "func":
			if sym.code == ir_name:
				return sym.ir_name;
	return null

func check_if_block_continued(i, code):
	cur_block.if_block_continued = false;
	if i+1 < len(code):
		var cmd2 = code[i+1];
		if cmd2[0] in ["ELSE_IF", "ELSE"]:
			cur_block.if_block_continued = true;

func generate_cmd(cmd:Array):
	if ADD_IR_TRACE: emit_raw("# IR: %s\n" % " ".join(PackedStringArray(cmd)), "generate_cmd.trace");
	match cmd[0]:
		"MOV": generate_cmd_mov(cmd);
		"OP": generate_cmd_op(cmd);
		"IF": generate_cmd_if(cmd);
		"ELSE_IF": generate_cmd_else_if(cmd);
		"ELSE": generate_cmd_else(cmd);
		"WHILE": generate_cmd_while(cmd);
		"CALL": generate_cmd_call(cmd);
		"RETURN": generate_cmd_return(cmd);
		"ENTER": generate_cmd_enter(cmd);
		"LEAVE": generate_cmd_leave(cmd);
		_: push_error("codegen: unknown IR command ["+str(cmd[0])+"]");

func generate_cmd_mov(cmd):
	#MOV dest src
	var dest = cmd[1];
	var src = cmd[2];
	emit("mov ^%s, $%s;\n" % [dest, src], "generate_cmd_mov");


const op_map = {
	"ADD":"add %a, %b;\n",
	"SUB":"sub %a, %b;\n",
	"MUL":"mul %a, %b;\n",
	"DIV":"div %a, %b;\n",
	"MOD":"mod %a, %b;\n",
	"GREATER":"cmp %a, %b; mov %a, CTRL; band %a, CMP_G; bnot %a; bnot %a;\n",
	"LESS":"cmp %a, %b; mov %a, CTRL; band %a, CMP_L; bnot %a; bnot %a;\n",
	"INDEX":"add %a, %b;\n", #deref separately?
	"DEC":"dec %a;\n",
	"INC":"inc %a;\n",
	"EQUAL":"cmp %a, %b; mov %a, CTRL; band %a, CMP_Z; bnot %a; bnot %a;\n",
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
	#var arg1_by_addr = false;
	const mono_ops = ["INC", "DEC"];
	if op in mono_ops:
		tmpA = "^%s" % arg1;
		emit("mov ^%s, $%s;\n" % [res, arg1], "generate_cmd_op.result2");
	else:
		tmpA = alloc_temporary();
		emit("mov %s, $%s;\n" % [tmpA, arg1], "generate_cmd_op.arg1");
	
	op_str = op_str.replace("%a", tmpA);
	if op_str.find("%b") != -1:
		tmpB = alloc_temporary();
		emit("mov %s, $%s;\n" % [tmpB, arg2], "generate_cmd_op.find_b");
		op_str = op_str.replace("%b", tmpB);
	emit(op_str, "generate_cmd_op.op_str");
	if op not in mono_ops: emit("mov ^%s, %s;\n" % [res, tmpA], "generate_cmd_op.result1");
	var res_handle = all_syms[res];
	if op == "INDEX": res_handle.needs_deref = true;
	free_val(tmpA);
	if(tmpB): free_val(tmpB);
	
func new_lbl(lbl_name):
	var ir_name = "lbl_"+str(len(all_syms)+1)+"__"+lbl_name;
	var handle = {"ir_name":ir_name, "val_type":"label"};
	all_syms[ir_name] = handle;
	return handle;

func new_imm(val):
	var ir_name = "imm_"+str(len(all_syms)+1)+"__"+str(val);
	var handle = {"ir_name":ir_name, "val_type":"immediate", "value":str(val), "data_type":"error", "storage":"NULL"};
	if val is int:
		handle["data_type"] = "int";
	elif val is String:
		handle["data_type"] = "string";
	all_syms[ir_name] = handle;
	return handle;

func generate_cmd_if(cmd):
	var cb_cond = cmd[1];
	var res = cmd[2];
	var cb_block = cmd[3];
	var lbl_else = new_lbl("if_else").ir_name;
	var lbl_end = new_lbl("if_end").ir_name;
	var imm_0_handle = new_imm(0);
	allocate_value(imm_0_handle, cur_scope);
	var imm_0 = imm_0_handle.ir_name;
	emit("$%s\n" % cb_cond, "generate_cmd_if.cb_cond");
	emit("cmp $%s, $%s;\n" % [res, imm_0], "generate_cmd_if.cmp");
	emit("jz %s;\n" % lbl_else, "generate_cmd_if.jz_else");
	emit("$%s\n" % cb_block, "generate_cmd_if.cb_block");
	emit("jmp %s;\n" % lbl_end, "generate_cmd_if.end_then");
	emit(":%s:\n" % lbl_else, "generate_cmd_if.lbl_else");
	if cur_block.if_block_continued:
		cur_block["if_block_lbl_end"] = lbl_end;
	else:
		emit(":%s:\n" % lbl_end, "generate_cmd_if.end_if");
		cur_block.if_block_lbl_end = null;

func generate_cmd_else_if(cmd):
	var cb_cond = cmd[1];
	var res = cmd[2];
	var cb_block = cmd[3];
	var lbl_else = new_lbl("if_else").ir_name;
	var lbl_end = cur_block.if_block_lbl_end;
	var imm_0_handle = new_imm(0);
	allocate_value(imm_0_handle, cur_scope);
	var imm_0 = imm_0_handle.ir_name;
	emit("$%s\n" % cb_cond, "generate_cmd_else_if.cb_cond");
	emit("cmp $%s, $%s;\n" % [res, imm_0], "generate_cmd_else_if.cmp");
	emit("jz %s;\n" % lbl_else, "generate_cmd_else_if.jz_else");
	emit("$%s\n" % cb_block, "generate_cmd_else_if.cb_block");
	emit("jmp %s\n" % lbl_end, "generate_cmd_else_if.end_then");
	emit(":%s:\n" % lbl_else, "generate_cmd_else_if.lbl_else");
	if not cur_block.if_block_continued:
		emit(":%s:\n" % lbl_end, "generate_cmd_else_if.end_if");
		cur_block.if_block_lbl_end = null;

func generate_cmd_else(cmd):
	var cb_block = cmd[1];
	var lbl_end = cur_block.if_block_lbl_end;
	emit("$%s\n" % [cb_block], "generate_cmd_else.cb_block");
	emit(":%s:\n" % [lbl_end], "generate_cmd_else.lbl_end");
	cur_block.if_block_lbl_end = null;

func generate_cmd_while(cmd):
	#WHILE cb_cond res cb_block lbl_next lbl_end
	var cb_cond = cmd[1];
	var res = cmd[2];
	var cb_block = cmd[3];
	var lbl_next = cmd[4];
	var lbl_end = cmd[5];
	var immediate_0 = new_imm(0);
	allocate_value(immediate_0, cur_scope);
	emit(":%s:\n" % lbl_next, "generate_cmd_while.lbl_next");		# loop:
	emit("$%s\n" % cb_cond, "generate_cmd_while.cb_cond");		#  (expr->cond)
	emit("cmp $%s, $%s;\n" % [res, immediate_0.ir_name], 
							"generate_cmd_while.cmp");		#  IF !cond 
	emit("jz %s;\n" % lbl_end, "generate_cmd_while.jz_end");		#  THEN GOTO "end"
	emit("$%s\n" % cb_block, "generate_cmd_while.cb_block");		#  (code block)
	emit("jmp %s;\n" % lbl_next, "generate_cmd_while.jmp_next");	#  GOTO "loop"
	emit(":%s:\n" % lbl_end, "generate_cmd_while.lbl_end");		# end:

func generate_cmd_call(cmd):
	#CALL fun arg(s) res
	var fun = cmd[1];
	assert(fun in all_syms);
	var fun_handle = all_syms[fun];
	var args = [];
	if cmd[2] == "[":
		var i = 3;
		while true:
			if cmd[i] == "]": break;
			args.append(cmd[i]);
			i += 1;
	else:
		args.append(cmd[3]);
	var res = cmd[-1];
	args.reverse();
	var n_args = len(args);
	var pushed_stack_size = 4*n_args;
	for arg in args:
		emit("push $%s;\n" % arg, "generate_cmd_call.args");
	emit("call @%s;\n" % fun, "generate_cmd_call.call");
	emit("add ESP, %s;\n" % pushed_stack_size, "generate_cmd_call.stack");
	emit("mov ^%s, eax;\n" % res, "generate_cmd_call.result");
	
	if fun_handle.storage.type != "extern":
		var cb_name = fun_handle.code;
		assert(cb_name in all_syms);
		var cb = all_syms[cb_name];
		if cb not in referenced_cbs: referenced_cbs.append(cb);

func emit(text:String, dbg_trace:String):
	var imm_flag = false;
	var allocs = [];
	while true:
		var ref_load = find_reference(text, "$");
		if not ref_load: break;
		var res = load_value(ref_load.val);
		var handle = all_syms[ref_load.val];
		if ("needs_deref" in handle) and handle.needs_deref:
			var reg = alloc_register();
			allocs.push_back(reg);
			assert(reg != null);
			emit_raw("mov %s, %s;\n" % [reg, res], "emit.needs_deref_1(%s)" % ref_load.val);
			emit_raw("mov %s, *%s;\n" % [reg, reg], "emit.needs_deref_2(%s)" % ref_load.val);
			res = reg;
			#note: imm_flag = false or imm_flag;
		else:
			if imm_flag: res = promote(res, allocs);
			imm_flag = true;
		text = text.substr(0, ref_load.from) + res + text.substr(ref_load.to);
	while true:
		var ref_addr = find_reference(text, "@");
		if not ref_addr: break;
		var res = address_value(ref_addr.val);
		if imm_flag: res = promote(res, allocs);
		imm_flag = true;
		text = text.substr(0, ref_addr.from) + res + text.substr(ref_addr.to);
	var vars_to_store = [];
	while true:
		var ref_store = find_reference(text, "^");
		if not ref_store: break;
		var handle = all_syms[ref_store.val];
		var res_load = load_value(ref_store.val);
		var res_store = store_val(ref_store.val);#alloc_temporary();
		var res = res_store;
		if imm_flag or (("needs_deref" in handle) and handle.needs_deref): 
			var reg = alloc_register();
			vars_to_store.append([reg, handle.needs_deref, res_load, res_store]);			
			res = reg;
		imm_flag = false;
		#vars_to_store.append([res, ref_store.val]);
		text = text.substr(0, ref_store.from) + res + text.substr(ref_store.to);
	emit_raw(text, dbg_trace + ":emit(%s)" % text);
	for touple in vars_to_store:
		#store_val(pair[0], pair[1]);
		var reg = touple[0];
		var needs_deref = touple[1];
		var res_load = touple[2];
		var res_store = touple[3];
		if needs_deref:
			var reg2 = alloc_register();
			emit_raw("mov %s, %s;\n" % [reg2, res_load], dbg_trace+":emit(%s).store_deref_3" % text);
			emit_raw("mov *%s, %s;\n" % [reg2, reg], dbg_trace+":emit(%s).store_deref_4" % text);
			free_val(reg2);
		else:
			emit_raw("mov %s, %s;\n" % [res_store, reg], dbg_trace + ":emit(%s).store" % text);
		free_val(reg);
	for val in allocs:
		free_val(val);

func promote(res:String, allocs:Array):
	var reg = alloc_register();
	allocs.append(reg);
	emit("mov %s, %s;\n" % [reg, res], "promote");
	res = reg;
	return res;


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

## returns a CPU-addressable string that can be used to copy the value
func load_value(val:String):
	assert(val in all_syms);
	var handle = all_syms[val];
	var res = "";
	if handle.val_type == "code":
		res = generate_code_block(handle).code;
	elif handle.val_type == "immediate":
		if handle.data_type == "string":
			res = handle.ir_name;
		else:
			assert(handle.value.is_valid_int());
			res = handle.value;
	else:
		match handle.storage.type:
			"global": 
				res = "*%s" % handle.ir_name; #handle.storage.pos; #emit("mov %s, *%d;\n" % [res, handle.storage.pos]);
			"stack":
				res = "EBP[%d]" % handle.storage.pos; #emit("mov %s, EBP[%d];\n" % [res, handle.storage.pos]);
			"extern":
				res = "*%s" % handle.ir_name;
			_: push_error("codegen: load_value: unknown storage type ["+handle.storage.type+"]");
		#print("load val [%s] is %s: res [%s]" % [val, handle.storage.type, res]);
	return res;

## returns the CPU-addressable string that yields the address of the value.
func address_value(val:String):
	assert(val in all_syms);
	var handle = all_syms[val];
	var res = "";
	match handle.storage.type:
		"global":
			res = "%s" % handle.ir_name;
		"stack":
			res = "EBP+%d" % handle.storage.pos; 
			res = res.replace("+-", "-");
		"code":
			res = "%s" % handle.ir_name;
		"extern":
			res = "%s" % handle.ir_name;
		_: push_error("codegen: address_value: unkown storage type ["+handle.storage.type+"]");
	return res;

func alloc_temporary():
	var res = alloc_register();
	if not res:
		#res = "EBP[%d]" % cur_stack_size;
		#cur_stack_size += 1;
		var ir_name = "tmp_%d" % (len(all_syms)+1);
		var handle = {"ir_name":ir_name, "val_type":"temporary", "storage":"NULL"};
		allocate_value(handle, cur_scope);
		all_syms[ir_name] = handle;
		res = ir_name;
	return res;

func emit_raw(text:String, dbg_trace:String):
	if ADD_DEBUG_TRACE: cur_assy_block.code += "#%s\n" % dbg_trace.remove_chars("\n");
	cur_assy_block.code += text;

## returns a CPU-addressable string that can be used to write into the value.
func store_val(val:String):
	assert(val in all_syms);
	var handle = all_syms[val];
	var res;
	match handle.storage.type:
		"global":
			res = "*%s" % handle.ir_name; #handle.storage.pos;
		"stack":
			res = "EBP[%d]" % handle.storage.pos;
			assert(handle.storage.pos != 0);
		_: push_error("codegen: store_value: unkown storage type ["+handle.storage.type+"]");
	#print("store val [%s] is %s: res [%s]" % [val, handle.storage.type, res]);
	#emit("mov %s, %s;\n" % [res, reg]);
	#return reg;
	return res;

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
		#var stack_pos = 0; # we will be placing local vars on the stack
		#var arg_pos = 0; # args are placed on the stack in the other direction
		scope["local_vars_count"] = 0;
		scope["local_vars_write_pos"] = to_local_pos(0);
		scope["args_count"] = 0;
		scope["args_write_pos"] = to_arg_pos(0);
		if "vars" in scope:
			for handle in scope.vars:
				allocate_value(handle, scope);
			#scope["local_var_stack_size"] = stack_pos;
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

func allocate_value(handle, scope):
	var data_size = 4;
	if handle.storage == "NULL":
		var storage_type;
		var pos;
		if(scope.user_name == "global"): 
			storage_type = "global";
			pos = 0;
		else:
			storage_type = "stack";
			var wp = scope.local_vars_write_pos;
			#pos = to_local_pos(wp);
			pos = wp;
			scope.local_vars_write_pos -= data_size;
			scope.local_vars_count += 1;
			assert(pos != 0);
		handle.storage = {"type":storage_type, "pos":pos};
	elif handle.storage == "extern":
		handle.storage = {"type":"extern", "pos":0};
	elif handle.storage == "arg":
		var wp = scope.args_write_pos;
		var pos = wp;
		handle.storage = {"type":"stack", "pos":pos};
		assert(handle.storage.pos != 0);
		scope.args_write_pos += data_size;
		scope.args_count += 1;
	else:
		push_error("codegen: allocate_vars: unknown storage type");
	handle["needs_deref"] = false;
	#print("alloc %s to %s: result %s" % [handle.ir_name, scope.ir_name, handle.storage]);

# defines a mapping between the input pos and stack pos for local vars of a function
func to_local_pos(pos):
	return -3+pos;

# defines a mapping between the input pos and stack pos for arguments of a function
func to_arg_pos(pos):
	return 9+pos;

func generate_cmd_return(cmd):
	if len(cmd) >= 2:
		var res = cmd[1];
		emit("mov EAX, $%s;\n" % res, "generate_cmd_return.arg");
	var scp_name = cur_scope.ir_name;
	emit("__LEAVE_%s;\n" % scp_name, "generate_cmd_return.leave");
	emit("ret;\n", "generate_cmd_return.ret");

func generate_cmd_enter(cmd):
	var scp_name = cmd[1];
	enter_scope(IR.scopes[scp_name]);
	emit("__ENTER_%s;\n" % scp_name, "generate_cmd_enter");

func generate_cmd_leave(_cmd):
	var scp_name = cur_scope.ir_name;
	emit("__LEAVE_%s;\n" % scp_name, "generate_cmd_leave");
	leave_scope();

func fixup_enter_leave(assy_block):
	for key in IR.scopes:
		var scope = IR.scopes[key];
		var scp_name = scope.ir_name;
		var stack_bytes = scope.local_vars_write_pos;
		var S:String = assy_block.code;
		S = S.replace("__ENTER_%s" % scp_name, "sub ESP, %d" % -stack_bytes);
		S = S.replace("__LEAVE_%s" % scp_name, "sub ESP, %d" % stack_bytes);
		assy_block.code = S;

func fixup_symtable(sym_table):
	fixup_symtable_scope(sym_table.global);
	for fun in sym_table.funcs:
		fixup_symtable_scope(fun);
	print(sym_table);
	pass;

func fixup_symtable_scope(fun):
	for cat in [fun.args, fun.vars, fun.constants]:
		for h2 in cat: fixup_symtable_val(h2);

func fixup_symtable_val(val):
	var sym = all_syms[val.ir_name];
	match sym.storage.type:
		"global": val.pos = {"type":"global", "lbl":val.ir_name};
		"stack": val.pos = {"type":"stack", "pos":sym.storage.pos};
		"immediate": val.pos = {"type":"immediate", "val":sym.value};
		_: assert(false, "unexpected sym storage type [%s]" % str(sym.storage.type));
	if val.user_name == null:
		val.pos["val"] = sym.value;
