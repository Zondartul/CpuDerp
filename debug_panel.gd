extends Control

@onready var n_regview = $V/reg_view;
@onready var n_stackview = $V/stack_view;
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

var cpu;
var bus;
var assembler;
var efile;
var editor;
var is_setup = false;

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

func init_reg_view():
	for reg in regnames:
		n_regview.add_item(reg);
		n_regview.add_item("");

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

func update_registers():
	for i in range(regnames.size()):
		var val = cpu.regs[i];
		n_regview.set_item_text(i*2+1, str(val));

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
		var ip = cpu.regs[cpu.REG_IP];
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
	print("k_has = ["+str(k_has)+"], k_want = ")

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
	var cur_ebp = cpu.regs[cpu.REG_EBP];
	var cur_ip = cpu.regs[cpu.REG_IP];
	for i in range(10):
		n_stackview.add_item(str(cur_ip));
		n_stackview.add_item(str(cur_ebp));
		n_stackview.add_item(decode_ip(cur_ip));
		if cur_ebp == 0: break;
		var prev_ebp_adr = cur_ebp+1;
		var prev_ip_adr = cur_ebp+5;
		var prev_ip = read32(prev_ip_adr);
		var prev_ebp = read32(prev_ebp_adr);
		cur_ebp = prev_ebp;
		cur_ip = prev_ip;

func _on_cpu_vm_cpu_step_done(_vm_cpu):
	assert(is_setup);
	if(cpu.regs[cpu.REG_CTRL] & cpu.BIT_STEP):
		update_cpu();


func _on_btn_run_pressed():
	cpu.regs[REG_CTRL] &= ~BIT_STEP;
	cpu.regs[REG_CTRL] |= BIT_PWR;
	
func _on_btn_pause_pressed():
	cpu.regs[REG_CTRL] ^= BIT_PWR;

func _on_btn_stop_pressed():
	cpu.regs[REG_CTRL] &= ~BIT_STEP;
	cpu.reset();
	update_cpu();

func _on_btn_step_pressed():
	cpu.regs[REG_CTRL] |= (BIT_STEP | BIT_PWR);

func _on_btn_next_line_pressed():
	print("unimplemented");

func _on_btn_step_in_pressed():
	print("unimplemented");

func _on_btn_step_out_pressed():
	print("unimplemented");

func _on_btn_run_to_line_pressed():
	print("unimplemented");
