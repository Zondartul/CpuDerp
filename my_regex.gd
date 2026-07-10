extends Node
# micro-regex:
# ur_node:
#  type: start, 	^ 
#		 end, 		$ 
#		 char,		a
#		 anychar,	.
#		 sequence, 	abc
#		 choice,	|
#		 star,		*
#		 plus,		+
#		 question,	?
#		 range,		[a-z]
#		 antirange,	[^a-z]
#		 capture_group ()
#  children[]
#  char C;
#  range_buff[255];
#  precedence: int


class RegexTok:
	var type:String = "";
	var children:Array[RegexTok] = [];
	var char:String = "";
	var range:Array[String] = [];
	var precedence:int = 0;

class ParseIter:
	var line:String;
	var i:int;
	func _init(_line:String,_i:int):
		line=_line;
		i=_i;

class RegexMatch:
	#{"id":null, "text":"", "pos":parser.i};
	var id:int;
	var text:String;
	var pos:int;
	func _init(_id:int,_text:String,_pos:int):
		id=_id;
		text=_text;
		pos=_pos;
		
class RegexParser:
	var line:String = "";
	var i:int = 0;
	#var settings:Dictionary = {};
	var matches:Array[RegexMatch] = [];
	var _compile:Callable;# = urp_compile;
	var _match:Callable;# = urp_match;
	func _init(f_compile:Callable, f_match:Callable):
		_compile=f_compile;
		_match=f_match;
	
func char_to_byte(S:String)->int: 
	if S == "":
		return 0; 
	else: 
		return S.to_ascii_buffer()[0];

func byte_to_char(B:int)->String: return String.chr(B);

#func _new_tok()->RegexTok: return RegexTok.new();#{"type":"", "children":[], "char":"", "range":[], "precedence":0};

func _tokenize_range(parse)->RegexTok:
	var tok:RegexTok = RegexTok.new(); #_new_tok();
	parse.i += 1; assert(parse.i < parse.line.length());
	var C:String = parse.line[parse.i];
	#----
	if(C == "^"):
		tok.type = "antirange";
		for b in range(256):
			tok.range.append(byte_to_char(b));
		parse.i += 1; assert(parse.i < parse.line.length());
	else:
		tok.type = "range";
	#---
	var lc:LoopCounter = LoopCounter.new();
	while(parse.i < parse.line.length()):
		lc.step();
		if(C == "]"): break;
		assert((parse.i+1) < parse.line.length());
		var C2:String = parse.line[parse.i+1];
		if(C == "\\"): #escaped char
			tok.range.append(C2);
			parse.i += 2;
		elif(C2 == "-"): #range
			assert((parse.i+2) < parse.line.length());
			var C3:String = parse.line[parse.i+2];
			var new_range:Array[int] = range(char_to_byte(C), char_to_byte(C3)+1);
			if tok.type == "range":
				for b in new_range: tok.range.append(byte_to_char(b));
			else:
				for b in new_range: tok.range.erase(byte_to_char(b));
			parse.i += 3;
		else: #single char
			tok.range.append(C);
			parse.i += 1;
	assert(parse.line[parse.i] == "]");
	parse.i += 1;
	return tok;
# splits a regex format string into regex format tokens
func _tokenize(parse:ParseIter)->Array[RegexTok]:
	var tokens:Array[RegexTok] = [];
	var i:int = parse.i;
	var lc:LoopCounter = LoopCounter.new();
	while(i < parse.line.length()):
		lc.step();
		var tok:RegexTok = RegexTok.new()#_new_tok();
		var C:String = parse.line[i];
		if(C == "^"):	tok.type = "start"; 	tok.precedence = 1; i+=1;
		elif(C == "$"):	tok.type = "end";		tok.precedence = 1; i+=1;
		elif(C == "."): tok.type = "anychar";	tok.precedence = 1; i+=1;
		elif(C == "|"): tok.type = "choice";	tok.precedence = 3; i+=1;
		elif(C == "*"): tok.type = "star";		tok.precedence = 2; i+=1;
		elif(C == "+"): tok.type = "plus";		tok.precedence = 2; i+=1;
		elif(C == "?"): tok.type = "question";	tok.precedence = 2; i+=1;
		elif(C == "["): tok = _tokenize_range(parse);
		elif(C == "("): tok.type = "capture_begin"; tok.precedence = 1; i+=1;
		elif(C == ")"): tok.type = "capture.end"; tok.precedence = 1; i+=1;
		else: tok.type = "char"; tok.char = C; tok.precendence = 1; i+= 1;
		tokens.append(tok);
	return tokens;

