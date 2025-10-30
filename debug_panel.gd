extends Control
# Debug Panel
const ISA = preload("res://lang_zvm.gd")

@onready var n_regview = $V/TabContainer/reg_view
@onready var n_locals = $V/TabContainer/local_view/V/locals
@onready var n_stackview = $V/TabContainer/stack_view
@onready var n_indicator = $V/TabContainer/local_view/V/H/indicator
@onready var n_hl_locals = $V/TabContainer/HL_locals/V/hl_locals
@onready var win = get_parent();

@onready var slider_top:Control =  $V/TabContainer/pointers/slider_top
@onready var slider_mid:ItemList = $V/TabContainer/pointers/slider_mid
@onready var slider_bot:ItemList = $V/TabContainer/pointers/slider_bot
@onready var n_sb_addr = $V/TabContainer/pointers/H/sb_addr
@onready var n_ob_view = $V/TabContainer/pointers/H/ob_view
@onready var n_sb_offs = $V/TabContainer/pointers/H/sb_offs

const class_PerfLimitDirectory = preload("res://PerfLimitDirectory.gd");

var perf = PerfLimitDirectory.new({
	"all":1.0,
	"regs":0.1,
	"stack":0.1,
	"ip":0.5,
	"pointers":1.0,
	"locals":1.0,
	});

var perf_always_on = ["all", "regs", "stack"];#, "ip"];

var regnames = [
	"NONE",
	"EAX", "EBX", "ECX", "EDX",
	"IP", 
	"ESP", "ESZ", "ESS", "EBP",
	"IVT", "IVS", "IRQ", 
	"CTRL"
];

const BIT_PWR = (0b1 << 0);
const BIT_STEP = (0b1 << 1);
const BIT_IRS = (0b1 << 2);
const BIT_CMP_L = (0b1 << 3);
const BIT_CMP_G = (0b1 << 4);
const BIT_CMP_Z = (0b1 << 5);
const BIT_IE = (0b1 << 6);
const BIT_DEREF1 = (0b1 << 0);
const BIT_DEREF2 = (0b1 << 1);
const BIT_IMDEST = (0b1 << 2);
const BIT_SPEC_IFLESS = (0b1 << 0);
const BIT_SPEC_IFZERO = (0b1 << 1);
const BIT_SPEC_IFGREATER = (0b1 << 2);
const REG_NONE = 0
const REG_EAX = 1;
const REG_EBX = 2;
const REG_ECX = 3;
const REG_EDX = 4;
const REG_IP = 5;
const REG_ESP = 6;
const REG_ESZ = 7;
const REG_ESS = 8;
const REG_EBP = 9;
const REG_IVT = 10;
const REG_IVS = 11;
const REG_IRQ = 12;
const REG_CTRL = 13;
const step_limit = 1000; #how many CPU steps are permitted per frame

var cpu:CPU_vm;
var bus;
var assembler;
var efile;
var editor;
var is_setup = false;
var mode_hex = false;
var stack_items = [];
var slider_base_addr:int = 0;
var cur_sym_table = null;
var symtable_label_ips = [];
var symtable_label_names = [];
enum HighlightMode {NONE, ASM, HIGH_LEVEL};
var highlight_mode = HighlightMode.HIGH_LEVEL;
var loc_map:LocationMap;
var cur_loc:LocationRange: set=set_cur_loc;
var cur_loc_line:String;
var n_locations = 0;
var all_locs_here:Array[LocationRange];
var all_locs_here_str = "";

signal set_highlight(loc:LocationRange);#(from_line, from_col, to_line, to_col);
# Called when the node enters the scene tree for the first time.
func _ready():
	init_reg_view();
	pass # Replace with function body.

func setup(dict:Dictionary):
	assert("cpu" in dict);
	assert("bus" in dict);
	assert("asm" in dict);
	assert("editor" in dict);
	cpu = dict.cpu;
	bus = dict.bus;
	assembler = dict.asm;
	editor = dict.editor;
	is_setup = true;
	init_sliders();
	reset_cpu_history();

func init_reg_view():
	for reg in regnames:
		n_regview.add_item(reg);
		n_regview.add_item("");

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

func format_val(val):
	if mode_hex:
		return "%08X" % val;
	else:
		return "%d" % val;

func update_registers():
	if not perf.regs.run(0): return;
	
	for i in range(regnames.size()):
		var val = cpu.regs[i];
		val = format_val(val);
		n_regview.set_item_text(i*2+1, val);

var op_ips:Array = [];
var op_locations:Array;

func cache_op_locations():
	op_ips = [];
	op_locations = assembler.op_locations.duplicate();
	for op in op_locations:
		op_ips.append(op.ip);

var last_highlighted_line = -1;
func update_ip_highlight():
	if not win.visible: return;
	if not perf.ip.run(0): return;
	
	if highlight_mode == HighlightMode.NONE: return;
	elif highlight_mode == HighlightMode.ASM:
		cur_loc = get_loc_asm();
	elif highlight_mode == HighlightMode.HIGH_LEVEL:
		cur_loc = get_loc_hl();
	set_highlight.emit(cur_loc);

