extends Control

@onready var n_screen = $Panel/TabContainer/Screen/V/TextureRect
@onready var n_VM = $VM;
@onready var n_VM_memory = $VM/Bus/RAM_64k
@onready var n_VM_KB = $VM/Bus/KB
@onready var n_Editor = $Panel/TabContainer/Editor
@onready var n_console = $Panel/TabContainer/Editor/V/TE_console
@onready var n_CPU = $VM/CPU_vm
@onready var n_led_error = $Panel/TabContainer/Screen/V/Control/GridContainer/cr_led_error
@onready var n_led_status = $Panel/TabContainer/Screen/V/Control/GridContainer/cr_led_on
@onready var n_Bus = $VM/Bus
@onready var n_assembler = $Panel/TabContainer/Editor/comp_build/comp_asm_zd

var has_kb_capture = false;
# Called when the node enters the scene tree for the first time.
func _ready():
	var dict = {
		"screen":n_screen,
		"VM":n_VM, 
		"memory":n_VM_memory, 
		"console":n_console,
		"cpu":n_CPU, 
		"bus":n_Bus, 
		"asm":n_assembler,
		"editor":n_Editor,
	};
	n_VM.setup(dict);
	n_Editor.setup(dict);
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	update_cpu_status_led();
	update_cpu_error_led();

func update_cpu_status_led():
	if (n_CPU.regs[n_CPU.ISA.REG_CTRL] & n_CPU.ISA.BIT_PWR):
		n_led_status.color = Color.GREEN;
	elif (n_CPU.regs[n_CPU.ISA.REG_CTRL] & n_CPU.ISA.BIT_STEP):
		n_led_status.color = Color.YELLOW;
	else:
		n_led_status.color = Color.BLACK;
		
func update_cpu_error_led():
	if n_CPU.errcode == 0:
		n_led_error.color = Color.BLACK;
	else:
		n_led_error.color = Color.RED;
#func _input(event):
#	if event is InputEventKey:
#		if event.pressed:
#			print("Main: key "+str(event.keycode));
#			n_VM_KB._input(event);

func _gui_input(event):
	if has_kb_capture and (event is InputEventKey):
		get_viewport().set_input_as_handled();
	#if has_kb_capture:
		#print("event eaten");
		#if event is InputEventKey:
			#print("was key, eaten");
			#get_viewport().set_input_as_handled();
	#elif event is InputEventKey:
		#print("event not eaten, key.");
	#else:
		#print("some event.");

func _on_cb_on_toggled(toggled_on): n_VM.set_on(toggled_on);

func _on_btn_reset_pressed(): 
	n_VM.reset();
	n_led_error.color = Color.BLACK;

func _on_cpu_vm_on_cpu_error(errcode):
	update_cpu_error_led();


func _on_btn_keyboard_toggled(toggled_on):
	has_kb_capture = toggled_on;
	n_VM_KB.has_capture = has_kb_capture;
	if has_kb_capture: 
		print("capture on");
		grab_focus();
	else:
		print("capture off");
