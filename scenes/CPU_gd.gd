extends Node

var Bus:Node;
var GPU:Node;
var KB:Node;
var is_setup:bool = false;


# Called when the node enters the scene tree for the first time.
func _ready()->void:
	pass # Replace with function body.

func setup(dict:Dictionary)->void:
	assert("bus" in dict);
	Bus = dict.bus;
	is_setup = true;
	GPU = _find_on_bus("GPU");
	KB = _find_on_bus("KB");
	print("CPU setup")
	postsetup();
	
func postsetup()->void:
	_print("Hello from CPU_gd!");
	_nl(); _print("another test");
	

func _find_on_bus(dev_name)->Node:
	for ch in Bus.get_children():
		if ch.name.begins_with(dev_name):
			return ch;
	assert(false, "could not find "+dev_name+" on the bus");
	return null;

#---------- GPU driver ----------
const textbuffer_offset:int = 2000;
const n_params:int = 7;
const n_tiles_x:int = 56;
const n_tiles_y:int = 36;

var print_pos:Vector2i = Vector2i(0,0);

func _nl()->void:
	print_pos.x = 0;
	print_pos.y += 1;
	if(print_pos.y >= n_tiles_y):
		print_pos.y = 0;
	

func _print(S:String)->void:
	for ch in S:
		_printChar(ch, print_pos);
		_advance_print_pos();

func _advance_print_pos()->void:
	print_pos.x += 1;
	if(print_pos.x >= n_tiles_x): _nl();


func _char_to_int(C:String)->int:
	if(C == ""): return 0;
	else: return C.to_ascii_buffer()[0];
	
func _int_to_char(N:int)->String:
	if(N == 0): return "";
	else: return PackedByteArray([N]).get_string_from_ascii();


func _printChar(C:String, pos:Vector2i, colFG=null, colBG=null)->void:
	var adr:int = textbuffer_offset + (pos.x+pos.y*n_tiles_x)*n_params;
	GPU.writeCell(adr+0, _char_to_int(C));
	if(colFG != null):
		GPU.writeCell(adr+1, int(colFG.r*255));
		GPU.writeCell(adr+2, int(colFG.g*255));
		GPU.writeCell(adr+3, int(colFG.b*255));
	if(colBG != null):
		GPU.writeCell(adr+4, int(colBG.r*255));
		GPU.writeCell(adr+5, int(colBG.g*255));
		GPU.writeCell(adr+6, int(colBG.b*255));
			

func has_kb()->int:
	return (KB.readCell(0) != 0);

func get_kb()->String:
	var key:String = _int_to_char(KB.readCell(1));
	KB.writeCell(0,1);
	return key;

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta:float)->void:
	if not is_setup: return;
	if not has_kb(): return;
	else:
		var C:String = get_kb();
		_print(C);
