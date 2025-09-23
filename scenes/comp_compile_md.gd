extends Node

var cur_filename: set=set_cur_filename;
var cur_path: set=set_cur_path;
@onready var tokenizer = $tokenizer_md;
const lang = preload("res://scenes/lang_md.gd");
signal tokens_ready;
signal parse_ready;
signal IR_ready;
signal sig_user_error;

func compile(text):
	var tokens = tokenizer.tokenize(text);
	if not tokens: return;
	var ast = parse(tokens);
	if not ast: return;
	var _IR = analyze(ast);
	#print(tokens);

func _on_tokenizer_md_tokens_ready(tokens) -> void:
	tokens_ready.emit(tokens);

func set_cur_filename(val): tokenizer.cur_filename = val;
func set_cur_path(val): tokenizer.cur_path = val;

#-------- Parser ---------------------

# LR(1) shift-reduce parser, always applies the first valid rule
func parse(tokens:Array):
	tokens = tokens.duplicate();
	tokens.append({"class":"EOF", "text":""});
	var stack = [];
	#tok is the look-ahead token
	for tok in tokens:
		var stabilized = false;
		while not stabilized:
			stabilized = true;
			for rule in lang.rules:
				if rule_matches(stack, tok, rule):
					if rule[-1] == "SHIFT": break; #(with stabilized == true)
					apply_rule(stack, rule);
					stabilized = false;
					break;
		dbg_print("PARSE","SHIFT "+str(tok)+"\n");
		if tok.class != "EOF": stack.push_back(tok);
	parse_ready.emit(stack);
	# parsed all tokens
	if len(stack) == 1:
		if stack[0].class != "start":
			push_error("snippet is not a valid program");
		return stack[0];
	elif len(stack) == 0:
		push_error("no input");
		return false;
	else:
		push_error("syntax error");
		return false;

var run_i = 0;

func rule_matches(stack:Array, tok_lookahead, rule:Array):
	#var rule_result = rule[-1];
	var rule_lookahead = rule[-2];
	var rule_input = rule.slice(0,-2);
	if len(stack) < len(rule_input): return false;
	var stack_input = stack.slice(-len(rule_input));
	dbg_print("PARSE","Rule matches? "+"(test "+str(run_i)+")"+"\n"+stack_to_str(stack_input,"\t\t") + "\n\tvs\n"+stack_to_str(rule_input,"\t\t")+"\n\t. "+str(tok_lookahead)+" vs "+str(rule_lookahead));
	run_i += 1;
	if not token_match(tok_lookahead, rule_lookahead): 
		dbg_print("PARSE","\tNo\n");
		return false;
	for i in range(len(rule_input)):
		if not token_match(stack_input[i], rule_input[i]): 
			dbg_print("PARSE","\tNo\n")
			return false;
	dbg_print("PARSE","\tYES\n");
	return true;

func token_match(tok, ref:String):
	if ref == "*": 
		return true;
	if ref[0] == "/": 
		return ref.substr(1) == tok.text;
	return ref == tok.class;

func apply_rule(stack:Array, rule:Array):
	var toks = [];
	for i in range(len(rule)-2):
		toks.append(stack.pop_back());
	toks.reverse();
	var new_tok = {"class":rule[-1], "text":""};
	dbg_print("PARSE","REDUCE "+str(new_tok)+"\n");
	new_tok["children"] = toks;
	stack.append(new_tok);


func stack_to_str(stack:Array, prefix:String):
	var text:String = "";
	for tok in stack:
		if tok is String:
			text += prefix + "["+tok+"]" + "\n";
		else:
			text += prefix + "["+tok.class + ":"+tok.text+"]"+"\n";
	text = text.erase(len(text)-1); #remove the last \n
	return text;

var dbg_to_console = false;
var dbg_to_file = true;
var dbg_filename = "log.txt";
var dbg_fp = FileAccess.open(dbg_filename, FileAccess.WRITE);
var dbg_prints_enabled = [
	#"TOKENIZE",
	"PARSE",
	#"ANALYZE",
];

func dbg_print(print_class, msg):
	if print_class in dbg_prints_enabled: 
		if dbg_to_console:	print(msg);
		if dbg_to_file: dbg_fp.store_line(msg);
#-------------------------------------
#----------- Anlysis ----------------------

const ast_bypass_list = ["start", "stmt_list", "stmt"];
var IR = null;
var cur_scope = null;
var cur_code_block = null;

func clear_IR():
	IR = {
		"code_blocks":[[]],
		"scopes":{
			"global":{
				"parent":null,
				"vars":[],
				"funcs":[],
			},
		}
	};
	cur_scope = IR.scopes.global;
	cur_code_block = IR.code_blocks[0];

func analyze(ast):
	clear_IR();
	analyze_one(ast);
	IR_ready.emit(IR);
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
	var res = new_val_temp();
	emit_IR(["OP", op, arg1, arg2, res]);

func analyze_expr_postfix_op(expr1, op):
	analyze_expr(expr1);
	var arg = expr_stack.pop_back();
	var res = new_val_temp();
	emit_IR(["OP", op, arg, null, res]);

func emit_IR(cmd:Array):
	#IR.commands.append(cmd);
	cur_code_block.append(cmd);
	
func analyze_expr_call(expr1, expr2):
	analyze_expr(expr1);
	analyze_expr(expr2);
	var args = expr_stack.pop_back();
	var fun = expr_stack.pop_back();
	var res = new_val_temp();
	emit_IR(["CALL", fun, args, res]);

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
	var var_handle = new_val_var(var_name);
	cur_scope.vars.append(var_handle);
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
	
	var ocb = push_code_block();
	analyze_one(expr_cond);
	var code_condition = pop_code_block(ocb);
	
	ocb = push_code_block();
	var arg = expr_stack.pop_back();
	analyze_one(stmt_block);
	var code_block = pop_code_block(ocb);
	
	emit_IR(["WHILE", code_condition, arg, code_block]);

func push_code_block(new_block=null):
	var old_cb = cur_code_block;
	if not new_block: 
		new_block = [];
		IR.code_blocks.append(new_block);
	cur_code_block = new_block;
	return old_cb;

func pop_code_block(old_block):
	var popped_block = cur_code_block;
	cur_code_block = old_block;
	return popped_block;

func analyze_assignment_stmt(ast):
	assert(ast.class == "assignment_stmt");
	var tok_ident = ast.children[0];
	assert(tok_ident.class == "IDENT");
	var expr = ast.children[2];
	assert(expr.class == "expr");
	var var_name = tok_ident.text;
	var var_handle = get_var(var_name);
	analyze_one(expr);
	var arg = expr_stack.pop_back();
	emit_IR(["MOV", var_handle, arg]);
	expr_stack.push_back(arg);

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
	var res = new_val_immediate(value, type);	
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
	var var_handle = get_var(var_name);
	if not var_handle:
		var_handle = get_func(var_name);
	if not var_handle: 
		user_error("Identifier not found: ["+var_name+"]");
		var_handle = new_val_error();
	expr_stack.push_back(var_handle);

func analyze_block(ast):
	assert(ast.class == "block");
	var stmt_list = ast.children[1];
	assert(stmt_list.class == "stmt_list");
	analyze_one(stmt_list);

func user_error(msg):
	sig_user_error.emit(msg);
