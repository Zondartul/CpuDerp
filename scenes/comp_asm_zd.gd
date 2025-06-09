extends Node
# assembles zvm assemly into machine code

var cur_filename = ""
var cur_path = ""
var code = []
var write_pos = 0;
var labels = {}

const ISA = preload("res://lang_zvm.gd");

func assemble(source:String):
	var lines = source.split("\n",false);
	print(lines);
	for line in lines:
		line = preproc(line);
		var tokens = tokenize(line);
		process(tokens);
		
# ---------- Basic preprocess ---------------------------------
# preprocess the line: remove comments, trim whitespace, etc
func preproc(line:String)->String:
	var line_old = line;
	line = remove_comments(line);
	line = trim_spaces(line);
	print("preproc: before ["+line_old+"] -> after ["+line+"]")
	return line;

# removes comments from the line. Comments start with the # character and last until end of string.
func remove_comments(line:String)->String:
	var idx = line.find("#");
	if(idx != -1):
		line = line.substr(idx);
	return line;

# removes space characters from the beginning and the end of a string
func trim_spaces(line:String)->String:
	var idx_first = first_non_space(line)
	var idx_last = last_non_space(line)
	var len = idx_last - idx_first;
	line = line.substr(idx_first, len);
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

#------------ Tokenization ----------------------------------
func tokenize(line:String):
	var tokens = [];
	var tok_class = -1;
	var cur_tok = "";
	for ch in line:
		var new_tok_class = tok_ch_class(ch);
		if new_tok_class != tok_class:
			if cur_tok != "":
				tokens.append({"class":tok_class, "text":cur_tok});
				cur_tok = "";
		tok_class = new_tok_class;
		cur_tok += ch;
	if cur_tok != "":
		tokens.append({"class":tok_class, "text":cur_tok});
		cur_tok = "";
	return tokens;

const ch_punct = ",:[]+";
const ch_alphabet = "qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM";
const ch_digits = "1234567890";

func tok_is_punct(ch:String): return ch in ch_punct;
func tok_is_word(ch:String): return ch in ch_alphabet;
func tok_is_num(ch:String): return ch in ch_digits;

# returns character class for tokenizer:
const TOK_ERROR = 0
const TOK_SPACE = 1
const TOK_WORD = 2
const TOK_NUMBER = 3
const TOK_PUNCT = 4 #and above - individual distinct punct symbols

func tok_ch_class(ch:String)->int:
	if ch == " ": return TOK_SPACE;
	if tok_is_word(ch): return TOK_WORD;
	if tok_is_num(ch): return TOK_NUMBER;
	if tok_is_punct(ch): return TOK_PUNCT + ch_punct.find(ch);
	return TOK_ERROR;
#-------------------------------------------------------------

#------------------ Analysis & codegen -----------------------

func process(tokens):
	if proc_is_label(tokens):
		var lbl_name = tokens[0]["text"];
		labels[lbl_name] = write_pos;
		return;
	if proc_is_command(tokens):
		var op_name = tokens[0]["text"];
		var op_code = ISA.opcodes.find_key(op_name);
		if not op_code: push_error("Invalid op ["+op_name+"]"); return;
		# TODO: also process arguments here
		emit(op_code);

func proc_is_label(tokens)->bool:
	return (len(tokens)==2) && \
			(tokens[0]["class"] == TOK_WORD) && \
			(tokens[1]["text"] == ":");

func proc_is_command(tokens)->bool:
	return (len(tokens)>=1) && \
			(tokens[0]["class"] == TOK_WORD);

#------------- CODE GEN -----------
func emit(val:int):
	if val not in range(0,255): push_error("can't emit value, doesn't fit in byte: ["+str(val)+"]")
	code[write_pos] = val;
	write_pos += 1;
