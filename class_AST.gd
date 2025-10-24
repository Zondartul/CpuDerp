extends Token
class_name AST;

var children:Array[AST];

func _init(cfg=null):
	if cfg: 
		if cfg is Dictionary:
			#var dict = cfg;		
			#for key in dict:
			#	assert(key in self);
			#	set(key, dict[key]);
			G.dictionary_init(self, cfg);
		elif cfg is Token:
			var tok = cfg;
			G.duplicate_shallow(tok, self);

func duplicate()->AST:
	var ast2 = AST.new();
	G.duplicate_shallow(self, ast2);
	return ast2;

func get_location()->LocationRange:
	var res;
	if loc:
		res = loc.duplicate();
	elif len(children):
		res = children[0].get_location();
	else:
		res = LocationRange.new();
	for ch in children:
		var ch_loc = ch.get_location();
		if ch_loc.begin.less_than(res.begin): res.begin = ch_loc.begin;
		if res.end.less_than(ch_loc.end): res.end = ch_loc.end;
	return res;
