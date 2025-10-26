extends Window

@export var Editor:Node;
@export var comp_file:Node;
@export var tab_EFiles:Node;
@export var comp_build:Node;
@export var debug_panel:Node;

@onready var n_list = $BC/IL;

var watch = [];

func _ready():
	watch = [
		{"node":comp_file, "propname":"cur_efile", "propval":null, "desc":"Editor's efile", "subprop":"language", "subpropval":null},
		{"node":tab_EFiles, "propname":"current_tab", "propval":null, "desc":"Current tab"},
		{"node":comp_build, "propname":"cur_efile", "propval":null, "desc":"Compiler's efile"},
		{"node":comp_build, "propname":"cur_lang", "propval":null, "desc":"Current language"},
		{"node":debug_panel, "propname":"cur_loc", "propval":null, "desc":"Current Location"},
		{"node":debug_panel, "propname":"cur_loc_line", "propval":null, "desc":"loc.line"},
		{"node":debug_panel, "propname":"n_locations", "propval":null, "desc":"num locations"},
	];

func _process(_delta):
	if not visible: return;
	update_watch_vars();
	update_watch_view();

func update_watch_vars():
	for v in watch:
		if v.propname in v.node:
			var val = v.node.get(v.propname);
			v.propval = dbg_to_string(val);
			if val and ("subprop" in v):
				if v.subprop in val:
					var val2 = val.get(v.subprop);
					v.subpropval = dbg_to_string(val2);
		else:
			v.propval = "<no property>";

func dbg_to_string(obj):
	if obj is Node:
		return "Node:"+obj.name;
	else:
		return str(obj);

func update_watch_view():
	n_list.clear();
	for v in watch:
		n_list.add_item("%s: " % v.desc);
		n_list.add_item(str(v.propval));
		if "subprop" in v:
			n_list.add_item("...%s: " % v.subprop);
			n_list.add_item(str(v.subpropval));


func _on_close_requested() -> void:
	hide();
	pass # Replace with function body.
