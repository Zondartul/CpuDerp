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
	return IR;

func analyze_expr(ast):
	assert(ast.class == "expr");
	var ch = ast.children[0];
	match ch.class:
		"expr_infix": analyze_expr_infix(ch);
		"expr_postfix": analyze_expr_postfix(ch);
		"expr_immediate": analyze_expr_immediate(ch);
		"expr_ident": analyze_expr_ident(ch);
		_: push_error("analyze_expr: unimplemented expr type");

func analyze_one(ast):
	if ast.class in ast_bypass_list:
		analyze_all(ast.children);
		return;
	
	match ast.class:
		"stmt_preproc": analyze_stmt_preproc(ast);
		"decl_assignment_stmt": analyze_decl_assignment(ast);
		"assignment_stmt": analyze_assignment_stmt(ast);
		"expr": analyze_expr(ast);
		"while_stmt": analyze_while_stmt(ast);
		"block": analyze_block(ast);
		"PUNCT": pass;
		_: push_error("analyze: not implemented for class "+ast.class); return null;

func analyze_all(list):
	for ast in list: analyze_one(ast);

var expr_stack = [];


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
	
	if op.text == "(": analyze_expr_call(expr1, expr2);
	elif op.text in op_map: analyze_expr_infix_op(expr1, expr2, op_map[op.text]);
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
	IR.emit_IR(["OP", op, arg1, arg2, res]);

func analyze_expr_postfix_op(expr1, op):
	analyze_expr(expr1);
	var arg = expr_stack.pop_back();
	var res = IR.new_val_temp();
	IR.emit_IR(["OP", op, arg, null, res]);


func analyze_expr_call(expr1, expr2):
	analyze_expr(expr1);
	analyze_expr(expr2);
	var args = expr_stack.pop_back();
	var fun = expr_stack.pop_back();
	var res = IR.new_val_temp();
	IR.emit_IR(["CALL", fun, args, res]);

func analyze_expr_list(expr_list):
	assert(expr_list.class == "expr_list");
	var res = [];
	for expr in expr_list.children:
		analyze_expr(expr);
		res.append(expr_stack.pop_back());
	expr_stack.push_back(res);

func analyze_stmt_preproc(ast):
	assert(ast.class == "stmt_preproc");
	push_error("analyze_stmt_preproc: unimplemented");
	
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
	var_handle.type = arg.type;

func analyze_while_stmt(ast):
	assert(ast.class == "while_stmt");
	var while_start = ast.children[0];
	assert(while_start.class == "while_start");
	var expr_cond = while_start.children[2];
	assert(expr_cond.class == "expr");
	var stmt_block = ast.children[1];
	assert(stmt_block.class == "block");
	
	var ocb = IR.push_code_block();
	analyze_one(expr_cond);
	var code_condition = IR.pop_code_block(ocb);
	
	ocb = IR.push_code_block();
	var arg = expr_stack.pop_back();
	analyze_one(stmt_block);
	var code_block = IR.pop_code_block(ocb);
	
	IR.emit_IR(["WHILE", code_condition, arg, code_block]);


func analyze_assignment_stmt(ast):
	assert(ast.class == "assignment_stmt");
	var tok_ident = ast.children[0];
	assert(tok_ident.class == "IDENT");
	var expr = ast.children[2];
	assert(expr.class == "expr");
	var var_name = tok_ident.text;
	var var_handle = IR.get_var(var_name);
	analyze_one(expr);
	var arg = expr_stack.pop_back();
	IR.emit_IR(["MOV", var_handle, arg]);
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
	if tok.class == "STRING":
		value = tok.text;
		type = "string";
	var res = IR.new_val_immediate(value, type);	
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
	assert(ast.class == "block");
	var stmt_list = ast.children[1];
	assert(stmt_list.class == "stmt_list");
	analyze_one(stmt_list);

func user_error(msg):
	sig_user_error.emit(msg);
