extends Node
class_name ErrorReporter;

@export var Editor:Node;
var proxy;
var context;
signal sig_highlight_line(line_idx);
#func _init(new_proxy, new_context=null):
#	proxy = new_proxy;
#	context = new_context;

func _ready():
	if Editor: proxy = Editor;

func assert_valid_proxy():
	for prop in ["error_code"]:#["user_error", "error_code", "cprint", "sig_highlight_line", "cur_line", "cur_line_idx"]:
		if not prop in proxy:
			push_error("ErrorReporter: proxy needs to have '%s'" % prop);

func error(msg):
	push_error(msg);
	if proxy.error_code != "": return; ## suppress cascading errors
	proxy.user_error(msg);
	proxy.error_code = msg;
	if context != null:
		if context is Token:
			point_out_error_tok("", context);
		elif context is Iter:
			point_out_error_iter("", context);
		else:
			push_error(E.ERR_01); assert(false);

func point_out_error(msg:String, line_text:String, line_idx:int, char_idx:int)->void:
	Editor._on_cprint("error at line "+str(line_idx)+":\n");
	Editor._on_cprint(line_text);
	Editor._on_cprint(" ".repeat(char_idx)+"^");
	Editor._on_cprint(msg);
	sig_highlight_line.emit(line_idx);
	

func point_out_error_iter(msg:String, iter:Iter)->void:
	#var char_idx = iter.tokens[iter.pos]["col"]; #iter[0][iter[1]]["col"];#iter_count_chars(iter);
	#point_out_error(msg, cur_line, cur_line_idx, char_idx)
	if(iter.pos >= len(iter.tokens)): iter.pos = len(iter.tokens)-1;
	var tok = iter.tokens[iter.pos];
	tok.line = proxy.cur_line; tok.line_idx = proxy.cur_line_idx;
	point_out_error_tok(msg, iter.tokens[iter.pos]);

func point_out_error_tok(msg:String, tok:Token)->void:
	point_out_error(msg, tok.line, tok.line_idx, tok.col);	
