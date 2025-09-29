extends Node

var IR = {};

func parse_file(filename):
	var fp = FileAccess.open(filename, FileAccess.READ);
	var text = fp.get_as_text();
	fp.close();
	var lines = text.split("\n",false);
	
	var path = [];
	for line in lines:
		if len(line) == 0: continue;
		if line[0] == "#": continue;
		var indent = find_first_not_of(line, " ");
		path.resize(indent);
		line = line.substr(indent);
		var colon_pos = line.find(":");
		if colon_pos == -1:
			# array-like object
			var words = line.split(" ", false);
			print("parse arr: ["+str(words)+"]");
			IR_append_path(IR, path, words);
		else:
			# key-value object
			var key = line.substr(0, colon_pos);
			var val = line.substr(colon_pos+1);
			print("parse kv: ["+key+"] : ["+val+"]");
			path.append(key);
			var words = val.split(" ",false);
			if len(words):
				IR_append_path(IR, path, words);
	print("parsed IR: ");
	print(IR);

func find_first_not_of(text:String, needle:String):
	var idx = 0;
	for ch in text: 
		if ch in needle:
			idx += 1; 
		else: 
			return idx;
	return -1;

func IR_append_path(dict, path, obj):
	var node = dict;
	var prev_node = node;
	var prev_key = null;
	for key in path:
		if key not in node: 
			node[key] = {};
		prev_node = node;
		prev_key = key;
		node = node[key];
	prev_node[prev_key] = [];
	node = prev_node[prev_key];
	node.append(obj);
