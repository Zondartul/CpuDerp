extends Control

var VM;
var memory;
var console;
var is_setup = false;

func _ready():
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
	dict2["ddm_language"] = $V/MenuBar/Language;
	
	#$comp_file.setup({"efiles":$V/EFiles});
	#$comp_highlight.setup({"ddm_language":$V/MenuBar/Language});
	#$comp_build.setup({"memory":memory, "console":console});
	$comp_file.setup(dict2);
	$comp_highlight.setup(dict2);
	$comp_build.setup(dict2);
	$window_debug/debug_panel.setup(dict2);

func switch_to_file(filename):
	$comp_file.switch_to_file(filename);
