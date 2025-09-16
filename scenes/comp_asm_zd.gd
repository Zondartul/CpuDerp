extends Node
# assembles zvm assemly into machine code

var cur_filename = ""
var cur_path = ""
var code = [];
var shadow = [];
var write_pos = 0;
var labels = {}
var label_refs = {}
const ISA = preload("res://lang_zvm.gd");

# error reporting
var cur_line = "";
var cur_line_idx = 0;
var error_code;

#debug info
var op_locations = []

func clear():
	cur_filename = "";
	cur_path = "";
	code.clear();
	shadow.clear();
	write_pos = 0;
	labels.clear();
	label_refs.clear();
	cur_line = "";
	cur_line_idx = 0;
	error_code = null;

func assemble(source:String):
	clear();
	var lines = source.split("\n",false);
	print(lines);
	for line in lines:
		cur_line = line;
		cur_line_idx += 1;
		line = preproc(line);
		cur_line = line;
		var tokens = tokenize(line);
		process(tokens);
	var chunk = output_chunk();
	chunk = link_internally(chunk);
	var unlinked = len(chunk["refs"]);
	if unlinked: push_error("Unlinked references remain (count "+str(unlinked)+")")
	print("Assembly done");
	print("stats: ")
	print("    "+str(len(chunk["code"]))+" bytes")
	print("    "+str(len(chunk["labels"]))+" labels")
	return chunk;

func point_out_error(msg, line_text, line_idx, char_idx):
	print("error at line "+str(line_idx)+":\n");
	print(line_text);
	print(" ".repeat(char_idx)+"^");
	print(msg);

func point_out_error_iter(msg, iter):
	var char_idx = iter[0][iter[1]]["col"];#iter_count_chars(iter);
	point_out_error(msg, cur_line, cur_line_idx, char_idx)

#func iter_count_chars(iter):
	#var tok_idx = 0;
	#var char_idx = 0;
	#for tok in iter[0]:
		#if tok_idx == iter[1]:
			#return char_idx;
		#char_idx += len(tok["text"]);
		#tok_idx += 1;
	#push_error("unreachable code")
	#return -1;

func output_chunk():
	var chunk = {"code":code.duplicate(), "labels":labels.duplicate(), "refs":label_refs.duplicate(), "shadow":shadow.duplicate()}
	code.clear();
	labels.clear();
	label_refs.clear();
	shadow.clear();
	return chunk;

## links the code chunk to itself
##  returns new code chunk
##  only unlinked references remain in the refs section
func link_internally(chunk):
	var in_code = chunk["code"];
	var in_labels = chunk["labels"];
	var in_refs = chunk["refs"];
	
	var code_out = in_code.duplicate();
	var shadow_out = chunk.shadow.duplicate();
	var refs_remain = {};
	for ref in in_refs:
		var lbl_name = in_refs[ref];
		if lbl_name in in_labels:
			var lbl_pos = in_labels[lbl_name];
			patch_ref(code_out, ref, lbl_pos, shadow_out);
		else:
			refs_remain[ref] = lbl_name;
	var out_chunk = {"code":code_out, "labels":in_labels.duplicate(), "refs":refs_remain, "shadow":shadow_out}
	return out_chunk;
	 
## modifies the code in-place to alter a command's offset to a given value.
##  ref: position of command (then the immediate value lies in bytes [ref+3...ref+7)
##  lbl_pos: the new value to insert
func patch_ref(out_code:Array, ref:int, lbl_pos:int, out_shadow:Array):
	var old_code = code;
	var old_wp = write_pos;
	var old_shadow = shadow;
	code = out_code;
	shadow = out_shadow;
	write_pos = ref; #ref+3;
	var prev_mark = out_shadow[write_pos];
	var shadow_flag = ISA.SHADOW_UNUSED;
	match prev_mark:
		ISA.SHADOW_DATA_UNRESOLVED: shadow_flag = ISA.SHADOW_DATA_RESOLVED;
		ISA.SHADOW_CMD_UNRESOLVED: shadow_flag = ISA.SHADOW_CMD_RESOLVED;
		_: push_error("patch_ref: reference not marked in shadows"); assert(false);
	emit32(lbl_pos, shadow_flag);
	code = old_code;
	write_pos = old_wp;
	shadow = old_shadow;

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
	var is_present:bool = false; #did we get supplied with this arg in assembly?
	var reg_name:String = "";
	var reg_idx:int = 0;
	var offset:int = 0;
	var is_deref:bool = false;
	var is_imm:bool = false;
	var is_32bit:bool = false; # is this even arg-level?
	var is_unresolved:bool = false; #is this a label that needs to be resolved by linker?

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
		deref_reg1 = arg.is_deref;
	func set_arg2(arg:Cmd_arg):
		reg2_im = arg.is_imm;
		if reg1_im and reg2_im: push_error("can only have one immediate/offset value per command")
		deref_reg2 = arg.is_deref;

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
	for ch in line:
		if is_string:
			if ch == "\"": is_string = false;
		else:
			if ch == "\"": is_string = true;
			if ch == "#": break;
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

