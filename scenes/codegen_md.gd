extends Node

@warning_ignore("unused_signal")
signal locations_ready(loc_map:LocationMap);

const uYaml = preload("res://scenes/uYaml.gd")
const ISA = preload("res://lang_zvm.gd")

# constants
const ADD_DEBUG_TRACE = false; # in emitted assembly, specify where it came from.
const ADD_IR_TRACE = false; # print the IR commands that are being generated
const WRITE_SHADOW = false; # mark bytes in shadow
const EMIT_COMMENTS = false; # debug tracing for emit()
const SHADOW_CODE_ADR = 30000;
const SHADOW_STACK_ADR = 50000;
const regs = ["EAX", "EBX", "ECX", "EDX"];
const cmd_size = 8; # size in bytes of an assembly instruction
const enter_leave_size = cmd_size; 
const shadow_update_size = cmd_size*50;
const op_map = {
	"ADD":["add %a, %b;\n"],
	"SUB":["sub %a, %b;\n"],
	"MUL":["mul %a, %b;\n"],
	"DIV":["div %a, %b;\n"],
	"MOD":["mod %a, %b;\n"],
	"GREATER":[
		"cmp %a, %b;\n", 
		"mov %a, CTRL;\n", 
		"band %a, CMP_G;\n", 
		"bnot %a;\n", 
		"bnot %a;\n"],
	"LESS":[
		"cmp %a, %b;\n",
		"mov %a, CTRL;\n",
		"band %a, CMP_L;\n",
		"bnot %a;\n",
		"bnot %a;\n"],
	"INDEX":["add %a, %b;\n"], #deref separately?
	"DEC":["dec %a;\n"],
	"INC":["inc %a;\n"],
	"EQUAL":[
		"cmp %a, %b;\n",
		"mov %a, CTRL;\n",
		"band %a, CMP_Z;\n",
		"bnot %a;\n",
		"bnot %a;\n",
	],
	"NOT_EQUAL":[
		"cmp %a, %b;\n",
		"mov %a, CTRL;\n",
		"band %a, CMP_NZ;\n",
		"bnot %a;\n",
		"bnot %a;\n",
	],
};
const imm_map = {
	"CMP_G":"CMP_G",
	"CMP_L":"CMP_L",
	"CMP_Z":"CMP_Z",
	"CMP_NZ":"CMP_NZ",
};
const word_size_bytes = 4; ## how many bytes does a plain "mov" grab?
# state
var IR:IRKind = IRKind.new();# = {};
#var all_syms:Dictionary[String,IR_Value] = {};
var assy_block_stack:Array[AssyBlock] = [];
var cur_assy_block:AssyBlock;
var cur_stack_size:int = 0; # number of bytes in the current frame used for local variables
var regs_in_use:Dictionary[String,bool] = {};
var referenced_cbs:Array[CodeBlock] = [];
var cur_block:CodeBlock;
var cb_stack:Array[CodeBlock] = [];
var entered_scopes:Array[Scope] = [];
var cur_scope:Scope;# = null;
var n_locations:int = 0;
var val_idx:int = 0;
#var location_map = {};

func reset()->void:
	IR = IRKind.new(); #{};
	#all_syms = {};
	assy_block_stack = [];
	cur_assy_block = null;
	cur_stack_size = 0;
	regs_in_use = {};
	referenced_cbs = [];
	cur_block = null;
	cb_stack = [];
	entered_scopes = [];
	cur_scope = null;
	n_locations = 0;

#---------- IR ingestion -------------------

func parse_file(input:CompilerMD.Context, task:Task)->String:
	reset();
	var filename:String = input.filename;
	var fp:FileAccess = FileAccess.open(filename, FileAccess.READ);
	var text:String = fp.get_as_text();
	fp.close();
	deserialize(text);
	return generate(task);

## @deprecated IR should have its own serdes
func deserialize(text:String)->void:
	IR = uYaml.deserialize(text);
	assert(not IR.is_empty());
	##inflate scopes
	for key in IR.scopes:
		bump_val_idx(key);
		var scope:Scope = IR.scopes[key];
		if not "vars" in scope: scope["vars"] = [];
		if not "funcs" in scope: scope["funcs"] = [];
		inflate_vals(scope.vars);
		inflate_vals(scope.funcs);
		
	##inflate code blocks
	for key in IR.code_blocks:
		bump_val_idx(key);
		var in_cb:CodeBlock = IR.code_blocks[key];
		var out_cb:CodeBlock = CodeBlock.new({"ir_name":key, "lbl_from":in_cb.lbl_from, "lbl_to":in_cb.lbl_to});
		if "code" in in_cb:
			for cmd in in_cb.code:
				var loc_str:String = cmd.pop_back();
				loc_str = G.unescape_string(loc_str);
				var loc:LocationRange = LocationRange.from_string(loc_str);
				assert(len(cmd));
				var out_cmd:IR_Cmd = IR_Cmd.new(cmd.words,loc);
				#out_cmd.words.assign(cmd.words);
				assert(len(out_cmd.words));
				out_cb.code.push_back(out_cmd);
		IR.code_blocks[key] = out_cb;
	#make a total list of vals
	for key in IR.code_blocks: IR.all_syms[key] = IR.code_blocks[key]; bump_val_idx(key);
	for key in IR.scopes:
		bump_val_idx(key);
		var scope:Scope = IR.scopes[key];
		for val in scope.vars: IR.all_syms[val.ir_name] = val; bump_val_idx(key);
		for val in scope.funcs: IR.all_syms[val.ir_name] = val; bump_val_idx(key);

## makes sure that val_idx > name_<idx> 
func bump_val_idx(ir_name)->void:
	var regex:RegEx = RegEx.new();
	regex.compile("[0-9]+");
	var rmatch:RegExMatch = regex.search(ir_name);
	assert(rmatch != null);
	var res:String = rmatch.get_string(0);
	assert(res != "");
	assert(res.is_valid_int());
	var old_idx:int = res.to_int();
	val_idx = max(val_idx, old_idx+1)

## @deprecated IR should have its own serdes
func inflate_vals(arr:Array)->void:
	const props:Array[String] = ["ir_name", "val_type", "user_name", "data_type", "data_size", "storage", "value", "scope", "code", "argc", "is_array", "array_size"];
	for i in range(len(arr)):
		var val:Variant = arr[i];
		assert(len(val) == len(props));
		var new_val:Dictionary = {};
		for j in range(len(props)):
			var S:String = G.unescape_string(val[j]);
			new_val[props[j]] = S;
		new_val.data_size = (new_val.data_size as String).to_int();
		bump_val_idx(new_val.ir_name);
		arr[i] = new_val;
	

#-------------- Code generation -----------------

