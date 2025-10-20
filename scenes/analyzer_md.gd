extends Node

signal IR_ready;
signal sig_user_error;
@export var IR:Node;
@export var erep:ErrorReporter;
#----------- Anlysis ----------------------

# error reporter support
#signal sig_highlight_line(line);
signal sig_cprint(msg, col);
@export var Editor:Node;

func cprint(msg): sig_cprint.emit(msg, null);
# constants
const ast_bypass_list = ["start", "stmt_list", "stmt"];

const  op_map = {
	"+":"ADD",
	"-":"SUB",
	"*":"MUL",
	"/":"DIV",
	"%":"MOD",
	"[":"INDEX",
	">":"GREATER",
	"<":"LESS",
	"==":"EQUAL",
	"!=":"NOT_EQUAL",
	"&&":"AND",
	"||":"OR",
	"!":"NOT",
	"and":"AND",
	"or":"OR",
	"not":"NOT",
	"&":"B_AND",
	"|":"B_OR",
	"^":"B_XOR",
	">>":"B_SHIFT_RIGHT",
	"<<":"B_SHIFT_LEFT",
	"~":"B_NOT",
	"++":"INC",
	"--":"DEC",
};

# state
var error_code = "";
var cur_line = "";
var cur_line_idx = 0;
var expr_stack = [];
var control_flow_stack = []; #for break and continue

func reset():
	error_code = "";
	cur_line = "";
	cur_line_idx = 0;
	expr_stack = [];
	control_flow_stack = [];

func analyze(ast):
	reset();
	erep.proxy = self;
	error_code = "";
	IR.clear_IR();
	analyze_one(ast);
	IR_ready.emit(IR.IR);
	#print(IR);
	IR.to_file("IR.txt");
	return IR;

func user_error(msg):
	#error_code = msg;
	#push_error(msg);
	sig_user_error.emit(msg);

func internal_error(msg):
	user_error(msg); #still gotta emit the signal so that compiler knows to stop
#	error_code = msg;
#	push_error(msg);
#	# no sig_user_error

func analyze_expr(ast):
	assert(ast.tok_class == "expr");
	var ch = ast.children[0];
	match ch.tok_class:
		"expr_infix": analyze_expr_infix(ch);
		"expr_postfix": analyze_expr_postfix(ch);
		"expr_immediate": analyze_expr_immediate(ch);
		"expr_ident": analyze_expr_ident(ch);
		"expr_call": analyze_expr_call(ch);
		"expr_parenthesis": analyze_expr_parenthesis(ch);
		_: internal_error(E.ERR_22 % ch.tok_class); return;

func analyze_expr_parenthesis(ast):
	assert(ast.tok_class == "expr_parenthesis");
	var expr = ast.children[1];
	assert(expr.tok_class == "expr");
	analyze_expr(expr);

func analyze_one(ast):
	if error_code != "": return;
	if ast.tok_class in ast_bypass_list:
		analyze_all(ast.children);
		return;
	
	if ast.tok_class != "expr": expr_stack.clear();
	
	match ast.tok_class:
		"preproc_stmt": analyze_preproc_stmt(ast);
		"var_decl_stmt": analyze_var_decl_stmt(ast);
		"func_decl_stmt": analyze_func_decl_stmt(ast);
		"decl_assignment_stmt": analyze_decl_assignment(ast);
		"assignment_stmt": analyze_assignment_stmt(ast);
		"decl_extern_stmt": analyze_decl_extern_stmt(ast);
		"if_stmt": analyze_if_stmt(ast);
		"func_def_stmt": analyze_func_def_stmt(ast);
		"expr": analyze_expr(ast);
		"while_stmt": analyze_while_stmt(ast);
		"block": analyze_block(ast);
		"flow_stmt": analyze_flow_stmt(ast);
		"PUNCT": pass;
		_: internal_error(E.ERR_23 % ast.tok_class); return;

