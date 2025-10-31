extends Node
# assembles zvm assemly into machine code
# signals
signal sig_cprint; # cprint(msg:String, col=null) - print a message to console
signal sig_user_error; # user_error(msg:String) - print a user error message
signal tokens_ready;
#signal sig_highlight_line; #highlight_line(line_idx:int) - scroll to and highlight a row of text
@export var erep:ErrorReporter;

# constants
const ISA = preload("res://lang_zvm.gd");
const USE_32BIT_BY_DEFAULT = true;
const USE_WIDE_STRINGS = false;
const cmd_size = 8;
const ch_punct = ".,:[]+;";
const ch_alphabet = "qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM_";
const ch_digits = "1234567890";

# state
var cur_filename:String = ""
var cur_path:String = ""
var code:Array[int] = [];
var shadow:Array[int] = [];
var write_pos:int = 0;
var labels = {};
var final_labels = {};
var label_refs = {};
var label_toks = {};
# error reporting
var lines:PackedStringArray;
var cur_line:String = "";
var cur_line_idx:int = 0;
var error_code:String; #:set = set_error;
#debug info
var op_locations = []
var output_tokens = [];

func reset():
	cur_filename = "";
	cur_path = "";
	code = [];
	shadow = [];
	write_pos = 0;
	labels = {};
	final_labels = {};
	label_refs = {};
	label_toks = {};
	lines.clear();
	cur_line = "";
	cur_line_idx = 0;
	error_code = "";
	op_locations = [];
	output_tokens = [];	

func new_chunk()->Chunk: 
	var res:Chunk = Chunk.new();
	return res;

func duplicate_chunk(in_chunk:Chunk)->Chunk:
	var out_chunk:Chunk = Chunk.new();
	G.duplicate_deep(in_chunk, out_chunk);
	return out_chunk;

func clear()->void:
	reset();
	#cur_filename = "";
	#cur_path = "";
	#code.clear();
	#shadow.clear();
	#write_pos = 0;
	#labels.clear();
	#label_refs.clear();
	#cur_line = "";
	#cur_line_idx = 0;
	#error_code = "";

func assemble(input:Dictionary)->Chunk:
	erep.proxy = self;
	clear();
	var source:String = input.text;
	cur_filename = input.filename;
	output_tokens.clear();
	lines = source.split("\n",true);
	#print(lines);
	var cur_loc = Location.new({"filename":cur_filename, "line":"<assemble.default>", "line_idx":0, "col":0});
	for line in lines:
		if line == "": cur_line_idx += 1; continue;
		cur_line = line;
		cur_loc.line = cur_line;
		cur_loc.line_idx = cur_line_idx;
		cur_loc.col = 0;
		line = preproc(line);
		cur_line = line;
		var tokens = tokenize(line, cur_loc);
		output_tokens.append_array(tokens);
		if output_tokens.size():
			output_tokens.back().set_meta("token_viewer_newline",true);
		assign_line_pos(tokens);
		process(tokens);
		if error_code != "": return Chunk.null_val();
		cur_line_idx += 1;
	tokens_ready.emit(output_tokens);
	var chunk:Chunk = output_chunk();
	chunk = link_internally(chunk);
	var unlinked = len(chunk.refs);
	if unlinked: 
		for ref in chunk.refs:
			var lbl_name = chunk.refs[ref];
			var lbl_tok = chunk.label_toks[ref];
			#var erep = ErrorReporter.new(self, lbl_tok);
			erep.context = lbl_tok;
			erep.error(E.ERR_13 % lbl_name);
			return Chunk.null_val();
		push_error(E.ERR_02 % str(unlinked))
	print("Assembly done");
	print("stats: ")
	print("    "+str(len(chunk.code))+" bytes")
	print("    "+str(len(chunk.labels))+" labels")
	return chunk;

func assign_line_pos(tokens:Array[Token])->void:
	for tok:Token in tokens:
		tok.loc.begin.line = cur_line;
		tok.loc.end.line = cur_line;
		tok.loc.begin.line_idx = cur_line_idx;
		tok.loc.end.line_idx = cur_line_idx;

func cprint(msg):
	sig_cprint.emit(msg);
	
func user_error(msg):
	sig_user_error.emit(msg);
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

func output_chunk()->Chunk:
	var chunk = Chunk.new(
		{"code":code.duplicate(), 
		"labels":labels.duplicate(), 
		"refs":label_refs.duplicate(),
		"label_toks":label_toks.duplicate(), 
		"shadow":shadow.duplicate()});
	code.clear();
	final_labels = labels.duplicate();
	labels.clear();
	label_refs.clear();
	label_toks.duplicate();
	shadow.clear();
	return chunk;

