extends Window

@onready var container = $SC/BC;

func set_stack(stack):
	clear();
	for item in stack:
		add_ast(item);

func clear():
	for ch in container.get_children():
		ch.queue_free();

func add_ast(item):
	var tree:Tree = Tree.new();
	container.add_child(tree);
	var root = tree.create_item();
	var text = token_to_str(item);
	root.set_text(0, text);
	if "children" in item:
		for ch in item.children:
			add_sub_ast(ch, tree, root);

func add_sub_ast(ast, tree:Tree, node:TreeItem):
	var leaf = tree.create_item(node);
	leaf.set_text(0, token_to_str(ast));
	if "children" in ast:
		for ch in ast.children:
			add_sub_ast(ch, tree, leaf);

func token_to_str(item):
	var text = "";
	text += item.class;
	if "text" in item and item.text != "":
		text += ": "+item.text;
	return text;


func _on_comp_compile_md_parse_ready(stack):
	set_stack(stack);