#------------ Tokenization ----------------------------------
func tokenize(line:String):
	var tokens = [];
	var tok_class = "";
	var cur_tok = "";
	var col = 0;
	for ch in line:
		var new_tok_class = tok_ch_class(ch);
		if should_split_on_transition(new_tok_class, tok_class):
			if tok_class == "STRING" and new_tok_class == "STRING":
				new_tok_class = "ENDSTRING";
				cur_tok = cur_tok.substr(1); #remove the leading \"
			if cur_tok != "":
				tokens.append({"class":tok_class, "text":cur_tok, "col":col-1});
				cur_tok = "";
			tok_class = new_tok_class;
		cur_tok += ch;
		col += 1;
	if cur_tok != "":
		tokens.append({"class":tok_class, "text":cur_tok, "col":col-1});
		cur_tok = "";
	tokens = tokens.filter(filter_tokens);
	return tokens;

func should_split_on_transition(new_tok_class, old_tok_class):
	#if (new_tok_class != tok_class) or (tok_class == "PUNCT"):
	if old_tok_class == "PUNCT": return true; # punctuation tokens are always one-by-one.
	elif old_tok_class == "WORD" and new_tok_class == "NUMBER": return false; #allow numbers to be included in names
	elif old_tok_class == "STRING" and new_tok_class == "STRING": return true; #split on beginning and end of string (ie \")  
	elif old_tok_class == "STRING": return false; # keep building the string
	else: return (old_tok_class != new_tok_class); #split on any other class change
	

func filter_tokens(tok):
	if tok["class"] in ["SPACE", "ENDSTRING"]: return false;
	return true;

const ch_punct = ".,:[]+;";
const ch_alphabet = "qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM_";
const ch_digits = "1234567890";

func tok_is_punct(ch:String): return ch in ch_punct;
func tok_is_word(ch:String): return ch in ch_alphabet;
func tok_is_num(ch:String): return ch in ch_digits;

# character class for tokenizer:
#const TOK_ERROR = 0
#const TOK_SPACE = 1
#const TOK_WORD = 2
#const TOK_NUMBER = 3
#const TOK_PUNCT = 4 #and above - individual distinct punct symbols
# deprecated - now using strings

func tok_ch_class(ch:String)->String:
	if ch == " ": return "SPACE";
	if tok_is_word(ch): return "WORD";
	if tok_is_num(ch): return "NUMBER";
	if tok_is_punct(ch): return "PUNCT";
	if ch == "\"": return "STRING";
	return "ERROR"
#-------------------------------------------------------------
# ---------- ASM syntax hint ----------------------------------
# comment: #reverses a string
# label:   str_rev:
# commands: (cmd)[.32] [[*](reg|num|label)['['num']']]x2 [;]
#	mov.32 eax, ebp[9];
#	push.32 eax;
#	call strlen; 				
#	add esp, 4;
#	mov edx, *ebx;
#	mov *ebx, *eax;
# note: immediate argument (offset) will be applied to one or the othe other arg
#       set immediate to 0 for no effect
#------------------ Analysis & codegen -----------------------

func process(tokens):
	var iter = [tokens, 0];
	while iter[1] != len(iter[0]):
		if parse_label(iter) \
		or parse_db(iter) \
		or parse_command(iter):
			pass; # all ok, continue to next command
		else:
			point_out_error_iter("unexpected input", iter);
			print("current tokens: ");
			print_tokens(tokens);
			error_code = "unexpected input";
			return;

