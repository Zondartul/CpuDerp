extends Node

@onready var n_bus = $Bus
@onready var n_CPU = $CPU_vm
# Called when the node enters the scene tree for the first time.
func _ready()->void:
	reset();
	pass # Replace with function body.

func setup(dict:Dictionary)->void:
	var dict2:Dictionary = dict.duplicate();
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

func set_on(on)->void: n_CPU.set_on(on);
func reset()->void: 
	n_CPU.reset();
	n_bus.reset();

func _on_sb_freq_value_changed(value)->void:
	n_CPU.freq = value;
