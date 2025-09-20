extends Node

var cur_filename: set=set_cur_filename;
var cur_path: set=set_cur_path;
@onready var tokenizer = $tokenizer_md;
signal tokens_ready;
signal parse_ready;

func compile(text):
	var tokens = tokenizer.tokenize(text);
	var ast = parse(tokens);
	#print(tokens);

func _on_tokenizer_md_tokens_ready(tokens) -> void:
	tokens_ready.emit(tokens);

func set_cur_filename(val): tokenizer.cur_filename = val;
func set_cur_path(val): tokenizer.cur_path = val;

#-------- Parser ---------------------

# LR(1) shift-reduce parser, always applies the first valid rule
func parse(tokens:Array):
	tokens = tokens.duplicate();
	tokens.append({"class":"EOF"});
	var stack = [];
	#tok is the look-ahead token
	for tok in tokens:
		var stabilized = false;
		while not stabilized:
			stabilized = true;
			for rule in rules:
				if rule_matches(stack, tok, rule):
					apply_rule(stack, rule);
					stabilized = false;
					break;
		stack.push_back(tok);
	parse_ready.emit(stack);
	# parsed all tokens
	if len(stack) == 1:
		return stack[0];
	elif len(stack) == 0:
		push_error("no input");
		return false;
	else:
		push_error("syntax error");
		return false;

func rule_matches(stack:Array, tok_lookahead, rule:Array):
	#var rule_result = rule[-1];
	var rule_lookahead = rule[-2];
	var rule_input = rule.slice(0,-2);
	if len(stack) < len(rule_input): return false;
	if not token_match(tok_lookahead, rule_lookahead): return false;
	var stack_input = stack.slice(-len(rule_input));
	for i in range(len(rule_input)):
		if not token_match(stack_input[i], rule_input[i]): return false;
	return true;

func token_match(tok, ref:String):
	if ref == "*": return true;
	if ref[0] == "/": return ref.substr(1) == tok.text;
	return ref == tok.class;

func apply_rule(stack:Array, rule:Array):
	var toks = [];
	for i in range(len(rule)-2):
		toks.append(stack.pop_back());
	toks.reverse();
	var new_tok = {"class":rule[-1], "text":"", "children":toks};
	stack.append(new_tok);

const rules = [
	["NUMBER", "*", "expr"],
	["IDENT", "/=", "expr", ";", "assignment"],
];

#-------------------------------------
