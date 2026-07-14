extends Node

# ------- syntax highlighting logic ------------

var ddm_language:OptionButton;
var is_setup:bool = false;
var languages:Dictionary[int,Language] = {};
var cur_language:Language;
var cur_efile:EditorFile;

# Called when the node enters the scene tree for the first time.
func _ready()->void:
	pass # Replace with function body.

func setup(dict:Dictionary)->void:
	assert("ddm_language" in dict);
	ddm_language = dict.ddm_language;
	is_setup = true;
	ddm_language.index_pressed.connect(_on_ddm_language_index_pressed);
	for ch in get_children():
		add_lang(ch);

func _on_ddm_language_index_pressed(index:int)->void:
	#set_lang(languages[index]);
	var obj:Language = languages[index];
	set_lang_name(obj.lang_name);

func set_lang_name(lname:String)->void:
	cur_efile.language = lname;
	set_lang(get_lang_by_name(lname));

func get_lang_by_name(lname:String)->Node:
	for key in languages:
		var obj:Language = languages[key];
		if obj.lang_name == lname:
			return obj;
	return null;

func add_lang(obj:Node)->void:
	var idx:int = ddm_language.item_count;	
	ddm_language.add_item(obj.lang_name, idx);
	languages[idx] = obj;

func set_lang(obj:Language)->void:
	cur_language = obj;
	if cur_efile and cur_language:
		cur_efile.set_syntax(cur_language.get_syntax());

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
	
func _on_comp_file_cur_efile_changed(efile)->void:
	cur_efile = efile;
	if cur_efile:
		set_lang_name(cur_efile.language);
	else:
		set_lang(null);