## links the code chunk to itself
##  returns new code chunk
##  only unlinked references remain in the refs section
func link_internally(in_chunk:Chunk)->Chunk:
	var out_chunk = in_chunk.duplicate();
	#var in_code = chunk.code;
	#var in_labels = chunk.labels;
	#var in_refs = chunk.refs;
	#var in_label_toks = chunk.label_toks;
	#
	#var code_out = in_code.duplicate();
	#var shadow_out = chunk.shadow.duplicate();
	var refs_remain = {};
	for ref in in_chunk.refs:
		var lbl_name = in_chunk.refs[ref];
		if lbl_name in in_chunk.labels:
			var lbl_pos = in_chunk.labels[lbl_name];
			var lbl_tok = in_chunk.label_toks[ref];
			patch_ref(out_chunk.code, ref, lbl_pos, out_chunk.shadow, lbl_tok);
		else:
			refs_remain[ref] = lbl_name;
			
	#var out_chunk = {"code":code_out, "labels":in_labels.duplicate(), "refs":refs_remain, "shadow":shadow_out}
	out_chunk.refs = refs_remain;
	return out_chunk;
	 
## modifies the code in-place to alter a command's offset to a given value.
##  ref: position of command (then the immediate value lies in bytes [ref+3...ref+7)
##  lbl_pos: the new value to insert
func patch_ref(out_code:Array, ref:int, lbl_pos:int, out_shadow:Array, lbl_tok:Token)->void:
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
		_: push_error(E.ERR_03); assert(false);
	#var erep:ErrorReporter = ErrorReporter.new(self, lbl_tok);
	erep.context = lbl_tok;
	emit32(lbl_pos, shadow_flag);
	code = old_code;
	write_pos = old_wp;
	shadow = old_shadow;

#-------------- INTERNAL DATA ------------------------
# command structure:
# bytes	0		1		2		3	4	5	6	7 
#	  [cmd]	[ flags ][reg1|reg2][immediate u32][pad]

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
	

#class Cmd_arg:
	#var is_present:bool = false; #did we get supplied with this arg in assembly?
	#var reg_name:String = "";
	#var reg_idx:int = 0;
	#var offset:int = 0;
	#var is_deref:bool = false;
	#var is_imm:bool = false;
	#var is_32bit:bool = false; # is this even arg-level?
	#var is_unresolved:bool = false; #is this a label that needs to be resolved by linker?

#class Cmd_flags:
	#var deref_reg1:bool = false;
	#var deref_reg2:bool = false;
	#var reg1_im:bool = false;
	#var reg2_im:bool = false; # not encoded
	#var is_32bit:bool = false;
	#var spec_flags:int = 0;
	#func to_byte()->int:
		#return  (int(deref_reg1) << 0) | \
				#(int(deref_reg2) << 1) | \
				#(int(reg1_im) << 2) | \
				#(int(is_32bit) << 3) | \
				#((spec_flags & 0b111) << 4);
	#func set_arg1(arg:Cmd_arg)->void:
		#reg1_im = arg.is_imm;
		#deref_reg1 = arg.is_deref;
	#func set_arg2(arg:Cmd_arg, erep:Error_reporter)->void:
		#reg2_im = arg.is_imm;
		#if reg1_im and reg2_im: 
			#erep.error(ERR_04);
		#deref_reg2 = arg.is_deref;

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
func tokenize(line:String, cur_loc:Location)->Array[Token]:
	var tokens:Array[Token] = [];
	var tok_class = "";
	var cur_tok = "";
	for ch in line:
		var new_tok_class = tok_ch_class(ch);
		if should_split_on_transition(new_tok_class, tok_class):
			if tok_class == "STRING" and new_tok_class == "STRING":
				new_tok_class = "ENDSTRING";
				cur_tok = cur_tok.substr(1); #remove the leading \"
			if cur_tok != "":
				var t_loc = to_tok_loc(cur_loc, cur_tok);
				tokens.append(Token.new({"tok_class":tok_class, "text":cur_tok, "loc":t_loc}));
				cur_tok = "";
			tok_class = new_tok_class;
		cur_tok += ch;
		cur_loc.col += 1;
	if cur_tok != "":
		var t_loc = to_tok_loc(cur_loc, cur_tok);
		tokens.append(Token.new({"tok_class":tok_class, "text":cur_tok, "loc":t_loc}));
		cur_tok = "";
	tokens = tokens.filter(filter_tokens);
	return tokens;

