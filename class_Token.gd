extends RefCounted
class_name Token

var tok_class:String;
var text:String;
var line:String;
var line_idx:int;
var col:int;

func _init(dict=null):
	if dict:
		for key in dict:
			assert(key in self); # weirdly motivational
			set(key, dict[key]);

func duplicate()->Token:
	var tok2 = Token.new();
	G.duplicate_shallow(self, tok2);
	return tok2;

func _to_string()->String:
	if text == "":
		return "[%s]" % tok_class;
	else:
		return "[%s:%s]" % [tok_class, text];
