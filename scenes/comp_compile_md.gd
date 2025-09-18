extends Node

var cur_filename;
var cur_path;
const script_tokenizer = preload("res://scenes/word_boundary_tokenizer.gd")
const lang = preload("res://scenes/lang_md.gd")
var tokenizer;
var cur_line = "";
var cur_line_idx = 0;
var error_code = 0;
signal tokens_ready;
var output_tokens = [];

func _ready():
	tokenizer = script_tokenizer.new();
	tokenizer.ch_punct = lang.get_all_punct();

func compile(text):
	var tokens = tokenize(text);
	tokens_ready.emit(tokens);
	print(tokens);

var char_classes = ["WORD", "PUNCT", "NUM", "STR"];

func tokenize(text):
	output_tokens.clear();
	var lines = text.split("\n",false);
	print(lines);
	for line in lines:
		cur_line = line;
		cur_line_idx += 1;
		line = preproc(line);
		cur_line = line;
		var tokens = tokenizer.tokenize(line);
		output_tokens.append_array(tokens);
		if output_tokens.size():
			output_tokens.back()["token_viewer_newline"] = true;
		#process(tokens);
		if error_code: return false;
	tokens_ready.emit(output_tokens);
	return output_tokens;

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
