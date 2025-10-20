extends Node

@onready var n_bus = $Bus
@onready var n_CPU = $CPU_vm
# Called when the node enters the scene tree for the first time.
func _ready():
	reset();
	pass # Replace with function body.

func setup(dict:Dictionary):
	var dict2 = dict.duplicate();
	dict2["bus"] = n_bus;
	for ch in get_children():
		if ch == n_bus:
			for ch2 in n_bus.get_children():
				if "setup" in ch2:
					ch2.setup(dict2);
		if "setup" in ch:
			ch.setup(dict2);
# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

func set_on(on): n_CPU.set_on(on);
func reset(): 
	n_CPU.reset();
	n_bus.reset();

func _on_sb_freq_value_changed(value):
	n_CPU.freq = value;
