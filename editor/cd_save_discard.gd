extends Popup

signal save_pressed();
signal discard_pressed();
signal cancel_pressed();
signal has_result(result);
var result = "cancel";
# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func ask(fname):
	$V/Label.text = "File "+fname+"has unsaved changes.";
	popup();

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass


func _on_btn_save_pressed():
	result = "save";
	save_pressed.emit();
	has_result.emit(result);
	hide();
func _on_btn_discard_pressed():
	result = "discard";
	discard_pressed.emit();
	has_result.emit(result);
	hide();
func _on_btn_cancel_pressed():
	result = "cancel";
	cancel_pressed.emit();
	has_result.emit(result);
	hide();
func _on_close_requested():
	result = "cancel";
	cancel_pressed.emit();
	has_result.emit(result);
	hide();
