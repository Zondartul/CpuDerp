extends Node

var cur_filename;
var cur_path;
const script_tokenizer = preload("res://scenes/word_boundary_tokenizer.gd")
const lang = preload("res://scenes/lang_md.gd")
var tokenizer;
var cur_line = "";
var cur_line_idx = 0;
var error_code = 0;
var output_tokens = [];
signal tokens_ready;

func _ready():
	tokenizer = script_tokenizer.new();
	tokenizer.ch_punct = lang.get_all_punct();

func tokenize(text:String)->Array[Token]:
	output_tokens.clear();
	cur_line = "";
	cur_line_idx = 0;
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
	var tokens:Array[Token] = [];
	var lines:PackedStringArray = text.split("\n",true);
	print(lines);
	for line:String in lines:
		cur_line = line;
		if line == "": 
			cur_line_idx += 1;
			continue;
		line = preproc(line);
		#cur_line = line;
		var line_tokens:Array[Token] = tokenizer.tokenize(line);
		for tok:Token in line_tokens:
			#tok["token_viewer_line"] = cur_line_idx;
			tok.set_meta("token_viewer_line", cur_line_idx)
			tok.line = line;
			tok.line_idx = cur_line_idx;
		tokens.append_array(line_tokens);
		#process(tokens);
		cur_line_idx += 1;
		if error_code: return [];
	return tokens;
# ---------- Basic preprocess ---------------------------------
# preprocess the line: remove comments, trim whitespace, etc
func preproc(line:String)->String:
	#var line_old = line;
	line = remove_comments(line);
	line = trim_spaces(line);
	#print("preproc: before ["+line_old+"] -> after ["+line+"]")
	return line;

# removes comments from the line. Comments start with the # character and last until end of string.
func remove_comments(line:String)->String:
	#var idx = line.find("#");
	#if(idx != -1):
	#	line = line.substr(0, idx);
	# need to handle strings as well
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

# removes space characters from the beginning and the end of a string
func trim_spaces(line:String)->String:
	var idx_first = first_non_space(line)
	var idx_last = last_non_space(line)
	var nsp_len = idx_last - idx_first+1;
	line = line.substr(idx_first, nsp_len);
	return line;

# returns the index of the first character in a string that is not some space character
func first_non_space(line:String)->int:
	var idx = 0;
	for ch in line:
		if ch in " \n\r\t":
			idx = idx+1;
		else:
			return idx;
	return -1;

# returns the index of the last character in a string that is not some space character
func last_non_space(line:String)->int:
	var idx = first_non_space(line.reverse())
	if idx == -1: return -1;
	else: return line.length() - idx - 1;
#------------------------------------------------------------

const recombinations = [
	["#", "/*"], ["+", "+"], ["-", "-"], ["+", "="], ["-", "="],
	["!", "="], ["=", "="],
	["/WORD", "/NUMBER"], ["/NUMBER", ".", "/NUMBER"],
];

func recombine_tokens(tokens:Array[Token]):
	var i = 0;
	var prev_toks:Array[Token] = [];
	var prev_count = 2;
	while(i < len(tokens)):
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

# returns true if the 
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


# replaces in-place tokens idx-len ... idx with a single token.
func recombine_n(toks:Array[Token], idx:int, length:int):
	var from = idx-length+1;
	for i in range(length-1):
		toks[from].text += toks[from+1].text;
		toks.remove_at(from+1);


# adjusts the token class based on a dictionary
func reclassify_tokens(tokens:Array[Token]):
	for tok:Token in tokens:
		if tok.tok_class == "WORD":
			if tok.text in lang.keywords:
				tok.tok_class = "KEYWORD";
			else:
				tok.tok_class = "IDENT";
		if tok.tok_class == "PUNCT":
			if tok.text in lang.ops:
				tok.tok_class = "OP";
			if tok.text[0] == "#":
				tok.tok_class = "PREPROC";

# removes unneded tokens
func filter_tokens(tokens:Array[Token])->Array[Token]:
	var filtered = ["SPACE", "ENDSTRING"];
	return tokens.filter(func(tok:Token): return tok.tok_class not in filtered);
#	return tokens.filter(
#		func(tok:Token): 
#			return not (
#						(tok.tok_class == "SPACE") or
#						(tok.tok_class == "ENDSTRING")
#					)
#	);

const token_colors = {
	"PREPROC":Color(0.91, 0.576, 0.109, 1.0),
	"KEYWORD":Color(0.974, 0.22, 0.365, 1.0),
	"IDENT":Color(0.693, 0.469, 0.946, 1.0),
	"OP":Color(0.998, 0.998, 0.0, 1.0),
	"NUMBER":Color(1.0, 1.0, 0.0, 1.0),
	"STRING":Color(0.0, 0.827, 0.0, 1.0),
	"PUNCT":Color(0.293, 0.506, 1.0, 1.0),
};

func colorize_tokens(toks:Array):
	for tok in toks:
		if tok.tok_class in token_colors:
			#tok["token_viewer_color"] = token_colors[tok.class];
			tok.set_meta("token_viewer_color", token_colors[tok.tok_class]);
