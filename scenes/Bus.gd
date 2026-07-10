extends Node

# memory bus. children must implement methods:
# getSize()->int (u32) - returns the size of accessible memory
# readCell(cell:int (u32))->int (u8) 
#	- returns the result of attempting to read a byte at the address "cell". 
#		If the cell is inaccessible, return 0.
# writeCell(cell:int (u32), val:int (u8))->void
#	- attempts to write a byte to address "cell".
#
# reads and writes may have side-effects and need not function as memory.


var ranges:Array[int] = [];
var sizes:Array[int] = [];
var total_size:int = 0;
var debug_bus_read:bool = false;
var debug_bus_write:bool = false;

func _ready():
	var maxmem:int = 0;
	for ch in get_children():
		ranges.append(maxmem);
		var size:int = ch.getSize();
		sizes.append(size);
		maxmem += size;
	total_size = maxmem;

func reset()->void:
	for ch in get_children():
		if "reset" in ch:
			ch.reset();

func getSize()->int:
	return total_size;

func readCell(cell:int)->int:
	if((cell < 0) || (cell >= total_size)): 
		if debug_bus_read: print("bus: read("+str(cell)+") <out of bounds> -> 0");
		return 0;
	var dev_idx:int = ranges.bsearch(cell, false)-1;
	assert(dev_idx >= 0);
	assert(dev_idx < ranges.size());
	var local_cell:int = cell - ranges[dev_idx];
	var dev:Node = get_child(dev_idx);
	var val:int = dev.readCell(local_cell);
	if debug_bus_read: print("bus: read("+str(cell)+") (dev "+str(dev_idx)+": "+str(local_cell)+") -> "+str(val));
	return val;

func writeCell(cell:int, val:int)->void:
	if((cell < 0) || (cell >= total_size)): 
		if debug_bus_write: print("bus: write("+str(cell)+") <out of bounds>");
		return;
	var dev_idx:int = ranges.bsearch(cell, false)-1;
	assert(dev_idx >= 0);
	assert(dev_idx <  ranges.size());
	var local_cell:int = cell - ranges[dev_idx];
	var dev:Node = get_child(dev_idx);
	dev.writeCell(local_cell, val);
	if debug_bus_write: print("bus: write("+str(cell)+") (dev "+str(dev_idx)+": "+str(local_cell)+") <- "+str(val));
