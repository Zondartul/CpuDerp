Todo

- '\n' // character literals
- var arr = [10] // array declaration
- x = [a,b,c]; // array construction
- #include // needs to be implemented
- += // infix ops need to implemented
- != doesn't compile?
- x[I] == y[I] parses as (x[I] == y)[I] // broken precedence!
- function arity not checked
- calling a variable as function doesn't compile: f() syntax

- fix callout line numbers in assembler erep, and search jump
- Refactor Analyzer_md: parse/capture first, logic second.
e.g.
var captures = [a_name, a_expr, a_lhs];
var pattern = ["expr/", 1, ["OR", ";", ["blah", "call/", ["ident",0,["OR", "expr", "expr_list"]], "=", "ANY", 2]]];
# {1:expr}/(
#	;
#	|call/
#		{0:ident} (expr|expr_list)
#	= {2:ANY}
var err = parse(AST,pattern,captures);
- verifies AST structure
- catches unimplemented syntax
- grabs typed values
maybe:
	const pattern_str = ...
	static pattern:AnalyzerPattern = compile_analyzer_pattern(pattern, pattern_str);
	func analyze_foo(): pattern.parse(AST, captures);
	or captures:Dictionary = pattern.parse(AST);
	if captures.err: return;
	
