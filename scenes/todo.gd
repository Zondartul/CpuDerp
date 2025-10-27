extends Node

# Todo
# [FIXED bug]			"CTRL-S" 
#	ctrl-s doesn't save
# [FIXED bug] 			"BUILD SAVE" 
#	build doesn't save
# [FIXED bug]			"TAB COMPILE"
#	opening another file and then tabbing back makes it not compile
# [refactor]			"ASSEMBLER SPLIT"
#	split assembler into low-lvl and high-lvl
# 		what does this mean???
# [idea]				"MEMORY FILE" 
#	paste file into memory or load from memory and save to disk
# [FIXED enhancement]	"COMPILE SUCCESS"
#	Editor should indicate when <build> succeeds.
# [FIXED enhancement]	"DEBUG UPDATE" 
#	Debugger should update continuously while CPU is running
# [FIXED bug] 			"CPU IP" 
#	CPU IP doesn't change when running (or calling?)
# [PARTIAL feature]		"DEBUG INSTRUCTION" 
#	Debugger should show current assembly instruction
#           - from debug symbols        
#			- also from decompiled
# [PARTIAL feature]		"DEBUG FUNCTION" 
#	Debugger should show current function
#			- from debug symbols
#			- from stack trace
# [FIXED automation]	"AUTOMATION SCRIPT" 
#	for debug, set a list of UI interactions 
#			that should happen automatically when starting
# [FIXED enhancement]	"EXTENSION SETS LANGUAGE" 
#	infer language from file extension
# [bug]					"NESTED ARRAY" 
#	I suspect that multiple array access has a landmine as it produces a needs_deref value
# [FIXED bug]			"TAB DIRTY" 
#	sometimes the wrong tab gets the filename*
# [FIXED bug]			"CLEAR COMPILER" 
#	compiler and codegen do not clear data between runs
# [enchancement]		"ARITY CHECK" 
#	analyzer should check argument count
# [FIXED enhancement]	"BUILD CPU RESET" 
#	compiling should also reset CPU and screen
# [FIXED enhancement] 	"BUILD CLEAR CONSOLE" 
#	compiling should clear the console
# [FIXED enhancement] 	"SEARCH GUI"		
#	the editor needs a Search (ctrl+F) function (GUI)
# [feature]				"ERROR PRODUCTIONS"		
#	parser should report errors:
#			- via first/follow sets
#			- by building a FSA
# [enhancement]			"EXPR REORDER" 
#	parser should re-order expressions based on operator precedence
# [feature]				"TYPES" 
#	implement types (char vs u32)
# [feature]				"HL DEBUG" 
#	high-level debugger
# [feature]				"DEBUG STACK SMASH" 
#	stack smash detection (stack modified by non-control-flow instruction)
# [feature]				"SETTINGS WINDOW"
# [feature]				"ASM COMMAND" 
#	#asm to embed assembly into miniderp code
# [feature]				"INCLUDE COMMAND" 
#	#include so libraries work
# [enhancement]			"FWD DECL OPTIONAL" 
#	make local functions not need a forward declaration
# [project]				"ASSY TEMPLATES" 
#	rewrite the code generator to use an assembly template DSL
# [project]				"ANALYZER SPLIT" 
#	split analyzer into parse/generate or parse/typecheck/generate
# [enhancement]			"HIGHLIGHT FILE"
#	highlighter and error-reporter should specify filename
# [FIXED bug]			"DEBUG LOCALS FLICKER"
#	maybe a race condition, it sometimes shows "null" function
# [legacy]				"OP LOCATIONS"
#	remove the old "op location" system for ASM debugging and replace with LocationRanges
# [refactor]			"ELM IN COMPILER"
#	expanded location map should be precomputed in the compiler, not the debugger.
#