func parse_label(iter):
	var toks = [];
	if match_tokens(iter, ["WORD", "\\:"], toks):
		var lbl_name = toks[0]["text"];
		labels[lbl_name] = write_pos;
		print("Parsed [label:"+lbl_name+"]");
		return true;
	else: return false;

func parse_db(iter):
	var old_iter = iter.duplicate();
	if match_tokens(iter, ["\\db"]):
		var items = [];
		while iter[1] != len(iter[0]):
			var toks = []
			if match_tokens(iter, ["STRING"],toks) \
			or match_tokens(iter, ["NUMBER"],toks) \
			or (match_tokens(iter, ["WORD"],toks) and is_label(toks[0]["text"])):
				items.append(toks[0]);
			else:
				push_error("unrecognized DB item");
				return false;
			match_tokens(iter, ["\\,"]);
			if match_tokens(iter, ["\\;"]):
				break;
		record_op_position(old_iter, iter);
		emit_db_items(items);
		#add debug info for this instuction
		print("Parsed DB (count "+str(len(items))+")");
		return true;
	else: return false;

func record_op_position(old_iter, iter):
	var tok_first = old_iter[0][old_iter[1]];
	var tok_last = iter[0][iter[1]-1];
	var begin_col = tok_first["col"];
	var end_col = tok_last["col"]+len(tok_last["text"]);
	var op = {"ip":write_pos,"filename":cur_filename, "line":cur_line_idx, "begin":begin_col, "end":end_col};
	op_locations.append(op);

func parse_command(iter):
	var old_iter = iter.duplicate();
	var toks = [];
	if match_tokens(iter, ["WORD"],toks):
		var op_name = str(toks[0]["text"]).to_upper();
		var flags:Cmd_flags = Cmd_flags.new()
		var op_code = 0;
		if op_name in ISA.spec_ops:
			var spec_op = ISA.spec_ops[op_name];
			op_code = spec_op["op_code"];
			flags.spec_flags = spec_op["flags"];
		else:
			op_code = ISA.opcodes.find_key(op_name);
		if not op_code: 
			push_error("Invalid op ["+op_name+"]"); 
			return false;
		if match_tokens(iter, ["\\.", "\\32"]): flags.is_32bit = true;
		var arg1:Cmd_arg = parse_arg(iter);
		match_tokens(iter, ["\\,"]);
		var arg2:Cmd_arg = parse_arg(iter);
		match_tokens(iter, ["\\;"]); # optional semicolon
		
		# if argument is present: arg1/arg2 gets set
		# if argument is not present: arg1/arg2 stays zero-ed
		# if syntax error: parse_arg pushes an error.
		flags.set_arg1(arg1);
		flags.set_arg2(arg2);
		var shadow_flags = {"unresolved":(arg1.is_unresolved or arg2.is_unresolved)};
		record_op_position(old_iter, iter);
		emit_opcode(op_code, flags, arg1.reg_idx, arg2.reg_idx, arg1.offset+arg2.offset, shadow_flags);
		print("Parsed ["+op_name+"("+str(int(arg1.is_present) + int(arg2.is_present))+")]")
		return true;
	else: return false;

func is_label(word:String):
	return (not ISA.opcodes.find_key(word)) and (word not in ISA.spec_ops);

func print_tokens(tokens):
	var S:String = "";
	for tok in tokens:
		S += tok["class"]+"("+tok["text"]+")"+"  ";
	print(S);

## peek_tokens:
## 	returns tokens if they match pattern
## 	returns null of they don't or if EOF
## 	pattern is either "class" or "\\text"
func peek_tokens(iter, ref_toks):
	var i = iter[1];
	var res = []
	for rt in ref_toks:
		if i >= len(iter[0]): return null;
		var it = iter[0][i];
		assert(len(rt)>0);
		if (rt[0] == "\\") and (it["text"] == rt.substr(1))\
		or (rt[0] != "\\") and (it["class"] == rt):
			res.append(it.duplicate());
		else:
			return null;
		i += 1;
	return res;

## match_tokens:
##  same as peek_tokens but also advances iter by the number of consumed tokens
func match_tokens(iter, ref_toks, out=null):
	assert(ref_toks is Array);
	var res = peek_tokens(iter, ref_toks);
	if res:	
		iter[1] += len(res);
		if out != null: 
			out.clear(); out.assign(res);
	return res;

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
# syntax: (cmd)[.32] [[*](reg|num|label)['['num']']]x2 [;]

