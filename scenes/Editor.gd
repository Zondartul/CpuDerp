extends Control

var VM;
var memory;
var console:RichTextLabel;
var is_setup = false;

func _ready():
	$V/MenuBar/Settings.set_item_submenu_node(0,$V/MenuBar/Settings/Language);
	pass;
	
func setup(dict:Dictionary):
	assert("VM" in dict);
	assert("memory" in dict);
	assert("console" in dict);
	var dict2 = dict.duplicate();
	VM = dict.VM;
	memory = dict.memory;
	console = dict.console;
	is_setup = true;
	dict2["efiles"] = $V/EFiles;
	dict2["ddm_language"] = $V/MenuBar/Settings/Language;
	
	#$comp_file.setup({"efiles":$V/EFiles});
	#$comp_highlight.setup({"ddm_language":$V/MenuBar/Language});
	#$comp_build.setup({"memory":memory, "console":console});
	$comp_file.setup(dict2);
	$comp_highlight.setup(dict2);
	$comp_build.setup(dict2);
	$window_debug/debug_panel.setup(dict2);

func switch_to_file(filename):
	$comp_file.switch_to_file(filename);

func print_console(text, col=Color.GRAY):
	#var console:TextEdit = $V/TE_console;
	console.text += "[color="+col.to_html(false)+"]"+ text + "[/color]" + "\n";
	#scroll to bottom
	#console.scroll_vertical = console.get_line_count();

func clear_console():
	console.text = "";

func _process(_delta):
	if Input.is_action_just_pressed("action_save"):
		await $comp_file.async_save_file();
	if Input.is_action_just_pressed("action_search"):
		$comp_search.popup();

func save():
	await $comp_file.async_save_file();

func _on_view_index_pressed(index: int) -> void:
	match index:
		0: $win_token_view.popup();
		1: $win_parse.popup();
		2: $win_IR.popup();

## signal receiver for "user error" - prints an error message to console
func _on_user_error(msg)->void:
	print_console(msg, Color.RED);

## signal receiver for "cprint" - prints to console
func _on_cprint(msg, col=null)->void:
	if col == null: col = Color.GRAY;
	print_console(msg,col);

## signal receiver for "cclear" - clears the console
func _on_cclear()->void:
	clear_console();

## signal receiver for "highlight_line" - highlights a region in the text editor
func _on_highlight_line(loc:LocationRange)->void:#(line_idx, col=-1, length=-1)->void:
	$comp_file.highlight_line(loc);#(loc.line_idx, loc.col, length);

func get_cur_line_idx()->int:
	return $comp_file.get_cur_line_idx();

func _on_settings_index_pressed(index: int) -> void:
	match index:
		0: pass; # Language...
		1: pass; # Settings
		2: $win_ed_dbg.popup();

func _on_comp_file_cur_efile_changed(efile: Variant) -> void:
	for item_idx in [1,2,4]: #save, save_as, close
		$V/MenuBar/File.set_item_disabled(item_idx, (efile == null));


func _on_edit_index_pressed(index: int) -> void:
	match index:
		0: $comp_search.popup();