func get_loc_asm()->LocationRange:
	if assembler and assembler.op_locations.size():
		cache_op_locations();
		var ip = cpu.regs[cpu.ISA.REG_IP];
		var idx = op_ips.bsearch(ip, false)-1;
		if(idx >= 0):
			var op = op_locations[idx];
			if op.line_idx != last_highlighted_line:
				last_highlighted_line = op.line_idx;
				editor.switch_to_file(op.filename)
				#set_highlight.emit(op.line, op.begin, op.line, op.end);
				var loc1 = Location.new({"filename":op.filename, "line":op.line, "line_idx":op.line_idx, "col":op.begin});
				var loc2 = Location.new({"filename":op.filename, "line":op.line, "line_idx":op.line_idx, "col":op.end});
				var loc = LocationRange.new({"begin":loc1, "end":loc2});
				return loc;
			return cur_loc;
	return LocationRange.new();

func get_loc_hl():
	#if loc_map:
		#var ip = cpu.regs[cpu.ISA.REG_IP];
		#var idx = loc_map.begin.keys().bsearch(ip, false)-1;
		#if(idx >= 0):
			#var nearest_ip = loc_map.begin.keys()[idx];
			#var loc_arr:Array[LocationRange] = loc_map.begin[nearest_ip];
			#all_locs_here = loc_arr;
			#all_locs_here_str = dbg_locs_to_str(loc_arr);
			#var loc:LocationRange = loc_arr[0];
			#return loc;
	var ELM:Array[ELM_entry] = ExpandedLocationMap;
	if ELM:
		var ip = cpu.regs[cpu.ISA.REG_IP];
		var cmd_idx = ip/cmd_size
		if cmd_idx < len(ELM):
			#if cmd_idx in ELM:
			var entry = ELM[cmd_idx];
			var subentry = entry.hl;
			all_locs_here = [];
			all_locs_here_str = "%d locs here\n" % len(subentry.all_ranges);
			for i in range(len(subentry.all_ranges)):
				var ip_range:IP_range = subentry.all_ranges[i];
				all_locs_here.append(ip_range.loc);
				all_locs_here_str += ("%d: " % i) + ip_range.loc.begin.to_string_full(true) + "\n";
			var smallest_ip = subentry.smallest_ip;
			var loc = smallest_ip.loc;
			return loc;
			#return ELM[cmd_idx].hl.smallest_ip.loc;
	return LocationRange.new();

func dbg_locs_to_str(loc_arr:Array[LocationRange]):
	var S = "";
	for loc in loc_arr:
		S += "%s [%s]\n" % [str(loc), loc.begin.line];
	return S;

func _process(delta):
	if not win.visible: return;
	perf.credit_all(delta);
	update_cpu();
	$V/H2/lbl_history.text = "steps recorded: "+str(cpu_n_steps);

func update_cpu():
	if not win.visible: return;
	update_registers();
	update_stack();
	update_ip_highlight();
	update_pointers();
	update_locals();
	update_HL_locals();
	
func read32(adr):
	var buff = PackedByteArray([0,0,0,0]);
	for i in range(4): buff[i] = bus.readCell(adr+i);
	return buff.decode_u32(0);

#reverse
func read32r(adr):
	var buff = PackedByteArray([0,0,0,0]);
	for i in range(4): buff[3-i] = bus.readCell(adr+i);
	return buff.decode_u32(0);
	
# cpu bug? push/pull store LSB while mov stores MSB
func custom_search(k_has, k_want):
	print("k_has = ["+str(k_has)+"], k_want = "+str(k_want))

# we need to do a binary search among the values of a dictionary,
# for that we need them sorted, so we make an inverse dictionary,
# so that we can then get the key.
var label_inv_dict = {};
var label_ips = [];
var label_names = [];

func update_labels():
	label_inv_dict = {};
	for k:String in assembler.final_labels.keys():
		var v:int = assembler.final_labels[k];
		label_inv_dict[v] = k;

	label_ips = [];
	label_names = [];
	for k:int in label_inv_dict.keys():
		var v:String = label_inv_dict[k];
		label_names.append(v);
		label_ips.append(k);

func assert_materialized(lbl):
	assert(lbl in assembler.final_labels, "Label [%s] not materialized" % str(lbl));

func update_labels_from_sym_table():
	symtable_label_ips.clear();
	symtable_label_names.clear();
	for key in cur_sym_table.funcs:
		var fun = cur_sym_table.funcs[key];
		assert_materialized(fun.lbl.from);
		assert_materialized(fun.lbl.to);
		var ip_from = assembler.final_labels[fun.lbl.from];
		var ip_to = assembler.final_labels[fun.lbl.to];
		symtable_label_ips.append(ip_from);
		symtable_label_names.append(fun.ir_name);
		symtable_label_ips.append(ip_to);
		symtable_label_names.append("(between)");

func decode_ip(ip):
	if(not assembler or (assembler.final_labels.size() == 0)):
		return "(no data)";
	else:
		update_labels();
		var res = null;
		if cur_sym_table:
			update_labels_from_sym_table();
			var idx = symtable_label_ips.bsearch(ip, false)-1;
			if idx != -1: res = symtable_label_names[idx];
			if (idx % 2) == 1: res = "(null)"
		if res == null:
			var idx = label_ips.bsearch(ip, false)-1;
			if idx != -1: res = label_names[idx];
		if res: return res;
		else: return "(null)";
	#return "(no data)";

