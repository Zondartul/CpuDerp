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


const scene_editorfile:PackedScene = preload("res://editor/editor_file.tscn");

#@onready var n_efiles = $V/EFiles
var n_efiles:int;
var is_setup:bool = false;
@onready var dialog_save:FileDialog = $fd_save
@onready var dialog_load:FileDialog = $fd_load
@onready var dialog_discard:Node = $cd_save_discard
var cur_efile:EditorFile = null;
var default_file_dir:String = "";
var efiles:Array[EditorFile] = [];
var close_file_list:Array[EditorFile] = [];
var op_cancelled:bool = false;
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

func setup(dict:Dictionary)->void:
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



func has_efile(ef_name)->bool:
	if get_efile(ef_name): return true;
	else: return false;

func get_efile(ef_name)->EditorFile:
	for ef in efiles:
		if(ef.file_name == ef_name):
			return ef;
	return null

func switch_to_file(filename)->void:
	var efile:EditorFile = get_efile(filename);
	if(efile): set_cur_efile(efile);

func set_cur_efile(efile)->void:		
	cur_efile = efile;
	if cur_efile: 
		n_efiles.current_tab = cur_efile.tab_idx;
	cur_efile_changed.emit(efile);

func update_efile_tab(efile)->void:
	var title:String = efile.file_name;
	if(efile.is_dirty): title += "(*)";
	n_efiles.set_tab_title(efile.tab_idx, title);

func rename_efile(efile, new_name)->void:
	efile.name = new_name;
	efile.file_name = new_name;
	update_efile_tab(efile);

func new_efile(ef_name)->Node:
	assert(is_setup);
	print("new_efile("+ef_name+")");
	var efile:Node = scene_editorfile.instantiate();
	efiles.append(efile);
	efile.tab_idx = n_efiles.get_tab_count();
	n_efiles.add_child(efile);
	rename_efile(efile, ef_name);
	efile.update_my_tab.connect(_on_efile_update_my_tab);
	return efile;

func remove_efile_actual(efile)->void:
	print("removing")
	n_efiles.remove_child(efile);
	efiles.erase(efile);
	
func async_close_file()->void:
	if cur_efile:
		await async_remove_efile(cur_efile.file_name);

func async_remove_efile(ef_name)->bool:
	print("remove_efile("+ef_name+")");
	var efile:EditorFile = get_efile(ef_name);
	if(efile.is_dirty): 
		set_cur_efile(efile);
		dialog_discard.ask(ef_name);
		var result:String = await dialog_discard.has_result;
		#await dialog_discard.popup_hide;
		if(result == "save"):
			print("save, then remove");
			var res:bool = await async_save_file();
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
	
func async_new_file(new_name:String)->bool:
	#print("new file");
	var efile:EditorFile = get_efile(new_name);
	if efile:
		#print("new: already have that file")
		cur_efile = efile;
		var res:bool = await async_remove_efile(new_name);
		if not res: print("new_file fail"); return false;
	else:
		#print("new: file not yet open");
		pass
	new_efile(new_name);
	set_cur_efile(get_efile(new_name));
	assert(cur_efile != null);
	return true;

func async_save_file()->bool:
	print("save file");
	if cur_efile == null: return false;
	#assert(cur_efile != null);
	if cur_efile.path != "":
		if cur_efile.file_save(): 
			return true;
		else:
			print("save file fail"); return false;
	else:
		var res:bool = await async_save_file_as();
		if not res: print("save file fail"); return false;
		return true;

func async_save_file_as()->bool:
	print("Save file as");
	assert(cur_efile != null);
	dialog_save.popup();
	var path:String = await file_selected;
	cur_efile.path = path;
	var fname:String = path_to_filename(path);
	rename_efile(cur_efile, fname);
	var res:bool = cur_efile.file_save();
	if not res: print("save file as fail"); return false;
	return true;

func async_load_file()->void:
	#print("Load file");
	dialog_load.popup();
	var path:String = await file_selected;
	var fname:String = path_to_filename(path);
	var res:bool = await async_new_file(fname);	
	if not res: print("async_load: fail"); return;
	cur_efile.path = path;
	cur_efile.name = fname;
	cur_efile.file_load(path);
	cur_efile.language = identify_lang(fname);
	cur_efile_changed.emit(cur_efile);

func _on_file_index_pressed(index)->void:
	op_cancelled = false;
	if index == 0: await async_new_file("unnamed");
	if index == 1: await async_save_file();
	if index == 2: await async_save_file_as();
	if index == 3: await async_load_file();
	if index == 4: await async_close_file();

func identify_lang(fname:String)->String:
	var ext:String = fname.get_extension();
	var res:String = "";
	match ext:
		"zd": res = "zderp";
		"md": res = "miniderp";
	return res;

func path_to_filename(path)->String:
	return path.substr(path.rfind("/")+1);

func _on_fd_save_file_selected(path)->void:
	file_selected.emit(path);

func _on_e_files_tab_changed(tab)->void:
	if tab != -1:
		set_cur_efile(n_efiles.get_child(tab));
	else:
		set_cur_efile(null);
	#cur_efile = n_efiles.get_child(tab);

func _on_fd_load_file_selected(path)->void:
	#print("file_selected("+path+")");
	file_selected.emit(path);

func _on_efile_update_my_tab(efile)->void:
	update_efile_tab(efile);

func highlight_line(loc:LocationRange)->void:#(line_idx, col=-1, length=-1):
	if not G.has(loc): 
		return;
	if cur_efile.file_name == loc.begin.filename:
		cur_efile.highlight_line(loc);
	#cur_efile.highlight_line(line_idx, col, length);

func get_cur_line_idx()->int:
	return cur_efile.get_cur_line_idx();
