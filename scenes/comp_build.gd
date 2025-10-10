extends Node

@onready var n_assembler = $comp_asm_zd
@onready var n_compiler = $comp_compile_md
@export var win_tokens:Node;
var cur_efile;
var Memory;
var Editor;
var view_Memory;
var cur_lang = "zderp" # we should probably figure out the lang from extension
#var is_setup = false;

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func setup(dict:Dictionary):
	assert("memory" in dict);
	assert("editor" in dict);
	assert("view_memory" in dict);
	Memory = dict["memory"];
	Editor = dict["editor"];
	view_Memory = dict["view_memory"];
	for ch in get_children():
		if "setup" in ch:
			ch.setup(dict);
		if "tokens_ready" in ch:
			ch.tokens_ready.connect(on_tokens_ready);
		

#func setup(dict:Dictionary):
#	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

func assemble_zderp():
	n_assembler.cur_path = cur_efile.path;
	var chunk = n_assembler.assemble(cur_efile.get_text());
	if G.has(chunk):
		assert("code" in chunk);
		var res = {"code":chunk.code};
		if "shadow" in chunk: res["shadow"] = chunk.shadow;
		return res;

func compile_miniderp():
	n_compiler.cur_path = cur_efile.path;
	var success = n_compiler.compile(cur_efile.get_text());
	if success:
		return {"code":[], "shadow":[]};
	else:
		return null;

func compile():
	if cur_efile:
		if cur_lang == "zderp":
			return assemble_zderp();
		elif cur_lang == "miniderp":
			return compile_miniderp()
	return null;

func upload(code):
	Memory.clear()
	view_Memory.clear();
	view_Memory.add_memory_region(0,len(code),"code");
	var idx = 0;
	# make sure all cells are initialized
	for i in range(len(code)):
		if not code[i]: code[i] = 0
	# actually upload
	for byte in code:
		Memory.writeCell(idx, byte);
		idx += 1;
	print("Uploaded "+str(idx)+" bytes");

func upload_shadow(bytes):
	view_Memory.add_memory_region(len(bytes), len(bytes),"shadow");
	var idx = len(bytes);
	for i in range(len(bytes)):
		if not bytes[i]: bytes[i] = 0
	for byte in bytes:
		Memory.writeCell(idx, byte);
		idx += 1;
	print("shadow memory uploaded");

func add_stack_region():
	var stack_end = 65536;
	var stack_size = 1024;
	var stack_pos = stack_end - stack_size;
	view_Memory.add_memory_region(stack_pos, stack_size, "stack");

func add_screen_region():
	var screen_start = 67536;
	var screen_size = 64*64*7;
	view_Memory.add_memory_region(screen_start, screen_size, "screen");

func _on_build_index_pressed(index):
	if index == 0: # "compile"
		var res = compile();
		#var code = compile();
		if res: 
			Editor.print_console("Compiled successfully");
			upload(res.code);
			upload_shadow(res.shadow);
			add_stack_region();
			add_screen_region();
			Editor.print_console("Code uploaded to memory");
		else: 
			Editor.print_console("Failed to compile");
			push_error("Code did not compile - not uploading")

func _on_comp_file_cur_efile_changed(efile):
	cur_efile = efile;
	n_assembler.cur_filename = efile.file_name;
	n_compiler.cur_filename = efile.file_name;

func set_highlight(from_line, from_col, to_line, to_col):
	var TE = cur_efile.find_child("TextEdit");
	assert(TE != null);
	TE.select(from_line, from_col, to_line, to_col);
	TE.set_caret_line(to_line);
	TE.set_caret_column(to_col);

func _on_comp_asm_zd_highlight_error(from_line, from_col, to_line, to_col):
	print("highlight error ("+str(from_line)+", "+str(from_col)+", "+str(to_line)+", "+str(to_col)+")");
	set_highlight(from_line, from_col, to_line, to_col);

func _on_debug_panel_set_highlight(from_line, from_col, to_line, to_col):
	set_highlight(from_line, from_col, to_line, to_col);


func _on_language_index_pressed(index: int) -> void:
	cur_lang = ["zderp", "miniderp"][index];

func on_tokens_ready(tokens):
	win_tokens.set_tokens(tokens);