func update_stack():
	if not perf.stack.run(0): return;
	
	n_stackview.clear();
	n_stackview.max_columns = 3;
	n_stackview.add_item("IP");
	n_stackview.add_item("EBP");
	n_stackview.add_item("Function");
	var cur_ebp = cpu.regs[cpu.ISA.REG_EBP];
	var cur_ip = cpu.regs[cpu.ISA.REG_IP];
	stack_items.clear();
	for i in range(10):
		var cur_func = decode_ip(cur_ip);
		n_stackview.add_item(format_val(cur_ip));
		n_stackview.add_item(format_val(cur_ebp));
		n_stackview.add_item(cur_func);
		stack_items.append({"ip":cur_ip, "ebp":cur_ebp, "fun":cur_func});
		if cur_ebp == 0: break;
		var prev_ebp_adr = cur_ebp+1;
		var prev_ip_adr = cur_ebp+5;
		var prev_ip = read32(prev_ip_adr);
		var prev_ebp = read32(prev_ebp_adr);
		cur_ebp = prev_ebp;
		cur_ip = prev_ip;

func _on_cpu_vm_cpu_step_done(_vm_cpu):
	assert(is_setup);
	#if(cpu.regs[cpu.ISA.REG_CTRL] & cpu.ISA.BIT_STEP):
	#	update_cpu();
	#update_cpu();
	save_cpu_state();

func _on_btn_run_pressed():
	cpu.regs[cpu.ISA.REG_CTRL] &= ~cpu.ISA.BIT_STEP;
	cpu.regs[cpu.ISA.REG_CTRL] |= cpu.ISA.BIT_PWR;
	
func _on_btn_pause_pressed():
	cpu.regs[cpu.ISA.REG_CTRL] ^= cpu.ISA.BIT_PWR;

func _on_btn_stop_pressed():
	cpu.regs[cpu.ISA.REG_CTRL] &= ~cpu.ISA.BIT_PWR; #~cpu.ISA.BIT_STEP;
	cpu.reset();
	reset_cpu_history();
	perf.all.prime();

func _on_btn_step_pressed():
	#cpu.regs[cpu.ISA.REG_CTRL] |= (cpu.ISA.BIT_STEP | cpu.ISA.BIT_PWR);
	if highlight_mode == HighlightMode.HIGH_LEVEL:
		var old_loc = cur_loc;
		for i in range(step_limit):
			if cur_loc != old_loc: break;
			cpu.step();
			cur_loc = get_loc_hl();
		perf.all.prime();
	else:
		cpu.step();
		perf.all.prime();

func _on_btn_next_line_pressed():
	print("unimplemented");

func _on_btn_step_in_pressed():
	print("unimplemented");

func _on_btn_step_out_pressed():
	var cur_ebp = cpu.regs[cpu.ISA.REG_EBP];
	for i in range(10000):
		if(cpu.regs[cpu.ISA.REG_EBP] > cur_ebp): break;
		cpu.step();
	perf.all.prime();

func _on_btn_run_to_line_pressed():
	print("unimplemented");
	var cur_line = editor.get_cur_line_idx();
	var best_oploc = op_locations[0];
	for i in range(len(op_locations)):
		var oploc = op_locations[i];
		if (oploc.line <= cur_line) and (oploc.line > best_oploc.line):
			best_oploc = oploc;
	var target_ip = best_oploc.ip;
	var lc = LoopCounter.new(step_limit);
	while(cpu.regs[cpu.ISA.REG_IP] != target_ip):
		lc.step();
		cpu.step();
	perf.all.prime();

func _on_cb_hex_toggled(toggled_on: bool) -> void:
	mode_hex = toggled_on;
	perf.all.prime();


func get_pointer_tooltip(addr, val)->String:
	var cur_ebp = cpu.regs[cpu.ISA.REG_EBP];
	return "byte %02X (%d) at address %02X (%d)\n(EBP + %d)" % [val, val, addr, addr, (addr-cur_ebp)];

func init_sliders():
	slider_base_addr = int(n_sb_addr.value);
	for i in range(-8,8):
		var addr = slider_base_addr+i;
		var val = bus.readCell(addr);
		var text = "%02X" % val;
		var item = slider_mid.add_item(text);
		slider_mid.set_item_tooltip(item, get_pointer_tooltip(addr, val));
	#for i in range(-8,8):
		#var addr = slider_base_addr+i;
		#var val = bus.readCell(addr);
		#var text = "%d" % val;
		#var item = slider_mid.add_item(text);
		#slider_mid.set_item_tooltip(item, get_pointer_tooltip(addr, val));
	#for i in range(32):
	#	slider_top.add_item("-"); 
	
func update_pointers():
	if not perf.pointers.run(0): return;
	update_mid();
	update_top();

func update_mid():
	slider_base_addr = n_sb_addr.value;
	var idx = 0;
	for i in range(-8,8):
		var addr = slider_base_addr+i;
		var val = bus.readCell(addr);
		var text1 = "%02X" % val;
		#var text1 = str(addr);
		slider_mid.set_item_text(idx, text1);
		slider_mid.set_item_tooltip(idx, get_pointer_tooltip(addr, val));
		var item_col = calc_highlight_color(addr);
		slider_mid.set_item_custom_bg_color(idx, item_col);
		idx += 1;