func generate(task:Task)->String:
	allocate_vars();
	#for key in IR.code_blocks:
	#	var cb = IR.code_blocks[key];
	#	generate_code_block(cb);
	var cb_global:CodeBlock = G.first_in_dict(IR.code_blocks); #IR.code_blocks[IR.code_blocks.keys()[0]];
	referenced_cbs.append(cb_global);
	var emitted_cbs:Array[CodeBlock] = [];
	#referenced_cbs.push_back(cb_global);
	var scp_global:Scope = IR.scopes[IR.scopes.keys()[0]];
	enter_scope(scp_global);
	
	#var assy_full = "";
	#var write_pointer = 0;
	#while not referenced_cbs.is_empty(): #we're using the dictionary as a Set.
	#	var cb = referenced_cbs.pop_front();
	#	if cb in emitted_cbs: continue;
	#	else: emitted_cbs.append(cb);
	#	var ab = generate_code_block(cb);
	#	fixup_enter_leave(ab);
	#	translate_ab_locations(ab.location.map, write_pointer);
	#	write_pointer += ab.write_pointer;
	#	assy_full += ab.code;
	#assy_full += generate_globals();
	#return assy_full;
	cur_assy_block = AssyBlock.new(); #{"code":"", "write_pos":0, "location_map":{"begin":{}, "end":{}}};
	var global_ab:AssyBlock = cur_assy_block;
	var lc:LoopCounter = LoopCounter.new();
	while not referenced_cbs.is_empty():
		task.work_units_total +=1; # we dunno how many there will be
		lc.step();
		var cb:CodeBlock = referenced_cbs.pop_front();
		if cb in emitted_cbs: continue;
		else: emitted_cbs.append(cb);
		emit_cb(cb.ir_name, "generate.referenced_cbs");
	task.work_units_complete = task.work_units_total;
	fixup_enter_leave(cur_assy_block);
	cur_assy_block.code += generate_globals();
	assert(cur_assy_block == global_ab);
	#var n_locations_in = n_locations;
	#var n_locations_out = len(cur_assy_block.loc_map.begin);
	#assert(n_locations_out == n_locations_in);
	call_deferred("defer_locations_ready", cur_assy_block.loc_map); #locations_ready.emit(cur_assy_block.loc_map);
	return cur_assy_block.code;
	
func defer_locations_ready(_arg)->void:
	#locations_ready.emit(arg);
	push_warning("can't emit locations_ready");
	pass;
	
func generate_code_block(cb:CodeBlock)->AssyBlock:
	if cur_block:
		cb_stack.push_back(cur_block);
	cur_block = cb;
	cb["if_block_continued"] = false;
	assy_block_stack.push_back(cur_assy_block);
	cur_assy_block = AssyBlock.new(); #{"code":"", "write_pos":0, "location_map":{"begin":{}, "end":{}}};
	emit_raw("# Begin code block %s\n" % cb.ir_name,  0, "generate_code_block.intro");
	emit_raw(":%s:\n" % cb.lbl_from, 0, "generate_code_block.lbl_from");
	#maybe_emit_func_label(cb.ir_name);
	if "code" in cb:
		for i in range(len(cb.code)):
			var cmd:IR_Cmd = cb.code[i];
			check_if_block_continued(i, cb.code);
			generate_cmd(cmd);
	maybe_emit_func_ret(cb.ir_name);
	emit_raw(":%s:\n" % cb.lbl_to, 0, "generate_code_block.lbl_to");
	emit_raw("# End code block %s\n" % cb.ir_name, 0, "generate_code_block.exit");
	var res:AssyBlock = cur_assy_block;
	cur_assy_block = assy_block_stack.pop_back();
	cur_block = cb_stack.pop_back();
	return res;

func generate_globals()->String:
	var text:String = "";
	for key in IR.all_syms:
		var sym:IR_Value = IR.all_syms[key];

		match sym.val_type:
			"code":
				pass;
			"func":
				pass;
			"label":
				pass;
			"variable":
				if sym.storage.type == "global":
					if ("is_array" in sym) and (int(sym.is_array) == 1):
						text += ":%s: alloc %s;\n" % [sym.ir_name, str(4*int(sym.array_size))];
					else:
						text += ":%s: db 0;\n" % sym.ir_name;
			"temporary":
				if sym.storage.type == "global":
					text += ":%s: db 0;\n" % sym.ir_name;
			"immediate":
				if sym.data_type == "String":
					var S:String = sym.value;
					S = format_db_string(S);
					text += ":%s: db %s;\n" % [sym.ir_name, S];
			"array":
				text += ":%s: alloc %s;\n" % [sym.ir_name, str(4*int(sym.array_size))];	
			_: assert(false, "codegen.generate_globals: unspecified value storage type");
	return text;

func format_db_string(S:String)->String:
	var text:String = "";
	#if USE_WIDE_STRINGS:
	#	for ch:String in S:
	#		text += "%d,0,0,0, " % ch.to_ascii_buffer()[0];
	#	#text = text.erase(len(text)-2,2);
	#	text += "0,0,0,0";
	#else:
	text = "\"%s\", 0" % S;
	#print("format db string: in ["+S+"], out ["+text+"]");
	return text;

func enter_scope(new_scope)->void:
	if cur_scope:
		entered_scopes.push_back(cur_scope);
	cur_scope = new_scope;
func leave_scope()->void:
	cur_scope = entered_scopes.pop_back();


#func maybe_emit_func_label(ir_name:String):
	#var calling_func = is_referenced_by_func(ir_name);
	#if calling_func:	emit_raw(":%s:\n" % calling_func, "maybe_emit_func_label(%s)" % ir_name);

func maybe_emit_func_ret(ir_name:String)->void:
	var calling_func:String = is_referenced_by_func(ir_name);
	if calling_func != "":	emit_raw("ret;\n", cmd_size, "maybe_emit_func_ret(%s)" % ir_name);

func is_referenced_by_func(ir_name:String)->String:
	for key in IR.all_syms:
		var sym:IR_Value = IR.all_syms[key];
		if sym.val_type == "func":
			if sym.code == ir_name:
				return sym.ir_name;
	return ""

func check_if_block_continued(i:int, code:Array[IR_Cmd])->bool:
	cur_block.if_block_continued = false;
	if i+1 < len(code):
		var cmd2:IR_Cmd = code[i+1];
		if cmd2.words[0] in ["ELSE_IF", "ELSE"]:
			cur_block.if_block_continued = true;
	return false;

func generate_cmd(cmd:IR_Cmd)->void:
	if ADD_IR_TRACE: emit_raw("# IR: %s\n" % " ".join(PackedStringArray(cmd.words)), 0, "generate_cmd.trace");
	match cmd.words[0]:
		"MOV": generate_cmd_mov(cmd);
		"OP": generate_cmd_op(cmd);
		"IF": generate_cmd_if(cmd);
		"ELSE_IF": generate_cmd_else_if(cmd);
		"ELSE": generate_cmd_else(cmd);
		"WHILE": generate_cmd_while(cmd);
		"CALL": generate_cmd_call(cmd);
		"CALL_INDIRECT": generate_cmd_call_indirect(cmd);
		"RETURN": generate_cmd_return(cmd);
		"ENTER": generate_cmd_enter(cmd);
		"LEAVE": generate_cmd_leave(cmd);
		"ALLOC": generate_cmd_alloc(cmd);
		"MOV_ARR": generate_cmd_mov_arr(cmd);
		_: push_error("codegen: unknown IR command ["+str(cmd.words[0])+"]");

func generate_cmd_mov(cmd:IR_Cmd)->void:
	var loc:LocationRange = cmd.loc;
	#MOV dest src
	var dest:String = cmd.words[1];
	var src:String = cmd.words[2];
	mark_loc_begin(loc);
	emit("mov ^%s, $%s;\n" % [dest, src], cmd_size, "generate_cmd_mov");
	mark_loc_end(loc);


