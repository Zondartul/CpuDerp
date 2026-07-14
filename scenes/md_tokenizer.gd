extends Node

@export var erep:ErrorReporter;

const script_tokenizer:GDScript = preload("res://scenes/word_boundary_tokenizer.gd")
static var lang:Language = preload("res://scenes/lang_md.gd").new()
signal tokens_ready;
signal sig_user_error(msg:String);

#constants
const assign_ops:Array[String] = ["=", "+=", "-=", "*=", "/=", "%="];

const recombinations:Array[Array] = [
	["#", "/*"], ["+", "+"], ["-", "-"], ["+", "="], ["-", "="],
	["!", "="], ["=", "="], ["-", ">"],
	["/WORD", "/NUMBER"], ["/NUMBER", ".", "/NUMBER"],
];

const token_colors:Dictionary[String,Color] = {
	"PREPROC":Color(0.91, 0.576, 0.109, 1.0),
	"KEYWORD":Color(0.974, 0.22, 0.365, 1.0),
	"IDENT":Color(0.693, 0.469, 0.946, 1.0),
	"OP":Color(0.998, 0.998, 0.0, 1.0),
	"NUMBER":Color(1.0, 1.0, 0.0, 1.0),
	"STRING":Color(0.0, 0.827, 0.0, 1.0),
	"PUNCT":Color(0.293, 0.506, 1.0, 1.0),
	"CHAR": Color(1.0, 1.0, 0.0, 1.0),
};

#state
var tokenizer:WordBoundaryTokenizer;
var cur_filename:String;
var cur_path:String;
var cur_line:String = "";
var cur_line_idx:int = 0;
var error_code:String = "";
var output_tokens:Array[Token] = [];


func reset()->void:
	tokenizer = script_tokenizer.new();
	tokenizer.ch_punct = lang.get_all_punct();
	cur_filename = "";
	cur_path = "";
	cur_line = "";
	cur_line_idx = 0;
	error_code = "";
	output_tokens = [];

func user_error(msg)->void: sig_user_error.emit(msg);

func _ready()->void:
	reset();

func tokenize(input:Dictionary, task:Task)->Array[Token]:
	task.work_units_total = 7;
	task.work_units_complete = 0;
	#reset();
	erep.proxy = self
	var text:String = input.text;
	cur_filename = input.filename;
	#output_tokens.clear();
	#cur_line = "";
	#cur_line_idx = 0;
	text = process_includes(text);
	task.work_units_complete += 1;
	var tokens:Array[Token] = basic_tokenize(text);
	task.work_units_complete += 1;
	#tokens_ready.emit(tokens);
	recombine_tokens(tokens);
	task.work_units_complete += 1;
	reclassify_tokens(tokens);
	task.work_units_complete += 1;
	resolve_char_tokens(tokens);
	task.work_units_complete += 1;
	colorize_tokens(tokens);
	task.work_units_complete += 1;
	tokens = filter_tokens(tokens);
	task.work_units_complete += 1;
	
	if error_code != "": return [];
	output_tokens = tokens;
	call_deferred("defer_tokens_ready");	
	return output_tokens;

func defer_tokens_ready()->void:
	tokens_ready.emit(output_tokens);

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
		if error_code != "": return [];
	return tokens;
# ---------- Basic preprocess ---------------------------------

func process_includes(text:String)->String:
	var I:int = text.find("#include")
	while(I != -1):
		var next_word:String = get_word_at(text, I+len("#include"));
		var file_text:String = include_file(next_word);
		text = text.erase(I, text.find("\n",I)) # remove this line
		text = text.insert(I, file_text);
		I = text.find("#include", I);
	return text;

func get_word_at(text:String, I:int)->String:
	while(text[I] in " \t"): I+=1; # skip spaces
	if text[I] == "\n": erep.error(E.ERR_34); return ""; # #include syntax error
	var word:String = "";
	while(text[I] not in " \t\n\r"): word += text[I]; I+=1;
	return word;

func include_file(filepath:String)->String:
	if (cur_path == null) or (cur_path == ""):
		push_error("can't process includes, cur_path is not set");
		assert(false);
	print("Looking for include file [%s]" % filepath);
	var base_dir:String = cur_path.rstrip("/\\"); #remove trailing slash
	filepath = filepath.strip_edges().lstrip("\"").rstrip("\"").lstrip("/\\")
	var canon_path:String = base_dir.path_join(filepath)
	if FileAccess.file_exists(canon_path):
		var fp:FileAccess = FileAccess.open(canon_path, FileAccess.READ)
		return fp.get_as_text();
	else:
		erep.error(E.ERR_35 % canon_path);
		return "";

## preprocess the line: remove comments, trim whitespace, etc
func preproc(line:String)->String:
	line = remove_comments(line);
	#line = G.trim_spaces(line); ##[2025.10.29] need to keep the line intact until we have locations
	return line;

## removes comments from the line. Comments start with the # character and last until end of string.
func remove_comments(line:String)->String:
	var is_string:bool = false;
	var idx:int = 0;
	var prev_ch:String = "";
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



func recombine_tokens(tokens:Array[Token])->Array[Token]:
	var i:int = 0;
	var prev_toks:Array[Token] = [];
	var prev_count:int = 2;
	var lc:LoopCounter = LoopCounter.new(len(tokens)+1);
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
func recombine_pattern_match(toks:Array[Token], pattern:Array[String])->bool:
	for i in range(len(pattern)):
		var p:String = pattern[G.rev_idx(pattern, i)];
		var t:Token = G.maybe_idx(toks, G.rev_idx(toks,i));
		if not t: return false;
		if p == "/*": continue;
		if p == "/WORD" and t.tok_class == "WORD": continue;
		if p == "/NUMBER" and t.tok_class == "NUMBER": continue;
		if t and t.text == p: continue;
		return false;
	return true;

## replaces in-place tokens idx-len ... idx with a single token.
func recombine_n(toks:Array[Token], idx:int, length:int)->void:
	var from:int = idx-length+1;
	for i in range(length-1):
		toks[from].text += toks[from+1].text;
		toks[from].loc.end = toks[from+1].loc.end;
		toks.remove_at(from+1);


## adjusts the token class based on a dictionary
func reclassify_tokens(tokens:Array[Token])->void:
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

## converts 'a' to ASCII code
func resolve_char_tokens(tokens:Array[Token])->void:
	for tok:Token in tokens:
		if tok.tok_class == "CHAR":
			var unescaped:String = tok.text.c_unescape();
			var buff:PackedByteArray = unescaped.to_ascii_buffer();
			var num:int = 0;
			if (buff.size() == 1):
				num = buff[0];
			else: 
				erep.error(E.ERR_33 % tok.text); # bad char literal
				break;
			var old_text:String = tok.text;
			tok.text = str(num);
			#print("md_tokenizer: char token resolved [%s]->[%s]" % [old_text, tok.text]);

## removes unneded tokens
func filter_tokens(tokens:Array[Token])->Array[Token]:
	var filtered:Array[String] = ["SPACE", "ENDSTRING", "ENDCHAR"];
	return tokens.filter(func(tok:Token): return tok.tok_class not in filtered);

func colorize_tokens(toks:Array)->void:
	for tok in toks:
		if tok.tok_class in token_colors:
			#tok["token_viewer_color"] = token_colors[tok.class];
			tok.set_meta("token_viewer_color", token_colors[tok.tok_class]);
