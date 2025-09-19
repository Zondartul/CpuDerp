extends Node

var cur_filename: set=set_cur_filename;
var cur_path: set=set_cur_path;
@onready var tokenizer = $tokenizer_md;
signal tokens_ready;

func compile(text):
	var tokens = tokenizer.tokenize(text);
	print(tokens);

func _on_tokenizer_md_tokens_ready(tokens) -> void:
	tokens_ready.emit(tokens);

func set_cur_filename(val): tokenizer.cur_filename = val;
func set_cur_path(val): tokenizer.cur_path = val;