func calc_highlight_color(addr):
	var item1_col = Color.BLACK;
	var item2_col = Color.BLACK;
	for item in stack_items:
		if addr == item.ip:
			item2_col = Color(0.35, 0.0, 0.0, 1.0);
		if is_in_range(addr, item.ebp+5, item.ebp+9):
			item1_col = Color.RED;
		if addr == item.ebp:
			item2_col = Color(0.0, 0.23, 0.0, 1.0);
		if is_in_range(addr, item.ebp+1, item.ebp+5):
			item1_col = Color.GREEN;
	if addr == cpu.regs[cpu.ISA.REG_ESP]:
		item2_col = Color.CYAN;
	return item1_col.lerp(item2_col, 0.5);

func is_in_range(x,from,to):
	return (x >= from) and (x < to);

const type_sizes = {
		"char":1,
		"sint8":1,
		"uint8":1,
		"sint32":4,
		"uint32":4,
		"float32":4,
		"double":8,
	};

#func pix_to_spaces(px):
	#const sp_width = 12.0;
	#return " ".repeat(int(float(px)/sp_width));
	
func update_top():
	for ch in slider_top.get_children():
		ch.queue_free();
	
	var view_type = n_ob_view.get_item_text(n_ob_view.selected);
	var top_offs = n_sb_offs.value;
	var view_size = type_sizes[view_type];
	#const step_px = 24;
	var offs_real = -(slider_base_addr % view_size) + top_offs;
	#var first_is_blank = 0;
	
	var n_views = ((16-offs_real)/view_size)+1;

	for i in range(n_views):
		var first_item = offs_real + i*view_size;
		var last_item = first_item + view_size - 1;
		if (first_item < 0) or (last_item >= 16): continue;
		var first_rect = slider_mid.get_item_rect(first_item);
		var last_rect = slider_mid.get_item_rect(last_item);
		var vec_from = first_rect.position;
		var vec_to = last_rect.end;
		#
		#var view_panel:Panel = Panel.new();
		#view_panel.set_position(vec_from);
		#view_panel.set_size(vec_to-vec_from);
		#slider_top.add_child(view_panel);
		
		var col_odd = Color(0.176, 0.192, 0.22, 1.0);
		var col_even = Color(0.114, 0.133, 0.161, 1.0);
		
		var view_box:ColorRect = ColorRect.new();
		view_box.color = col_odd;
		var pos = int(slider_base_addr+i*view_size+offs_real-8);
		var is_even = (pos/view_size)%2 == 0;
		if is_even: view_box.color = col_even;
		view_box.set_position(vec_from);
		view_box.set_size(vec_to-vec_from);
		slider_top.add_child(view_box);
		
		var lbl:Label = Label.new();
		lbl.text = get_slider_text(pos, view_type);
		#lbl.text = str(int(pos));
		view_box.add_child(lbl);
		lbl.size = view_box.size;
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER;
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
		
		var cur_ebp = cpu.regs[cpu.ISA.REG_EBP];
		view_box.tooltip_text = "Value at %d+%d (EBP%+d)" % [pos, view_size, pos-cur_ebp];
	#if offs_real:
	#	first_is_blank = 1;
	#	slider_top.set_item_text(0, pix_to_spaces(step_px*offs_real));
	#for i in range(first_is_blank, 16):
	#	slider_top.set_item_text(i, pix_to_spaces(step_px*view_size));
	
func get_slider_text(pos, view_type):
	var view_size = type_sizes[view_type];
	var arr = [];
	for i in range(view_size):
		arr.append(bus.readCell(pos+i));
	var data = PackedByteArray(arr);
	var num = 0;
	match view_type:
		"char": num = data.get_string_from_ascii();
		"sint8": num = data.decode_s8(0);
		"uint8": num = data.decode_u8(0);
		"sint32": num = data.decode_s32(0);
		"uint32": num = data.decode_u32(0);
		"float32": num = data.decode_float(0);
		"double": num = data.decode_double(0);
		_: push_error("debug_panel: unknown view type");
	return str(num);

func _on_sb_addr_value_changed(_value: float) -> void:
	perf.pointers.prime();

var always_update_locals = false;

@onready var n_locals_view = $V/TabContainer/local_view/V/H/ob_view;

var local_is_lbl = false;
var locals = [];
var locals_func = "";
var locals_ebp = 0;

func update_locals():
	if not perf.locals.run(0): return;
	
	n_indicator.color = Color.GREEN;
	n_locals.clear();
	var cur_func = get_cur_func_name();
	var cur_ebp = cpu.regs[cpu.ISA.REG_EBP];
	if always_update_locals:
		if cur_ebp != locals_ebp:
			locals = find_locals();
			locals_func = cur_func;
			locals_ebp = cur_ebp;
	
	var col_main = Color(0.74, 0.666, 0.0, 1.0);
	var col_acc = col_main.darkened(0.5);
	
	var view_type = n_locals_view.get_item_text(n_locals_view.get_selected_id());
	if view_type == "storage pos":
		n_locals.max_columns = 3;
		format_intro_line(cur_func);
		var grouped_locals = group_locals(locals, "by_pos");
		# BLUEPRINT
		# <stuff @ pos> value ...
		# <access> 		...  <ip>
		# <access> 		...  <ip>
		#
		
		n_locals.add_item("type");
		n_locals.add_item("val");
		n_locals.add_item("ip");
		for group in grouped_locals:
			var local =group[0];
			format_local_main_word(local, col_main);
			format_local_val_word(local, col_main);
			G.complete_line(n_locals);
			# other lines
			for local2 in group:
				format_local_access_word(local2, col_acc);
				n_locals.add_item(" ");
				format_local_ip_word(local2, col_acc);
				G.complete_line(n_locals);
	elif view_type == "access ip":
		n_locals.max_columns = 4;
		format_intro_line(cur_func);
		var grouped_locals = group_locals(locals, "by_ip");
		n_locals.add_item("ip");
		n_locals.add_item("type");
		n_locals.add_item("access");
		n_locals.add_item("val");
		var cur_ip = cpu.regs[cpu.ISA.REG_IP];
		for local in grouped_locals:
			var col = col_main;
			if local.ip < cur_ip: col = col_acc;
			format_local_ip_word(local, col);
			format_local_main_word(local, col);
			format_local_access_word(local, col);
			format_local_val_word(local, col);

