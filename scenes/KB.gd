extends Node

var buffer = [0];
var has_capture = false;
# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func reset():
	buffer = [0];

func _char_to_int(C:String):
	if(C == ""): return 0;
	else: return C.to_ascii_buffer()[0];
	
func _int_to_char(N:int):
	if(N == 0): return "";
	else: return PackedByteArray([N]).get_string_from_ascii();


func _input(event):
	if not has_capture: return;
	if event is InputEventKey:
		if event.pressed:
			#print("kb.input "+str(event));
			#var C = _char_to_int(OS.get_keycode_string(event.key_label));
			var C = event.get_unicode();
			if(C == 0): C = event.keycode;
			buffer.append(C);
			buffer[0] += 1;

func getSize(): return 64;

func readCell(cell:int):
	if((cell < 0) || (cell >= buffer.size())): return 0;
	#print("KB:readCell("+str(cell)+") == "+str(buffer[cell]));
	return buffer[cell];

func writeCell(cell:int, val:int):
	if(cell != 0): return;
	#print("KB:writeCell("+str(cell)+", "+str(val)+")")
	if(cell == 0):
		while val and buffer[0]:
			assert(buffer.size() >= 2);
			assert(buffer[0] > 0);
			buffer[0] -= 1;
			buffer.remove_at(1);
			val -= 1;

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