func _restack(rx_toks:Array[RegexTok])->void:
	var out_stack:Array[RegexTok] = [];
	var in_stack:Array[RegexTok] = [];
	for tok in rx_toks:
		if(tok.type == "capture_end"): #')'
			var lc:LoopCounter = LoopCounter.new();
			while true: #collect stuff in braces ()
				lc.step();
				assert(not out_stack.is_empty());
				var tok2:RegexTok = out_stack.pop_back();
				if(tok2.type == "capture_begin"): #'('
					var capture_tok:RegexTok = RegexTok.new()#_new_tok();
					capture_tok.type = "capture";
					capture_tok.children = in_stack.duplicate();
					break;
				else:
					in_stack.push_back(tok2);
		else:
			if out_stack.is_empty(): out_stack.push_back(tok);
			else:
				# pick up all tokens of lower precedence
				var lc:LoopCounter = LoopCounter.new();
				while not out_stack.is_empty():
					lc.step();
					if (out_stack.back().precedence < tok.precedence) and \
					(out_stack.back().type != "capture_begin"):
						var tok2:RegexTok = out_stack.pop_back();
						in_stack.push_back(tok2);
					else:
						break;
				out_stack.push_back(tok);
				# put picked up tokens after this one
				lc = LoopCounter.new();
				while not in_stack.is_empty(): 
					lc.step();
					out_stack.push_back(in_stack.pop_back());

# analyzes the regex tokens to build a regex AST
func _analyze(aparse)->RegexTok:
	assert(aparse.i < aparse.size);
	var tok_head:RegexTok = aparse.toks[aparse.i]; aparse.i += 1;
	# 0-arg operators
	if(tok_head.type == "start"):	assert(aparse.i == 1);
	elif(tok_head.type == "end"):	assert(aparse.i+1 <= aparse.size());
	elif(tok_head.type in ["anychar", "char", "capture", "sequence"]): pass;
	# 1-arg operators
	elif(tok_head.type in ["star", "plus", "question"]):
		var opt:RegexTok = _analyze(aparse);
		tok_head.children.push_back(opt);
	# 2-arg operators
	elif(tok_head.type == "choice"):
		var opt1:RegexTok = _analyze(aparse);
		var opt2:RegexTok = _analyze(aparse);
		tok_head.children.push_back(opt1);
		tok_head.children.push_back(opt2);
	else:
		assert(false, "unimplemented regex operator");
	
	if aparse.i >= aparse.size():
		#we've got all of it
		return tok_head;
	else:
		#other stuff after this, make it a sequence
		var ast_list:RegexTok = RegexTok.new(); #_new_tok();
		ast_list.type = "sequence";
		aparse.i += 1;
		var ast_rest:RegexTok = _analyze(aparse);
		ast_list.children.append(ast_rest);
		return ast_list;

# A        A
#  \   ->   \
#   B        B
#
# A			A
#  \		 \
#   A   ->	  B
#    \
#     B

# changes f(f(A,B),C) to f(A,B,C)
func _linearize(ast)->RegexTok:
	if (not ast.children.empty()) and (ast.type in ["sequence", "choice"]):
		var lin_children:Array[RegexTok] = [];
		for ch in ast.children:
			if ch.type == ast.type:
				for ch2 in ch.children:
					lin_children.append(_linearize(ch2));
			else:
				lin_children.append(_linearize(ch));
		ast.children = lin_children;
	return ast;



# compiles a regex format string into a regex operator AST
func compile(regex:String)->RegexTok:
	var parse:ParseIter = ParseIter.new(regex,0); #{"line":regex, "i":0};
	var toks:Array[RegexTok] = _tokenize(parse);
	_restack(toks);
	#var anal_parse = {"toks":toks, "i":0, "size":toks.size()};
	var ast:RegexTok = _analyze(toks);
	ast = _linearize(ast);
	return ast;

