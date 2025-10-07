extends Node

signal IR_ready;
signal sig_user_error;
@export var IR:Node;
#----------- Anlysis ----------------------

const ast_bypass_list = ["start", "stmt_list", "stmt"];

func analyze(ast):
	IR.clear_IR();
	analyze_one(ast);
	IR_ready.emit(IR.IR);
	print(IR);
	IR.to_file("IR.txt");
	return IR;

func analyze_expr(ast):
	assert(ast.class == "expr");
	var ch = ast.children[0];
	match ch.class:
		"expr_infix": analyze_expr_infix(ch);
		"expr_postfix": analyze_expr_postfix(ch);
		"expr_immediate": analyze_expr_immediate(ch);
		"expr_ident": analyze_expr_ident(ch);
		"expr_call": analyze_expr_call(ch);
		_: push_error("analyze_expr: unimplemented expr type: "+ch.class);

func analyze_one(ast):
	if ast.class in ast_bypass_list:
		analyze_all(ast.children);
		return;
	
	if ast.class != "expr": expr_stack.clear();
	
	match ast.class:
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
		_: push_error("analyze: not implemented for class "+ast.class); return null;

func analyze_all(list):
	for ast in list: analyze_one(ast);

var expr_stack = [];
var control_flow_stack = []; #for break and continue

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

func analyze_expr_infix(ast):
	assert(ast.class == "expr_infix");
	var expr1 = ast.children[0];
	assert(expr1.class == "expr");
	var op = ast.children[1];
	var expr2 = ast.children[2];
	assert(expr2.class == "expr");
	
	if op.text in op_map: analyze_expr_infix_op(expr1, expr2, op_map[op.text]);
	else: push_error("analyze: expr op not implemented: "+op.text); return;

func analyze_expr_postfix(ast):
	assert(ast.class == "expr_postfix");
	var expr1 = ast.children[0];
	assert(expr1.class == "expr");
	var op = ast.children[1];
	
	if op.text in op_map: analyze_expr_postfix_op(expr1, op_map[op.text]);
	else: push_error("analyze: expr op not implemented: "+op.text); return;

func analyze_expr_infix_op(expr1, expr2, op):
	analyze_expr(expr1);
	analyze_expr(expr2);
	var arg2 = expr_stack.pop_back();
	var arg1 = expr_stack.pop_back();
	var res = IR.new_val_temp();
	IR.save_variable(res);
	IR.emit_IR(["OP", op, arg1, arg2, res]);
	expr_stack.push_back(res);

func analyze_expr_postfix_op(expr1, op):
	analyze_expr(expr1);
	var arg = expr_stack.pop_back();
	var res = IR.new_val_temp();
	IR.save_variable(res);
	IR.emit_IR(["OP", op, arg, IR.new_val_none(), res]);
	expr_stack.push_back(res);

func analyze_expr_call(ast):
	# expr_call -> expr ( ) or expr ( expr ) or expr ( expr_list )
	assert(ast.class == "expr_call");
	var expr1 = ast.children[0];
	assert(expr1.class == "expr");
	analyze_expr(expr1);
	var fun = expr_stack.pop_back();
	var args = [];
	if(ast.children[2].text != ")"):
		var expr = ast.children[2];
		while true:
			if expr.class == "expr_list":
				# expr_list -> (expr_list, expr) or (expr, expr)
				var expr_arg = expr.children[2];
				assert(expr_arg.class == "expr");
				analyze_expr(expr_arg);
				args.push_front(expr_stack.pop_back());
				expr = expr.children[0];
			elif expr.class == "expr":
				analyze_expr(expr);
				args.push_front(expr_stack.pop_back());
				break;
			else:
				push_error("analyzer: func_call: unexpected expr class");
				break;
	var res = IR.new_val_temp();
	IR.save_variable(res);
	IR.emit_IR(["CALL", fun, args, res]);
	expr_stack.push_back(res);

func analyze_expr_list(expr_list):
	assert(expr_list.class == "expr_list");
	var res = [];
	for expr in expr_list.children:
		analyze_expr(expr);
		res.append(expr_stack.pop_back());
	expr_stack.push_back(res);