func generate_cmd_op(cmd:IR_Cmd)->void:
	#OP op arg1 arg2 res
	var op:String = cmd.words[1];
	var arg1:String = cmd.words[2];
	var arg2:String = cmd.words[3];
	var res:String = cmd.words[4];
	var loc:LocationRange = cmd.loc;
	if op not in op_map: push_error("codegen: can't generate op ["+op+"]"); return;
	mark_loc_begin(loc);
	var op_arr:Array = op_map[op];
	for op_str in op_arr:
		generate_cmd_op_helper(op,arg1,arg2,res,op_str);
	mark_loc_end(loc);

func generate_cmd_op_helper(op:String, arg1:String, arg2:String, res:String, op_str:String)->void:
	for imm in imm_map: ## for CMP_Z and other assembly constants
		var imm_val:String = imm_map[imm];
		if op_str.find(imm) != -1:
			var imm_handle:IR_Imm = IR_Imm.new(IR,0);#new_imm(0);
			allocate_value(imm_handle, cur_scope);
			imm_handle.value = imm_val;
			imm_handle["is_assy_constant"] = true;
			op_str = op_str.replace(imm, "$"+imm_handle.ir_name);
			
	var tmpA:String;
	var tmpB:String;
	var arg1_is_array:bool = false;
	if arg1 in IR.all_syms:
		var arg1_handle:IR_Value = IR.all_syms[arg1];
		#print("arg1 (%s): %s" % [arg1, arg1_handle]);
		if int(arg1_handle.is_array) == 1:
			arg1_is_array = true;
	#else:
		#print("arg1 (%s) NOT IN ALL_SYMS" % arg1);
	#var arg1_by_addr = false;
	const mono_ops:Array[String] = ["INC", "DEC"];
	if op in mono_ops:
		tmpA = "%s" % arg1;
		emit("mov ^%s, $%s;\n" % [res, arg1], cmd_size, "generate_cmd_op.result2");
	elif arg1_is_array:
		tmpA = alloc_temporary();
		emit("mov ^%s, @%s;\n" % [tmpA, arg1], cmd_size, "generate_cmd_op.arg1_idx");
	else:
		tmpA = alloc_temporary();
		emit("mov ^%s, $%s;\n" % [tmpA, arg1], cmd_size, "generate_cmd_op.arg1_normal");
		#emit("mov ^%s, $%s;\n" % [tmpA, arg1], cmd_size, "generate_cmd_op.arg1");

	op_str = op_str.replace("%a", "!"+tmpA);
	if op_str.find("%b") != -1:
		tmpB = alloc_temporary();
		emit("mov ^%s, $%s;\n" % [tmpB, arg2], cmd_size, "generate_cmd_op.find_b");
		op_str = op_str.replace("%b", "$"+tmpB);
		
	if op == "INDEX":
		var arg1_handle:IR_Value = IR.all_syms[arg1];
		assert(arg1_handle != null);
		var arg1_type:Type = arg1_handle.data_type;
		var pointer_step:int = 1;
		if arg1_type != null:#"NULL":
			var arg1T:Type = arg1_type;#Type.from_string(arg1_type);
			assert(arg1T != null);
			var arg1dT:Type = arg1T.get_deref_type();
			assert(arg1dT != null);
			pointer_step = arg1dT.size;
		var ptr_step:IR_Imm = IR_Imm.new(IR, pointer_step); #new_imm(pointer_step);
		allocate_value(ptr_step, cur_scope);
		emit("mul ^%s, $%s;\n" % [tmpB, ptr_step.ir_name], cmd_size, "generate_cmd_op.index_step");
	if op == "NOT_EQUAL":
		push_warning("need to replace constants CMP_NZ etc");
		
	var op_cmd_size:int = cmd_size * op_str.count(";");
	emit(op_str, op_cmd_size, "generate_cmd_op.op_str");
	if op not in mono_ops: emit("mov ^%s, $%s;\n" % [res, tmpA], cmd_size, "generate_cmd_op.result1");
	var res_handle:IR_Value = IR.all_syms[res];
	if op == "INDEX": res_handle.needs_deref = true;
	free_val(tmpA);
	if(tmpB): free_val(tmpB);

#func new_lbl(lbl_name:String)->Dictionary:
	#var ir_name = "lbl_"+str(val_idx)+"__"+lbl_name; val_idx += 1;
	#assert(ir_name not in all_syms, "ir sym uid count broken");
	#var handle = {"ir_name":ir_name, "val_type":"label"};
	#all_syms[ir_name] = handle;
	#return handle;

func generate_cmd_if(cmd:IR_Cmd)->void:
	var cb_cond:String = cmd.words[1];
	var res:String = cmd.words[2];
	var cb_block:String = cmd.words[3];
	var lbl_else:String = IR_lbl.new(IR,"if_else").ir_name;#new_lbl("if_else").ir_name;
	var lbl_end:String = IR_lbl.new(IR,"if_end").ir_name;#new_lbl("if_end").ir_name;
	var imm_0_handle:IR_Imm = IR_Imm.new(IR,0); #new_imm(0);
	allocate_value(imm_0_handle, cur_scope);
	var imm_0:String = imm_0_handle.ir_name;
	
	var loc:LocationRange = cmd.loc;
	mark_loc_begin(loc);
	emit_cb(cb_cond, "generate_cmd_if.cb_cond");
	#emit("$%s\n" % cb_cond, get_cb_cmd_size(cb_cond), "generate_cmd_if.cb_cond");
	emit("cmp $%s, $%s;\n" % [res, imm_0], cmd_size, "generate_cmd_if.cmp");
	emit("jz %s;\n" % lbl_else, cmd_size, "generate_cmd_if.jz_else");
	emit_cb(cb_block, "generate_cmd_if.cb_block");
	#emit("$%s\n" % cb_block, get_cb_cmd_size(cb_block), "generate_cmd_if.cb_block");
	emit("jmp %s;\n" % lbl_end, cmd_size, "generate_cmd_if.end_then");
	emit(":%s:\n" % lbl_else, 0, "generate_cmd_if.lbl_else");
	if cur_block.if_block_continued:
		cur_block.if_block_lbl_end = lbl_end;
	else:
		emit(":%s:\n" % lbl_end, 0, "generate_cmd_if.end_if");
		cur_block.if_block_lbl_end = "";
	mark_loc_end(loc);

func generate_cmd_else_if(cmd:IR_Cmd)->void:
	var cb_cond:String = cmd.words[1];
	var res:String = cmd.words[2];
	var cb_block:String = cmd.words[3];
	var lbl_else:String = IR_lbl.new(IR,"if_else").ir_name; #new_lbl("if_else").ir_name;
	var lbl_end:String = cur_block.if_block_lbl_end;
	var imm_0_handle:IR_Imm = IR_Imm.new(IR,0)#new_imm(0);
	allocate_value(imm_0_handle, cur_scope);
	var imm_0:String = imm_0_handle.ir_name;
	var loc:LocationRange = cmd.loc;
	mark_loc_begin(loc);
	emit_cb(cb_cond, "generate_cmd_else_if.cb_cond");
	#emit("$%s\n" % cb_cond, get_cb_cmd_size(cb_cond), "generate_cmd_else_if.cb_cond");
	emit("cmp $%s, $%s;\n" % [res, imm_0], cmd_size, "generate_cmd_else_if.cmp");
	emit("jz %s;\n" % lbl_else, cmd_size, "generate_cmd_else_if.jz_else");
	emit_cb(cb_block, "generate_cmd_else_if.cb_block");
	#emit("$%s\n" % cb_block, get_cb_cmd_size(cb_block), "generate_cmd_else_if.cb_block");
	emit("jmp %s\n" % lbl_end, cmd_size, "generate_cmd_else_if.end_then");
	emit(":%s:\n" % lbl_else, 0, "generate_cmd_else_if.lbl_else");
	if not cur_block.if_block_continued:
		emit(":%s:\n" % lbl_end, 0, "generate_cmd_else_if.end_if");
		cur_block.if_block_lbl_end = "";
	mark_loc_end(loc);

