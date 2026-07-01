extends Control
# an editor file or "efile" is an object that boths displays an editor
# for a single file, and stores metadata about that file
# like path, language, etc.

@onready var n_text:TextEdit = $TextEdit;

var path = "";
var is_dirty = false; # has file been edited?
var file_name = "";
var tab_idx = 0; 	  # position of this tab in the parent tab container
var language = "";
signal update_my_tab(efile);

# Called when the node enters the scene tree for the first time.
func _ready():
	show_line_numbers();
	pass # Replace with function body.

func show_line_numbers():
	n_text.add_gutter();
	update_line_numbers();

func update_line_numbers():
	var num_lines = n_text.get_line_count();
	#print("update line numbers: "+str(num_lines)+" lines");
	var col_linenum = Color.DIM_GRAY;
	for i in range(num_lines):
		n_text.set_line_gutter_text(i,0,str(i));
		n_text.set_line_gutter_item_color(i,0,col_linenum);
		#n_text.set_line_gutter_text(0,i,str(i));

func file_save(): return file_save_as(path);

func file_save_as(new_path): 
	path = new_path;
	var text = n_text.text;
	var file = FileAccess.open(new_path, FileAccess.WRITE);
	if file:
		file.store_string(text);
		is_dirty = false;
		print("saved file ("+file_name+") to ["+new_path+"]");
		update_my_tab.emit(self);
		return true;
	else:
		print("could not save file ("+file_name+") to ["+new_path+"]");
		return false;

func file_load(new_path):
	var file = FileAccess.open(new_path, FileAccess.READ);
	if file:
		var text = file.get_as_text();
		path = new_path;
		n_text.text = text; 
		print("loaded file ("+name+") from ["+path+"]");
		return true;
	else:
		print("could not load file ("+name+") from ["+path+"]");
		return false;

# Called every frame. 'delta' is the elapsed time since the previous frame.
#var printI = 0;
#func _process(delta):
#	if((printI % 60) == 0):
#		var num_lines = n_text.get_line_count();
#		print("proc: "+str(num_lines)+" lines");
#	printI += 1;
#	pass

func _on_text_edit_text_changed():
	is_dirty = true;
	update_line_numbers();
	update_my_tab.emit(self);

func set_syntax(new_syntax:SyntaxHighlighter):
	n_text.syntax_highlighter = new_syntax;

func get_text():
	return n_text.text;


func _on_text_edit_text_set():
	update_line_numbers();

func highlight_line(loc:LocationRange):#(line_idx, col=-1, length=-1):
	var line_idx = loc.begin.line_idx;
	#print("highlighting line %d, col %d, length %d" % [line_idx, col, length])
	#print("highlighting %s" % str(loc));
	var line_idx_to = loc.end.line_idx;
	var col = loc.begin.col;
	var col_to = loc.end.col;
	if (col == -1) or (col_to == -1): 
		line_idx_to = line_idx+1;
		col = 0;
		col_to = 0;
	#else:
	#	line_idx_to = line_idx;
	#	col_to = col+length;
	#n_text.select(line_idx,0,line_idx+1,0,0);
	n_text.select(line_idx, col, line_idx_to, col_to);	
	var spos = n_text.get_scroll_pos_for_line(line_idx);
	n_text.scroll_vertical = spos-5;

func get_cur_line_idx():
	return n_text.get_caret_line(0);
