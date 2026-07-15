extends Control

@onready var map:ItemList = $BoxContainer/mem_map;
@onready var memview:RichTextLabel = $BoxContainer/TextEdit;
static var ISA:ISA_ZVM = preload("res://lang_zvm.gd").new();

class MemHandle:
	var pos:int;
	var size:int;
	var name:String;
	var item_no:int;
	var valid:bool;
	func _init(_pos=0,_size=0,_name="",_item_no=0,_valid=true):
		pos=_pos;
		size=_size;
		name=_name;
		item_no=_item_no;
		valid=_valid
	static var _null:MemHandle = MemHandle.new(0,0,"",0,false);
		
# memory handles are buttons on the memory map
var mem_handles:Array[MemHandle] = [];
var handle_map:Dictionary[int,MemHandle] = {};
var Memory:Node;
var cpu_vm:Node;
var is_setup:bool = false;
#var mvhl:CodeHighlighter = CodeHighlighter.new();
## Todo: replace perf_limiter dict with real PerfLimiter/PLDirectory
var perf_limiter:Dictionary = {"freq":1, "credit":0.0, "updates":{"mem":true, "color":true, "disasm":true}};
func run_perf_limiter(delta:float)->bool:
	perf_limiter.credit += delta;
	var cost:float = 1.0/float(perf_limiter.freq);
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

func setup(dict:Dictionary)->void:
	assert("memory" in dict);
	assert("cpu" in dict);
	Memory = dict.memory;
	cpu_vm = dict.cpu;
	is_setup = true;

func clear()->void:
	map.clear();
	mem_handles = [];
	handle_map = {};

const step:int = 8;
func align_addr(addr)->int: return addr - addr % step;
func align_size(s)->int: return max(step, s + step-1 - ((s+step-1) % step));


func add_memory_region(m_pos, m_size, m_name)->MemHandle:
	m_pos = align_addr(m_pos);
	m_size = align_size(m_size);
	var text:String = m_name + "\n"+str(m_size);
	var idx:int = map.add_item(text)
	var handle_info:MemHandle = MemHandle.new(m_pos,m_size,m_name,idx);#{"pos":m_pos, "size":m_size, "name":m_name, "item_no":idx};
	handle_map[idx] = handle_info;
	mem_handles.append(handle_info);
	return handle_info;

func update_memory_handle_text(idx)->void:
	var handle:MemHandle = handle_map[idx]
	var text:String = handle.name + "\n" + str(handle.size);
	map.set_item_text(idx, text);
	
#var color_fixups = [];
var shadow_at:int = 0;

func _process(delta)->void:
	var lc:LoopCounter = LoopCounter.new();
	while run_perf_limiter(delta):
		lc.step();
		update_mem_view();

func update_mem_view()->void:
	if not perf_limiter.updates.mem: return;
	perf_limiter.updates.mem = false;
	#color_fixups = [];
	var selected:PackedInt32Array = map.get_selected_items();
	if not len(selected): memview.clear(); return;
	var handle_idx:int = selected[0];
	var handle:MemHandle = handle_map[handle_idx];
	var text:String = "";
	var start:int = handle.pos;#["pos"];
	var end:int = start + handle.size;#["size"];
	shadow_at = end;
	#var end_adj = end + (step-end%step); we maybe will need to think about unaligned end of region
	var mode:String = "hex";
	var n_addr_decimals:int = len(str(end));
	
	# lets grab the ip and highlight the line
	var ip:int = cpu_vm.regs[ISA.REG_IP];
	
	for i in range(start, end, step):
		var line_text:String = "";
		if i == ip: line_text += "[bgcolor="+Color.DARK_BLUE.to_html(false)+"]";
		line_text += str(i).pad_zeros(n_addr_decimals)+": ";
		for j in range(i,i+step):
			var val:int = read_cell(j);
			var shadow_byte:int = read_cell(shadow_at+j);
			var col:Color = Color.WHITE;
			if shadow_byte in shadow_colors:
				col = shadow_colors[shadow_byte];
			#color_fixups.append({"pos":line_text.length(), "line":i, "col":col});
			line_text += "[color="+col.to_html(false)+"]"
			var val_text:String = "";
			if(mode == "normal"): val_text = str(val);
			if(mode == "hex"): val_text = to_hex(val);
			line_text += val_text + " ";
			line_text += "[/color]";
		if i == ip: line_text += "[/bgcolor]";
		line_text += "| " + interp_text(i,i+step);
		line_text += "| " + interp_numbers(i,i+step);
		text += line_text + "\n";
	memview.text = text;
#	apply_color_fixups();

#func apply_color_fixups():
	#print("applying "+str(len(color_fixups))+" color patches")
	#for fx in color_fixups:
		#var highlight = mvhl.get_line_syntax_highlighting(fx.line);
		#highlight[0] = Color.DEEP_PINK;

func read_cell(idx)->int:
	return Memory.readCell(idx);

func _on_mem_map_item_selected(_index)->void:
	perf_limiter.updates.mem = true;
	update_mem_view();

func to_hex(num:int)->String:
	const hex_alph:String = "0123456789ABCDEF";
	if(num < 0) or (num > 255): return "XX";
	@warning_ignore("integer_division")
	return hex_alph[num/16] + hex_alph[num % 16];