func analyze_all(list):
	if error_code != "": return;
	for ast in list: analyze_one(ast);

func analyze_expr_infix(ast):
	if error_code != "": return;
	assert(ast.tok_class == "expr_infix");
	var expr1 = ast.children[0];
	assert(expr1.tok_class == "expr");
	var op = ast.children[1];
	var expr2 = ast.children[2];
	assert(expr2.tok_class == "expr");
	#var erep = ErrorReporter.new(self, op);
	erep.context = op;
	if op.text in op_map: analyze_expr_infix_op(expr1, expr2, op_map[op.text]);
	else: erep.error(E.ERR_31 % op.text); return;
	return;

func analyze_expr_postfix(ast):
	if error_code != "": return;
	assert(ast.tok_class == "expr_postfix");
	var expr1 = ast.children[0];
	assert(expr1.tok_class == "expr");
	var op = ast.children[1];
	
	if op.text in op_map: analyze_expr_postfix_op(expr1, op_map[op.text]);
	else: internal_error(E.ERR_25 % op.text); return;

func analyze_expr_infix_op(expr1, expr2, op):
	if error_code != "": return;
	analyze_expr(expr1);
	analyze_expr(expr2);
	var arg2 = expr_stack.pop_back();
	var arg1 = expr_stack.pop_back();
	var res = IR.new_val_temp();
	IR.save_variable(res);
	IR.emit_IR(["OP", op, arg1, arg2, res]);
	expr_stack.push_back(res);

func analyze_expr_postfix_op(expr1, op):
	if error_code != "": return;
	analyze_expr(expr1);
	var arg = expr_stack.pop_back();
	var res = IR.new_val_temp();
	IR.save_variable(res);
	IR.emit_IR(["OP", op, arg, IR.new_val_none(), res]);
	expr_stack.push_back(res);

func analyze_expr_call(ast):
	if error_code != "": return;
	# expr_call -> expr ( ) or expr ( expr ) or expr ( expr_list )
	assert(ast.tok_class == "expr_call");
	var expr1 = ast.children[0];
	assert(expr1.tok_class == "expr");
	analyze_expr(expr1);
	var fun = expr_stack.pop_back();
	var args = [];
	if(ast.children[2].text != ")"):
		var expr = ast.children[2];
		if expr.tok_class == "expr":
			analyze_expr(expr);
			args.push_front(expr_stack.pop_back());
		elif expr.tok_class == "expr_list":
			for sub_expr in expr.children:
				assert(sub_expr.tok_class == "expr");
				analyze_expr(sub_expr);
				args.push_front(expr_stack.pop_back()); 
		else:
			internal_error(E.ERR_26); return;
	var res = IR.new_val_temp();
	IR.save_variable(res);
	IR.emit_IR(["CALL", fun, args, res]);
	expr_stack.push_back(res);

func analyze_expr_list(expr_list):
	if error_code != "": return;
	assert(expr_list.tok_class == "expr_list");
	var res = [];
	for expr in expr_list.children:
		analyze_expr(expr);
		res.append(expr_stack.pop_back());
	expr_stack.push_back(res);

func analyze_preproc_stmt(ast):
	if error_code != "": return;
	assert(ast.tok_class == "preproc_stmt");
	pass;

func analyze_var_decl_stmt(ast):
	if error_code != "": return;
	assert(ast.tok_class == "var_decl_stmt");
	var tok_ident = ast.children[1];
	assert(tok_ident.tok_class == "IDENT");
	var var_name = tok_ident.text;
	var var_handle = IR.new_val_var(var_name);
	IR.save_variable(var_handle);

