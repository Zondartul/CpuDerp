extends Control

@onready var map = $BoxContainer/mem_map;
@onready var memview = $BoxContainer/TextEdit;

# memory handles are buttons on the memory map
var mem_handles = [];
var handle_map = {};
var Memory;
var cpu_vm;
var is_setup = false;

func _ready():
	var mvhl:CodeHighlighter = CodeHighlighter.new();
	mvhl.add_keyword_color("00", Color.GRAY);
	mvhl.number_color = Color.WHITE;
	mvhl.function_color = Color.WHITE;
	mvhl.symbol_color = Color.WHITE;
	mvhl.member_variable_color = Color.WHITE;
	memview.syntax_highlighter = mvhl;

func setup(dict:Dictionary):
	assert("memory" in dict);
	assert("cpu" in dict);
	Memory = dict.memory;
	cpu_vm = dict.cpu;
	is_setup = true;

func clear():
	map.clear();
	mem_handles = [];
	handle_map = {};

func add_memory_region(m_pos, m_size, m_name):
	var text = m_name + "\n"+str(m_size);
	var idx = map.add_item(text)
	var handle_info = {"pos":m_pos, "size":m_size, "name":m_name, "item_no":idx};
	handle_map[idx] = handle_info;
	mem_handles.append(handle_info);

func update_mem_view():
	var selected = map.get_selected_items();
	if not len(selected): memview.clear(); return;
	var handle_idx = selected[0];
	var handle = handle_map[handle_idx];
	var text = "";
	var start = handle["pos"];
	var end = start + handle["size"];
	var step = 8;
	var end_adj = end + (step-end%step);
	var mode = "hex";
	var n_addr_decimals = len(str(end));
	for i in range(start, end, step):
		text = text + str(i).pad_zeros(n_addr_decimals)+": ";
		for j in range(i,i+step):
			var val = read_cell(j);
			var val_text = "";
			if(mode == "normal"): val_text = str(val);
			if(mode == "hex"): val_text = to_hex(val);
			text = text + val_text + " ";
		text = text + "| " + interp_text(i,i+step);
		text = text + "\n";
	memview.text = text;

func read_cell(idx):
	return Memory.readCell(idx);

func _on_mem_map_item_selected(_index):
	update_mem_view();

func to_hex(num:int):
	const hex_alph = "0123456789ABCDEF";
	if(num < 0) or (num > 255): return "XX";
	return hex_alph[num/16] + hex_alph[num % 16];

# returns a string with a possible interpretation of the selected bytes
func interp_text(from, to):
	var bytes:PackedByteArray = PackedByteArray();
	for i in range(from,to):
		bytes.append(Memory.readCell(i));
	var text = "";
	# try to disassemble
	if is_all_empty(bytes): text = interp_as_text(bytes);
	else:
		var diss = cpu_vm.disasm_pure(bytes);
		if diss: text = diss;
		if not diss:	text = interp_as_text(bytes);
	return text;

func interp_as_text(bytes):
	var text = "";
	# if not disassembled, conver to chars
	for i in range(bytes.size()):
		var c = ".";
		var b:int = bytes[i]
		if (b >= 32) and (b <= 127):
			c = String.chr(b);
		text += c;
	return text;

func is_all_empty(bytes):
	for b in bytes:
		if b != 0: return false;
	return true;
