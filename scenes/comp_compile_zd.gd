extends Node

# compiler for zderp - outputs zdasm
# ZDerp is a low-level systems programming language that gives you direct memory access
# it has both static and dynamic typing (via Variant), lambdas and exceptions.
#
# runtime features:
# - type DB for user-structs
# - memory mapping stack
# - construct-destruct stack
# 
# types: 
# ----- raw (no malloc)
# Char:8 bits, - an unsigned 0-255 integer or ASCII character
# Int:32 bits, - an unsigned 0-2^32-1 integer
# Float:32 bits, - +- floating point number
# DString:80 bytes, - an ASCII string with max length of 79 chars
# DArray: (const), - a constant-length array
# Struct: (const),	- a 
# DPtr:(1 int) - a raw pointer
# Func:(2 DPtrs) - a function pointer w/ capture or functor data
# AddrRange:(2 DPtrs + int) - an address range for applying an offset to a pointer
# ----- managed (yes malloc)------------
# String: (const head, dynamic body)
# Array: (const head, dynamic body)
# Dict: (dynamic)
# Variant: (dynamic)
# MemMap: (1 Array) - an array of AddrRanges for software emulated MMU mapping
#                      can be "pushed" or "popped" from the stack of active MMs
#-----------------------------------------------
# control structures
# if cond { } else { }
# while cond {}
# for (a;b;c) {}
# for (x in y) {}
# func name (args -> type)
# struct Type {}
# throw catch 
#--------------------------------
# when two programs interact, they
# need to share type info DB and memmap stack
# ... possibly the whole runtime.
# though memmap could be per-object or per-thread
# per-thread runtime data?
#--------------------------------
# operators:
# arithmetic: + - * / ** ++ --
# assignment: = += -= *= /=
# logic: and or not
# bitwise: & | ^ ~
# types: is as to -> 
# index: []
# member access: . (both vals and ptrs)
# memory: new delete
#--------------------------------

const regex = preload("res://my_regex.gd");

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func tokenize(text):
	pass

func compile(text):
	var toks = tokenize(text);
	print(str(toks));
