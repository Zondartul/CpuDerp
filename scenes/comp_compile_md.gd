extends Node

var cur_filename;
var cur_path;
const script_tokenizer = preload("res://scenes/word_boundary_tokenizer.gd")
const lang = preload("res://scenes/lang_md.gd")
var tokenizer;

func _ready():
	tokenizer = script_tokenizer.new();
	tokenizer.ch_punct = lang.get_all_punct();

func compile(text):
	var tokens = tokenize(text);
	print(tokens);

var char_classes = ["WORD", "PUNCT", "NUM", "STR"];

func tokenize(text):
	return tokenizer.tokenize(text);
