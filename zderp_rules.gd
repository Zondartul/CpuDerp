extends Node

# tokens:
# [type|text|pos]
# [keyword] - if, else, func, struct, etc.
# [type]    - Int, Float - starts with a capital letter
# [ident]   - any word made of _abcDEFG where the first letter is lowercase
# [number]  - 123, 123.324, 0xB00F, 0b11001; (no minus, that's an operator)
# [op]		- +, -, ...
# [punct]   - (){},;
# [space]	- \s \t \n \r
# [comment]	- // stuff (till end of line)



var token_rules = [
	["[A-Z][a-zA-Z0-9_]*", "type"],
	["[a-z][a-zA-Z0-9_]*", "ident"],
	["(0-9)+(.[0-9]+)?", "number"],
	["(0b)([01]+)", "number"],
	["(0x)([0-9A-F]+)", "number"],
	["++|--|+=|-=|/=|*=|==|->|in|to|as", "op"],
	["[=+\\-*/^.]", "op"],
	["[(){}:,;]","punct"],
	["[ \t\n\r]","space"],
	["//.*$", "comment"],
];

