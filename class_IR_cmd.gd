extends RefCounted
class_name IR_Cmd;

var words:Array[String];
var loc:LocationRange;

func _init(_words:Array[String],_loc:LocationRange):
	words=_words;loc=_loc;

#func _get(index):
	#if index is int:
		#return words[index];
	#return null;
#
#func _set(index, value):
	#if index is int:
		#words[index] = value;
		#return true;
	#return false;
#
#func pop_back():
	#return words.pop_back();
#
#func push_back(value):
	#words.push_back(value);
