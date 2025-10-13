extends Node

#------------ what this module should do ideally --------
# this node handles multiple-file new/save/load logic,
# provides a "File" drop-down-menu in the menu bar,
# and interacts with a TabContainer where tabs
# for individual files are displayed.
# --------------------------
# The currently active tab is considered the "current file",
# this is reflected through cur_efile, where "efile" is
# an "editor file" node is a single-file editor tab
# that also stores metadata about that file (maybe I should separate the two)
# --------------------------------


const scene_editorfile = preload("res://editor/editor_file.tscn");

#@onready var n_efiles = $V/EFiles
var n_efiles;
var is_setup = false;
@onready var dialog_save = $fd_save
@onready var dialog_load = $fd_load
@onready var dialog_discard = $cd_save_discard
var cur_efile = null;
var default_file_dir = "";
var efiles = [];
var close_file_list = [];
var op_cancelled = false;
signal file_selected(path);
signal cur_efile_changed(efile);

# Called when the node enters the scene tree for the first time.
func _ready():
	if OS.has_feature("editor"):
		default_file_dir = ProjectSettings.globalize_path("res://res/data");
	else:
		default_file_dir = OS.get_executable_path().get_base_dir().path_join("res/data");
	#print("default_file_dir = ["+default_file_dir+"]");
	dialog_save.root_subfolder = default_file_dir;
	dialog_load.root_subfolder = default_file_dir;
	dialog_save.current_dir = default_file_dir;
	dialog_load.current_dir = default_file_dir;
	pass # Replace with function body.

func setup(dict:Dictionary):
	assert("efiles" in dict);
	n_efiles = dict.efiles;
	is_setup = true;

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

# not enough brain to unfuck this
# 1) make a diagram of state transition for waiting on pop-ups and such
# 2) make sure everything works
# 3) throw it into a separate logic component
# ponder: code is spaghett and buggy
# because I have to wait on user
# and I am erronously mixing non-waiting, await, and actually waiting
# with popups and signals
# also, cancel isn't always handled

#-------- okay it basically works now -----------
# [bug] saving an untitled file opens a new file instead of renaming the original



func has_efile(ef_name):
	if get_efile(ef_name): return true;
	else: return false;

func get_efile(ef_name):
	for ef in efiles:
		if(ef.file_name == ef_name):
			return ef;
	return null

func switch_to_file(filename):
	var efile = get_efile(filename);
	if(efile): set_cur_efile(efile);

func set_cur_efile(efile):
	cur_efile = efile;
	n_efiles.current_tab = cur_efile.tab_idx;
	cur_efile_changed.emit(efile);

func update_efile_tab(efile):
	var title = efile.file_name;
	if(efile.is_dirty): title += "(*)";
	n_efiles.set_tab_title(efile.tab_idx, title);

func rename_efile(efile, new_name):
	efile.name = new_name;
	efile.file_name = new_name;
	update_efile_tab(efile);

func new_efile(ef_name):
	assert(is_setup);
	print("new_efile("+ef_name+")");
	var efile = scene_editorfile.instantiate();
	efiles.append(efile);
	efile.tab_idx = n_efiles.get_tab_count();
	n_efiles.add_child(efile);
	rename_efile(efile, ef_name);
	efile.update_my_tab.connect(_on_efile_update_my_tab);
	return efile;

func remove_efile_actual(efile):
	print("removing")
	n_efiles.remove_child(efile);
	efiles.erase(efile);
	

func async_remove_efile(ef_name):
	print("remove_efile("+ef_name+")");
	var efile = get_efile(ef_name);
	if(efile.is_dirty): 
		set_cur_efile(efile);
		dialog_discard.ask(ef_name);
		var result = await dialog_discard.has_result;
		#await dialog_discard.popup_hide;
		if(result == "save"):
			print("save, then remove");
			var res = await async_save_file();
			if not res: print("remove file fail"); return false;
			remove_efile_actual(efile);
			return true;
		elif(result == "discard"):
			print("discard");
			remove_efile_actual(efile);
			return true;
		else: #cancel
			print("cancel, do not remove");
			return false;
	else:
		print("clean");
		remove_efile_actual(efile);
		return true;
	
func async_new_file(new_name):
	#print("new file");
	var efile = get_efile(new_name);
	if efile:
		#print("new: already have that file")
		cur_efile = efile;
		var res = await async_remove_efile(new_name);
		if not res: print("new_file fail"); return false;
	else:
		#print("new: file not yet open");
		pass
	new_efile(new_name);
	set_cur_efile(get_efile(new_name));
	assert(cur_efile != null);
	return true;

func async_save_file():
	print("save file");
	assert(cur_efile != null);
	if cur_efile.path != "":
		if cur_efile.file_save(): 
			return true;
		else:
			print("save file fail"); return false;
	else:
		var res = await async_save_file_as();
		if not res: print("save file fail"); return false;
		return true;

func async_save_file_as():
	print("Save file as");
	assert(cur_efile != null);
	dialog_save.popup();
	var path = await file_selected;
	cur_efile.path = path;
	var fname = path_to_filename(path);
	rename_efile(cur_efile, fname);
	var res = cur_efile.file_save();
	if not res: print("save file as fail"); return false;
	return true;

func async_load_file():
	#print("Load file");
	dialog_load.popup();
	var path = await file_selected;
	var fname = path_to_filename(path);
	var res = await async_new_file(fname);	
	if not res: print("async_load: fail"); return;
	cur_efile.path = path;
	cur_efile.name = fname;
	cur_efile.file_load(path);

func _on_file_index_pressed(index):
	op_cancelled = false;
	if index == 0: await async_new_file("unnamed");
	if index == 1: await async_save_file();
	if index == 2: await async_save_file_as();
	if index == 3: await async_load_file();

func path_to_filename(path):
	return path.substr(path.rfind("/")+1);

func _on_fd_save_file_selected(path):
	file_selected.emit(path);

func _on_e_files_tab_changed(tab):
	cur_efile = n_efiles.get_child(tab);

func _on_fd_load_file_selected(path):
	#print("file_selected("+path+")");
	file_selected.emit(path);

func _on_efile_update_my_tab(efile):
	update_efile_tab(efile);

func highlight_line(line_idx):
	cur_efile.highlight_line(line_idx);

func get_cur_line_idx():
	return cur_efile.get_cur_line_idx();
