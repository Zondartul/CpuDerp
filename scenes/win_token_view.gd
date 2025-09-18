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
	for token in tokens:
		var tooltip = array_to_str(token);
		add_item(token.text, Color.WHITE, tooltip);
		if "token_viewer_newline" in token:
			add_newline();
	call_deferred("hide");

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
