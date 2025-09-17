extends Node
# miniDerp language reference

var lang_name = "miniderp";

const keywords = ["var", "func", "if", "else", "while", "return"];
const punct_range = ["([{", ")]}"];
const punct_single = [";"];
const punct_multi = ["//"];
const ops_single = [".+-*/%="];

func get_syntax():
	var syn = CodeHighlighter.new();
	var col_orange = Color(1.0,0.5,0.0,	1);
	#var col_red = 	 Color(1.0,0.2,0.1,	1);
	var col_gray = 	 Color(0.5,0.5,0.5,	1);
	var col_yellow = Color(1.0,1.0,0.0,	1);
	var col_purple = Color(0.8,0.4,0.7,	1);
	var col_blue = 	 Color(0.0,0.3,1.0,	1);
	var col_green =  Color(0.2,1.0,0.1,	1);
	syn.member_variable_color = col_yellow;
	syn.number_color = col_orange;
	syn.symbol_color = col_yellow;
	syn.function_color=col_blue;
	var opcode_color = col_purple;
	var comment_color =col_gray;
	var string_color  =col_green;
	add_keywords(syn, keywords, opcode_color);
	syn.add_color_region("//","",comment_color,true);
	syn.add_color_region("\"","\"",string_color,false);
	return syn;

func add_keywords(syn, kws, col):
	for kw in kws:
		syn.keyword_colors[kw.to_upper()] = col;
		syn.keyword_colors[kw.to_lower()] = col;

static func get_all_punct():
	var s = "";
	for list in [punct_range, punct_single, punct_multi, ops_single]:
		for entry in list:
			s += entry;
	return s;
