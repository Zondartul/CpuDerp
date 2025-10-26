extends Node
# this tokenizer was grabbed from comp_asm_zd

#------------ Tokenization ----------------------------------
func tokenize(line:String)->Array[Token]:
	var tokens:Array[Token] = [];
	var tok_class = "";
	var cur_tok = "";
	var col = 0;
	var cur_loc:Location = Location.new({"col":0, "line":line});
	for ch in line:
		var new_tok_class = tok_ch_class(ch);
		if should_split_on_transition(new_tok_class, tok_class):
			if tok_class == "STRING" and new_tok_class == "STRING":
				new_tok_class = "ENDSTRING";
				cur_tok = cur_tok.substr(1); #remove the leading \"
			if cur_tok != "":
				cur_loc.col -= 1;
				var tok_loc = LocationRange.from_loc_len(cur_loc, len(cur_tok));
				tokens.append(Token.new({"tok_class":tok_class, "text":cur_tok, "loc":tok_loc}));#"col":col-1}));
				cur_tok = "";
			tok_class = new_tok_class;
		cur_tok += ch;
		col += 1;
		cur_loc.col = col;
	if cur_tok != "":
		cur_loc.col -= 1;
		var tok_loc = LocationRange.from_loc_len(cur_loc, len(cur_tok));
		tokens.append(Token.new({"tok_class":tok_class, "text":cur_tok, "loc":tok_loc}));
		cur_tok = "";
	#tokens = tokens.filter(filter_tokens);
	return tokens;

func should_split_on_transition(new_tok_class:String, old_tok_class:String):
	#if (new_tok_class != tok_class) or (tok_class == "PUNCT"):
	if old_tok_class == "PUNCT": return true; # punctuation tokens are always one-by-one.
	elif old_tok_class == "WORD" and new_tok_class == "NUMBER": return false; #allow numbers to be included in names
	elif old_tok_class == "STRING" and new_tok_class == "STRING": return true; #split on beginning and end of string (ie \")  
	elif old_tok_class == "STRING": return false; # keep building the string
	else: return (old_tok_class != new_tok_class); #split on any other class change
	

#func filter_tokens(tok):
#	if tok["class"] in ["SPACE", "ENDSTRING"]: return false;
#	return true;

var ch_punct = ".,:[]+;";
const ch_alphabet = "qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM_";
const ch_digits = "1234567890";

func tok_is_punct(ch:String)->bool: return ch in ch_punct;
func tok_is_word(ch:String)->bool: return ch in ch_alphabet;
func tok_is_num(ch:String)->bool: return ch in ch_digits;

# character class for tokenizer:
#const TOK_ERROR = 0
#const TOK_SPACE = 1
#const TOK_WORD = 2
#const TOK_NUMBER = 3
#const TOK_PUNCT = 4 #and above - individual distinct punct symbols
# deprecated - now using strings

func tok_ch_class(ch:String)->String:
	if ch == " ": return "SPACE";
	if tok_is_word(ch): return "WORD";
	if tok_is_num(ch): return "NUMBER";
	if tok_is_punct(ch): return "PUNCT";
	if ch == "\"": return "STRING";
	return "ERROR"
#-------------------------------------------------------------
