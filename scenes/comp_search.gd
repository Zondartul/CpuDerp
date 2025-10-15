extends Node

@export var Editor:Node;
@export var comp_file:Node;
var n_VSearch:Node;
var n_LE:LineEdit;
var n_lbl_results:Label;

const col_normal = Color.YELLOW;
const col_good = Color.GREEN;
const col_bad = Color.RED;

var results = [];
var n_results = 0;
var result_idx = 0;
var query_len = 0;
signal sig_highlight_line(line_idx, col, len);

func setup():
	pass;

func _ready():
	n_VSearch = Editor.get_node("V/VSearch");
	n_LE = n_VSearch.get_node("H/LineEdit");
	n_lbl_results = n_VSearch.get_node("H/lbl_res");

func popup():
	n_VSearch.show();
	n_LE.grab_focus();
	n_LE.select_all();

func hide():
	n_VSearch.hide();


func _on_line_edit_text_submitted(new_text: String) -> void:
	n_LE.deselect();
	search(new_text);

func search(text):
	print("Search "+text);
	query_len = len(text);
	if comp_file.cur_efile:
		var ftext:String = comp_file.cur_efile.get_text();
		var positions = G.str_find_all_instances(text, ftext);
		results = G.str_to_row_col_arr(positions, ftext);
		n_results = len(results);
	result_idx = 0;
	if n_results:
		n_LE.add_theme_color_override("font_color", col_good);
		jump_to_result(0);
	else:
		n_LE.add_theme_color_override("font_color", col_bad);
		update_lbl_res();
	pass;


func _on_btn_prev_pressed() -> void:
	print("prev search result");
	jump_to_result(result_idx-1);
	pass;

func _on_btn_next_pressed() -> void:
	print("next search result");
	jump_to_result(result_idx+1);
	pass # Replace with function body.

func jump_to_result(idx):
	if not n_results: return;
	idx = idx % n_results; #clamp(idx, 0, n_results-1);
	result_idx = idx;
	update_lbl_res();
	sig_highlight_line.emit(results[idx][0], results[idx][1], query_len);

func _on_btn_close_search_pressed() -> void:
	hide();

func _on_line_edit_text_changed(_new_text: String) -> void:
	n_LE.add_theme_color_override("font_color", col_normal);
	pass

func _on_line_edit_gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			hide();

func update_lbl_res():
	n_lbl_results.text = "%s/%s Results" % [result_idx+1, n_results];