func generate_cmd_else(cmd:IR_Cmd)->void:
	var cb_block:String = cmd.words[1];
	var lbl_end:String = cur_block.if_block_lbl_end;
	var loc:LocationRange = cmd.loc;
	mark_loc_begin(loc);
	emit_cb(cb_block,"generate_cmd_else.cb_block");
	#emit("$%s\n" % [cb_block], get_cb_cmd_size(cb_block), "generate_cmd_else.cb_block");
	emit(":%s:\n" % [lbl_end], 0, "generate_cmd_else.lbl_end");
	cur_block.if_block_lbl_end = "";
	mark_loc_end(loc);

func generate_cmd_while(cmd:IR_Cmd)->void:
	#WHILE cb_cond res cb_block lbl_next lbl_end
	var cb_cond:String = cmd.words[1];
	var res:String = cmd.words[2];
	var cb_block:String = cmd.words[3];
	var lbl_next:String = cmd.words[4];
	var lbl_end:String = cmd.words[5];
	var immediate_0:IR_Imm = IR_Imm.new(IR,0);#new_imm(0);
	var loc:LocationRange = cmd.loc;
	mark_loc_begin(loc);
	allocate_value(immediate_0, cur_scope);
	emit(":%s:\n" % lbl_next, 0, "generate_cmd_while.lbl_next");		# loop:
	emit_cb(cb_cond, "generate_cmd_while.cb_cond");
	#emit("$%s\n" % cb_cond, "generate_cmd_while.cb_cond");		#  (expr->cond)
	emit("cmp $%s, $%s;\n" % [res, immediate_0.ir_name], 
		cmd_size, "generate_cmd_while.cmp");		#  IF !cond 
	emit("jz %s;\n" % lbl_end, 0, "generate_cmd_while.jz_end");		#  THEN GOTO "end"
	emit_cb(cb_block, "generate_cmd_while.cb_block");
	#emit("$%s\n" % cb_block, "generate_cmd_while.cb_block");		#  (code block)
	emit("jmp %s;\n" % lbl_next, cmd_size, "generate_cmd_while.jmp_next");	#  GOTO "loop"
	emit(":%s:\n" % lbl_end, 0, "generate_cmd_while.lbl_end");		# end:
	mark_loc_end(loc);

func generate_cmd_call(cmd:IR_Cmd)->void:
	#CALL fun arg(s) res
	var fun:String = cmd.words[1];
	assert(fun in IR.all_syms);
	var fun_handle:IR_func = IR.all_syms[fun];
	var args:Array[String] = [];
	if cmd.words[2] == "[":
		var i:int = 3;
		var lc:LoopCounter = LoopCounter.new();
		while true:
			lc.step();
			if cmd.words[i] == "]": break;
			args.append(cmd.words[i]);
			i += 1;
	else:
		args.append(cmd.words[3]);
	var res:String = cmd.words[-1];
	args.reverse();
	var n_args:int = len(args);
	var pushed_stack_size:int = 4*n_args;
	push_warning("codegen:cmd_call:didn't check arg size");
	var loc:LocationRange = cmd.loc;
	mark_loc_begin(loc);
	for arg in args:
		emit("push $%s;\n" % arg, cmd_size, "generate_cmd_call.args");
	emit("call @%s;\n" % fun, cmd_size, "generate_cmd_call.call");
	emit("add ESP, %s;\n" % pushed_stack_size, cmd_size, "generate_cmd_call.stack");
	emit("mov ^%s, eax;\n" % res, cmd_size, "generate_cmd_call.result");
	mark_loc_end(loc);
	
	if fun_handle.storage.type != "extern":
		#var cb_name = fun_handle.code;
		#assert(cb_name in all_syms);
		#var cb = all_syms[cb_name];
		var cb:CodeBlock = fun_handle.code;
		assert(cb.ir_name in IR.all_syms);
		if cb not in referenced_cbs: referenced_cbs.append(cb);

func generate_cmd_call_indirect(cmd:IR_Cmd)->void:
	#CALL fun arg(s) res
	var funvar:String = cmd.words[1];
	assert(funvar in IR.all_syms);
	var args:Array[String] = [];
	if cmd.words[2] == "[":
		var i:int = 3;
		while true:
			if cmd.words[i] == "]": break;
			args.append(cmd.words[i]);
			i += 1;
	else:
		args.append(cmd.words[3]);
	var res:String = cmd.words[-1];
	args.reverse();
	var n_args:int = len(args);
	var pushed_stack_size:int = 4*n_args;
	push_warning("codegen:call_indirect:arg size not checked");
	for arg in args:
		emit("push $%s;\n" % arg, cmd_size, "generate_cmd_call_indirect.args");
	emit("call $%s;\n" % funvar, cmd_size, "generate_cmd_call_indirect.call");
	emit("add ESP, %s;\n" % pushed_stack_size, cmd_size, "generate_cmd_call_indirect.stack");
	emit("mov ^%s, eax;\n" % res, cmd_size, "generate_cmd_call_indirect.result");
	
class StoreRequest:
	var reg:String;
	var needs_deref:bool;
	var res_store:String;
	var res_load:String;
	func _init(_reg:String, _needs_deref:bool, _res_store:String, _res_load:String):
		reg=_reg; needs_deref=_needs_deref;res_store=_res_store;res_load=_res_load;
	
