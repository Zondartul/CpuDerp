extends Node

@onready var tokenizer = $tokenizer_md;
@onready var parser = $parser_md;
@onready var analyzer = $analyzer_md;
@onready var codegen = $codegen_md;
const lang = preload("res://scenes/lang_md.gd");
signal tokens_ready;
signal parse_ready;
signal IR_ready;
signal sig_user_error;
signal open_file_request;
signal sym_table_ready;
#state
var cur_filename: set=set_cur_filename;
var cur_path: set=set_cur_path;
var has_error = false;

func reset():
	cur_filename = "";
	cur_path = "";
	has_error = false;

func compile(text):
	reset();
	var tokens = tokenizer.tokenize(text);		if has_error: return false;
	if not tokens: return;
	var ast = parser.parse(tokens);				if has_error: return false;
	if not ast: return;
	var _IR = analyzer.analyze(ast);			if has_error: return false;
	var _assy = codegen.parse_file("IR.txt");	if has_error: return false;
	codegen.fixup_symtable(analyzer.sym_table); if has_error: return false;
	sym_table_ready.emit(analyzer.sym_table);
	#print(_assy);
	save_file(_assy, "a.zd");
	open_file_request.emit("a.zd");
	return true;
func save_file(text:String, filename:String):
	var fp = FileAccess.open(filename, FileAccess.WRITE);
	if not fp: push_error("Can't save file ["+filename+"]"); has_error = true; return;
	fp.store_string(text);
	fp.close();

func _on_tokenizer_md_tokens_ready(tokens) -> void:
	tokens_ready.emit(tokens);

func set_cur_filename(val): tokenizer.cur_filename = val;
func set_cur_path(val): tokenizer.cur_path = val;



func _on_analyzer_md_ir_ready(new_IR) -> void:
	IR_ready.emit(new_IR);

func _on_analyzer_md_sig_user_error(msg) -> void:
	sig_user_error.emit(msg);
	has_error = true;


func _on_parser_md_sig_parse_ready(stack: Array[AST]) -> void:
	parse_ready.emit(stack);

func _on_parser_md_sig_user_error(msg: String) -> void:
	sig_user_error.emit(msg);