func analyze_preproc_stmt(ast):
	assert(ast.class == "preproc_stmt");
	#push_error("analyze_stmt_preproc: unimplemented");
	pass;

func analyze_var_decl_stmt(ast):
	assert(ast.class == "var_decl_stmt");
	var tok_ident = ast.children[1];
	assert(tok_ident.class == "IDENT");
	var var_name = tok_ident.text;
	var var_handle = IR.new_val_var(var_name);
	IR.save_variable(var_handle);

func analyze_func_decl_stmt(ast):
	assert(ast.class == "func_decl_stmt");
	var expr_call = ast.children[1];
	assert(expr_call.class == "expr_call");
	var expr = expr_call.children[0];
	assert(expr.class == "expr");
	var expr_ident = expr.children[0];
	assert(expr_ident.class == "expr_ident");
	var tok_ident = expr_ident.children[0];
	assert(tok_ident.class == "IDENT");
	var fun_name = tok_ident.text;
	var fun_scp = IR.new_val_none();
	var fun_cb = IR.new_val_none();
	var fun_handle = IR.new_val_func(fun_name,fun_scp,fun_cb);
	IR.save_function(fun_handle);

func analyze_decl_extern_stmt(ast):
	assert(ast.class == "decl_extern_stmt");
	var decl = ast.children[1];
	if (decl.class == "var_decl_stmt"):
		var tok_ident = decl.children[1];
		assert(tok_ident.class == "IDENT");
		var var_name = tok_ident.text;
		var var_handle = IR.new_val_var(var_name);
		var_handle.storage = "extern";
		IR.save_variable(var_handle);
	elif (decl.class == "func_decl_stmt"):
		var tok_ident = decl.children[1].children[0].children[0].children[0];
		assert(tok_ident.class == "IDENT");
		var fun_name = tok_ident.text;
		var fun_handle = IR.new_val_func(fun_name, IR.new_val_none(), IR.new_val_none());
		fun_handle.storage = "extern";
		IR.save_function(fun_handle);
		

func analyze_decl_assignment(ast):
	# decl part
	assert(ast.class == "decl_assignment_stmt");
	var stmt_ass = ast.children[1];
	assert(stmt_ass.class == "assignment_stmt");
	var tok_ident = stmt_ass.children[0];
	assert(tok_ident.class == "IDENT");
	var var_name = tok_ident.text;
	var var_handle = IR.new_val_var(var_name);
	IR.save_variable(var_handle);
	# assign part
	analyze_one(stmt_ass);
	var arg = expr_stack.pop_back();
	var_handle.data_type = arg.data_type;

func analyze_while_stmt(ast):
	assert(ast.class == "while_stmt");
	var while_start = ast.children[0];
	assert(while_start.class == "while_start");
	var expr_cond = while_start.children[2];
	assert(expr_cond.class == "expr");
	var stmt_block = ast.children[1];
	assert(stmt_block.class == "block");
	
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
	assert(ast.class == "assignment_stmt");
	var LHS;
	var RHS;
	if ast.children[0].class == "IDENT":
		var tok_ident = ast.children[0];
		assert(tok_ident.class == "IDENT");
		var var_name = tok_ident.text;
		var var_handle = IR.get_var(var_name);
		LHS = var_handle;
	elif ast.children[0].class == "expr":
		var lhs_expr = ast.children[0];
		assert(lhs_expr.class == "expr");
		analyze_expr(lhs_expr);
		LHS = expr_stack.pop_back();
	else:
		assert(false);
	var rhs_expr = ast.children[2];
	assert(rhs_expr.class == "expr");
	analyze_expr(rhs_expr);
	var arg = expr_stack.pop_back();
	RHS = arg;
	IR.emit_IR(["MOV", LHS, RHS]);
	expr_stack.push_back(arg);

func analyze_expr_immediate(ast):
	assert(ast.class == "expr_immediate");
	var tok = ast.children[0];
	var value = null;
	var type = null;
	if tok.class == "NUMBER": 
		value = read_number(tok.text);
		if value is int: type = "int";
		if value is float: type = "float";
		value = str(value);
	if tok.class == "STRING":
		value = tok.text;
		type = "string";
	var res = IR.new_val_immediate(value, type);	
	IR.save_variable(res);
	expr_stack.push_back(res);

