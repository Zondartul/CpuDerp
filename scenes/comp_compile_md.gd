extends Node

@onready var tokenizer = $tokenizer_md;
@onready var parser = $parser_md;
@onready var analyzer = $analyzer_md;
@onready var codegen = $codegen_md;
@onready var codegen_new = $comp_codegen_new if has_node("comp_codegen_new") else null;
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
	tokenizer.reset();

# Switch between old and new codegen.
# When use_new_codegen is true (default), the new data-driven
# template-based codegen pipeline is used (codegen_master.gd).
# Set to false to fall back to the old codegen_md.gd.
#
# The new pipeline uses the .tg template system and supports
# incremental migration of individual IR commands via
# codegen_master.migrate_op().
var use_new_codegen: bool = true

func compile(input):
	tokenizer.cur_path = cur_path;
	input["tokens"] = tokenizer.tokenize(input);		if has_error: return false;
	if not input.tokens: return;
	input["ast"] = parser.parse(input);				if has_error: return false;
	if not input.ast: return;
	input["IR"] = analyzer.analyze(input);			if has_error: return false;
	input.filename = "IR.txt";
	if use_new_codegen and codegen_new != null:
		input["assy"] = codegen_new.parse_file(input);	if has_error: return false;
		codegen_new.fixup_symtable(analyzer.sym_table); if has_error: return false;
	else:
		input["assy"] = codegen.parse_file(input);	if has_error: return false;
		codegen.fixup_symtable(analyzer.sym_table); if has_error: return false;
	sym_table_ready.emit(analyzer.sym_table);
	save_file(input.assy, "a.zd");
	open_file_request.emit("a.zd");
	return true;
func save_file(text:String, filename:String):
	var fp = FileAccess.open(filename, FileAccess.WRITE);
	if not fp: push_error("Can't save file ["+filename+"]"); has_error = true; return;
	fp.store_string(text);
	fp.close();

func _on_tokenizer_md_tokens_ready(tokens) -> void:
	tokens_ready.emit(tokens);

func set_cur_filename(val): cur_filename = val; tokenizer.cur_filename = val;
func set_cur_path(val): cur_path = val; tokenizer.cur_path = val;



func _on_analyzer_md_ir_ready(new_IR) -> void:
	IR_ready.emit(new_IR);

func _on_analyzer_md_sig_user_error(msg) -> void:
	sig_user_error.emit(msg);
	has_error = true;


func _on_parser_md_sig_parse_ready(stack: Array[AST]) -> void:
	parse_ready.emit(stack);

func _on_parser_md_sig_user_error(msg: String) -> void:
	sig_user_error.emit(msg);