func emit(text:String, wp_diff:int, dbg_trace:String)->void:
	emit_comment("\n# EMIT BEGIN\n");
	var imm_flag:bool = false;
	var allocs:Array[String] = [];
	## ---- process $load commands: provide the value that can be read
	var lc:LoopCounter = LoopCounter.new();
	while true:
		lc.step();
		var ref_load:StringRef = find_reference(text, "$");
		if ref_load == StringRef.none: break;
		var res:String = load_value(ref_load.val);
		emit_comment("# load_value(%s)->%s\n" % [ref_load.val, res]);
		var handle:IR_Value = IR.all_syms[ref_load.val];
		if ("needs_deref" in handle) and handle.needs_deref:
			#var reg = alloc_register();
			var tmp:String;
			if res not in regs:
				tmp = promote(res, allocs);
				allocs.append(tmp);
				emit("mov %s, *%s;\n" % [tmp, tmp], cmd_size, "emit.needs_deref_3(%s)" % ref_load.val);
			else:
				tmp = alloc_temporary();
				emit("mov ^%s, *%s;\n" % [tmp, res], cmd_size, "emit.needs_deref_4(%s)" % ref_load.val);
			#allocs.push_back(reg);
			#assert(reg != null);
			#emit("mov ^%s, %s;\n" % [tmp, res], cmd_size, "emit.needs_deref_1(%s)" % ref_load.val);
			#emit("mov ^%s, *$%s;\n" % [tmp, tmp], cmd_size, "emit.needs_deref_2(%s)" % ref_load.val);
			
			if (tmp in regs) and not imm_flag:
				tmp = demote(tmp, allocs);
				res = load_value(tmp);
				imm_flag = true;
			else:
				res = tmp;
			#note: imm_flag = false or imm_flag;
		else:
			if imm_flag: 
				var res_old:String = res;
				res = promote(res, allocs);
				emit_comment("# promote(%s)->%s\n" % [res_old, res]);
			imm_flag = true;
		## ---------- truncate loaded value if it's small ----
		#var handle = all_syms[val];
		var size_bytes:int = 4;
		if "data_size" in handle: size_bytes = handle.data_size;
		
		if size_bytes < word_size_bytes:
			var reg:String = alloc_register("load_val.truncate");
			var mask:int = (2**(8*size_bytes)-1); #"0x"+"FF".repeat(size_bytes);
			emit_raw("mov %s, %s;\n" % [reg, res], cmd_size, "load_value.truncate1");
			emit_raw("band %s, %d;\n" % [reg, mask], cmd_size, "load_value.truncate2");
			var tmp:String = alloc_temporary();
			emit("mov ^%s, %s;\n" % [tmp, reg], cmd_size, "load_value.truncate3");
			free_val(reg);
			res = load_value(tmp);	
		
		text = text.substr(0, ref_load.from) + res + text.substr(ref_load.to);
	## ----- process @address commands: provide the memory address of a value
	lc = LoopCounter.new();
	while true:
		lc.step();
		var ref_addr:StringRef = find_reference(text, "@");
		if ref_addr.is_empty(): break;
		var res:String = address_value(ref_addr.val);
		emit_comment("# address_value(%s)->%s\n" % [ref_addr.val, res]);
		if imm_flag: 
			var res_old:String = res;
			res = promote(res, allocs);
			emit_comment("# promote(%s)->%s\n" % [res_old, res]);
		imm_flag = true;
		text = text.substr(0, ref_addr.from) + res + text.substr(ref_addr.to);
	var vars_to_store:Array[StoreRequest] = [];
	## --------- process !loadstore commands: first provide a value that can be read, and then store it.
	lc = LoopCounter.new();
	while true:
		lc.step();
		var ref_loadstore:StringRef = find_reference(text, "!");
		if ref_loadstore.is_empty(): break;
		var res:String = load_value(ref_loadstore.val);
		var handle:IR_Value = IR.all_syms[ref_loadstore.val];
		if ("needs_deref" in handle) and handle.needs_deref:
			if res not in regs:
				var res_load:String = res;
				var reg:String = promote(res, allocs);
				allocs.append(reg);
				emit("mov %s, *%s;\n" % [reg, res], cmd_size, "emit.needs_deref_5(%s)" % ref_loadstore.val);
				res = reg; # can't demote because we need a register to store with deref
				vars_to_store.append(StoreRequest.new(
					reg, handle.needs_deref, res_load, ""));
			else:
				var tmp1:String = alloc_temporary();
				emit("mov ^%s, %s;\n" % [tmp1, res], cmd_size, "emit.needs_deref_61_to_store(%s)" % ref_loadstore.val)
				var tmp:String = alloc_temporary();	
				emit("mov ^%s, *%s;\n" % [tmp, res], cmd_size, "emit.needs_deref_6(%s)" % ref_loadstore.val);
				var res_load:String = tmp1;
				vars_to_store.append(StoreRequest.new(
					tmp, handle.needs_deref, res_load, ""));
				res = tmp;
		else:
			if imm_flag: 
				var reg:String = promote(res, allocs);
				var res_store:String = res;
				vars_to_store.append(StoreRequest.new(
					reg, handle.needs_deref, "", res_store));
				res = reg;
			imm_flag = true;
		
		## ---------- truncate loaded value if it's small ----
		#var handle = all_syms[val];
		var size_bytes:int = 4;
		if "data_size" in handle: size_bytes = handle.data_size;
		
		if size_bytes < word_size_bytes:
			var reg:String = alloc_register("load_val.truncate");
			var mask:int = (2**(8*size_bytes)-1); #"0x"+"FF".repeat(size_bytes);
			emit_raw("mov %s, %s;\n" % [reg, res], cmd_size, "load_value.truncate1");
			emit_raw("band %s, %d;\n" % [reg, mask], cmd_size, "load_value.truncate2");
			var tmp:String = alloc_temporary();
			emit("mov ^%s, %s;\n" % [tmp, reg], cmd_size, "load_value.truncate3");
			free_val(reg);
			res = load_value(tmp);	
		
		text = text.substr(0, ref_loadstore.from) + res + text.substr(ref_loadstore.to);
	## --------- process ^store commands: provide a value that can be written to
	lc = LoopCounter.new();
	while true:
		lc.step();
		var ref_store:StringRef = find_reference(text, "^");
		if ref_store.is_empty(): break;
		var handle:IR_Value = IR.all_syms[ref_store.val];
		var res_load:String = load_value(ref_store.val); allocs.append(res_load);
		emit_comment("# load_value(%s)->%s\n" % [ref_store.val, res_load]);
		var res_store:String = store_val(ref_store.val);#alloc_temporary();
		emit_comment("# store_val(%s)->%s\n" % [ref_store.val, res_load]);
		var res:String = res_store;
		if imm_flag or (("needs_deref" in handle) and handle.needs_deref): 
			var reg:String = alloc_register("emit.store1_needs_deref");
			vars_to_store.append([reg, handle.needs_deref, res_load, res_store]);			
			res = reg;
		imm_flag = false;
		#vars_to_store.append([res, ref_store.val]);
		text = text.substr(0, ref_store.from) + res + text.substr(ref_store.to);
	emit_raw(text, wp_diff, dbg_trace + ":emit(%s)" % text);
	for sreq in vars_to_store:
		#store_val(pair[0], pair[1]);
		#var reg = touple[0];
		#var needs_deref = touple[1];
		#var res_load = touple[2];
		#var res_store = touple[3];
		if sreq.needs_deref:
			var reg2:String = alloc_register("emit.store2_needs_deref");
			emit_raw("mov %s, %s;\n" % [reg2, sreq.res_load], cmd_size, dbg_trace+":emit(%s).store_deref_3" % text);
			emit_raw("mov *%s, %s;\n" % [reg2, sreq.reg], cmd_size, dbg_trace+":emit(%s).store_deref_4" % text);
			free_val(reg2);
		else:
			emit_raw("mov %s, %s;\n" % [sreq.res_store, sreq.reg], cmd_size, dbg_trace + ":emit(%s).store" % text);
		free_val(sreq.reg);
	for val in allocs:
		free_val(val);
	emit_comment("# EMIT END\n\n");

## move a value into a register
func promote(res:String, allocs:Array)->String:
	var reg:String = alloc_register("promote %s" % res);
	allocs.append(reg);
	emit("mov %s, %s;\n" % [reg, res], cmd_size, "promote");
	res = reg;
	return res;

## move a value from a register into a temporary
func demote(reg:String, allocs:Array)->String:
	var tmp:String = alloc_temporary();
	allocs.erase(reg);
	emit("mov ^%s, %s;\n" % [tmp, reg], cmd_size, "demote");
	free_val(reg);
	return tmp;

