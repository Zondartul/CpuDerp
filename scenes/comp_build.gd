extends Node

@onready var n_assembler = $comp_asm_zd

var cur_efile;

#var is_setup = false;

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func setup(dict:Dictionary):
	for ch in get_children():
		if "setup" in ch:
			ch.setup(dict);

#func setup(dict:Dictionary):
#	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

func compile():
	if cur_efile:
		n_assembler.cur_path = cur_efile.path;
		n_assembler.assemble(cur_efile.get_text());

func _on_build_index_pressed(index):
	if index == 0: # "compile"
		compile();

func _on_comp_file_cur_efile_changed(efile):
	cur_efile = efile;
	n_assembler.cur_filename = efile.file_name;


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
