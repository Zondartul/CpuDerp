extends Node
# miniDerp language reference

var lang_name = "miniderp";

const keywords = ["var", "func", "if", "else", "elif", "continue", 
				"break", "while", "return", "extern"];
const types = ["int", "char", "float", "double", "u8", "u16", "u32", "u64",
				"s8", "s16", "s32", "s64"];
const ops = [".", "+", "-", "*", "/", "%", 
			"=", "+=", "-=", "*=", "/=", "%=", 
			"&", "|", "^", ">", "<", "!=", "==",
			"--", "++", "and", "or", "not"];
const punct = [";", "//", "(", "[", "{", ")", "]", "}", "#"];
const punct_range_begin = ["(", "[", "{"];
const punct_range_end = [")", "]", "}"];

# shift-reduce rules
# 0..N-2 - rule input
# N-1 - lookahead
# N - result
const rules = [
	["stmt_list", 					"EOF", "start"],
	["stmt_list", "stmt", 			"*", "stmt_list"],
	["stmt", 						"*", "stmt_list"],
	["/{", "stmt_list", "/}", 		"*", "block"],
	["/{", "/}",					"*", "block"],
	# statements
	["var_decl_stmt", "/;",			"*", "stmt"],
	["assignment_stmt", "/;",		"*", "stmt"],
	["decl_assignment_stmt", "/;",	"*", "stmt"],
	["decl_extern_stmt","/;",		"*", "stmt"],
	["func_decl_stmt",	"/;",		"*", "stmt"],
	["func_def_stmt", 				"*", "stmt"],
	["while_stmt", 					"*", "stmt"],
	["if_stmt",						"*", "stmt"],
	["flow_stmt", "/;",				"*", "stmt"],
	["preproc_stmt", 				"*", "stmt"],
	["expr", "/;", 					"*", "stmt"],
	
	#sub-statements
	#-- var_decl_stmt
	["/var", "IDENT",					"/;", "var_decl_stmt"],
	#-- assignment_stmt
	#["IDENT", "/=", "expr", 			"/;", "assignment_stmt"],
	["expr", "/=", "expr",				"/;", "assignment_stmt"],
	#-- decl_assignment_stmt
	["/var", "assignment_stmt", 		"*", "decl_assignment_stmt"],
	#-- decl_extern_stmt
	["/extern", "var_decl_stmt",		"/;", "decl_extern_stmt"],
	["/extern", "func_decl_stmt",		"/;", "decl_extern_stmt"],
	#-- func_decl_stmt
	["/func", "expr_call",				"/;", "func_decl_stmt"],
	#-- func_def_stmt
	["expr_call",						"/{", "SHIFT"],
	["/func", "expr_call", "block", 	"*", "func_def_stmt"],
	#-- while_stmt
	["/while", "/(", "expr", "/)", 		"*", "while_start"],
	["while_start", "block", 			"*", "while_stmt"],
	#-- if_stmt
	["/if", "/(", "expr", "/)",								"*", "SHIFT"],
	["/if", "/(", "expr", "/)",	"block",					"*", "if_block"],
	["if_block", "/elif", "/(", "expr", "/)",				"*", "SHIFT"],
	["if_block", "/elif", "/(", "expr", "/)", "block",		"*", "if_block"],
	["if_block", "/else", "block",							"*", "if_else_block"],
	["if_block", 											"/else", "SHIFT"],
	["if_block", 											"/elif", "SHIFT"],
	["if_block", 											"/else", "SHIFT"],
	["if_block", 											"*", "if_stmt"],
	["if_else_block", 										"*", "if_stmt"],
	#-- flow_stmt
	["/break",							"/;", "flow_stmt"],
	["/continue",						"/;", "flow_stmt"],
	["/return",							"/;", "flow_stmt"],
	["/return", "expr", 				"/;", "flow_stmt"],
	#-- preproc_stmt
	["/#include", "STRING", 			"*", "preproc_stmt"],
	
	# expressions
	["expr_immediate", 					"*", "expr"],
	["expr_ident", 						"*", "expr"],
	["expr_postfix", 					"*", "expr"],
	["expr_infix", 						"*", "expr"],
	["expr_call",						"*", "expr"],
	["expr_parenthesis",				"*", "expr"],
	
	# sub-expressions
	# -- expr_immediate
	["NUMBER", 							"*", "expr_immediate"],
	["STRING", 							"*", "expr_immediate"],
	# -- expr_ident
	#["IDENT", 							"/=", "SHIFT"],
	["IDENT", 							"*", "expr_ident"],
	# -- expr_postfix
	["expr", "OP", 						"/;", "expr_postfix"],
	["expr", "OP",						"/)", "expr_postfix"],
	["expr", "OP", 						"/]", "expr_postfix"],
	# -- expr_infix
	["expr", "OP", "expr", 				"*", "expr_infix"],
	["expr", "/[", "expr", "/]",		"*", "expr_infix"],
	# -- expr_call
	["expr", "/,", "expr", 				"*", "expr_list"],
	["expr_list", "/,", "expr", 		"*", "expr_list"],
	["expr", "/(", "/)",				"*", "expr_call"],
	["expr", "/(", "expr", "/)",		"*", "expr_call"],
	["expr", "/(", "expr_list", "/)",	"*", "expr_call"],
	["/(", "expr", "/)",				"*", "expr_parenthesis"],
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
	var col_type =	 Color(0.6,0.9,0.6,	1);
	syn.member_variable_color = col_yellow;
	syn.number_color = col_orange;
	syn.symbol_color = col_yellow;
	syn.function_color=col_blue;
	var opcode_color = col_purple;
	var comment_color =col_gray;
	var string_color  =col_green;
	add_keywords(syn, keywords, opcode_color);
	add_keywords(syn, types, col_type);
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
