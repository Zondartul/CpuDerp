extends Node
# miniDerp language reference

var lang_name = "miniderp";

const keywords = ["var", "func", "if", "else", "while", "return", "and", "or", "not"];
const ops = [".", "+", "-", "*", "/", "%", 
			"=", "+=", "-=", "*=", "/=", "%=", 
			"&", "|", "^", ">", "<", "!=", "==",
			"--", "++",];
const punct = [";", "//", "(", "[", "{", ")", "]", "}", "#"];
const punct_range_begin = ["(", "[", "{"];
const punct_range_end = [")", "]", "}"];

# shift-reduce rules
# 0..N-2 - rule input
# N-1 - lookahead
# N - result
const rules = [
	["stmt_list", "EOF", "start"],
	["/#include", "STRING", "*", "stmt_preproc"],
	["stmt_preproc", "*", "stmt"],
	["NUMBER", "*", "expr_immediate"],
	["STRING", "*", "expr_immediate"],
	["expr_immediate", "*", "expr"],
	["IDENT", "/=", "SHIFT"],
	["IDENT", "*", "expr_ident"],
	["expr_ident", "*", "expr"],
	["IDENT", "/=", "expr", "/;", "*","assignment_stmt"],
	["/var", "assignment_stmt", "*", "decl_assignment_stmt"],
	["assignment_stmt", "*", "stmt"],
	["decl_assignment_stmt", "*", "stmt"],
	["/var", "IDENT", "/;", "*", "var_decl_stmt"],
	["var_decl_stmt", "*", "stmt"],
	["/if", "/(", "expr", "/)", "*", "if_start" ],
	["/{", "stmt_list", "/}", "*", "block"],
	["if_start", "block", "*","if_stmt"],
	["/while", "/(", "expr", "/)", "*", "while_start"],
	["while_start", "block", "*", "while_stmt"],
	["while_stmt", "*", "stmt"],
	["expr", "/;", "*", "stmt"],
	["expr", "OP", "expr", "*", "expr_infix"],
	["expr", "OP", "/;", "expr_postfix"],
	["expr", "OP", "/)", "expr_postfix"],
	["expr", "OP", "/]", "expr_postfix"],
	["expr_postfix", "*", "expr"],
	["expr", "/(", "expr", "/)", "*", "expr_infix"],
	["expr", "/(", "expr_list", "/)", "*", "expr_infix"],
	["expr", "/[", "expr", "/]", "*", "expr_infix"],
	["expr_infix", "*", "expr"],
	["expr", "/,", "expr", "*", "expr_list"],
	["stmt_list", "stmt", "*", "stmt_list"],
	["stmt", "*", "stmt_list"],
];

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
	for list in [punct, ops]:
		for entry in list:
			s += entry;
	return s;
