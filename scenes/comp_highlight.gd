extends Node

# ------- syntax highlighting logic ------------

var ddm_language;
var is_setup = false;
var languages = {};
var cur_language;
var cur_efile;

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func setup(dict:Dictionary):
	assert("ddm_language" in dict);
	ddm_language = dict.ddm_language;
	is_setup = true;
	ddm_language.index_pressed.connect(_on_ddm_language_index_pressed);
	for ch in get_children():
		add_lang(ch);

func _on_ddm_language_index_pressed(index):
	#set_lang(languages[index]);
	var obj = languages[index];
	set_lang_name(obj.lang_name);

func set_lang_name(lname):
	cur_efile.language = lname;
	set_lang(get_lang_by_name(lname));

func get_lang_by_name(lname):
	for key in languages:
		var obj = languages[key];
		if obj.lang_name == lname:
			return obj;
	return null;

func add_lang(obj):
	var idx = ddm_language.item_count;	
	ddm_language.add_item(obj.lang_name, idx);
	languages[idx] = obj;

func set_lang(obj):
	cur_language = obj;
	if cur_efile and cur_language:
		cur_efile.set_syntax(cur_language.get_syntax());

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
	
func _on_comp_file_cur_efile_changed(efile):
	cur_efile = efile;
	if cur_efile:
		set_lang_name(cur_efile.language);
	else:
		set_lang(null);