func analyze_func_decl_stmt(ast):
	if error_code != "": return;
	assert(ast.tok_class == "func_decl_stmt");
	var expr_call = ast.children[1];
	assert(expr_call.tok_class == "expr_call");
	var expr = expr_call.children[0];
	assert(expr.tok_class == "expr");
	var expr_ident = expr.children[0];
	assert(expr_ident.tok_class == "expr_ident");
	var tok_ident = expr_ident.children[0];
	assert(tok_ident.tok_class == "IDENT");
	var fun_name = tok_ident.text;
	var fun_scp = IR.new_val_none();
	var fun_cb = IR.new_val_none();
	var fun_handle = IR.new_val_func(fun_name,fun_scp,fun_cb);
	IR.save_function(fun_handle);

func analyze_decl_extern_stmt(ast):
	if error_code != "": return;
	assert(ast.tok_class == "decl_extern_stmt");
	var decl = ast.children[1];
	if (decl.tok_class == "var_decl_stmt"):
		var tok_ident = decl.children[1];
		assert(tok_ident.tok_class == "IDENT");
		var var_name = tok_ident.text;
		var var_handle = IR.new_val_var(var_name);
		var_handle.storage = "extern";
		IR.save_variable(var_handle);
	elif (decl.tok_class == "func_decl_stmt"):
		var tok_ident = decl.children[1].children[0].children[0].children[0];
		assert(tok_ident.tok_class == "IDENT");
		var fun_name = tok_ident.text;
		var fun_handle = IR.new_val_func(fun_name, IR.new_val_none(), IR.new_val_none());
		fun_handle.storage = "extern";
		IR.save_function(fun_handle);
		

func analyze_decl_assignment(ast):
	if error_code != "": return;
	# decl part
	assert(ast.tok_class == "decl_assignment_stmt");
	var stmt_ass = ast.children[1];
	assert(stmt_ass.tok_class == "assignment_stmt");
	#var tok_ident = stmt_ass.children[0];
	#assert(tok_ident.tok_class == "IDENT");
	var expr_lhs = stmt_ass.children[0];
	assert(expr_lhs.tok_class == "expr");
	var var_name = "";
	#var var_type = null;
	var expr_lhs_2 = expr_lhs.children[0];
	match expr_lhs_2.tok_class:
		"expr_ident":
			var tok_ident = expr_lhs_2.children[0];
			assert(tok_ident.tok_class == "IDENT");
			var_name = tok_ident.text;
		_: user_error(E.ERR_32 % expr_lhs_2.tok_class);
	
	#var var_name = tok_ident.text;
	var var_handle = IR.new_val_var(var_name);
	IR.save_variable(var_handle);
	# assign part
	analyze_one(stmt_ass);
	var arg = expr_stack.pop_back();
	var_handle.data_type = arg.data_type;

func analyze_while_stmt(ast):
	if error_code != "": return;
	assert(ast.tok_class == "while_stmt");
	var while_start = ast.children[0];
	assert(while_start.tok_class == "while_start");
	var expr_cond = while_start.children[2];
	assert(expr_cond.tok_class == "expr");
	var stmt_block = ast.children[1];
	assert(stmt_block.tok_class == "block");
	
	var label_next = IR.new_val_lbl("while_next");
	var label_end = IR.new_val_lbl("while_end");
	control_flow_stack.push_back({"type":"while", "next":label_next, "end":label_end});
	var ocb = IR.push_code_block();
	analyze_expr(expr_cond);
	var arg = expr_stack.pop_back();
	var code_condition = IR.pop_code_block(ocb);
	
	ocb = IR.push_code_block();
	analyze_one(stmt_block);
	var code_block = IR.pop_code_block(ocb);
	control_flow_stack.pop_back();
	IR.emit_IR(["WHILE", code_condition, arg, code_block, label_next, label_end]);