class StringRef:
	var from:int;
	var to:int;
	var val:String;
	func _init(_from:int=0,_to:int=0,_val:String=""):
		from=_from;
		to=_to;
		val=_val;
	static var none = StringRef.new();

func find_reference(text:String, marker:String)->StringRef:
	var marker_pos:int = text.find(marker);
	if(marker_pos == -1): return StringRef.none;
	var end_pos:int = G.find_first_of(text, " ,:;\n", marker_pos);
	var val:String = text.substr(marker_pos+1, end_pos-(marker_pos+1));
	#var res = {"from":marker_pos, "to":end_pos, "val":val};
	return StringRef.new(marker_pos,end_pos,val);;

## returns a CPU-addressable string that can be used to copy the value
func load_value(val:String)->String:
	assert(val in IR.all_syms);
	var handle:IR_Value = IR.all_syms[val];
	var size_bytes:int = 4;
	var res:String = "";
	if handle.val_type == "code":
		assert(false, "Deprecated, need to generate before emitting");
		res = generate_code_block(handle).code;
	elif handle.val_type == "immediate":
		#size_bytes = handle.data_size;
		if handle.data_type == "String":
			res = handle.ir_name;
		else:
			if ("is_assy_constant" in handle) and handle.is_assy_constant:
				res = handle.value;
			else:
				assert(handle.value.is_valid_int());
				res = handle.value;
				res = str(truncate_number((res as String).to_int(), size_bytes));
	else:
		#size_bytes = handle.data_size;
		match handle.storage.type:
			"global": 
				if int(handle.is_array) == 1:
					res = "%s" % handle.ir_name;
				else:
					res = "*%s" % handle.ir_name; #handle.storage.pos; #emit("mov %s, *%d;\n" % [res, handle.storage.pos]);
			"stack":
				if int(handle.is_array) == 1:
					res = "EBP+%d" % handle.storage.pos;
					res = res.replace("+-","-");
				else:
					res = "EBP[%d]" % handle.storage.pos; #emit("mov %s, EBP[%d];\n" % [res, handle.storage.pos]);
			"extern":
				res = "*%s" % handle.ir_name;
			_: push_error("codegen: load_value: unknown storage type ["+handle.storage.type+"]");
		#print("load val [%s] is %s: res [%s]" % [val, handle.storage.type, res]);
	#if size_bytes < word_size_bytes:
		#var reg = alloc_register("load_val.truncate");
		#var mask = (2**(8*size_bytes)-1); #"0x"+"FF".repeat(size_bytes);
		#emit_raw("mov %s, %s;\n" % [reg, res], cmd_size, "load_value.truncate1");
		#emit_raw("band %s, %d;\n" % [reg, mask], cmd_size, "load_value.truncate2");
		#var tmp = alloc_temporary();
		#emit("mov ^%s, %s;\n" % [tmp, reg], cmd_size, "load_value.truncate3");
		#free_val(reg);
		#res = load_value(tmp);
	return res;

## makes the number smaller so that it fits in size_bytes
func truncate_number(num:int, size_bytes:int)->int:
	var max_b:int = 2**(8*size_bytes)-1;
	var res:int = sign(num)*min(abs(num), max_b);
	#print("truncate_number(%d, %d) = %d (max_b = %d)\n" % [num, size_bytes, res, max_b]);
	return res;

## returns the CPU-addressable string that yields the address of the value.
func address_value(val:String)->String:
	assert(val in IR.all_syms);
	var handle:IR_Value = IR.all_syms[val];
	var res:String = "";
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

func alloc_temporary()->String:
	var res:String = ""; #alloc_register();
	#if not res:
	#res = "EBP[%d]" % cur_stack_size;
	#cur_stack_size += 1;
	var ir_name:String = "tmp_%d" % val_idx; val_idx += 1;
	assert(ir_name not in IR.all_syms, "ir sym uid count broken");
	var handle:IR_Tmp = IR_Tmp.new(IR); #{"ir_name":ir_name, "val_type":"temporary", "data_type":"error", "data_size":4,"storage":"NULL", "is_array":0, "array_size":0};
	allocate_value(handle, cur_scope);
	cur_scope.vars.append(handle);
	#var N = len(all_syms);
	IR.all_syms[ir_name] = handle;
	#var M = len(all_syms);
	#assert(M > N, "watafak");
	res = ir_name;
	return res;

func emit_raw(text:String, wp_diff:int, dbg_trace:String)->void:
	if ADD_DEBUG_TRACE: cur_assy_block.code += "#%s\n" % dbg_trace.remove_chars("\n");
	cur_assy_block.code += text;
	cur_assy_block.write_pos += wp_diff;

func emit_comment(text:String)->void:
	if EMIT_COMMENTS: cur_assy_block.code += text;
	
## returns a CPU-addressable string that can be used to write into the value.
func store_val(val:String)->String:
	assert(val in IR.all_syms);
	var handle:IR_Value = IR.all_syms[val];
	var res:String;
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

func free_val(val:String)->void:
	if val in regs:
		regs_in_use[val] = false;
	else:
		pass;

func alloc_register(_where:String)->String:
	for reg in regs:
		if not reg in regs_in_use: regs_in_use[reg] = false;
		if not regs_in_use[reg]:
			regs_in_use[reg] = true; #where;
			return reg;
	assert(false, "Codegen: out of registers!");
	return "";

func allocate_vars()->void:
	for key in IR.scopes:
		var scope:Scope = IR.scopes[key];
		#var stack_pos = 0; # we will be placing local vars on the stack
		#var arg_pos = 0; # args are placed on the stack in the other direction
		scope.local_vars_count = 0;
		scope.local_vars_write_pos = to_local_pos(0);
		scope.args_count = 0;
		scope.args_write_pos = to_arg_pos(0);
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
	#for key in IR.code_blocks:
	#	var cb = IR.code_blocks[key];
	#	cb["val_type"] = "code";

func allocate_value(handle:IR_Value, scope:Scope)->void:
	var data_size:int = 4;
	if "is_array" in handle and int(handle.is_array):
		data_size *= int(handle.array_size);
	
	if handle.storage is String:
		if handle.storage == "NULL":
			var storage_type:String;
			var pos:int;
			if (handle.val_type == "immediate"):
				storage_type = "none";
				pos = 0;
			elif(scope.user_name == "global"): 
				storage_type = "global";
				pos = 0;
			else:
				storage_type = "stack";
				var wp:int = scope.local_vars_write_pos;
				#pos = to_local_pos(wp);
				pos = wp;
				if "is_array" in handle and int(handle.is_array):
					pos = pos-data_size;
				scope.local_vars_write_pos -= data_size;
				scope.local_vars_count += 1;
				assert(pos != 0);
			handle.storage = {"type":storage_type, "pos":pos};
		elif handle.storage == "extern":
			handle.storage = {"type":"extern", "pos":0};
		elif handle.storage == "arg":
			var wp:int = scope.args_write_pos;
			var pos:int = wp;
			handle.storage = {"type":"stack", "pos":pos};
			assert(handle.storage.pos != 0);
			scope.args_write_pos += data_size;
			scope.args_count += 1;
		else:
			push_error("codegen: allocate_vars: unknown storage type");
		handle["needs_deref"] = false;
	if handle not in scope.vars:
		scope.vars.append(handle);
	#print("alloc %s to %s: result %s" % [handle.ir_name, scope.ir_name, handle.storage]);