func to_tok_loc(cur_loc:Location, cur_tok:String)->LocationRange:
	var t_loc = cur_loc.duplicate();
	t_loc.col -= 1;
	t_loc = LocationRange.from_loc_len(t_loc, len(cur_tok));
	return t_loc;

func should_split_on_transition(new_tok_class:String, old_tok_class:String):
	#if (new_tok_class != tok_class) or (tok_class == "PUNCT"):
	if old_tok_class == "PUNCT": return true; # punctuation tokens are always one-by-one.
	elif old_tok_class == "WORD" and new_tok_class == "NUMBER": return false; #allow numbers to be included in names
	elif old_tok_class == "STRING" and new_tok_class == "STRING": return true; #split on beginning and end of string (ie \")  
	elif old_tok_class == "STRING": return false; # keep building the string
	else: return (old_tok_class != new_tok_class); #split on any other class change
	

func filter_tokens(tok:Token):
	if tok.tok_class in ["SPACE", "ENDSTRING"]: return false;
	return true;


func tok_is_punct(ch:String)->bool: return ch in ch_punct;
func tok_is_word(ch:String)->bool: return ch in ch_alphabet;
func tok_is_num(ch:String)->bool: return ch in ch_digits;

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

func process(tokens:Array[Token])->bool:
	var iter = Iter.new(tokens, 0);
	#var erep:ErrorReporter = ErrorReporter.new(self, iter);
	erep.context = iter;
	var lc = LoopCounter.new(10000);
	while iter.pos != len(iter.tokens):
		lc.step();
		if parse_label(iter) \
		or parse_db(iter) \
		or parse_command(iter):
			pass # all ok, continue to next command
		else:
			erep.context = iter;
			erep.error(E.ERR_12);
			print("current tokens: ");
			print_tokens(tokens);
			return false;
	return true;

func parse_label(iter:Iter)->bool:
	var toks = [];
	if (   match_tokens(iter, ["\\:", "WORD", "\\:"], toks)
		or match_tokens(iter, ["WORD", "\\:"], toks)		):
		var lbl_name = toks[0]["text"];
		if lbl_name == ":": lbl_name = toks[1]["text"];
		if lbl_name in labels:
			user_error("Label already defined: "+lbl_name);
			return false;
		labels[lbl_name] = write_pos;
		#print("Parsed [label:"+lbl_name+"]");
		return true;
	else: return false;

func parse_db(iter:Iter)->bool:
	var old_iter = iter.duplicate();
	if match_tokens(iter, ["\\db"]):
		var items:Array[Token] = [];
		var lc = LoopCounter.new();
		while iter.pos != len(iter.tokens):
			lc.step();
			var toks = []
			if match_tokens(iter, ["STRING"],toks) \
			or match_tokens(iter, ["NUMBER"],toks) \
			or (match_tokens(iter, ["WORD"],toks) and is_label(toks[0]["text"])):
				items.append(toks[0]);
			else:
				push_error(E.ERR_05);
				return false;
			match_tokens(iter, ["\\,"]);
			if match_tokens(iter, ["\\;"]):
				break;
		record_op_position(old_iter, iter);
		emit_db_items(items);
		#add debug info for this instuction
		#print("Parsed DB (count "+str(len(items))+")");
		return true;
	else: return false;

func record_op_position(old_iter:Iter, iter:Iter)->void:
	var tok_first = old_iter.tokens[old_iter.pos];
	var tok_last = iter.tokens[iter.pos-1];
	var begin_col = tok_first.loc.begin.col;
	var end_col = tok_last.loc.end.col;#tok_last.loc.from.col+len(tok_last.text);
	var op = {"ip":write_pos,"filename":cur_filename, "line":cur_line, "line_idx":cur_line_idx, "begin":begin_col, "end":end_col};
	op_locations.append(op);