func analyze_assignment_stmt(ast):
	if error_code != "": return;
	assert(ast.tok_class == "assignment_stmt");
	var LHS;
	var RHS;
	if ast.children[0].tok_class == "IDENT":
		var tok_ident = ast.children[0];
		assert(tok_ident.tok_class == "IDENT");
		var var_name = tok_ident.text;
		var var_handle = IR.get_var(var_name);
		LHS = var_handle;
	elif ast.children[0].tok_class == "expr":
		var lhs_expr = ast.children[0];
		assert(lhs_expr.tok_class == "expr");
		analyze_expr(lhs_expr);
		LHS = expr_stack.pop_back();
	else:
		assert(false);
	var rhs_expr = ast.children[2];
	assert(rhs_expr.tok_class == "expr");
	analyze_expr(rhs_expr);
	var arg = expr_stack.pop_back();
	RHS = arg;
	IR.emit_IR(["MOV", LHS, RHS]);
	expr_stack.push_back(arg);

func analyze_expr_immediate(ast):
	if error_code != "": return;
	assert(ast.tok_class == "expr_immediate");
	var tok = ast.children[0];
	var value = null;
	var type = null;
	if tok.tok_class == "NUMBER": 
		value = read_number(tok.text);
		if value is int: type = "int";
		if value is float: type = "float";
		value = str(value);
	if tok.tok_class == "STRING":
		value = tok.text;
		type = "string";
	var res = IR.new_val_immediate(value, type);	
	IR.save_variable(res);
	expr_stack.push_back(res);

func read_number(text:String):
	if error_code != "": return;
	if text.is_valid_int():
		return text.to_int();
	elif text.is_valid_float():
		return text.to_float();
	return null;

func analyze_expr_ident(ast):
	if error_code != "": return;
	assert(ast.tok_class == "expr_ident");
	var tok = ast.children[0];
	assert(tok.tok_class == "IDENT");
	#var erep = ErrorReporter.new(self, tok);
	erep.context = tok;
	var var_name = tok.text;
	var var_handle = IR.get_var(var_name);
	if not var_handle:
		var_handle = IR.get_func(var_name);
	if not var_handle: 
		erep.error(E.ERR_29 % var_name);
		var_handle = IR.new_val_error();
	expr_stack.push_back(var_handle);

func analyze_block(ast):
	if error_code != "": return;
	# block -> { stmt_list } or { }
	assert(ast.tok_class == "block");
	if ast.children[1].text != "}":
		var stmt_list = ast.children[1];
		assert(stmt_list.tok_class == "stmt_list");
		analyze_one(stmt_list);

func analyze_if_stmt(ast):
	if error_code != "": return;
	assert(ast.tok_class == "if_stmt");
	var if_block = ast.children[0];
	if (if_block.tok_class == "if_block"):
		analyze_if_block(if_block);
	elif (if_block.tok_class == "if_else_block"):
		analyze_if_else_block(if_block);
	else:
		assert(false);

func analyze_if_block(ast):
	if error_code != "": return;
	assert(ast.tok_class == "if_block");
	var tok_start = ast.children[0];
	var cond = null;
	var block = null;
	var is_elif = false;
	if tok_start.text == "if":
		cond = ast.children[2];
		block = ast.children[4];
	elif tok_start.tok_class == "if_block":
		var tok_elif = ast.children[1];
		assert(tok_elif.text == "elif"); 
		analyze_if_block(tok_start);
		cond = ast.children[3];
		block = ast.children[5];
		is_elif = true;
	elif ast.children[1].text == ";":
		pass;
	else:
		internal_error(E.ERR_27); return;
		
	assert(cond.tok_class == "expr");
	assert(block.tok_class == "block");
	
	var ocb = IR.push_code_block();
	analyze_expr(cond);
	var arg = expr_stack.pop_back();
	var code_cond = IR.pop_code_block(ocb);
	
	ocb = IR.push_code_block();
	analyze_block(block);
	var code_block = IR.pop_code_block(ocb);
	
	var cmd = "IF"; if is_elif: cmd = "ELSE_IF";
	
	IR.emit_IR([cmd, code_cond, arg, code_block]);