## defines a mapping between the input pos and stack pos for local vars of a function
func to_local_pos(pos:int)->int:
	return -3+pos;

## defines a mapping between the input pos and stack pos for arguments of a function
func to_arg_pos(pos:int)->int:
	return 9+pos;

func generate_cmd_return(cmd:IR_Cmd)->void:
	var loc:LocationRange = cmd.loc;
	mark_loc_begin(loc);
	if len(cmd.words) >= 2:
		var res:String = cmd.words[1];
		emit("mov EAX, $%s;\n" % res, cmd_size, "generate_cmd_return.arg");
	var scp_name:String = cur_scope.ir_name;
	emit_raw("__LEAVE_%s;\n" % scp_name, enter_leave_size, "generate_cmd_return.leave");
	if(WRITE_SHADOW): emit_raw("__SHADOW_LEAVE_%s\n" % scp_name, shadow_update_size, "generate_cmd_return.shadow");
	emit("ret;\n", cmd_size, "generate_cmd_return.ret");
	mark_loc_end(loc);

func generate_cmd_enter(cmd:IR_Cmd)->void:
	var scp_name:String = cmd.words[1];
	var loc:LocationRange = cmd.loc;
	mark_loc_begin(loc);
	enter_scope(IR.scopes[scp_name]);
	emit_raw("__ENTER_%s;\n" % scp_name, enter_leave_size, "generate_cmd_enter");
	if(WRITE_SHADOW): emit_raw("__SHADOW_ENTER_%s\n" % scp_name, shadow_update_size, "generate_cmd_enter.shadow");
	mark_loc_end(loc);
	
func generate_cmd_leave(cmd:IR_Cmd)->void:
	var scp_name:String = cur_scope.ir_name;
	var loc:LocationRange = cmd.loc;
	mark_loc_begin(loc);
	emit_raw("__LEAVE_%s;\n" % scp_name, enter_leave_size, "generate_cmd_leave");
	if(WRITE_SHADOW): emit_raw("__SHADOW_LEAVE_%s\n" % scp_name, shadow_update_size, "generate_cmd_leave.shadow");
	leave_scope();
	mark_loc_end(loc);

func generate_cmd_alloc(cmd:IR_Cmd)->void:
	var size:String = cmd.words[1];
	var res:String = cmd.words[2];
	var arr_storage:IR_array = IR_array.new(IR,size.to_int());#new_arr(size);
	allocate_value(arr_storage, cur_scope);
	cur_scope.vars.append(arr_storage);
	emit("mov ^%s @%s;\n" % [res, arr_storage.ir_name], cmd_size, "generate_cmd_alloc");

func generate_cmd_mov_arr(cmd:IR_Cmd)->void:
	var dest:String = cmd.words[1];
	var src:Array[String] = cmd.words.slice(3,-1);
	#var dest_handle:IR_Value = IR.all_syms[dest];
	#assert(int(dest_handle.is_array)==1)
	assert(cmd.words[2] == "[");
	assert(cmd.words[-1] == "]");
	#var tmp = alloc_temporary();
	#var imm_0 = new_imm(0);
	#var imm_4_handle = new_imm(4);
	#allocate_value(imm_4_handle, cur_scope);
	#var imm_4 = imm_4_handle.ir_name;
	#emit("sub %s, %s;\n" % [tmp, src.size()*4], cmd_size, "generate_cmd_mov_arr.offset");
	emit("sub ESP, 3;\n" , cmd_size, "generate_cmd_mov_arr.init");
	src.reverse();
	for i in range(src.size()):
		var val:String = src[i];
		var last:bool = false;
		if i+1 == src.size(): last = true;
		emit("mov *ESP, $%s;\n" % val, cmd_size, "generate_cmd_mov_arr.mov");
		if not last: emit("sub ESP, 4;\n" , cmd_size, "generate_cmd_mov_arr.inc");
	emit("mov $%s, ESP;\n" % dest, cmd_size, "generate_cmd_mov_arr.init");
	emit("sub ESP, 4;\n" , cmd_size, "generate_cmd_mov_arr.inc2");
	#free_val(tmp);

class ShadowMarker:
	var marker:int=0;
	var ir_name:String="";
	func _init(_marker=0,_ir_name=""):
		marker=_marker;
		ir_name=_ir_name;

class EmitCounter:
	var cur_offset:int=0;
	var n_emitted:int=0;

func calc_shadow_markers(scope)->Dictionary[int,ShadowMarker]:
	var markers:Dictionary[int,ShadowMarker] = {}
	#markers["markers"] = {};
	#markers["ir_names"] = {};
	#3. mark EBP and IP
	markers[1] = ShadowMarker.new(ISA.SHADOW_FRAME_PREV_EBP, "PREV_EBP");
	markers[5] = ShadowMarker.new(ISA.SHADOW_FRAME_PREV_IP, "PREV_IP");
	#markers.markers[1] = ISA.SHADOW_FRAME_PREV_EBP;
	#markers.ir_names[1] = "PREV_EBP";
	#markers.markers[5] = ISA.SHADOW_FRAME_PREV_IP;
	#markers.ir_names[5] = "PREV_IP";
	#4. mark arguments (ecx = number of arguments at time of call)
	#5. mark locals and temporaries according to their storage location within current scope
	for handle in scope.vars:
		if handle.val_type in "func": continue;
		if handle.storage.type == "stack":
			var marker:int = ISA.SHADOW_FRAME_VAR;
			if handle.val_type == "temporary":
				marker = ISA.SHADOW_FRAME_TEMP;
			assert(handle.storage.pos not in markers, "INTERNAL ERROR: stack location double-booked");
			var pos:int = handle.storage.pos;
			markers[pos] = ShadowMarker.new(marker,handle.ir_name);
			#markers.markers[pos] = marker;
			#markers.ir_names[pos] = handle.ir_name;
	return markers;

func flip_markers_when_leaving(markers)->void:
	for key in markers.markers:
		markers[key] = ISA.SHADOW_UNUSED;

func text_emit_shadow_frame_pointer(counters:EmitCounter)->String:
	var text:String = "";
	text += "mov eax, ebp;\n"
	text += "sub eax, %d;\n" % (65536 - SHADOW_STACK_ADR - counters.cur_offset);
	counters.n_emitted += 2;
	return text;

func text_emit_mark_shadow_positions(markers, positions, counters:EmitCounter)->String:
	var text:String = "";
	var first:bool = true;
	for pos in positions:
		var delta:int = pos - counters.cur_offset;
		if not first: 
			text += "add eax, %d;\n" % delta;
			counters.n_emitted += 1;
			counters.cur_offset += delta;	
		else: first = false;
		text += "mov *eax, %d;\n" % markers.markers[pos];
		text += "#g.s.e.u: EBP[%d] is SHADOW.%s called \"%s\"\n" % [pos, ISA.SHADOW_TO_STRING[markers.markers[pos]], markers.ir_names[pos]];
		counters.n_emitted += 1;	
	return text;