func format_local_main_word(local, col):
	var text = "";
	if local.type in ["lbl", "imm"]:
		if local.pos in label_inv_dict:
			var lbl_name = label_inv_dict[local.pos];
			text += "%s" % lbl_name;
			local_is_lbl = true;
		else:
			text += "<imm>"# %d" % local.pos;
	#elif local.type == "imm":
	#	text += "<imm>";# % local.pos;
	elif local.type == "stack":
		text += "ebp[%d]" % local.pos;
	else:
		text += "error @ %d" % local.pos;
	#text += " @ %d" % local.ip;
	var idx = n_locals.add_item(text);
	n_locals.set_item_custom_fg_color(idx, col);

func format_intro_line(cur_func:String):
	n_locals.add_item("Showing:");
	n_locals.add_item(locals_func);
	if cur_func != locals_func:
		n_locals.add_item("Current:");
		n_locals.add_item(cur_func);
	G.complete_line(n_locals);

func format_local_val_word(local, col):
	var val = 0;
	var EBP = locals_ebp;
	if local.type == "stack":
		val = read32(EBP+local.pos);
	elif local_is_lbl:
		val = "%d -> %d" % [local.pos, read32(local.pos)];
	elif local.type in ["lbl", "imm"]:
		val = local.pos;
	else:
		val = -404;
	var idx = n_locals.add_item(str(val));
	n_locals.set_item_custom_fg_color(idx, col);

func format_local_access_word(local, col):
	var idx = n_locals.add_item(local.access);
	n_locals.set_item_custom_fg_color(idx, col);

func format_local_ip_word(local, col):
	var idx = n_locals.add_item(str(local.ip));
	n_locals.set_item_custom_fg_color(idx, col);

func get_cur_func_name():
	var cur_ip = cpu.regs[cpu.ISA.REG_IP];
	var cur_func = decode_ip(cur_ip);
	return cur_func;

func find_locals():
	var found_locals = [];
	var cur_ip = cpu.regs[cpu.ISA.REG_IP];
	var next_ret = find_ret(cur_ip);
	print("next_ret = %d" % next_ret);
	if not next_ret: return locals;
	var lc = LoopCounter.new();
	while(cur_ip < next_ret):
		lc.step();
		var cmd = get_cmd(cur_ip);
		var rcmd = cmd.duplicate();
		rcmd.reverse();
		#var cmd_op = rcmd.decode_u32(4);
		var cmd_offs = cmd.decode_s32(3);
		#var local_pos = 0;
		var access_type = "error";
		var local_type = "error";
		var is_valid = false;
		var decoded = cpu.decode_pure(cmd);
		if not decoded: break;
		const access_types = {
			0x09: ["w", "r"],
			0x0A: ["push", "push"],
			0x06: ["cmp", "cmp"],
		};
		if decoded.op_num in [0x09, 0x0A, 0x06]: # MOV, PUSH, CMP
			var acc_w = access_types[decoded.op_num][0];
			var acc_r = access_types[decoded.op_num][1];
			if decoded.reg1_im:
				if decoded.reg1_num == 0:
					if decoded.flags.deref1: #none
						local_type = "lbl";
						access_type = "*lbl/"+acc_w;
						is_valid = true;
					else:
						local_type = "imm";
						access_type = "imm/"+acc_w;
						is_valid = true;
				elif decoded.reg1_num == 9: #EBP
					if decoded.flags.deref1:
						local_type = "stack";
						access_type = "ebp[x]/"+acc_w;
						is_valid = true;
					else:
						local_type = "stack";
						access_type = "ebp+x/"+acc_w;
						is_valid = true;
			elif decoded.reg2_im:
				if decoded.reg2_num == 0: #none
					if decoded.flags.deref2:
						local_type = "lbl";
						access_type = "*lbl/"+acc_r;
						is_valid = true;
					else:
						local_type = "imm";
						access_type = "imm/"+acc_r;
						is_valid = true;
				elif decoded.reg2_num == 9: #EBP
					if decoded.flags.deref2:
						local_type = "stack";
						access_type = "ebp[x]/"+acc_r;
						is_valid = true;
					else:
						local_type = "stack";
						access_type = "ebp+x/"+acc_r;
						is_valid = true;
		if is_valid: 
			found_locals.append(
			{"pos":cmd_offs, "type":local_type, 
			"ip":cur_ip, "access":access_type});
		cur_ip += cmd_size;
	return found_locals;