func read_number(text:String):
	if text.is_valid_int():
		return text.to_int();
	elif text.is_valid_float():
		return text.to_float();
	return null;

func analyze_expr_ident(ast):
	assert(ast.class == "expr_ident");
	var tok = ast.children[0];
	assert(tok.class == "IDENT");
	var var_name = tok.text;
	var var_handle = IR.get_var(var_name);
	if not var_handle:
		var_handle = IR.get_func(var_name);
	if not var_handle: 
		user_error("Identifier not found: ["+var_name+"]");
		var_handle = IR.new_val_error();
	expr_stack.push_back(var_handle);

func analyze_block(ast):
	# block -> { stmt_list } or { }
	assert(ast.class == "block");
	if ast.children[1].text != "}":
		var stmt_list = ast.children[1];
		assert(stmt_list.class == "stmt_list");
		analyze_one(stmt_list);

func user_error(msg):
	sig_user_error.emit(msg);

func analyze_if_stmt(ast):
	assert(ast.class == "if_stmt");
	var if_block = ast.children[0];
	if (if_block.class == "if_block"):
		analyze_if_block(if_block);
	elif (if_block.class == "if_else_block"):
		analyze_if_else_block(if_block);
	else:
		assert(false);

func analyze_if_block(ast):
	assert(ast.class == "if_block");
	var tok_start = ast.children[0];
	var cond = null;
	var block = null;
	var is_elif = false;
	if tok_start.text == "if":
		cond = ast.children[2];
		block = ast.children[4];
	elif tok_start.class == "if_block":
		var tok_elif = ast.children[1];
		assert(tok_elif.text == "elif"); 
		analyze_if_block(tok_start);
		cond = ast.children[3];
		block = ast.children[5];
		is_elif = true;
	elif ast.children[1].text == ";":
		pass;
	else:
		push_error("analyze: broken if-else block");
		
	assert(cond.class == "expr");
	assert(block.class == "block");
	
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
	assert(ast.class == "if_else_block");
	var if_block = ast.children[0];
	assert(if_block.class == "if_block");
	var block = ast.children[2];
	assert(block.class == "block");
	analyze_if_block(if_block);
	
	var ocb = IR.push_code_block();
	analyze_block(block);
	var code_block = IR.pop_code_block(ocb);
	IR.emit_IR(["ELSE", code_block]);

func analyze_func_def_stmt(ast):
	assert(ast.class == "func_def_stmt");
	var tok_func = ast.children[0];
	assert(tok_func.text == "func");
	var expr_call = ast.children[1];
	assert(expr_call.class == "expr_call");
	var block = ast.children[2];
	assert(block.class == "block");
	
	var tok_ident = expr_call.children[0].children[0].children[0];
	assert(tok_ident.class == "IDENT");
	var fun_name = tok_ident.text;
	
	var arg_names = [];
	if expr_call.children[2].text != ")":
		var expr = expr_call.children[2];
		while true:
			if expr.class == "expr_list":
				var arg = expr.children[2].children[0].children[0];
				assert(arg.class == "IDENT");
				arg_names.push_front(arg.text);
				expr = expr.children[0];
			elif expr.class == "expr":
				var arg = expr.children[0].children[0];
				assert(arg.class == "IDENT");
				arg_names.push_front(arg.text);
				break;
			else:
				push_error("analyzer: func_def: unexpected expr class");
				break;
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
	
func analyze_flow_stmt(ast):
	assert(ast.class == "flow_stmt");
	var cmd = ast.children[0];
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
				user_error("'Continue' statement outside of a loop");
				return;
		"return":
			if len(ast.children) == 2:
				var expr = ast.children[1];
				assert(expr.class == "expr");
				analyze_expr(expr);
				var res = expr_stack.pop_back();
				IR.emit_IR(["RETURN", res]);
			else:
				IR.emit_IR(["RETURN"]);
		
