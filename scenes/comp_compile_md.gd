extends Node

var cur_filename: set=set_cur_filename;
var cur_path: set=set_cur_path;
@onready var tokenizer = $tokenizer_md;
const lang = preload("res://scenes/lang_md.gd");
signal tokens_ready;
signal parse_ready;
signal IR_ready;

func compile(text):
	var tokens = tokenizer.tokenize(text);
	var ast = parse(tokens);
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

func clear_IR():
	IR = {
		"commands":[],
	};

func analyze(ast):
	clear_IR();
	analyze_one(ast);
	IR_ready.emit(IR);
	return IR;

func analyze_one(ast):
	if ast.class in ast_bypass_list:
		analyze_all(ast.children);
	
	match ast.class:
		"expr": analyze_expr(ast);
		_: push_error("analyze: not implemented for class "+ast.class); return null;

func analyze_all(list):
	for ast in list: analyze_one(ast);

var expr_stack = [];

var val_idx = 0;
# returns a handle to a new IR value
func new_value():
	var val_name = "val_"+str(val_idx);
	return {"name":val_name};

func analyze_expr(ast):
	assert(ast.class == "expr");
	var expr1 = ast.children[0];
	assert(expr1.class == "expr");
	var op = ast.children[1];
	var expr2 = null
	if len(ast.children) > 2: 
		expr2 = ast.children[2];
		assert(expr2.class == "expr");
	match op.text:
		"+": analyze_expr_infix_op(expr1, expr2, "ADD");
		"-": analyze_expr_infix_op(expr1, expr2, "SUB");
		"*": analyze_expr_infix_op(expr1, expr2, "MUL");
		"++": analyze_expr_postfix_op(expr1, "INC");
		"--": analyze_expr_postfix_op(expr1, "DEC");
		"(": analyze_expr_call(expr1, expr2);
		"[": analyze_expr_infix_op(expr1, expr2, "INDEX");
		_: push_error("analyze: expr op not implemented"); return;

func analyze_expr_infix_op(expr1, expr2, op):
	analyze_expr(expr1);
	analyze_expr(expr2);
	var arg2 = expr_stack.pop();
	var arg1 = expr_stack.pop();
	var res = new_value();
	emit_IR(["OP", op, arg1, arg2, res]);

func analyze_expr_postfix_op(expr1, op):
	analyze_expr(expr1);
	var arg = expr_stack.pop();
	var res = new_value();
	emit_IR(["OP", op, arg, null, res]);

func emit_IR(cmd:Array):
	IR.commands.append(cmd);

func analyze_expr_call(expr1, expr2):
	analyze_expr(expr1);
	analyze_expr_list(expr2);
	var args = expr_stack.pop();
	var fun = expr_stack.pop();
	var res = new_value();
	emit_IR(["CALL", fun, args, res]);

func analyze_expr_list(expr_list):
	assert(expr_list.class == "expr_list");
	var res = [];
	for expr in expr_list.children:
		analyze_expr(expr);
		res.append(expr_stack.pop());
	expr_stack.push_back(res);