func group_locals(in_locals, mode:String):
	var new_locals:Array = [];
	if mode == "by_ip":
		new_locals = in_locals.duplicate();
		new_locals.sort_custom(func(a,b): 
			return a.ip < b.ip;
		)
	elif mode == "by_pos":
		var pos_dict = {};
		for local in in_locals:
			var key = local.pos;
			if key not in pos_dict: pos_dict[key] = [];
			pos_dict[key].append(local);
		for key in pos_dict:
			new_locals.append(pos_dict[key]);
			new_locals.sort_custom(func(a,b):
				return a[0].pos < b[0].pos;
			)
	return new_locals;

const cmd_size = 8;
# returns the ip of the next "ret" instruction
func find_ret(cur_ip):
	for i in range(100):
		var pos = i*cmd_size+cur_ip;
		if get_cmd(pos).decode_u8(0) == 0x05:
			return pos;
	return 0;
	
func get_cmd(pos):
	var arr = [];
	for j in range(cmd_size):
		arr.append(bus.readCell(pos+j));
	print("got cmd: %s" % str(arr));
	var cmd = PackedByteArray(arr);
	return cmd;
#ADD UNCOMPUTE BUTTON step back\

func _on_cb_update_toggled(toggled_on):
	always_update_locals = toggled_on;
	if toggled_on: locals_ebp = -1;
	perf.locals.prime();

func _on_ob_view_item_selected(_index: int) -> void:
	perf.locals.prime();

func _on_btn_unstep_pressed() -> void:
	if highlight_mode == HighlightMode.HIGH_LEVEL:
		var old_loc = cur_loc;
		for i in range(step_limit):
			if cur_loc != old_loc: break;
			unstep();
			cur_loc = get_loc_hl();
		perf.all.prime();
	else:
		unstep();
		perf.all.prime();

func _on_cpu_vm_mem_accessed(addr: Variant, val: Variant, is_write: Variant) -> void:
	save_mem_access(addr,val,is_write);

const max_cpu_history = 1000;
var cpu_history = [];
var cpu_n_steps = 0;

func reset_cpu_history():
	cpu_history.clear();
	cpu_n_steps = 0;
	save_cpu_state();

func save_cpu_state():
	#print("--- + Step + ---");
	var state = {"regs":cpu.regs.duplicate()};
	var event = {"type":"cpu", "state":state};
	if len(cpu_history) >= max_cpu_history: 
		var old_event = cpu_history.pop_front();
		if(old_event.type == "cpu"):
			cpu_n_steps -= 1;
	cpu_history.push_back(event);
	cpu_n_steps += 1;

func save_mem_access(addr, val, is_write):
	if not is_write: return;
	var access = {"addr":addr, "old":bus.readCell(addr), "new":val};
	var event = {"type":"mem", "access":access};
	if len(cpu_history) >= max_cpu_history: 
		var old_event = cpu_history.pop_front();
		if(old_event.type == "cpu"):
			cpu_n_steps -= 1;
	cpu_history.push_back(event);

func unstep():
	#print("---- UNSTEP BEFORE ---");
	#print_cpu_hist(10);
	#print("---- UNSTEP ----");
	if cpu_history.is_empty(): 
		#print("<empty>"); 
		return;
	var event = cpu_history.pop_back();
	var lc = LoopCounter.new();
	while(event.type == "mem"):
		lc.step();
		#print("<got mem>");
		undo_mem(event);
		if cpu_history.is_empty(): 
			cpu_history.push_back(event); 
			#print("<pb 1>"); 
			break;
		event = cpu_history.pop_back();
	lc = LoopCounter.new();
	while(event.type == "cpu"):
		lc.step();
		#print("<got cpu>");
		cpu_n_steps -= 1;
		if undo_cpu(event):
			# we are at previous CPU state, after that CPU state was completed.
			# our current CPU state and our current mem stuff has been undone.
			if cpu_history.is_empty(): 
				cpu_history.push_back(event); 
				cpu_n_steps += 1; 
				#print("<pb 2>"); 
				break;
			#print("<ok>");
			break;
		else:
			#print("<same ip>");
			if cpu_history.is_empty(): 
				cpu_history.push_back(event); 
				cpu_n_steps += 1; 
				#print("<pb 3>"); 
				break;
			event = cpu_history.pop_back();
			var lc2 = LoopCounter.new();
			while(event.type == "mem"):
				lc2.step();
				#print("<got mem>");
				# if we are here, we are still undoing the current CPU state,
				# and we need to remove the mem stuff we did.
				undo_mem(event);
				if cpu_history.is_empty(): 
					cpu_history.push_back(event); 
					#print("<pb 4>");
					break;
				event = cpu_history.pop_back();
			continue;
		if cpu_history.is_empty():
			cpu_history.push_back(event);
			cpu_n_steps += 1; 
			#print("<pb 3>"); 
			break;
		event = cpu_history.pop_back();
	#cpu_history.push_back(event);
	#print("<next>");
	#print_cpu_hist(10);

func undo_mem(event):
	bus.writeCell(event.access.addr, event.access.old);
	print("undo mem %d -> %d" % [event.access.old, event.access.addr]);
	
