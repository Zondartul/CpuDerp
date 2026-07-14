extends Node
class_name Language

var lang_name:String;
func get_syntax()->CodeHighlighter: 
	return CodeHighlighter.new();
