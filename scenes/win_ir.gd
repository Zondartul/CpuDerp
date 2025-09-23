extends Window

@onready var tree = $SC/Tree;
var root = null;

func _ready():
	root = tree.create_item();

func set_stuff(obj, node):
	if obj is Dictionary:
		for key in obj:
			var val = obj[key];
			var leaf:TreeItem = tree.create_item(node);
			leaf.set_text(0, str(key));
			set_stuff(val, leaf);
	elif obj is Array:
		for i in len(obj):
			var val = obj[i];
			var leaf:TreeItem = tree.create_item(node);
			leaf.set_text(0, str(i));
			set_stuff(val, leaf);
	else:
		node.set_text(1, str(obj));
	


func _on_comp_compile_md_ir_ready(IR):
	set_stuff(IR, root);
