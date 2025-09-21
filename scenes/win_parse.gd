extends Window

#@onready var container = $SC/BC;
@onready var tree = $SC/Tree
var root;

func set_stack(stack):
	clear();
	root = tree.create_item();
	for item in stack:
		add_ast(item, root);

func clear():
	tree.clear();
	#for ch in container.get_children():
	#	ch.queue_free();

func add_ast(ast, node:TreeItem):
	var leaf = tree.create_item(node);
	leaf.set_text(0, token_to_str(ast));
	if "children" in ast:
		for ch in ast.children:
			add_ast(ch, leaf);

func token_to_str(item):
	var text = "";
	text += item.class;
	if "text" in item and item.text != "":
		text += ": "+item.text;
	return text;


func _on_comp_compile_md_parse_ready(stack):
	set_stack(stack);
