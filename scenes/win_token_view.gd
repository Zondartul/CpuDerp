extends Window

@onready var content = $BC/SC/FC
var scene_tile:PackedScene = load("res://scenes/tile_label_tooltip.tscn");

func _ready():
	add_item("red", Color.RED, "red");
	add_item("green", Color.GREEN, "green");
	add_item("blue", Color.BLUE, "blue");

func clear():
	for ch in content.get_children():
		ch.queue_free();

func add_item(text:String, col:Color, tooltip:String):
	var tile:Control = scene_tile.instantiate();
	var lbl:Label = tile.get_node(NodePath("M/Label"));
	lbl.text = text;
	lbl.add_theme_color_override("font_color", col);
	lbl.tooltip_text = tooltip;
	content.add_child(tile);

func set_tokens(tokens):
	clear();
	show();
	var prev_line_idx = [null];
	for token in tokens:
		var line_idx = maybe_prop(token, "token_viewer_line");
		if val_changed(line_idx, prev_line_idx):
			add_newline();
		var tooltip = array_to_str(token);
		var color = maybe_prop(token, "token_viewer_color", Color.WHITE);
		add_item(token.text, color, tooltip);
		if "token_viewer_newline" in token:
			add_newline();
	call_deferred("hide");

# returns true if the value changed and saves the new value
func val_changed(new_val, prev_val:Array):
	var res = false;
	if prev_val[0] != null:
		if new_val != prev_val[0]:
			res = true;
	prev_val[0] = new_val;
	return res;

func maybe_prop(obj:RefCounted, propname, default=null):
	if obj.has_meta(propname):
		return obj.get_meta(propname, default);
	elif propname in obj:
		return obj[propname];
	return default;

func array_to_str(arr):
	return str(arr);

func add_newline():
	var sp:Control = Control.new();
	#sp.size_flags_horizontal = Control.SIZE_EXPAND;
	content.add_child(sp);
	call_deferred("resize_newline", sp);

func resize_newline(sp):
	sp.custom_minimum_size = Vector2(content.size.x-10, 1);
	sp.size = Vector2(content.size.x-10,1);