# uregex_parser
# line:String -- the string to parse
# i:int   -- offset into the string
# settings:{greedy? etc}
# matches:[
# 	{capture_id, text, pos}
# ]
# --- methods:
# compile(sting)->void
# match(ast)->bool



#func new_parser()->RegexParser: return RegexParser.new(); #{"line":"", "i":0, "settings":{},"matches":[],"compile":urp_compile,"match":urp_match};
func new_parser()->RegexParser: return RegexParser.new(urp_compile, urp_match);
func urp_compile(this:RegexParser, format)->Variant: return compile(format);

# returns true if this ast matches.
# if given a capture group number, puts it into the matches.
func _submatch(this:RegexParser, ast, is_capture_group=false,text_out=null)->bool:
	var parser:RegexParser = this;
	var _match:RegexMatch = RegexMatch.new(0,"",parser.i);#{"id":null, "text":"", "pos":parser.i};
	if(is_capture_group):
		_match.id = parser.matches.size();
		parser.matches.push_back(_match);
	var last_pos:int = parser.i;
	var text_cur:String = "";
	var text_in:Array[String] = [""];
	if text_out: text_out[0] = "";
	var success:bool = false;
	#  type: start, 	^ 
	#		 end, 		$ 
	#		 char,		a
	#		 anychar,	.
	#		 sequence, 	abc
	#		 choice,	|
	#		 star,		*
	#		 plus,		+
	#		 question,	?
	#		 range,		[a-z]
	#		 antirange,	[^a-z]
	#		 capture_group ()
	match ast.type:
		"sequence":
			var ok:bool = true;
			for ch in ast.children():
				var res:bool = _submatch(this, ch, false, text_in);
				if res: text_cur += text_in[0];
				else: ok = false; break;
			success = ok;
		"start": 
			assert(ast.children.empty());
			success = (parser.i == 0);
		"end": 
			assert(ast.children.empty());
			success = (parser.i >= (parser.line.length()-1));
		"char": 
			assert(ast.children.empty());
			success = (parser.line[parser.i] == ast.char); 
			parser.i += 1;
		"anychar": 
			assert(ast.children.empty());
			success = is_anychar(parser.line[parser.i]); 
			parser.i += 1;
		"choice":
			assert(ast.children.size() >= 2);
			var ok:bool = false;
			for ch in ast.children:
				var res:bool = _submatch(this, ch, false, text_in);
				if res: 
					text_cur += text_in[0];
					ok = true;
					break;
				else:
					parser.i = last_pos;
			success = ok;
		"star":
			assert(ast.children.size() == 1);
			var ch:RegexTok = ast.children[0];
			var lc:LoopCounter = LoopCounter.new();
			while parser.i < parser.line.length():
				lc.step();
				var res:bool = _submatch(this, ch, false, text_in);
				if res:	
					text_cur += text_in[0];
					last_pos = parser.i;
				else:
					parser.i = last_pos;
			success = true;
		"plus":
			assert(ast.children.size() == 1);
			var ch:RegexTok = ast.children[0];
			var ok:bool = false;
			var lc:LoopCounter = LoopCounter.new();
			while parser.i < parser.line.length():
				lc.step();
				var res:bool = _submatch(this, ch, false, text_in);
				if res:	
					ok = true;
					text_cur += text_in[0];
					last_pos = parser.i;
				else:
					parser.i = last_pos;
			success = ok;
		"question":
			assert(ast.children.size() == 1);
			var ch:RegexTok = ast.children[0];
			var res:bool = _submatch(this, ch, false, text_in);
			if res: text_cur += text_in[0];
			else: parser.i = last_pos;
			success = true;
		"range":
			assert(ast.children.empty());
	return success;

func is_space(C:String)->bool: return (C in [" ", "\t", "\n", "\r"]);
func is_anychar(C:String)->bool: return not (C in ["\n", "\r"]);
	
func urp_match(this:RegexParser, ast)->bool:
	var parser:RegexParser = this;
	parser.matches = [];
	var res:bool = _submatch(this, ast, true);
	if res:
		return true;
	else: 
		parser.matches = [];
		return false;
