extends Node

const script_tokenizer = preload("res://scenes/word_boundary_tokenizer.gd")
const lang = preload("res://scenes/lang_md.gd")
signal tokens_ready;

#constants
const assign_ops = ["=", "+=", "-=", "*=", "/=", "%=","!="];

const recombinations = [
	["#", "/*"], ["+", "+"], ["-", "-"], ["+", "="], ["-", "="],
	["!", "="], ["=", "="],
	["/WORD", "/NUMBER"], ["/NUMBER", ".", "/NUMBER"],
];

const token_colors = {
	"PREPROC":Color(0.91, 0.576, 0.109, 1.0),
	"KEYWORD":Color(0.974, 0.22, 0.365, 1.0),
	"IDENT":Color(0.693, 0.469, 0.946, 1.0),
	"OP":Color(0.998, 0.998, 0.0, 1.0),
	"NUMBER":Color(1.0, 1.0, 0.0, 1.0),
	"STRING":Color(0.0, 0.827, 0.0, 1.0),
	"PUNCT":Color(0.293, 0.506, 1.0, 1.0),
};

#state
var tokenizer;
var cur_filename;
var cur_path;
var cur_line = "";
var cur_line_idx = 0;
var error_code = 0;
var output_tokens = [];


func reset():
	tokenizer = script_tokenizer.new();
	tokenizer.ch_punct = lang.get_all_punct();
	cur_filename = "";
	cur_path = "";
	cur_line = "";
	cur_line_idx = 0;
	error_code = 0;
	output_tokens = [];


func _ready():
	reset();

func tokenize(input:Dictionary)->Array[Token]:
	reset();
	var text:String = input.text;
	cur_filename = input.filename;
	#output_tokens.clear();
	#cur_line = "";
	#cur_line_idx = 0;
	var tokens:Array[Token] = basic_tokenize(text);
	#tokens_ready.emit(tokens);
	recombine_tokens(tokens);
	reclassify_tokens(tokens);
	colorize_tokens(tokens);
	tokens = filter_tokens(tokens);
	
	output_tokens = tokens;
	tokens_ready.emit(output_tokens);	
	return output_tokens;

func basic_tokenize(text:String)->Array[Token]:
	var cur_loc:Location = Location.new({"filename":cur_filename})
	var tokens:Array[Token] = [];
	var lines:PackedStringArray = text.split("\n",true);
	for line:String in lines:
		cur_line = line;
		cur_loc.line = cur_line;
		cur_loc.line_idx = cur_line_idx;
		if line == "": 
			cur_line_idx += 1;
			continue;
		line = preproc(line);
		var line_tokens:Array[Token] = tokenizer.tokenize(line);
		for tok:Token in line_tokens:
			tok.set_meta("token_viewer_line", cur_line_idx)
			#tok.line = line;
			#tok.line_idx = cur_line_idx;
			for prop in ["filename", "line", "line_idx"]:
				for dest in [tok.loc.begin, tok.loc.end]:
					dest.set(prop, cur_loc.get(prop));
		tokens.append_array(line_tokens);
		cur_line_idx += 1;
		if error_code: return [];
	return tokens;
# ---------- Basic preprocess ---------------------------------
## preprocess the line: remove comments, trim whitespace, etc
func preproc(line:String)->String:
	line = remove_comments(line);
	#line = G.trim_spaces(line); ##[2025.10.29] need to keep the line intact until we have locations
	return line;

## removes comments from the line. Comments start with the # character and last until end of string.
func remove_comments(line:String)->String:
	var is_string = false;
	var idx = 0;
	var prev_ch = "";
	for ch in line:
		if is_string:
			if ch == "\"": is_string = false;
		else:
			if ch == "\"": is_string = true;
			if ch == "/" and prev_ch == "/": 
				idx -= 1;
				break;
		prev_ch = ch;
		idx += 1;
	return line.substr(0,idx);


#------------------------------------------------------------



func recombine_tokens(tokens:Array[Token]):
	var i = 0;
	var prev_toks:Array[Token] = [];
	var prev_count = 2;
	var lc = LoopCounter.new(len(tokens)+1);
	while(i < len(tokens)):
		lc.step();
		var tok:Token = tokens[i];
		prev_toks.append(tok);
		if(len(prev_toks) > prev_count):
			prev_toks.remove_at(0);
		for recomb:Array in recombinations:
			var t_recomb:Array[String]; t_recomb.assign(recomb); #type conv
			if recombine_pattern_match(prev_toks, t_recomb):
				recombine_n(tokens, i, len(t_recomb));
				prev_toks.clear();
				continue;
		i += 1;
	return tokens;

## returns true if the tokens match a pattern
func recombine_pattern_match(toks:Array[Token], pattern:Array[String]):
	for i in range(len(pattern)):
		var p = pattern[G.rev_idx(pattern, i)];
		var t = G.maybe_idx(toks, G.rev_idx(toks,i));
		if not t: return false;
		if p == "/*": continue;
		if p == "/WORD" and t.tok_class == "WORD": continue;
		if p == "/NUMBER" and t.tok_class == "NUMBER": continue;
		if t and t.text == p: continue;
		return false;
	return true;

## replaces in-place tokens idx-len ... idx with a single token.
func recombine_n(toks:Array[Token], idx:int, length:int):
	var from = idx-length+1;
	for i in range(length-1):
		toks[from].text += toks[from+1].text;
		toks[from].loc.end = toks[from+1].loc.end;
		toks.remove_at(from+1);


## adjusts the token class based on a dictionary
func reclassify_tokens(tokens:Array[Token]):
	for tok:Token in tokens:
		if tok.tok_class == "WORD":
			if tok.text in lang.keywords:
				tok.tok_class = "KEYWORD";
			elif tok.text in lang.ops:
				tok.tok_class = "OP";
			elif tok.text in lang.types:
				tok.tok_class = "TYPE";
			else:
				tok.tok_class = "IDENT";
		elif tok.tok_class == "PUNCT":
			if tok.text in lang.ops and tok.text not in assign_ops:
				tok.tok_class = "OP";
			if tok.text[0] == "#":
				tok.tok_class = "PREPROC";

## removes unneded tokens
func filter_tokens(tokens:Array[Token])->Array[Token]:
	var filtered = ["SPACE", "ENDSTRING"];
	return tokens.filter(func(tok:Token): return tok.tok_class not in filtered);



func colorize_tokens(toks:Array):
	for tok in toks:
		if tok.tok_class in token_colors:
			#tok["token_viewer_color"] = token_colors[tok.class];
			tok.set_meta("token_viewer_color", token_colors[tok.tok_class]);