func parse_command(iter:Iter)->bool:
	var old_iter = iter.duplicate();
	var toks = [];
	if match_tokens(iter, ["WORD"],toks):
		var op_name = str(toks[0].text).to_upper();
		var flags:Cmd_flags = Cmd_flags.new()
		var op_code = 0;
		if op_name in ISA.spec_ops:
			var spec_op = ISA.spec_ops[op_name];
			op_code = spec_op["op_code"];
			flags.spec_flags = spec_op["flags"];
		else:
			op_code = ISA.opcodes.find_key(op_name);
		if not op_code: 
			push_error(E.ERR_07 % op_name); 
			return false;
		flags.is_32bit = USE_32BIT_BY_DEFAULT;
		if match_tokens(iter, ["\\.", "\\32"]): flags.is_32bit = true;
		elif match_tokens(iter, ["\\.", "\\8"]): flags.is_32bit = false;
		#var erep:ErrorReporter = ErrorReporter.new(self, iter);
		erep.context = iter;
		var arg1:Cmd_arg = parse_arg(iter);
		match_tokens(iter, ["\\,"]);
		var arg2:Cmd_arg = parse_arg(iter);
		match_tokens(iter, ["\\;"]); # optional semicolon
		
		# if argument is present: arg1/arg2 gets set
		# if argument is not present: arg1/arg2 stays zero-ed
		# if syntax error: parse_arg pushes an error.
		flags.set_arg1(arg1);
		flags.set_arg2(arg2, erep);
		var shadow_flags = {"unresolved":(arg1.is_unresolved or arg2.is_unresolved)};
		record_op_position(old_iter, iter);
		emit_opcode(op_code, flags, arg1.reg_idx, arg2.reg_idx, arg1.offset+arg2.offset, shadow_flags);
		#print("Parsed ["+op_name+"("+str(int(arg1.is_present) + int(arg2.is_present))+")]")
		return true;
	else: return false;

func is_label(word:String)->bool:
	return (not ISA.opcodes.find_key(word)) and (word not in ISA.spec_ops);

func print_tokens(tokens:Array[Token])->void:
	var S:String = "";
	for tok:Token in tokens:
		S += tok.tok_class+"("+tok.text+")"+"  ";
	print(S);

## peek_tokens:
## 	returns tokens if they match pattern
## 	returns null of they don't or if EOF
## 	pattern is either "class" or "\\text"
func peek_tokens(iter:Iter, ref_toks:Array[String],out=null)->bool:
	var i = iter.pos;
	var res = []
	for rt:String in ref_toks:
		if i >= len(iter.tokens): return false;
		var it = iter.tokens[i];
		assert(len(rt)>0);
		if (rt[0] == "\\") and (it.text == rt.substr(1))\
		or (rt[0] != "\\") and (it.tok_class == rt):
			res.append(it.duplicate());
		else:
			return false;
		i += 1;
	if out != null:
		out.clear(); out.assign(res);
	return true;

## match_tokens:
##  same as peek_tokens but also advances iter by the number of consumed tokens
func match_tokens(iter:Iter, ref_toks:Array[String], out=null)->bool:
	assert(ref_toks is Array);
	var res:Array[Token];
	if peek_tokens(iter, ref_toks, res):	
		iter.pos += len(res);
		if out != null: 
			out.clear(); out.assign(res);
		return true;
	else:
		return false;

# possible addressing modes:
# mnemonic  | ... meaning ......... | reg | deref | offset
# ---------------------------------------------------------
#           | no argument           | no  |   no  | no
#  eax		| register				| yes |   no  | no
#  eax+1	| register+offset		| yes |	  no  | yes 
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
	var toks_word:Array[Token]; 
	if match_tokens(iter, ["WORD"], toks_word):
		arg.is_present = true;
		var word = toks_word[0]["text"]; 
		var reg = get_reg(word);
		var flag = get_flag(word);
		if G.has(reg):
			arg.reg_idx = reg["idx"];
			arg.reg_name = reg["name"];
		elif flag != null:
			arg.is_imm = true;
			arg.offset = flag;
		else: #is label
			var lbl_name = word;
			arg.reg_name = lbl_name;
			arg.is_imm = true;
			arg.is_unresolved = true;
			# register the reference for later,
			# we will patch the command when linking
			label_refs[write_pos+3] = lbl_name;
			label_toks[write_pos+3] = toks_word[0];
	else:
		var toks_num:Array[Token];
		if match_tokens(iter, ["NUMBER"], toks_num):
			arg.is_present = true;
			var word = toks_num[0]["text"];
			var num = str(word).to_int()
			arg.is_imm = true;
			arg.offset = num;
		
	#+123 - offset
	var pos_offs:Array[Token];
	var neg_offs:Array[Token];
	var has_pos_offs = match_tokens(iter, ["\\+", "NUMBER"], pos_offs);
	var has_neg_offs = match_tokens(iter, ["\\-", "NUMBER"], neg_offs);
	assert(not (has_pos_offs and has_neg_offs));
	if has_pos_offs or has_neg_offs:
		var num = 0;
		if has_pos_offs: num = str(pos_offs[1]["text"]).to_int();
		if has_neg_offs: num = - str(neg_offs[1]["text"]).to_int();
		if arg.is_imm: 
			erep.error(E.ERR_08);
			return arg;
		arg.is_imm = true;
		arg.offset = num;
		arg.is_deref = false;
	#[123] - array access
	var pos_arr:Array[Token];
	var neg_arr:Array[Token];
	var has_pos_arr = match_tokens(iter, ["\\[", "NUMBER", "\\]"], pos_arr);
	var has_neg_arr = match_tokens(iter, ["\\[", "\\-", "NUMBER", "\\]"], neg_arr);
	assert(not (has_pos_arr and has_neg_arr));
	if has_pos_arr or has_neg_arr:
		var num = 0;
		if has_pos_arr: num = str(pos_arr[1]["text"]).to_int();
		if has_neg_arr: num = - str(neg_arr[2]["text"]).to_int();
		if arg.is_imm: 
			erep.error(E.ERR_09);
			return arg;
		arg.is_imm = true;
		arg.offset = num;
		if(arg.is_deref):
			erep.error(E.ERR_14);
			return arg;
		arg.is_deref = true;
	return arg;

