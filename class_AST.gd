extends Token
class_name AST;

var children:Array[AST];

func _init(cfg=null):
	if cfg: 
		if cfg is Dictionary:
			var dict = cfg;		
			for key in dict:
				assert(key in self);
				set(key, dict[key]);
		elif cfg is Token:
			var tok = cfg;
			G.duplicate_shallow(tok, self);
