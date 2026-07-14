extends Window

@export var Editor:Node;
@export var comp_file:Node;
@export var tab_EFiles:Node;
@export var comp_build:Node;
@export var debug_panel:Node;

@onready var n_list = $BC/IL;

var watch:Array[DbgWatchItem] = [];

class DbgWatchItem:
	var node:Node;
	var propname:String;
	var propval:Variant;
	var desc:String;
	var subprop:String;
	var subpropval:Variant;
	func _init(_node:Node,_propname:String,_propval:Variant,_desc:String,_subprop:String="",_subpropval:Variant=null):
		node=_node;
		propname=_propname;propval=_propval;
		desc=_desc;
		subprop=_subprop;subpropval=_subpropval;

func _ready()->void:
	watch = [
		DbgWatchItem.new(comp_file,"cur_efile",null,"Editor's efile","language",null),
		#{"node":comp_file, "propname":"cur_efile", "propval":null, "desc":"Editor's efile", "subprop":"language", "subpropval":null},
		DbgWatchItem.new(tab_EFiles,"current_tab",null,"Current tab"),
		#{"node":tab_EFiles, "propname":"current_tab", "propval":null, "desc":"Current tab"},
		DbgWatchItem.new(comp_build,"cur_efile",null,"Compiler's efile"),
		#{"node":comp_build, "propname":"cur_efile", "propval":null, "desc":"Compiler's efile"},
		DbgWatchItem.new(comp_build,"cur_lang",null,"Current language"),
		#{"node":comp_build, "propname":"cur_lang", "propval":null, "desc":"Current language"},
		DbgWatchItem.new(debug_panel,"cur_loc",null,"Current Location"),
		#{"node":debug_panel, "propname":"cur_loc", "propval":null, "desc":"Current Location"},
		DbgWatchItem.new(debug_panel,"cur_loc_line",null,"loc.line"),
		#{"node":debug_panel, "propname":"cur_loc_line", "propval":null, "desc":"loc.line"},
		DbgWatchItem.new(debug_panel,"n_locations",null,"num locations"),
		#{"node":debug_panel, "propname":"n_locations", "propval":null, "desc":"num locations"},
		DbgWatchItem.new(debug_panel,"all_locs_here_str",null,"locs here"),
		#{"node":debug_panel, "propname":"all_locs_here_str", "propval":null, "desc":"locs here"},
	];

func _process(_delta)->void:
	if not visible: return;
	update_watch_vars();
	update_watch_view();

func update_watch_vars()->void:
	for v in watch:
		if v.propname in v.node:
			var val:Variant = v.node.get(v.propname);
			v.propval = dbg_to_string(val);
			if val and ("subprop" in v):
				if v.subprop in val:
					var val2:Variant = val.get(v.subprop);
					v.subpropval = dbg_to_string(val2);
		else:
			v.propval = "<no property>";

func dbg_to_string(obj)->String:
	if obj is Node:
		return "Node:"+obj.name;
	else:
		return str(obj);

func update_watch_view()->void:
	n_list.clear();
	for v in watch:
		n_list.add_item("%s: " % v.desc);
		print_val(v.propval);
		if "subprop" in v:
			n_list.add_item("...%s: " % v.subprop);
			print_val(v.subpropval);
			
func print_val(val)->void:
	var S:String = val;
	var SS:Array[String] = S.split("\n",false);
	if len(SS) > 1:
		G.complete_line(n_list);
		for S2 in SS:
			n_list.add_item(" ");
			n_list.add_item(S2);
	else:
		n_list.add_item(str(val));
	

func _on_close_requested() -> void:
	hide();
	pass # Replace with function body.