func verify_and_text_emit_padding(counters:EmitCounter)->String:
	var text:String = "";
	@warning_ignore("integer_division")
	var n_remaining:int = (shadow_update_size/cmd_size - counters.n_emitted);
	#7. assert false if out of space in the update block
	assert(n_remaining >= 0, "INTERNAL ERROR: shadow update size insufficient for this stack frame. Need %d bytes for %d commands" % [counters.n_emitted*cmd_size, counters.n_emitted]);
	#6. fill out remaining "update block" space with NOPs
	text += "nop;\n".repeat(n_remaining);
	return text;


func generate_shadow_update(scope, is_leaving)->String:
	var text:String = "";
	if is_leaving: text += "#-- SHADOW.leave begin\n";
	else: text += "#-- SHADOW.enter begin\n";
	var markers:Dictionary[int,ShadowMarker] = calc_shadow_markers(scope);
	if is_leaving: flip_markers_when_leaving(markers);
	var counters:EmitCounter = EmitCounter.new()#{"cur_offset":0, "n_emitted":0};
	var positions:Array[int] = markers.keys();
	if positions.size():
		positions.sort();
		counters.cur_offset = positions[0];
	#1. make a counter for how many unused bytes remain in the update block (=shadow_update_size)
	#2. get shadow stack frame pointer by shifting EBP from 65536 to SHADOW_STACK_ADR
	text += text_emit_shadow_frame_pointer(counters);
	text += text_emit_mark_shadow_positions(markers, positions, counters);
	text += verify_and_text_emit_padding(counters);
	if is_leaving: text += "#-- SHADOW.leave done\n";
	else: text += "#-- SHADOW.enter done\n";
	#8. return resulting block assembly text.
	return text;

func generate_shadow_enter_update(scope)->String:
	return generate_shadow_update(scope, false);

func generate_shadow_leave_update(scope)->String:
	return generate_shadow_update(scope, true);

func fixup_enter_leave(assy_block:AssyBlock)->void:
	for key in IR.scopes:
		var scope:Scope = IR.scopes[key];
		var scp_name:String = scope.ir_name;
		var stack_bytes:int = scope.local_vars_write_pos;
		var S:String = assy_block.code;
		S = S.replace("__ENTER_%s" % scp_name, "sub ESP, %d" % -stack_bytes);
		S = S.replace("__LEAVE_%s" % scp_name, "sub ESP, %d" % stack_bytes);
		if(WRITE_SHADOW):
			var shadow_enter_update:String = generate_shadow_enter_update(scope);
			var shadow_leave_update:String = generate_shadow_leave_update(scope);
			S = S.replace("__SHADOW_ENTER_%s" % scp_name, shadow_enter_update);
			S = S.replace("__SHADOW_LEAVE_%s" % scp_name, shadow_leave_update);
		assy_block.code = S;

func fixup_symtable(sym_table:Dictionary, task:Task)->void:
	fixup_symtable_scope(sym_table.global);
	task.work_units_total = sym_table.funcs.size()
	for key in sym_table.funcs:
		var fun:IR_func = sym_table.funcs[key];
		fixup_symtable_scope(fun);
		task.work_units_complete += 1;
	#print(sym_table);
	pass;

func fixup_symtable_scope(fun:IR_func)->void:
	for cat in [fun.args, fun.vars, fun.constants]:
		for h2 in cat: fixup_symtable_val(h2);

func fixup_symtable_val(val:IR_Value)->void:
	var sym:IR_Value = IR.all_syms[val.ir_name];
	match sym.storage.type:
		"global": val.pos = {"type":"global", "lbl":val.ir_name};
		"stack": val.pos = {"type":"stack", "pos":sym.storage.pos};
		"immediate": val.pos = {"type":"immediate", "val":sym.value};
		"none": val.pos = {"type":"immediate", "val":sym.value};
		_: assert(false, "unexpected sym storage type [%s]" % str(sym.storage.type));
	if val.user_name == null:
		val.pos["val"] = sym.value;

func mark_loc(loc:LocationRange, lmap:Dictionary, wp:int)->void:
	if wp not in lmap: lmap[wp] = [];
	lmap[wp].append(loc);

func mark_loc_begin(loc:LocationRange)->void:
	var wp:int = cur_assy_block.write_pos;
	var lmap:LocationMap = cur_assy_block.loc_map;
	n_locations += 1;
	mark_loc(loc, lmap.begin, wp);

func mark_loc_end(loc:LocationRange)->void:
	var wp:int = cur_assy_block.write_pos;
	var lmap:LocationMap = cur_assy_block.loc_map;
	mark_loc(loc, lmap.end, wp);

#func get_cb_cmd_size(cb_name):
#	var handle = all_syms[cb_name];
#	assert(handle.val_type == "code");
#	#res = generate_code_block(handle).code;
#	## Problem: code block isn't generated yet by the time we hit "emit"...
#	assert(handle.is_generated == true);
#	return handle.assy_block.write_pos;

func emit_cb(cb_name:String, msg:String)->void:
	var handle:IR_Value = IR.all_syms[cb_name];
	assert(handle.val_type == "code");
	var assy_block:AssyBlock = generate_code_block(handle);
	translate_ab_locations(assy_block.loc_map, cur_assy_block.write_pos);
	add_ab_locations(assy_block.loc_map);
	emit_raw("%s" % assy_block.code, assy_block.write_pos, msg);
	
	
## generate a location map offset by the current write pointer
func translate_ab_locations(loc_map:LocationMap, wp:int)->void:
	var dbg_len_in:int = len(loc_map.begin.keys());
	var loc_map_trans:LocationMap = LocationMap.new(); #{"begin":{}, "end":{}};
	var offs:int = wp; #cur_assy_block.write_pointer;
	#print("translate %d ips by offs %d: " % [dbg_len_in, offs]);
	for ip in loc_map.begin:
		translate_ab_loc(loc_map.begin, ip, loc_map_trans.begin, ip+offs);
	for ip in loc_map.end:
		translate_ab_loc(loc_map.end, ip, loc_map_trans.end, ip+offs);
	loc_map.begin.assign(loc_map_trans.begin);
	loc_map.end.assign(loc_map_trans.end);
	var dbg_len_out:int = len(loc_map.begin.keys());
	assert(dbg_len_out >= dbg_len_in);
## translate a single location and insert it into the destination map
func translate_ab_loc(src_lmap:Dictionary, src_ip:int, dest_lmap:Dictionary, dest_ip:int)->void:
	if not src_ip in src_lmap: 
		var new_arr:Array[LocationRange] = [];
		src_lmap[src_ip] = new_arr;
	var src_arr:Array[LocationRange] = src_lmap[src_ip];
	var len_src:int = len(src_arr);
	if not dest_ip in dest_lmap: 
		var new_arr:Array[LocationRange] = [];
		dest_lmap[dest_ip] = new_arr;
	var dest_arr:Array[LocationRange] = dest_lmap[dest_ip];
	var len_dst:int = len(dest_arr);
	dest_arr.append_array(src_arr);
	var len_out:int = len(dest_arr);
	assert(len_out == (len_src + len_dst));
	#print("   (ip %d->%d): src %d + dest %d = out %d" % [src_ip, dest_ip, len_src, len_dst, len_out]);

func add_ab_locations(loc_map_in:LocationMap)->void:
	for ip in loc_map_in.begin:
		translate_ab_loc(loc_map_in.begin, ip, cur_assy_block.loc_map.begin, ip);
	for ip in loc_map_in.end:
		translate_ab_loc(loc_map_in.end, ip, cur_assy_block.loc_map.end, ip);
	
