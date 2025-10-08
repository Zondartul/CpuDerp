extends Control
# Debug Panel
const ISA = preload("res://lang_zvm.gd")

@onready var n_regview = $V/TabContainer/reg_view
@onready var n_locals = $V/TabContainer/local_view/V/locals
@onready var n_stackview = $V/TabContainer/stack_view
@onready var n_indicator = $V/TabContainer/local_view/V/H/indicator

const class_PerfLimitDirectory = preload("res://PerfLimitDirectory.gd");

var perf = PerfLimitDirectory.new({
	"all":1.0,
	"regs":0.1,
	"stack":0.1,
	"ip":0.5,
	"pointers":1.0,
	"locals":1.0,
	});

var perf_always_on = ["all", "regs", "stack", "ip"];

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

var cpu:CPU_vm;
var bus;
var assembler;
var efile;
var editor;
var is_setup = false;
var mode_hex = false;
var stack_items = [];

signal set_highlight(from_line, from_col, to_line, to_col);
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

func update_ip_highlight():
	if not perf.ip.run(0): return;
	
	if assembler and assembler.op_locations.size():
		cache_op_locations();
		var ip = cpu.regs[cpu.ISA.REG_IP];
		var idx = op_ips.bsearch(ip, false)-1;
		if(idx >= 0):
			var op = op_locations[idx];
			editor.switch_to_file(op.filename)
			set_highlight.emit(op.line, op.begin, op.line, op.end);
		else:
			set_highlight.emit(0,0,0,0);

func _process(delta):
	perf.credit_all(delta);
	update_cpu();
	$V/H2/lbl_history.text = "steps recorded: "+str(cpu_n_steps);

func update_cpu():
	update_registers();
	update_stack();
	update_ip_highlight();
	update_pointers();
	update_locals();
	
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

func decode_ip(ip):
	if(not assembler or (assembler.final_labels.size() == 0)):
		return "(no data)";
	else:
		update_labels();
		var idx = label_ips.bsearch(ip, false)-1;
		if(idx < 0): return "(null)";
		return label_names[idx];
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
	cpu.step();
	perf.all.prime();

func _on_btn_next_line_pressed():
	print("unimplemented");

func _on_btn_step_in_pressed():
	print("unimplemented");

func _on_btn_step_out_pressed():
	var cur_ebp = cpu.regs[cpu.ISA.REG_EBP];
	for i in range(1000):
		if(cpu.regs[cpu.ISA.REG_EBP] != cur_ebp): break;
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
	while(cpu.regs[cpu.ISA.REG_IP] != target_ip):
		cpu.step();
	perf.all.prime();

func _on_cb_hex_toggled(toggled_on: bool) -> void:
	mode_hex = toggled_on;
	perf.all.prime();

@onready var slider_top:Control =  $V/TabContainer/pointers/slider_top
@onready var slider_mid:ItemList = $V/TabContainer/pointers/slider_mid
@onready var slider_bot:ItemList = $V/TabContainer/pointers/slider_bot
@onready var n_sb_addr = $V/TabContainer/pointers/H/sb_addr
@onready var n_ob_view = $V/TabContainer/pointers/H/ob_view
@onready var n_sb_offs = $V/TabContainer/pointers/H/sb_offs
var slider_base_addr:int = 0;

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
			complete_line();
			# other lines
			for local2 in group:
				format_local_access_word(local2, col_acc);
				n_locals.add_item(" ");
				format_local_ip_word(local2, col_acc);
				complete_line();
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
	complete_line();

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

func complete_line():
	var n = n_locals.max_columns-1 - ((n_locals.item_count-1) % n_locals.max_columns);
	for i in range(n): n_locals.add_item(" ");

func get_cur_func_name():
	var cur_ip = cpu.regs[cpu.ISA.REG_IP];
	var cur_func = decode_ip(cur_ip);
	return cur_func;

func find_locals():
	var locals = [];
	var cur_ip = cpu.regs[cpu.ISA.REG_IP];
	var next_ret = find_ret(cur_ip);
	print("next_ret = %d" % next_ret);
	if not next_ret: return locals;
	while(cur_ip < next_ret):
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
			locals.append(
			{"pos":cmd_offs, "type":local_type, 
			"ip":cur_ip, "access":access_type});
		cur_ip += cmd_size;
	return locals;

func group_locals(locals, mode:String):
	var new_locals:Array = [];
	if mode == "by_ip":
		new_locals = locals.duplicate();
		new_locals.sort_custom(func(a,b): 
			return a.ip < b.ip;
		)
	elif mode == "by_pos":
		var pos_dict = {};
		for local in locals:
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
	while(event.type == "mem"):
		#print("<got mem>");
		undo_mem(event);
		if cpu_history.is_empty(): 
			cpu_history.push_back(event); 
			#print("<pb 1>"); 
			break;
		event = cpu_history.pop_back();
	while(event.type == "cpu"):
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
			while(event.type == "mem"):
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
