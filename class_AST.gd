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
		if ch_loc.from.less_than(res.from): res.from = ch_loc.from;
		if res.to.less_than(ch_loc.to): res.to = ch_loc.to;
	return res;
