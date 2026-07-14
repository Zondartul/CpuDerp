extends Window

@onready var tree:Tree = $TC/Tree;
@onready var view_file:RichTextLabel = $TC/File;
var root:TreeItem = null;

func _ready()->void:
	tree.set_column_expand_ratio(1,3);
	root = tree.create_item();

var array_vertical:bool = false;

func set_stuff(obj, node)->void:
	if obj is Dictionary:
		for key in obj:
			var val:Variant = obj[key];
			var leaf:TreeItem = tree.create_item(node);
			leaf.set_text(0, str(key));
			set_stuff(val, leaf);
	elif obj is Array:
		if array_vertical or (len(obj) and obj[0] is not String):
			for i in len(obj):
				var val:Variant = obj[i];
				var leaf:TreeItem = tree.create_item(node);
				leaf.set_text(0, str(i));
				set_stuff(val, leaf);
		else:
			var text:String = "";
			for i in len(obj):
				var val:Variant = obj[i];
				if val is String:
					text += val + " ";
				elif val == null:
					text += "NULL" + " ";
				else:
					push_error("unrepresentable value in IR window");
			node.set_text(1, text);
	else:
		node.set_text(1, str(obj));
	


func _on_comp_compile_md_ir_ready(IR)->void:
	set_stuff(IR, root);
	update_file_view();

func update_file_view()->void:
	var fp:FileAccess = FileAccess.open("IR.txt", FileAccess.READ);
	var text:String = fp.get_as_text();
	fp.close();
	$TC/File.text = text;