# returns a string with a possible interpretation of the selected bytes
func interp_text(from, to)->String:
	var bytes:PackedByteArray = PackedByteArray();
	var sbytes:PackedByteArray = PackedByteArray();
	for i in range(from,to):
		bytes.append(read_cell(i));
		sbytes.append(read_cell(shadow_at+i));
	var text:String = "";
	# try to disassemble
	if is_all_empty(bytes): 
		text = interp_as_text(bytes);
	elif is_shadow_cmd(sbytes):
		var diss:String = cpu_vm.disasm_pure(bytes);
		if diss: 
			text = to_bb(Color.GREEN, diss);
		else:
			text = to_bb(Color.RED, interp_as_text(bytes));
	elif is_shadow_data(sbytes):
		text = to_bb(Color.YELLOW, interp_as_text(bytes));
	else:
		text = to_bb(Color.DEEP_PINK, interp_as_text(bytes));
	return text;

func interp_numbers(from, to)->String:
	var bytes:PackedByteArray = PackedByteArray();
	for i in range(from,to):
		bytes.append(read_cell(i));
	var text:String = ""
	var I:int = 0;
	while(I+4 <= bytes.size()):
		var num:int = bytes.decode_u32(I);
		text += "%d " % num;
		I += 4;
	return text;

func to_bb(col:Color, text)->String:
	return "[color=" + col.to_html(false)+"]" + text + "[/color]";

func interp_as_text(bytes)->String:
	var text:String = "";
	# if not disassembled, conver to chars
	for i in range(bytes.size()):
		var c:String = ".";
		var b:int = bytes[i]
		if (b >= 32) and (b <= 127):
			c = String.chr(b);
		text += c;
	return text;

func is_all_empty(bytes)->bool:
	for b in bytes:
		if b != 0: return false;
	return true;

const shadow_colors:Dictionary[int,Color] = {
	ISA.SHADOW_UNUSED: Color.GRAY,
	ISA.SHADOW_DATA: Color.YELLOW,
	ISA.SHADOW_CMD_HEAD: Color.GREEN,
	ISA.SHADOW_CMD_TAIL: Color.DARK_GREEN,
	ISA.SHADOW_CMD_RESOLVED: Color.YELLOW_GREEN,
	ISA.SHADOW_CMD_UNRESOLVED: Color.RED,
	ISA.SHADOW_PADDING: Color.WHITE,
	ISA.SHADOW_DATA_UNRESOLVED: Color.ORANGE,
	ISA.SHADOW_DATA_RESOLVED: Color.CYAN,
	ISA.SHADOW_FRAME_PREV_EBP: Color.RED,
	ISA.SHADOW_FRAME_PREV_IP: Color.CYAN,
	ISA.SHADOW_FRAME_ARGUMENT: Color.ORANGE,
	ISA.SHADOW_FRAME_VAR: Color.YELLOW,
	ISA.SHADOW_FRAME_TEMP: Color.PURPLE,
	ISA.SHADOW_FRAME_PADDING: Color.DARK_BLUE,
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

func is_shadow_cmd(sbytes)->bool:
	if not (sbytes[0] == ISA.SHADOW_CMD_HEAD): return false;
	for i in range(1,8):
		if not sbytes[i] in allowed_cmd_tail_bytes:
			return false;
	return true;

func is_shadow_data(sbytes)->bool:
	for i in range(8):
		if not sbytes[i] in allowed_data_bytes:
			return false;
	return true;


func _on_cpu_vm_cpu_step_done(_cpu)->void:
	perf_limiter.updates.mem = true; #update_mem_view();


func _on_cpu_vm_mem_accessed(addr: Variant, _val: Variant, _is_write: Variant) -> void:
	var region:MemHandle = get_mem_region(addr);
	if region.valid:
		var next_up:MemHandle = get_mem_region(addr+1);
		var next_down:MemHandle = get_mem_region(addr-1);
		if next_up.valid and next_down.valid:
			merge_mem_region(next_up, next_down);
			print("mem region: merged")
		elif next_up.valid:
			extend_mem_region(next_up, addr);
			print("mem region: ext up")
		elif next_down.valid:
			extend_mem_region(next_down, addr);
			print("mem region: ext down")
		else:
			var new_reg:MemHandle = add_memory_region(addr, 1, "unk");
			print("mem region: new")
			next_up = get_mem_region(new_reg.pos+new_reg.size);
			next_down = get_mem_region(new_reg.pos-1);
			if next_up.valid and next_down.valid:
				merge_mem_region(next_up, next_down);
				remove_mem_region(new_reg);
				print("mem region: merged2")
			elif next_up.valid:
				extend_mem_region(next_up, addr);
				remove_mem_region(new_reg);
				print("mem region: ext up2")
			elif next_down.valid:
				extend_mem_region(next_down, addr);
				remove_mem_region(new_reg);
				print("mem region: ext down2")

func get_mem_region(addr)->MemHandle:
	for handle in mem_handles:
		if (handle.pos <= addr) and (handle.pos + handle.size > addr):
			return handle;
	return MemHandle._null;

func extend_mem_region(handle, addr)->void:
	if handle.pos > addr: 
		var diff:int = handle.pos - addr;
		handle.pos = align_addr(addr);
		handle.size = align_size(handle.size+diff);
	elif handle.pos + handle.size < addr:
		handle.size = align_size(addr - handle.pos + 1);
	update_memory_handle_text(handle.item_no);
	
func merge_mem_region(handle1, handle2)->void:
	var min_start:int = min(handle1.pos, handle2.pos);
	var max_end:int = max(handle1.pos+handle1.size, handle2.pos+handle2.size);
	remove_mem_region(handle2);
	handle1.pos = align_addr(min_start);
	handle1.size = align_size(max_end - min_start + 1);
	update_memory_handle_text(handle1.item_no);

func remove_mem_region(handle)->void:
	for handle2 in mem_handles:
		if handle2.item_no > handle.item_no:
			handle2.item_no -= 1;
	map.remove_item(handle.item_no);
	mem_handles.erase(handle);
	handle_map.erase(handle.item_no);
	
