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

#-------------- INTERNAL DATA ------------------------
# command structure:
# bytes	0		1		2		3	4	5	6	7 
#	  [cmd]	[ flags ][reg1|reg2][immediate u32][pad]
const cmd_size = 8;
# decoding code for reference:
	#var op:int = cmd[0];
	#var flags:int = cmd[1];
	#var regsel:int = cmd[2];
	#var im:int = cmd.decode_u32(3); #offset = byte 3
	#var reg1 = regsel & 0b1111;
	#var reg2 = (regsel>>4) & 0b1111;
	#var deref_reg1:bool = flags & (0b1 << 0);
	#var deref_reg2:bool = flags & (0b1 << 1);
	#var reg1_im:bool = flags & (0b1 << 2);
	#var reg2_im:bool = not reg1_im;
	#var is_32bit = flags & (0b1 << 3);
	#var spec_flags = (flags >> 4) & 0b111;
	

class Cmd_arg:
	var reg_name:String = "";
	var reg_idx:int = 0;
	var offset:int = 0;
	var b_deref:bool = false;
	var is_imm:bool = false;
	var is_32bit:bool = false; # is this even arg-level?

class Cmd_flags:
	var deref_reg1:bool = false;
	var deref_reg2:bool = false;
	var reg1_im:bool = false;
	var reg2_im:bool = false; # not encoded
	var is_32bit:bool = false;
	var spec_flags:int = 0;
	func to_byte():
		return  (int(deref_reg1) << 0) | \
				(int(deref_reg2) << 1) | \
				(int(reg1_im) << 2) | \
				(int(is_32bit) << 3) | \
				((spec_flags & 0b111) << 4);
	func set_arg1(arg:Cmd_arg):
		reg1_im = arg.is_imm;
		deref_reg1 = arg.b_deref;
		is_32bit = is_32bit || arg.is_32bit;
	func set_arg2(arg:Cmd_arg):
		reg2_im = arg.is_imm;
		deref_reg2 = arg.b_deref;
		is_32bit = is_32bit || arg.is_32bit;

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
		var flags:Cmd_flags;
		var arg1:Cmd_arg;
		var arg2:Cmd_arg;
		var tok_pos = 1;
		tok_pos = parse_arg(tokens, tok_pos, arg1);
		tok_pos = parse_arg(tokens, tok_pos, arg2);
		# if argument is present: arg1/arg2 gets set
		# if argument is not present: arg1/arg2 stays zero-ed
		# if syntax error: parse_arg pushes an error.
		flags.set_arg1(arg1);
		flags.set_arg2(arg2);
		emit_opcode(op_code, flags, arg1.reg_idx, arg2.reg_idx, 0);

func proc_is_label(tokens)->bool:
	return (len(tokens)==2) && \
			(tokens[0]["class"] == TOK_WORD) && \
			(tokens[1]["text"] == ":");

func proc_is_command(tokens)->bool:
	return (len(tokens)>=1) && \
			(tokens[0]["class"] == TOK_WORD);

# possible addressing modes:
# mnemonic  | ... meaning ......... | reg | deref | offset
# ---------------------------------------------------------
#           | no argument           | no  |   no  | no
#  eax		| register				| yes |   no  | no 
# *eax		| reg-is-ptr			| yes |  yes  | no
#  eax[9]	| reg-is-array			| yes |   no  | yes
# *eax[9]	| reg-is-array-of-ptr	| yes |  yes  | yes
# 123		| immediate				| no  |   no  | yes
# *123		| ptr					| no  |  yes  | yes
#.... AKSHUALLY, need to check with VM how the addressing modes actually ork
# w.r.t. dereference + offset order
func parse_arg(tokens:Array, tok_pos:int, arg:Cmd_arg)->int:
	return tok_pos; # dummy

#------------- CODE GEN -----------


func emit_opcode(cmd:int, flags:Cmd_flags, reg1:int=0, reg2:int=0, imm_u32:int=0):
	emit(cmd);
	emit(flags.to_byte());
	emit(reg1);
	emit(reg2);
	emit((imm_u32 >> 8*0) & 0xFF);
	emit((imm_u32 >> 8*1) & 0xFF);
	emit((imm_u32 >> 8*2) & 0xFF);
	emit((imm_u32 >> 8*3) & 0xFF);
	emit(0xFF); # pad


func emit(val:int):
	if val not in range(0,255): push_error("can't emit value, doesn't fit in byte: ["+str(val)+"]")
	code[write_pos] = val;
	write_pos += 1;
