extends Node

var memory:PackedByteArray;

func _ready()->void:
	reset();

func getSize()->int:
	return memory.size();

func readCell(cell:int)->int:
	if((cell < 0) || (cell >= memory.size())): 
		#print("ram: read("+str(cell)+") <out of bounds> -> 0");
		return 0;
	var val = memory[cell];
	#print("ram: read("+str(cell)+") -> "+str(val));
	return val;

func writeCell(cell:int, val:int)->void:
	if((cell < 0) || (cell >= memory.size())): 
		#print("ram: write("+str(cell)+") <out of bounds>");
		return;
	memory[cell] = val;
	#print("ram: write("+str(cell)+") <- "+str(val));

func clear()->void: reset();

func reset()->void:
	memory = PackedByteArray();
	memory.resize(65536);
