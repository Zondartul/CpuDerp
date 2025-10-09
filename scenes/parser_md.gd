extends Node
const lang = preload("res://scenes/lang_md.gd");
signal sig_parse_ready(stack:Array[AST]);
signal sig_user_error(msg:String);

#-------- Parser ---------------------

# LR(1) shift-reduce parser, always applies the first valid rule
func parse(in_tokens:Array[Token]):
	#tokens = tokens.duplicate();
	var tokens:Array[AST] = [];
	for tok in in_tokens:
		tokens.push_back(AST.new(tok));
	
	tokens.append(AST.new({"tok_class":"EOF", "text":""}));
	var stack:Array[AST] = [];
	#tok is the look-ahead token
	for tok:AST in tokens:
		var stabilized = false;
		while not stabilized:
			stabilized = true;
			for ut_rule:Array in lang.rules:
				var rule:Array[String]; rule.assign(ut_rule); #type conv
				if rule_matches(stack, tok, rule):
					if rule[-1] == "SHIFT": break; #(with stabilized == true)
					apply_rule(stack, rule);
					stabilized = false;
					break;
		dbg_print("PARSE","SHIFT "+str(tok)+"\n");
		if tok.tok_class != "EOF": stack.push_back(tok);
	sig_parse_ready.emit(stack);
	# parsed all tokens
	if len(stack) == 1:
		if stack[0].tok_class != "start":
			push_error("snippet is not a valid program");
		return stack[0];
	elif len(stack) == 0:
		push_error("no input");
		return false;
	else:
		sig_user_error.emit("syntax error");
		return false;

var run_i = 0;

func rule_matches(stack:Array[AST], tok_lookahead:AST, rule:Array[String])->bool:
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
	var new_tok = AST.new({"tok_class":rule[-1], "text":""});
	dbg_print("PARSE","REDUCE "+str(new_tok)+"\n");
	new_tok.children = toks;
	stack.append(new_tok);


func stack_to_str(stack:Array, prefix:String)->String:
	var text:String = "";
	for tok in stack:
		if tok is String:
			text += prefix + "["+tok+"]" + "\n";
		else:
			text += prefix + "["+tok.tok_class + ":"+tok.text+"]"+"\n";
	text = text.erase(len(text)-1); #remove the last \n
	return text;

var dbg_to_console = false;
var dbg_to_file = true;
var dbg_filename = "log.txt";
var dbg_fp = FileAccess.open(dbg_filename, FileAccess.WRITE);
var dbg_prints_enabled = [
	#"TOKENIZE",
	#"PARSE",
	#"ANALYZE",
];

func dbg_print(print_class, msg):
	if print_class in dbg_prints_enabled: 
		if dbg_to_console:	print(msg);
		if dbg_to_file: dbg_fp.store_line(msg);
#-------------------------------------
