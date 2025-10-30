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
var perf_limiter = {"freq":1, "credit":0.0, "updates":{"mem":true, "color":true, "disasm":true}};
func run_perf_limiter(delta:float):
	perf_limiter.credit += delta;
	var cost = 1.0/float(perf_limiter.freq);
	if perf_limiter.credit >= cost:
		perf_limiter.credit -= cost;
		return true;
	return false;

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

const step = 8;
func align_addr(addr): return addr - addr % step;
func align_size(s): return max(step, s + step-1 - ((s+step-1) % step));

func add_memory_region(m_pos, m_size, m_name):
	m_pos = align_addr(m_pos);
	m_size = align_size(m_size);
	var text = m_name + "\n"+str(m_size);
	var idx = map.add_item(text)
	var handle_info = {"pos":m_pos, "size":m_size, "name":m_name, "item_no":idx};
	handle_map[idx] = handle_info;
	mem_handles.append(handle_info);

var color_fixups = [];
var shadow_at = 0;

func _process(delta):
	var lc = LoopCounter.new();
	while run_perf_limiter(delta):
		lc.step();
		update_mem_view();

func update_mem_view():
	if not perf_limiter.updates.mem: return;
	perf_limiter.updates.mem = false;
	color_fixups = [];
	var selected = map.get_selected_items();
	if not len(selected): memview.clear(); return;
	var handle_idx = selected[0];
	var handle = handle_map[handle_idx];
	var text = "";
	var start = handle["pos"];
	var end = start + handle["size"];
	shadow_at = end;
	#var end_adj = end + (step-end%step); we maybe will need to think about unaligned end of region
	var mode = "hex";
	var n_addr_decimals = len(str(end));
	
	# lets grab the ip and highlight the line
	var ip = cpu_vm.regs[ISA.REG_IP];
	
	for i in range(start, end, step):
		var line_text = "";
		if i == ip: line_text += "[bgcolor="+Color.DARK_BLUE.to_html(false)+"]";
		line_text += str(i).pad_zeros(n_addr_decimals)+": ";
		for j in range(i,i+step):
			var val = read_cell(j);
			var shadow_byte = read_cell(shadow_at+j);
			var col:Color = Color.WHITE;
			if shadow_byte in shadow_colors:
				col = shadow_colors[shadow_byte];
			#color_fixups.append({"pos":line_text.length(), "line":i, "col":col});
			line_text += "[color="+col.to_html(false)+"]"
			var val_text = "";
			if(mode == "normal"): val_text = str(val);
			if(mode == "hex"): val_text = to_hex(val);
			line_text += val_text + " ";
			line_text += "[/color]";
		if i == ip: line_text += "[/bgcolor]";
		line_text += "| " + interp_text(i,i+step);
		text += line_text + "\n";
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
	perf_limiter.updates.mem = true;
	update_mem_view();

func to_hex(num:int):
	const hex_alph = "0123456789ABCDEF";
	if(num < 0) or (num > 255): return "XX";
	@warning_ignore("integer_division")
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


func _on_cpu_vm_cpu_step_done(_cpu):
	perf_limiter.updates.mem = true; #update_mem_view();


func _on_cpu_vm_mem_accessed(addr: Variant, _val: Variant, _is_write: Variant) -> void:
	var region = get_mem_region(addr);
	if not region:
		var next_up = get_mem_region(addr+1);
		var next_down = get_mem_region(addr-1);
		if next_up and next_down:
			merge_mem_region(next_up, next_down);
			print("mem region: merged")
		elif next_up:
			extend_mem_region(next_up, addr);
			print("mem region: ext up")
		elif next_down:
			extend_mem_region(next_down, addr);
			print("mem region: ext down")
		else:
			add_memory_region(addr, 1, "unk");
			print("mem region: new")

func get_mem_region(addr):
	for handle in mem_handles:
		if (handle.pos <= addr) and (handle.pos + handle.size > addr):
			return handle;
	return null;

func extend_mem_region(handle, addr):
	if handle.pos > addr: 
		var diff = handle.pos - addr;
		handle.pos = align_addr(addr);
		handle.size = align_size(handle.size+diff);
	elif handle.pos + handle.size < addr:
		handle.size = align_size(addr - handle.pos + 1);

func merge_mem_region(handle1, handle2):
	var min_start = min(handle1.pos, handle2.pos);
	var max_end = max(handle1.pos+handle1.size, handle2.pos+handle2.size);
	remove_mem_region(handle2);
	handle1.pos = align_addr(min_start);
	handle1.size = align_size(max_end - min_start + 1);

func remove_mem_region(handle):
	map.remove_item(handle.idx);
	mem_handles.erase(handle);
	handle_map.erase(handle.idx);