func undo_cpu(event):
	var cur_ip = cpu.regs[cpu.ISA.REG_IP];
	var old_ip = event.state.regs[cpu.ISA.REG_IP];
	event.state.regs[cpu.ISA.REG_CTRL] &= ~cpu.ISA.BIT_PWR;
	cpu.regs = event.state.regs.duplicate();
	if cur_ip == old_ip:
		return false;
	else:
		print("undo cpu ip %d -> ip %d" % [cur_ip, old_ip]);
		return true;

func print_cpu_hist(n_events):
	print("cpu history:");
	for i in range(n_events):
		if i >= len(cpu_history): return;
		var idx = len(cpu_history)-i-1;
		var event = cpu_history[idx];
		var S = "%d: %s" % [idx, event.type];
		if event.type == "cpu":
			S += " %d" % event.state.regs[cpu.ISA.REG_IP];
		print(S);

func on_sym_table_ready(sym_table) -> void:
	cur_sym_table = sym_table;

func update_HL_locals():
	n_hl_locals.clear();
	if not cur_sym_table:
		n_hl_locals.add_item("No symbol table");
		return;
	var cur_ebp = cpu.regs[cpu.ISA.REG_EBP];
	var cur_ip = cpu.regs[cpu.ISA.REG_IP];
	var cur_func_name = decode_ip(cur_ip);
	n_hl_locals.add_item(cur_func_name);
	G.complete_line(n_hl_locals);
	if cur_func_name == "(null)": cur_func_name = "global";
	if cur_func_name not in cur_sym_table.funcs:
		n_hl_locals.add_item("[No symbols for this function]");
		return;
	var fun_handle;
	if cur_func_name == "global":
		fun_handle = cur_sym_table.global;
	else:
		fun_handle = cur_sym_table.funcs[cur_func_name];
	var count = len(fun_handle.args) + len(fun_handle.vars);
	n_hl_locals.add_item("%d symbols" % count); G.complete_line(n_hl_locals);
	for cat in [fun_handle.args, fun_handle.vars]:
		for val in cat:
			n_hl_locals.add_item(val.user_name);
			var value = read_hl_local(val, cur_ebp);
			n_hl_locals.add_item(str(value));

func read_hl_local(val, cur_ebp):
	if "value" in val.pos: return val.pos.value;
	match val.pos.type:
		"global":pass;
		"stack":
			var adr = cur_ebp + val.pos.pos;
			var data = read32(adr);
			return data;
		"immediate": pass;
		"temporary": pass;
		_: assert(false, "unknown hl_local pos type [%s]" % str(val.pos.type));
	return "<error>";


func _on_btn_highlight_hl_pressed() -> void: highlight_mode = HighlightMode.HIGH_LEVEL;
func _on_btn_highlight_asm_pressed() -> void: highlight_mode = HighlightMode.ASM;
func _on_btn_highlight_none_pressed() -> void: highlight_mode = HighlightMode.NONE;

func _on_locations_ready(new_loc_map: LocationMap) -> void:
	loc_map = new_loc_map;
	n_locations = len(loc_map.begin);
	expand_location_map();
	pass # Replace with function body.

class IP_range:
	var begin:int = -1;
	var end:int = -1;
	var loc:LocationRange;
	func _init(dict=null):
		if dict:
			G.dictionary_init(self, dict);
	func is_valid():
		if not (begin != -1):
			print("IP_range: begin unset");
			return false;
		if not (end != -1):
			print("IP_range: end unset");
			return false;
		if not (loc != null):
			print("IP_range: loc is null");
			return false;
		if not (loc.is_valid()):
			print("IP_range: loc invalid");
			return false;
		return true;
		#return (begin != -1) and (end != -1) \
		#	and (loc != null) and loc.is_valid();
	func ip_dist()->float:
		assert(is_valid());
		return (end - begin);
	func src_dist()->float:
		assert(is_valid());
		return loc.dist();
		
	
class ELM_sub_entry:
	var all_ranges:Array[IP_range] = []; ## all ranges that overlap with current ip
	var smallest_src:IP_range; ## range that corresponds to the smallest source text
	var smallest_ip:IP_range; ## range that covers the smallest ip distance
	func _init(dict=null):
		if dict:
			G.dictionary_init(self, dict);
	func is_valid():
		if not (all_ranges.all(func(x): return x.is_valid())):
			print(" ELM_sub_entry: some ranges invalid");
			return false;
		if not (smallest_src != null):
			print(" ELM_sub_entry: smallest_src is null");
			return false;
		if not (smallest_src.is_valid()):
			print(" ELM_sub_entry: smallest_src invalid");
			return false;
		if not (smallest_ip != null):
			print(" ELM_sub_entry: smallest_ip is null");
			return false;
		if not (smallest_ip.is_valid()):
			print(" ELM_sub_entry: smallest_ip invalid");
			return false;
		return true;
		#return (all_ranges.all(func(x): x.is_valid())) \
		#	and	(smallest_src != null) and (smallest_src.is_valid()) \
		#	and (smallest_ip != null) and (smallest_ip.is_valid());

