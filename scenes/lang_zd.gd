extends Node

var lang_name = "zderp";

var keywords = ["HALT", "RESET", "JMP", "CALL", "RET", "CMP", "INT", "INTRET", 
"MOV", "PUSH", "POP", "ADD", "SUB", "MUL", "DIV", "MOD", "ABS", "NEG", "INC", 
"DEC", "AND", "OR", "XOR", "NOT", "BAND", "BOR", "BXOR", "BNOT", "SHIFT", 
"BSET", "BGET", "BCLEAR", "NOP"];
var registers = ["NONE", "EAX", "EBX", "ECX", "EDX", "IP", "ESP", "ESZ", "ESS", 
"EBP", "IVT", "IVS", "IRQ", "CTRL"];
var extra_keywords = ["JE", "JL", "JG", "DB"];

func get_syntax():
	var syn = CodeHighlighter.new();
	var col_orange = Color(1.0,0.5,0.0,	1);
	var col_red = 	 Color(1.0,0.2,0.1,	1);
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
	var register_color=col_red;
	var comment_color =col_gray;
	var string_color  =col_green;
	add_keywords(syn, keywords, opcode_color);
	add_keywords(syn, extra_keywords, opcode_color);
	add_keywords(syn, registers, register_color);
	syn.add_color_region("#","",comment_color,true);
	syn.add_color_region("\"","\"",string_color,false);
	return syn;

func add_keywords(syn, kws, col):
	for kw in kws:
		syn.keyword_colors[kw.to_upper()] = col;
		syn.keyword_colors[kw.to_lower()] = col;
	
# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