func analyze_if_else_block(ast):
	if error_code != "": return;
	assert(ast.tok_class == "if_else_block");
	var if_block = ast.children[0];
	assert(if_block.tok_class == "if_block");
	var block = ast.children[2];
	assert(block.tok_class == "block");
	analyze_if_block(if_block);
	
	var ocb = IR.push_code_block();
	analyze_block(block);
	var code_block = IR.pop_code_block(ocb);
	IR.emit_IR(["ELSE", code_block]);

func analyze_func_def_stmt(ast):
	if error_code != "": return;
	assert(ast.tok_class == "func_def_stmt");
	var tok_func = ast.children[0];
	assert(tok_func.text == "func");
	var expr_call = ast.children[1];
	assert(expr_call.tok_class == "expr_call");
	var block = ast.children[2];
	assert(block.tok_class == "block");
	
	var tok_ident = expr_call.children[0].children[0].children[0];
	assert(tok_ident.tok_class == "IDENT");
	var fun_name = tok_ident.text;
	
	var arg_names = [];
	if expr_call.children[2].text != ")":
		var expr = expr_call.children[2];
		if expr.tok_class == "expr":
			analyze_func_def_arg_expr(expr, arg_names);
		elif expr.tok_class == "expr_list":
			for expr2 in expr.children:
				assert(expr2.tok_class == "expr");
				analyze_func_def_arg_expr(expr2, arg_names);
		else:
			internal_error(E.ERR_28); return;
		#while true:
			#if expr.tok_class == "expr_list":
				#var arg = expr.children[2].children[0].children[0];
				#assert(arg.tok_class == "IDENT");
				#arg_names.push_front(arg.text);
				#expr = expr.children[0];
			#elif expr.tok_class == "expr":
				#var arg = expr.children[0].children[0];
				#assert(arg.tok_class == "IDENT");
				#arg_names.push_front(arg.text);
				#break;
			#else:
				#internal_error(E.ERR_28); return;
	var ocb = IR.push_code_block();
	var osc = IR.push_scope();
	IR.emit_IR(["ENTER", IR.cur_scope.ir_name]);
	for arg_name in arg_names:
		var arg_handle = IR.new_val_var(arg_name);
		arg_handle.storage = "arg";
		IR.save_variable(arg_handle);
	analyze_block(block);
	IR.emit_IR(["LEAVE"]);
	var fun_scope = IR.pop_scope(osc);
	var fun_code = IR.pop_code_block(ocb);
	var fun_handle = IR.get_func(fun_name);
	if fun_handle:
		fun_handle.code = fun_code.ir_name;
		fun_handle.scope = fun_scope.ir_name;
	else:
		fun_handle = IR.new_val_func(fun_name, fun_scope, fun_code);
		IR.save_function(fun_handle);

func analyze_func_def_arg_expr(expr, arg_names):
	assert(expr.tok_class == "expr");
	var sub_expr = expr.children[0];
	match sub_expr.tok_class:
		"expr_ident":
			var tok_ident = sub_expr.children[0];
			arg_names.push_front(tok_ident.text);
		_: internal_error(E.ERR_28); return;

func analyze_flow_stmt(ast):
	if error_code != "": return;
	assert(ast.tok_class == "flow_stmt");
	var cmd = ast.children[0];
	#var erep = ErrorReporter.new(self, cmd);
	erep.context = cmd;
	match cmd.text:
		"break":
			if len(control_flow_stack):
				var cur_loop = control_flow_stack.back();
				IR.emit_IR(["GOTO", cur_loop.end]);
		"continue":
			if len(control_flow_stack):
				var cur_loop = control_flow_stack.back();
				IR.emit_IR(["GOTO", cur_loop.next]);
			else:
				erep.error(E.ERR_30);
				return;
		"return":
			if len(ast.children) == 2:
				var expr = ast.children[1];
				assert(expr.tok_class == "expr");
				analyze_expr(expr);
				var res = expr_stack.pop_back();
				IR.emit_IR(["RETURN", res]);
			else:
				IR.emit_IR(["RETURN"]);
		
