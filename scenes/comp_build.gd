extends Node

@onready var n_assembler = $comp_asm_zd
@onready var n_compiler = $comp_compile_md
@onready var n_threads = $comp_threads
@export var n_VM:Node;
@export var win_tokens:Node;
var cur_efile;
var Memory;
var Editor;
var view_Memory;
var cur_lang = "";


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
func _process(delta):
	update_task_progress();
#	pass

func assemble_zderp(task:Task):
	n_assembler.cur_path = cur_efile.path;
	var asm_input = {"text":cur_efile.get_text(), "filename":cur_efile.file_name};
	var chunk = n_assembler.assemble(asm_input, task);
	if G.has(chunk):
		assert("code" in chunk);
		var res = {"code":chunk.code};
		if "shadow" in chunk: res["shadow"] = chunk.shadow;
		return res;

func compile_miniderp(task:Task):
	n_compiler.reset();
	n_compiler.cur_path = cur_efile.path.get_base_dir();
	var compiler_input = {"text":cur_efile.get_text(), "filename":cur_efile.file_name};
	var success = n_compiler.compile(compiler_input, task);
	if success:
		return {"code":[], "shadow":[]};
	else:
		return null;

func compile(task:Task):
	if cur_efile:
		if cur_lang == "zderp":
			return assemble_zderp(task);
		elif cur_lang == "miniderp":
			return compile_miniderp(task)
	return null;

func upload(code):
	Memory.clear()
	view_Memory.call_deferred("clear");
	view_Memory.call_deferred("add_memory_region", 0,len(code),"code");
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
	view_Memory.call_deferred("add_memory_region", len(bytes), len(bytes),"shadow");
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
	view_Memory.call_deferred("add_memory_region", stack_pos, stack_size, "stack");

func add_screen_region():
	var screen_start = 67536;
	var screen_size = 64*64*7;
	view_Memory.call_deferred("add_memory_region", screen_start, screen_size, "screen");

func _on_build_index_pressed(index):
	if index == 0: # "compile"
		n_threads.start(compile_async)
	if index == 1: # "test"
		n_threads.check();

func compile_async(task:Task):
	task.user_name = "Compile";
	task.work_units_total = 1;
	
	n_VM.call_deferred("reset"); #.reset();
	Editor.call_deferred("save"); #await Editor.save();
	Editor.call_deferred("clear_console"); #.clear_console();
	
	
	var res = compile(task);
	if res: 
		task.work_units_complete += 1;
		Editor.call_deferred("print_console","Compiled successfully");
		if not (res.code.is_empty()):
			task.work_units_total += 1;
			upload(res.code);
			upload_shadow(res.shadow);
			add_stack_region();
			add_screen_region();
			Editor.call_deferred("print_console", "Code uploaded to memory");
			task.work_units_complete += 1;
	else: 
		task.happy_path = false;
		Editor.call_deferred("print_console", "Failed to compile");
		push_error("Code did not compile - not uploading")
	task.done = true;
	call_deferred("compile_end", task);

func compile_end(task):
	n_threads.end(task);
	update_task_progress();

func _on_comp_file_cur_efile_changed(efile):
	cur_efile = efile;
	if cur_efile:
		cur_lang = efile.language;
		n_assembler.cur_filename = efile.file_name;
		n_compiler.cur_filename = efile.file_name;
	else:
		cur_lang = "";
		n_assembler.cur_filename = "";
		n_compiler.cur_filename = "";

func set_highlight(loc:LocationRange):#(from_line, from_col, to_line, to_col):
	var comp_file = (Editor as Control).get_node("comp_file");
	comp_file.highlight_line(loc);
	## why are we doing this when comp_highlight and editor_file
	##  both alerady have set_highlight?
	#var TE = cur_efile.find_child("TextEdit");
	#assert(TE != null);
	#if G.has(loc):
		#var from_line = loc.begin.line_idx;
		#var from_col = loc.begin.col;
		#var to_line = loc.end.line_idx;
		#var to_col = loc.end.col;
		#TE.select(from_line, from_col, to_line, to_col);
		#TE.set_caret_line(to_line);
		#TE.set_caret_column(to_col);
	#else:
		#TE.deselect();

func _on_comp_asm_zd_highlight_error(loc:LocationRange):#(from_line, from_col, to_line, to_col):
	#print("highlight error ("+str(from_line)+", "+str(from_col)+", "+str(to_line)+", "+str(to_col)+")");
	print("highlight error %s" % loc);
	set_highlight(loc);#(from_line, from_col, to_line, to_col);

func _on_debug_panel_set_highlight(loc:LocationRange):#(from_line, from_col, to_line, to_col):
	set_highlight(loc);#(from_line, from_col, to_line, to_col);


func _on_language_index_pressed(index: int) -> void:
	cur_lang = ["zderp", "miniderp"][index];

func on_tokens_ready(tokens):
	win_tokens.set_tokens(tokens);

var progress_timeout = 0;
func update_task_progress():
	var task = n_threads.get_first_task();
	if task:
		var text = task.get_progress_tree(0);
		Editor.set_progress(text, true);
		progress_timeout = 100;
	else:
		if progress_timeout:
			progress_timeout -= 1;
		else:
			Editor.set_progress("",false);


		