class ELM_entry:
	var ip:int = -1;
	var asm:ELM_sub_entry;
	var hl:ELM_sub_entry;
	func _init(dict=null):
		if dict:
			G.dictionary_init(self, dict);
	func is_valid():
		#if not (asm != null):
		#	print("ELM_entry: asm is null");
		#	return false;
		#if not (asm.is_valid()):
		#	print("ELM_entry: asm invalid");
		#	return false;
		if not (hl != null):
			print("ELM_entry: hl is null");
			return false;
		if not (hl.is_valid()):
			print("ELM_entry: hl invalid");
			return false;
		return true;
		#return (asm != null) and asm.is_valid() \
		#		and (hl != null) and hl.is_valid();

var ExpandedLocationMap:Array[ELM_entry]; ## <cmd_idx, entry>

## changes the loc_map from sparse to dense representation.
##  every ip will point to all the ranges that ovelap with it.
func expand_location_map():
	var ELM:Array[ELM_entry] = ExpandedLocationMap;
	ELM.clear();
	var max_ip = get_max_loc_map_key();
	var n_cmd_idxes = (max_ip / cmd_size) + 1;
	ELM.resize(n_cmd_idxes);
	var open_locs = {}; ## <loc, ip_range>
	print("putting %d+%d locations into %d/%d ips" % [len(loc_map.begin.keys()), len(loc_map.end.keys()), len(ELM), cmd_size]);
	var unvisited_keys_begin = loc_map.begin.keys();
	var unvisited_keys_end = loc_map.begin.keys();
	for cmd_idx in range(n_cmd_idxes):
		var ip = cmd_idx * cmd_size;
		ELM[cmd_idx] = ELM_entry.new({"ip":ip});
		unvisited_keys_begin.erase(ip);
		if ip in loc_map.begin:
			var loc_arr = loc_map.begin[ip];
			for loc in loc_arr:
				if loc not in open_locs:
					var ip_range = ELM_open_loc(ip, "hl", loc);
					open_locs[loc] = ip_range;
		else:
			for loc in open_locs:
				var ip_range = open_locs[loc];
				ELM_continue_loc(ip, "hl", ip_range);
		unvisited_keys_end.erase(ip);
		if ip in loc_map.end:
			var loc_arr = loc_map.end[ip];
			for loc in loc_arr:
				ELM_close_loc(ip, open_locs[loc]);
				open_locs.erase(loc);
	assert(unvisited_keys_begin.is_empty());
	assert(unvisited_keys_end.is_empty());
	assert(open_locs.is_empty());
	for entry in ELM:
		#var ip = cmd_idx * cmd_size;
		ELM_sort_ranges(entry.hl);
	for entry in ELM:
		assert(entry.is_valid(), "ELM entry at %d (out of %d) is invalid" % [entry.ip, len(ELM)]);

func ELM_open_loc(ip:int, sub_entry_key:String, loc:LocationRange)->IP_range:
	#print("open loc [%s] at ip %d" % [loc.begin.line, ip]);
	var ELM:Array[ELM_entry] = ExpandedLocationMap;
	var cmd_idx = ip / cmd_size;
	var entry = ELM[cmd_idx];
	assert(entry);
	if entry[sub_entry_key] == null:
		entry[sub_entry_key] = ELM_sub_entry.new();
	var subentry = entry[sub_entry_key];
	var all_ranges:Array[IP_range] = subentry.all_ranges;
	var ip_range = IP_range.new({"begin":ip, "end":-1, "loc":loc});
	all_ranges.append(ip_range);
	return ip_range;

func ELM_close_loc(ip:int, ip_range:IP_range):
	#print("close loc [%s] at ip %d" % [ip_range.loc.begin.line, ip]);
	ip_range.end = ip;

func ELM_continue_loc(ip:int, sub_entry_key:String, ip_range:IP_range):
	var ELM:Array[ELM_entry] = ExpandedLocationMap;
	var cmd_idx = ip / cmd_size;
	var entry = ELM[cmd_idx];
	assert(entry);
	if entry[sub_entry_key] == null:
		entry[sub_entry_key] = ELM_sub_entry.new();
	var subentry = entry[sub_entry_key];
	var all_ranges:Array[IP_range] = subentry.all_ranges;
	assert(ip_range not in all_ranges);
	all_ranges.append(ip_range);

func ELM_sort_ranges(subentry:ELM_sub_entry):
	assert(len(subentry.all_ranges), "can't have it so no ranges cover an ip");
	subentry.all_ranges.sort_custom(
		func(a:IP_range,b:IP_range)->bool:
			return a.ip_dist() < b.ip_dist());
	subentry.smallest_ip = subentry.all_ranges.front();
	subentry.all_ranges.sort_custom(
		func(a:IP_range,b:IP_range)->bool:
			return a.src_dist() < b.src_dist());
	subentry.smallest_src = subentry.all_ranges.front();

#func get_ip_range_for_loc(all_ranges:Array[IP_range], loc:LocationRange):
	#for ip_range in all_ranges:
		#if ip_range.loc == loc: return ip_range;
	#return null

func get_max_loc_map_key():
	var keys = loc_map.begin.keys().duplicate(); 
	keys.sort(); 
	var max_key = keys.back();
	keys = loc_map.end.keys().duplicate();
	keys.sort();
	max_key = max(max_key, keys.back());
	return max_key;

func set_cur_loc(new_loc):
	cur_loc = new_loc;
	if G.has(cur_loc):
		cur_loc_line = cur_loc.begin.line;
	else:
		cur_loc_line = "<no loc>";