func get_reg(rname:String)->Dictionary:
	rname = rname.to_upper();
	var idx = 0;
	if rname in ISA.regnames:
		idx = ISA.regnames.find(rname);
		return {"idx":idx, "name":rname};
	else: return {};
	
func get_flag(fname:String):
	fname = fname.to_upper();
	if fname in ISA.ctrl_flag_masks:
		return ISA.ctrl_flag_masks[fname];
	return null;
#------------- CODE GEN -----------


func emit_opcode(cmd:int, flags:Cmd_flags, reg1:int=0, reg2:int=0, imm_u32:int=0, shadow_flags={})->void:
	assert(write_pos % cmd_size == 0);
	emit8(cmd, ISA.SHADOW_CMD_HEAD);
	emit8(flags.to_byte(), ISA.SHADOW_CMD_TAIL);
	emit8((reg1 & 0b1111) | ((reg2 & 0b1111) << 4), ISA.SHADOW_CMD_TAIL);
	var tail_flag = ISA.SHADOW_CMD_TAIL;
	if "unresolved" in shadow_flags and shadow_flags.unresolved: tail_flag = ISA.SHADOW_CMD_UNRESOLVED;
	emit32(imm_u32, tail_flag);
	emit8(0xFF, ISA.SHADOW_CMD_TAIL); # pad

func emit8(val:int, shadow_val:int):
	if (val < 0):
		val = 256 - val;
	if (val < 0) or (val > 255): 
		erep.error(E.ERR_10 % val);
		return;
	if len(code) <= write_pos: code.resize(write_pos+1); shadow.resize(write_pos+1);
	code[write_pos] = val;
	shadow[write_pos] = shadow_val;
	write_pos += 1;

func emit32(val:int, shadow_val:int):
	if(val < 0):
		val = (2**32)+val;
	if (val < 0) or (val > ((2**32)-1)): 
		erep.error(E.ERR_11 % val)
		return;
	emit8((val >> 8*0) & 0xFF, shadow_val);
	emit8((val >> 8*1) & 0xFF, shadow_val);
	emit8((val >> 8*2) & 0xFF, shadow_val);
	emit8((val >> 8*3) & 0xFF, shadow_val);	
	
func emit_db_items(items:Array[Token])->void: #maybe we could use the .32 specifier with db too
	#var erep:ErrorReporter = ErrorReporter.new(self, Token.new());
	erep.context = Token.new();
	for item:Token in items:
		erep.context = item;
		match item.tok_class:
			"NUMBER": # a 32-bit number
				var num = str(item["text"]).to_int();
				emit32(num, ISA.SHADOW_DATA);
			"WORD": # it's a label
				emit32(0, ISA.SHADOW_DATA_UNRESOLVED);
				label_refs[write_pos] = item["text"];
			"STRING": # a bunch of text
				var text = str(item["text"]).to_ascii_buffer()
				for ch in text:
					if USE_WIDE_STRINGS:
						emit32(ch, ISA.SHADOW_DATA);
					else:
						emit8(ch, ISA.SHADOW_DATA);
				#if USE_WIDE_STRINGS:
				#	emit32(0, ISA.SHADOW_DATA, erep);
				#else:
				#	emit8(0, ISA.SHADOW_DATA,erep);
			_:
				erep.error(E.ERR_06);
				return;
	#if (write_pos % cmd_size): # if not aligned
	#	write_pos += (cmd_size - (write_pos % cmd_size)); # pad until alignement is reached
	
	var lc = LoopCounter.new();
	while(write_pos % cmd_size):
		lc.step();
		emit8(0, ISA.SHADOW_PADDING);
	assert(write_pos % cmd_size == 0);
