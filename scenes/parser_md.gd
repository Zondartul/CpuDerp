extends Node
signal sig_parse_ready(stack:Array[AST]);
signal sig_user_error(msg:String);
#signal sig_highlight_line(line_idx);
signal sig_cprint(msg:String);
@export var erep:ErrorReporter;
#--- error reporter support ---
func user_error(msg)->void: sig_user_error.emit(msg);
func cprint(msg)->void: sig_cprint.emit(msg);
# constants
static var lang:Language = preload("res://scenes/lang_md.gd").new();
const list_types:Dictionary[String,Array] = {
	"stmt_list":["stmt"],
	"expr_list":["expr", "const_expr", "const_expr_list","type_expr", "type_expr_list"],
	"const_expr_list":["const_expr", "type_expr", "type_expr_list"],
	"type_expr_list":["type_expr"],
	};

const dbg_to_console:bool = false;
const dbg_to_file:bool = true;
const dbg_filename:String = "log.txt";
const dbg_prints_enabled:Array[int] = [
	#"TOKENIZE",
	#"PARSE",
	#"ANALYZE",
];
# state
var cur_line:String = "";
var cur_line_idx:int = 0;
var error_code:String = "";
var run_i:int = 0;
var dbg_fp:FileAccess = FileAccess.open(dbg_filename, FileAccess.WRITE);
#-------- Parser ---------------------
func reset()->void:
	cur_line = "";
	cur_line_idx = 0;
	error_code = "";
	run_i = 0;
	if(dbg_fp): dbg_fp.close();
	dbg_fp = FileAccess.open(dbg_filename, FileAccess.WRITE);

# LR(1) shift-reduce parser, always applies the first valid rule
func parse(input:CompilerMD.Context, task:Task)->AST:
	reset();
	var in_tokens:Array[Token] = input.tokens;
	task.work_units_total = in_tokens.size();
	task.work_units_complete = 0;
	erep.proxy = self;
	erep.task = task;
	#tokens = tokens.duplicate();
	var tokens:Array[AST] = [];
	for tok in in_tokens:
		tokens.push_back(AST.new(tok));
	
	tokens.append(AST.new({"tok_class":"EOF", "text":""}));
	var stack:Array[AST] = [];
	#tok is the look-ahead token
	for tok:AST in tokens:
		task.work_units_complete += 1;
		var stabilized:bool = false;
		var lc:LoopCounter = LoopCounter.new();
		while not stabilized:
			lc.step();
			stabilized = true;
			for ut_rule:Array in lang.rules:
				var rule:Array[String]; rule.assign(ut_rule); #type conv
				if rule_matches(stack, tok, rule):
					if rule[-1] == "SHIFT": break; #(with stabilized == true)
					apply_rule(stack, rule);
					stabilized = false;
					break;
		#dbg_print("PARSE","SHIFT "+str(tok)+"\n");
		if tok.tok_class != "EOF": stack.push_back(tok);
	
	for i in range(len(stack)):
		linearize_ast(stack[i]);
		stack[i].precompute_location();
	call_deferred("defer_parse_ready", stack); #sig_parse_ready.emit(stack);
	# parsed all tokens
	if len(stack) == 1:
		if stack[0].tok_class != "start":
			push_error("snippet is not a valid program");
		return stack[0];
	elif len(stack) == 0:
		push_error("no input");
		return null;
	else:
		call_deferred("defer_user_error", "syntax error");
		var ctx:Token = stack[1];#find_best_error_token(stack);
		#var erep:ErrorReporter = ErrorReporter.new(self, ctx as Token);
		erep.context = ctx as Token;
		erep.error("syntax error");
		return null;
#
#func find_best_error_token(stack:Array[AST])->AST:
	#for i in range(1, len(stack)):
		#var ast = stack[i];
		#if ast.children.is_empty():
			#return ast;
	#return stack[1];
func defer_parse_ready(stack)->void:
	sig_parse_ready.emit(stack);

func defer_user_error(arg)->void:
	sig_user_error.emit(arg);

func rule_matches(stack:Array[AST], tok_lookahead:AST, rule:Array[String])->bool:
	#var rule_result = rule[-1];
	var rule_lookahead:String = rule[-2];
	var rule_input:Array[String] = rule.slice(0,-2);
	if len(stack) < len(rule_input): return false;
	var stack_input:Array[AST] = stack.slice(-len(rule_input));
	#dbg_print("PARSE","Rule matches? "+"(test "+str(run_i)+")"+"\n"+stack_to_str(stack_input,"\t\t") + "\n\tvs\n"+stack_to_str(rule_input,"\t\t")+"\n\t. "+str(tok_lookahead)+" vs "+str(rule_lookahead));
	run_i += 1;
	if not token_match(tok_lookahead, rule_lookahead): 
		#dbg_print("PARSE","\tNo\n");
		return false;
	for i in range(len(rule_input)):
		if not token_match(stack_input[i], rule_input[i]): 
			#dbg_print("PARSE","\tNo\n")
			return false;
	#dbg_print("PARSE","\tYES\n");
	return true;

func token_match(tok:AST, ref:String)->bool:
	if ref == "*": 
		return true;
	if ref[0] == "/": 
		return ref.substr(1) == tok.text;
	return ref == tok.tok_class;

func apply_rule(stack:Array[AST], rule:Array[String])->void:
	var toks:Array[AST] = [];
	for i in range(len(rule)-2):
		toks.append(stack.pop_back());
	toks.reverse();
	var new_tok:AST = AST.new({"tok_class":rule[-1], "text":""});
	dbg_print("PARSE","REDUCE "+str(new_tok)+"\n");
	new_tok.children = toks;
	stack.append(new_tok);


func linearize_ast(ast:AST)->void:
	for ch:AST in ast.children:
		linearize_ast(ch);
	if ast.tok_class in list_types:
		print("linearize: visit "+ast.tok_class);
		var base_types:Array = list_types[ast.tok_class];
		print("before gather: ch = %s" % print_child_types(ast));
		var ch_list:Array[AST] = gather_instances(ast, base_types);
		print("gathered %d children" % len(ch_list));
		ast.children.assign(ch_list);
		print("after gather: ch = %s" % print_child_types(ast));
	#else:
	#	print("not a list");

func gather_instances(ast:AST, types:Array)->Array[AST]:
	var res:Array[AST] = [];
	for ch in ast.children:
		if ch.tok_class in types:
			#print("gather: append base child");
			res.append(ch);
		elif ch.tok_class == ast.tok_class:
			#print("gather: recurse");
			res.append_array(gather_instances(ch, types));
		# other types are discarded
	return res;

#debug func
func print_child_types(ast:AST)->String:
	var S:String = "";
	for ch in ast.children:
		S += ch.tok_class + " ";
	return S;

func stack_to_str(stack:Array, prefix:String)->String:
	var text:String = "";
	for tok in stack:
		if tok is String:
			text += prefix + "["+tok+"]" + "\n";
		else:
			text += prefix + "["+tok.tok_class + ":"+tok.text+"]"+"\n";
	text = text.erase(len(text)-1); #remove the last \n
	return text;

func dbg_print(print_class, msg)->void:
	if print_class in dbg_prints_enabled: 
		if dbg_to_console:	print(msg);
		if dbg_to_file: dbg_fp.store_line(msg);
#-------------------------------------
