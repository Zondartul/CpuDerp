extends Control
# Debug Panel
const ISA = preload("res://lang_zvm.gd")

@onready var n_regview = $V/reg_view
@onready var n_stackview = $V/TabContainer/stack_view

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

func update_cpu():
	update_registers();
	update_stack();
	update_ip_highlight();
	update_pointers();
	
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
	for k:String in assembler.labels.keys():
		var v:int = assembler.labels[k];
		label_inv_dict[v] = k;

	label_ips = [];
	label_names = [];
	for k:int in label_inv_dict.keys():
		var v:String = label_inv_dict[k];
		label_names.append(v);
		label_ips.append(k);

func decode_ip(ip):
	if(not assembler or (assembler.labels.size() == 0)):
		return "(no data)";
	else:
		update_labels();
		var idx = label_ips.bsearch(ip, false)-1;
		if(idx < 0): return "(null)";
		return label_names[idx];
	#return "(no data)";

func update_stack():
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
	if(cpu.regs[cpu.ISA.REG_CTRL] & cpu.ISA.BIT_STEP):
		update_cpu();


func _on_btn_run_pressed():
	cpu.regs[cpu.ISA.REG_CTRL] &= ~cpu.ISA.BIT_STEP;
	cpu.regs[cpu.ISA.REG_CTRL] |= cpu.ISA.BIT_PWR;
	
func _on_btn_pause_pressed():
	cpu.regs[cpu.ISA.REG_CTRL] ^= cpu.ISA.BIT_PWR;

func _on_btn_stop_pressed():
	cpu.regs[cpu.ISA.REG_CTRL] &= ~cpu.ISA.BIT_STEP;
	cpu.reset();
	update_cpu();

func _on_btn_step_pressed():
	cpu.regs[cpu.ISA.REG_CTRL] |= (cpu.ISA.BIT_STEP | cpu.ISA.BIT_PWR);

func _on_btn_next_line_pressed():
	print("unimplemented");

func _on_btn_step_in_pressed():
	print("unimplemented");

func _on_btn_step_out_pressed():
	print("unimplemented");

func _on_btn_run_to_line_pressed():
	print("unimplemented");


func _on_cb_hex_toggled(toggled_on: bool) -> void:
	mode_hex = toggled_on;
	update_cpu();

@onready var slider_top:Control = $V/TabContainer/pointers/slider_top
@onready var slider_mid:ItemList = $V/TabContainer/pointers/slider_mid
@onready var slider_bot:ItemList = $V/TabContainer/pointers/slider_bot
@onready var n_sb_addr = $V/TabContainer/pointers/H/sb_addr
@onready var n_ob_view = $V/TabContainer/pointers/H/ob_view
@onready var n_sb_offs = $V/TabContainer/pointers/H/sb_offs
var slider_base_addr:int = 0;

func get_pointer_tooltip(addr, val)->String:
	return "byte %02X (%d) at address %02X (%d)" % [val, val, addr, addr];

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
	update_mid();
	update_top();

func update_mid():
	slider_base_addr = n_sb_addr.value;
	var idx = 0;
	for i in range(-8,8):
		var addr = slider_base_addr+i;
		var val = bus.readCell(addr);
		var text1 = "%02X" % val;
		#var text2 = "%d" % val;
		slider_mid.set_item_text(idx, text1);
		#slider_mid.set_item_text(idx+16, text2);
		slider_mid.set_item_tooltip(idx, get_pointer_tooltip(addr, val));
		#slider_mid.set_item_tooltip(idx+16, get_pointer_tooltip(addr, val));
		var item_col = calc_highlight_color(addr);
		slider_mid.set_item_custom_bg_color(idx, item_col);
		#slider_mid.set_item_custom_bg_color(idx+16, item2_col);
		idx += 1;

func calc_highlight_color(addr):
	var item1_col = Color.BLACK;
	var item2_col = Color.BLACK;
	for item in stack_items:
		if addr == item.ip:
			item2_col = Color.RED;
		if is_in_range(addr, item.ebp+5, item.ebp+9):
			item1_col = Color.RED;
		if addr == item.ebp:
			item2_col = Color.GREEN;
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
	const step_px = 24;
	var offs_real = slider_base_addr % view_size + top_offs;
	var first_is_blank = 0;
	
	var n_views = ((16-offs_real)/view_size);

	for i in range(n_views):
		var first_item = offs_real + i*view_size;
		var last_item = first_item + view_size - 1;
		var first_rect = slider_mid.get_item_rect(first_item);
		var last_rect = slider_mid.get_item_rect(last_item);
		var vec_from = first_rect.position;
		var vec_to = last_rect.end;
		
		var view_panel:Panel = Panel.new();
		view_panel.set_position(vec_from);
		view_panel.set_size(vec_to-vec_from);
		slider_top.add_child(view_panel);
	#if offs_real:
	#	first_is_blank = 1;
	#	slider_top.set_item_text(0, pix_to_spaces(step_px*offs_real));
	#for i in range(first_is_blank, 16):
	#	slider_top.set_item_text(i, pix_to_spaces(step_px*view_size));
	
		
func _on_sb_addr_value_changed(_value: float) -> void:
	update_pointers();

#ADD UNCOMPUTE BUTTON step back\
