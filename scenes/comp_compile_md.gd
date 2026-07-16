extends Node
class_name CompilerMD

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
var cur_filename:String: set=set_cur_filename;
var cur_path:String: set=set_cur_path;
var has_error:bool = false;

func _ready():
	analyzer.n_IR = $IR_md;
	analyzer.sig_user_error.connect(sig_user_error.emit);

func reset()->void:
	cur_filename = "";
	cur_path = "";
	has_error = false;
	tokenizer.reset();

class Context:
	var tokens:Array[Token];
	var ast:AST;
	var IR:IRKind;
	var filename:String;
	var assy:String;

func compile(input:Build.BuildInput, task:Task)->bool:
	var t_tok:Task = task.add_subtask("tokenize");
	var t_parse:Task = task.add_subtask("parse");
	var t_anz:Task = task.add_subtask("analyze");
	var t_cg:Task = task.add_subtask("codegen");
	var t_lnk:Task = task.add_subtask("link");
	tokenizer.cur_path = cur_path;
	var ctx:Context = Context.new();
	ctx.tokens = tokenizer.tokenize(input, t_tok);	#if has_error: return false;
	if not ctx.tokens or not t_tok.happy_path: task.fail(); return false;
	
	ctx.ast = parser.parse(ctx, t_parse);	#if has_error: return false;
	if not ctx.ast or not t_parse.happy_path: return false;
	
	ctx.IR = analyzer.analyze(ctx, t_anz); #if has_error: return false;
	if not t_anz.happy_path: return false;
	
	ctx.filename = "IR.txt";
	codegen.IR = ctx.IR;
	ctx.assy = codegen.generate(t_cg);#codegen.parse_file(ctx, t_cg); #if has_error: return false;
	if not t_cg.happy_path: return false;
	#codegen.fixup_symtable(analyzer.sym_table, t_lnk); #if has_error: return false;
	#if not t_lnk.happy_path: return false;
	
	call_deferred("defer_sym_table_ready", analyzer.sym_table); #sym_table_ready.emit(analyzer.sym_table);
	#print(_assy);
	save_file(ctx.assy, "a.zd");
	call_deferred("defer_open_file_request", "a.zd");#open_file_request.emit("a.zd");
	t_lnk.mark_done();
	return true;

func defer_open_file_request(arg)->void:
	open_file_request.emit(arg);

func defer_sym_table_ready(arg)->void:
	sym_table_ready.emit(arg);

func save_file(text:String, filename:String)->void:
	var fp:FileAccess = FileAccess.open(filename, FileAccess.WRITE);
	if not fp: push_error("Can't save file ["+filename+"]"); has_error = true; return;
	fp.store_string(text);
	fp.close();

func _on_tokenizer_md_tokens_ready(tokens) -> void:
	tokens_ready.emit(tokens);

func set_cur_filename(val)->void: cur_filename = val; tokenizer.cur_filename = val;
func set_cur_path(val)->void: cur_path = val; tokenizer.cur_path = val;



func _on_analyzer_md_ir_ready(new_IR) -> void:
	IR_ready.emit(new_IR);

func _on_analyzer_md_sig_user_error(msg) -> void:
	sig_user_error.emit(msg);
	has_error = true;


func _on_parser_md_sig_parse_ready(stack: Array[AST]) -> void:
	parse_ready.emit(stack);

func _on_parser_md_sig_user_error(msg: String) -> void:
	sig_user_error.emit(msg);
