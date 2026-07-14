extends Node

var buffer:Array[int] = [0];
var has_capture:bool = false;
var last_captured:int = 0;
signal sig_keypress(character, byte);

# Called when the node enters the scene tree for the first time.
func _ready()->void:
	pass # Replace with function body.

func reset()->void:
	buffer = [0];

func _char_to_int(C:String)->int:
	if(C == ""): return 0;
	else: return C.to_ascii_buffer()[0];
	
func _int_to_char(N:int)->String:
	if(N == 0): return "";
	else: return PackedByteArray([N]).get_string_from_ascii();

func _input(event)->void:
	if not has_capture: return;
	if event is InputEventKey:
		if event.pressed:
			#print("kb.input "+str(event));
			#var C = _char_to_int(OS.get_keycode_string(event.key_label));
			#var C = event.get_unicode();
			#if(C == 0): C = event.keycode;
			var character:String = get_special_ASCII(event);
			var buff:PackedByteArray = character.to_utf8_buffer()
			#var number = character.to_ascii_buffer()[0]
			var number:int = 0;
			if buff.size() == 1:
				number = buff[0];
			else:
				print("KB: non-ascii codepoint ignored: [%s]" % character)
			buffer.append(number);
			buffer[0] += 1;
			last_captured = number;
			sig_keypress.emit(character, number);

func get_special_ASCII(event)->String:
	var res:String="";
	match event.keycode:
		KEY_ENTER:		res = "\n"  # ASCII 10
		KEY_BACKSPACE:	res = "\b"  # ASCII 8
		KEY_TAB:        res = "\t"  # ASCII 9
		KEY_ESCAPE:     res = char(27) # ASCII 27
		KEY_DELETE:     res = char(127)  # ASCII 127 (DEL)
		KEY_SPACE:      res = " "  # ASCII 32
		_: res = char(event.get_unicode())
	return res;

func getSize()->int: return 64;

func readCell(cell:int)->int:
	if((cell < 0) || (cell >= buffer.size())): return 0;
	#print("KB:readCell("+str(cell)+") == "+str(buffer[cell]));
	return buffer[cell];

func writeCell(cell:int, val:int)->void:
	if(cell != 0): return;
	#print("KB:writeCell("+str(cell)+", "+str(val)+")")
	if(cell == 0):
		var lc:LoopCounter = LoopCounter.new();
		while val and buffer[0]:
			lc.step();
			assert(buffer.size() >= 2);
			assert(buffer[0] > 0);
			buffer[0] -= 1;
			buffer.remove_at(1);
			val -= 1;

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
