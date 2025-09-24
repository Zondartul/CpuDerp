extends Window

@onready var tree = $SC/Tree;
var root = null;

func _ready():
	tree.set_column_expand_ratio(1,3);
	root = tree.create_item();

var array_vertical = false;

func set_stuff(obj, node):
	if obj is Dictionary:
		for key in obj:
			var val = obj[key];
			var leaf:TreeItem = tree.create_item(node);
			leaf.set_text(0, str(key));
			set_stuff(val, leaf);
	elif obj is Array:
		if array_vertical or (len(obj) and obj[0] is not String):
			for i in len(obj):
				var val = obj[i];
				var leaf:TreeItem = tree.create_item(node);
				leaf.set_text(0, str(i));
				set_stuff(val, leaf);
		else:
			var text = "";
			for i in len(obj):
				var val = obj[i];
				if val is String:
					text += val + " ";
				elif val == null:
					text += "NULL" + " ";
				else:
					push_error("unrepresentable value in IR window");
			node.set_text(1, text);
	else:
		node.set_text(1, str(obj));
	


func _on_comp_compile_md_ir_ready(IR):
	set_stuff(IR, root);
