extends Control

@onready var map = $BoxContainer/mem_map;
@onready var memview = $BoxContainer/TextEdit;
const ISA = preload("res://lang_zvm.gd");

# memory handles are buttons on the memory map
var mem_handles = [];
var handle_map = {};
var Memory;
var cpu_vm;
var is_setup = false;
#var mvhl:CodeHighlighter = CodeHighlighter.new();

#func _ready():
#	mvhl.add_keyword_color("00", Color.GRAY);
#	mvhl.number_color = Color.WHITE;
#	mvhl.function_color = Color.WHITE;
#	mvhl.symbol_color = Color.WHITE;
#	mvhl.member_variable_color = Color.WHITE;
#	memview.syntax_highlighter = mvhl;

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

var color_fixups = [];
var shadow_at = 0;

func update_mem_view():
	color_fixups = [];
	var selected = map.get_selected_items();
	if not len(selected): memview.clear(); return;
	var handle_idx = selected[0];
	var handle = handle_map[handle_idx];
	var text = "";
	var start = handle["pos"];
	var end = start + handle["size"];
	shadow_at = end;
	var step = 8;
	var end_adj = end + (step-end%step);
	var mode = "hex";
	var n_addr_decimals = len(str(end));
	for i in range(start, end, step):
		var line_text = "";
		line_text = line_text + str(i).pad_zeros(n_addr_decimals)+": ";
		for j in range(i,i+step):
			var val = read_cell(j);
			var col:Color = shadow_colors[read_cell(shadow_at+j)];
			#color_fixups.append({"pos":line_text.length(), "line":i, "col":col});
			line_text = line_text + "[color="+col.to_html(false)+"]"
			var val_text = "";
			if(mode == "normal"): val_text = str(val);
			if(mode == "hex"): val_text = to_hex(val);
			line_text = line_text + val_text + " ";
			line_text = line_text + "[/color]";
		line_text = line_text + "| " + interp_text(i,i+step);
		text = text + line_text + "\n";
	memview.text = text;
#	apply_color_fixups();

#func apply_color_fixups():
	#print("applying "+str(len(color_fixups))+" color patches")
	#for fx in color_fixups:
		#var highlight = mvhl.get_line_syntax_highlighting(fx.line);
		#highlight[0] = Color.DEEP_PINK;

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
	var sbytes:PackedByteArray = PackedByteArray();
	for i in range(from,to):
		bytes.append(read_cell(i));
		sbytes.append(read_cell(shadow_at+i));
	var text = "";
	# try to disassemble
	if is_all_empty(bytes): 
		text = interp_as_text(bytes);
	elif is_shadow_cmd(sbytes):
		var diss = cpu_vm.disasm_pure(bytes);
		if diss: 
			text = to_bb(Color.GREEN, diss);
		else:
			text = to_bb(Color.RED, interp_as_text(bytes));
	elif is_shadow_data(sbytes):
		text = to_bb(Color.YELLOW, interp_as_text(bytes));
	else:
		text = to_bb(Color.DEEP_PINK, interp_as_text(bytes));
	return text;

func to_bb(col:Color, text):
	return "[color=" + col.to_html(false)+"]" + text + "[/color]";

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

const shadow_colors = {
	ISA.SHADOW_UNUSED: Color.GRAY,
	ISA.SHADOW_DATA: Color.YELLOW,
	ISA.SHADOW_CMD_HEAD: Color.GREEN,
	ISA.SHADOW_CMD_TAIL: Color.DARK_GREEN,
	ISA.SHADOW_CMD_RESOLVED: Color.YELLOW_GREEN,
	ISA.SHADOW_CMD_UNRESOLVED: Color.RED,
	ISA.SHADOW_PADDING: Color.WHITE,
	ISA.SHADOW_DATA_UNRESOLVED: Color.ORANGE,
	ISA.SHADOW_DATA_RESOLVED: Color.CYAN,
};

const allowed_cmd_tail_bytes = [
	ISA.SHADOW_CMD_TAIL,
	ISA.SHADOW_CMD_RESOLVED,
	ISA.SHADOW_CMD_UNRESOLVED,
];

const allowed_data_bytes = [
	ISA.SHADOW_DATA,
	ISA.SHADOW_DATA_RESOLVED,
	ISA.SHADOW_DATA_UNRESOLVED,
	ISA.SHADOW_PADDING
];

func is_shadow_cmd(sbytes):
	if not (sbytes[0] == ISA.SHADOW_CMD_HEAD): return false;
	for i in range(1,8):
		if not sbytes[i] in allowed_cmd_tail_bytes:
			return false;
	return true;

func is_shadow_data(sbytes):
	for i in range(8):
		if not sbytes[i] in allowed_data_bytes:
			return false;
	return true;