func parse_arg(iter)->Cmd_arg:
	var arg:Cmd_arg = Cmd_arg.new()
	# * - deref star
	if match_tokens(iter, ["\\*"]): arg.is_deref = true;
	
	# (reg|num|label) - main body
	var toks_word = match_tokens(iter, ["WORD"]);
	if toks_word:
		arg.is_present = true;
		var word = toks_word[0]["text"]; 
		var reg = get_reg(word);
		if reg:
			arg.reg_idx = reg["idx"];
			arg.reg_name = reg["name"];
		else: #is label
			var lbl_name = word;
			arg.reg_name = lbl_name;
			arg.is_imm = true;
			arg.is_unresolved = true;
			# register the reference for later,
			# we will patch the command when linking
			label_refs[write_pos+3] = lbl_name;
	var toks_num = match_tokens(iter, ["NUMBER"]);
	if toks_num:
		arg.is_present = true;
		var word = toks_num[0]["text"];
		var num = str(word).to_int()
		arg.is_imm = true;
		arg.offset = num;
	
	#[123] - array access
	var arr = match_tokens(iter, ["\\[", "NUMBER", "\\]"])
	if arr:
		var num = str(arr[1]["text"]).to_int()
		if arg.is_imm: push_error("Can't have array access on top of immediate")
		arg.is_imm = true;
		arg.offset = num;
		arg.is_deref = true;
	return arg;

func get_reg(rname:String):
	rname = rname.to_upper();
	var idx = 0;
	if rname in ISA.regnames:
		idx = ISA.regnames.find(rname);
		return {"idx":idx, "name":rname};
	else: return null;
#------------- CODE GEN -----------


func emit_opcode(cmd:int, flags:Cmd_flags, reg1:int=0, reg2:int=0, imm_u32:int=0, shadow_flags={}):
	assert(write_pos % cmd_size == 0);
	emit8(cmd, ISA.SHADOW_CMD_HEAD);
	emit8(flags.to_byte(), ISA.SHADOW_CMD_TAIL);
	emit8((reg1 & 0b1111) | ((reg2 & 0b1111) << 4), ISA.SHADOW_CMD_TAIL);
	var tail_flag = ISA.SHADOW_CMD_TAIL;
	if "unresolved" in shadow_flags and shadow_flags.unresolved: tail_flag = ISA.SHADOW_CMD_UNRESOLVED;
	emit32(imm_u32, tail_flag);
	emit8(0xFF, ISA.SHADOW_CMD_TAIL); # pad

func emit8(val:int, shadow_val:int):
	if (val < 0) or (val > 255): push_error("can't emit value, doesn't fit in byte: ["+str(val)+"]")
	if len(code) <= write_pos: code.resize(write_pos+1); shadow.resize(write_pos+1);
	code[write_pos] = val;
	shadow[write_pos] = shadow_val;
	write_pos += 1;

func emit32(val:int, shadow_val:int):
	if (val < 0) or (val > (2**32-1)): push_error("can't emit value, doesn't fit in u32: ["+str(val)+"]")
	emit8((val >> 8*0) & 0xFF, shadow_val);
	emit8((val >> 8*1) & 0xFF, shadow_val);
	emit8((val >> 8*2) & 0xFF, shadow_val);
	emit8((val >> 8*3) & 0xFF, shadow_val);	
	
func emit_db_items(items:Array): #maybe we could use the .32 specifier with db too
	for item in items:
		if item["class"] == "NUMBER": # a 32-bit number
			var num = str(item["text"]).to_int();
			emit32(num, ISA.SHADOW_DATA);
		elif item["class"] == "WORD": # it's a label
			emit32(0, ISA.SHADOW_DATA_UNRESOLVED);
			label_refs[write_pos] = item["text"];
		elif item["class"] == "STRING": # a bunch of text
			var text = str(item["text"]).to_ascii_buffer()
			for ch in text:
				emit8(ch, ISA.SHADOW_DATA);
			emit8(0, ISA.SHADOW_DATA);
		else:
			push_error("unknown DB item");
	#if (write_pos % cmd_size): # if not aligned
	#	write_pos += (cmd_size - (write_pos % cmd_size)); # pad until alignement is reached
	while(write_pos % cmd_size):
		emit8(0, ISA.SHADOW_PADDING);
	assert(write_pos % cmd_size == 0);
