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

func tokenize(text):
	output_tokens.clear();
	var tokens = basic_tokenize(text);
	#tokens_ready.emit(tokens);
	recombine_tokens(tokens);
	reclassify_tokens(tokens);
	colorize_tokens(tokens);
	tokens = filter_tokens(tokens);
	
	output_tokens = tokens;
	tokens_ready.emit(output_tokens);	
	return output_tokens;

func basic_tokenize(text):
	var tokens = [];
	var lines = text.split("\n",false);
	print(lines);
	for line in lines:
		cur_line = line;
		cur_line_idx += 1;
		line = preproc(line);
		cur_line = line;
		var line_tokens = tokenizer.tokenize(line);
		for tok in line_tokens:
			tok["token_viewer_line"] = cur_line_idx;
		tokens.append_array(line_tokens);
		#process(tokens);
		if error_code: return false;
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
	["/WORD", "/NUMBER"], ["/NUMBER", ".", "/NUMBER"],
];

func recombine_tokens(tokens):
	var i = 0;
	var prev_toks = [];
	var prev_count = 2;
	while(i < len(tokens)):
		var tok = tokens[i];
		prev_toks.append(tok);
		if(len(prev_toks) > prev_count):
			prev_toks.remove_at(0);
		for recomb in recombinations:
			if recombine_pattern_match(prev_toks, recomb):
				recombine_n(tokens, i, len(recomb));
				prev_toks.clear();
				continue;
		i += 1;
	return tokens;

# returns true if the 
func recombine_pattern_match(toks:Array, pattern:Array):
	for i in range(len(pattern)):
		var p = pattern[rev_idx(pattern, i)];
		var t = maybe_idx(toks, rev_idx(toks,i));
		if not t: return false;
		if p == "/*": continue;
		if p == "/WORD" and t.class == "WORD": continue;
		if p == "/NUMBER" and t.class == "NUMBER": continue;
		if t and t.text == p: continue;
		return false;
	return true;

# returns an index of "idx from the end".
func rev_idx(arr:Array, idx:int):
	return len(arr)-1-idx;

# replaces in-place tokens idx-len ... idx with a single token.
func recombine_n(toks:Array, idx:int, length:int):
	var from = idx-length+1;
	for i in range(length-1):
		toks[from].text += toks[from+1].text;
		toks.remove_at(from+1);

# returns N'th array element or null if there isn't one.
func maybe_idx(arr:Array, idx:int):
	if (idx >= 0) and (idx < len(arr)): return arr[idx];
	else: return null;

# adjusts the token class based on a dictionary
func reclassify_tokens(tokens:Array):
	for tok in tokens:
		if tok.class == "WORD":
			if tok.text in lang.keywords:
				tok.class = "KEYWORD";
			else:
				tok.class = "IDENT";
		if tok.class == "PUNCT":
			if tok.text in lang.ops:
				tok.class = "OP";
			if tok.text[0] == "#":
				tok.class = "PREPROC";

# removes unneded tokens
func filter_tokens(tokens:Array)->Array:
	return tokens.filter(
		func(tok): 
			return not (
						(tok.class == "SPACE") or
						(tok.class == "ENDSTRING")
					)
	);

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
		if tok.class in token_colors:
			tok["token_viewer_color"] = token_colors[tok.class];
