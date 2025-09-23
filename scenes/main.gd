extends Control

@onready var n_screen = $Panel/TabContainer/Screen/V/TextureRect
@onready var n_VM = $VM;
@onready var n_VM_memory = $VM/Bus/RAM_64k
@onready var n_VM_KB = $VM/Bus/KB
@onready var n_Editor = $Panel/TabContainer/Editor
@onready var n_console = $Panel/TabContainer/Editor/V/RTL_console
@onready var n_CPU = $VM/CPU_vm
@onready var n_led_error = $Panel/TabContainer/Screen/V/Control/GridContainer/cr_led_error
@onready var n_led_status = $Panel/TabContainer/Screen/V/Control/GridContainer/cr_led_on
@onready var n_Bus = $VM/Bus
@onready var n_assembler = $Panel/TabContainer/Editor/comp_build/comp_asm_zd
@onready var n_view_memory = $Panel/TabContainer/Memory

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
		"view_memory":n_view_memory,
	};
	n_VM.setup(dict);
	n_Editor.setup(dict);
	n_view_memory.setup(dict);
	
	debug_automation_script();
	pass # Replace with function body.

func debug_automation_script():
	#automate_compile_asm_zd();
	automate_compile_miniderp();

func automate_compile_asm_zd():
		# Go to editor and open the file
	autotab($Panel/TabContainer, "Editor");
	automenu($Panel/TabContainer/Editor/V/MenuBar, ["File", "Load"]);
	autofile($Panel/TabContainer/Editor/comp_file/fd_load, "res://res/data/main.txt");#"C:/Stride/godot/CpuDerp/res/data/main.txt");
	# Compile it
	automenu($Panel/TabContainer/Editor/V/MenuBar, ["Build", "compile"]);
	# Go to memory map and open the first region
	autotab($Panel/TabContainer, "Memory");
	autolist($Panel/TabContainer/Memory/BoxContainer/mem_map, 0);

func automate_compile_miniderp():
	# Go to editor and open the file
	autotab($Panel/TabContainer, "Editor");
	automenu($Panel/TabContainer/Editor/V/MenuBar, ["File", "Load"]);
	autofile($Panel/TabContainer/Editor/comp_file/fd_load, "res://res/data/miniderp.txt");#"C:/Stride/godot/CpuDerp/res/data/main.txt");
	# Compile it
	automenu($Panel/TabContainer/Editor/V/MenuBar, ["Language", "miniderp"]);
	automenu($Panel/TabContainer/Editor/V/MenuBar, ["Build", "compile"]);
	# Go to memory map and open the first region
	#autotab($Panel/TabContainer, "Memory");
	#autolist($Panel/TabContainer/Memory/BoxContainer/mem_map, 0);

# activates the tab in a TabContainer
func autotab(node:TabContainer, tab_name):
	for i in range(node.get_tab_count()):
		var title = node.get_tab_title(i)
		if title == tab_name:
			node.current_tab = i;
			return true;
	push_error("automation: can't find tab named ["+tab_name+"]");
	return false;

func autofile(node:FileDialog, filename):
	node.file_selected.emit(filename);
	node.hide();

# clicks the buttons on a menu
func automenu(node, selections:Array):
	if node is MenuBar:
		for child in node.get_children():
			if child.name == selections[0]:
				var sel2 = selections.duplicate();
				sel2.remove_at(0);
				return automenu(child, sel2);
	if node is PopupMenu:
		for i in range(node.item_count):
			var item_text = node.get_item_text(i);
			if item_text == selections[0]:
				assert(selections.size() == 1);
				node.index_pressed.emit(i);
				return true;
	push_error("automation: can't find menu entry ["+selections[0]+"]")
	return false;

func autolist(node:ItemList, index):
	if index < node.item_count:
		node.select(index);
		node.item_selected.emit(index);
		return true;
	push_error("automation: can't find list item number "+str(index));
	return false;


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

func _on_cpu_vm_on_cpu_error(_errcode):
	update_cpu_error_led();


func _on_btn_keyboard_toggled(toggled_on):
	has_kb_capture = toggled_on;
	n_VM_KB.has_capture = has_kb_capture;
	if has_kb_capture: 
		print("capture on");
		grab_focus();
	else:
		print("capture off");
