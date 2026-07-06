extends Node
class_name Storage

const NONE = 0; # no value
const GLOBAL = 1; # global location
const STACK = 2; # generic stack location
const STACK_ARG = 3; # stored in the stack-positive direction (above EBP)
const STACK_VAR = 4; # stored in the stack-negative direction (below EBP)
const STACK_DYNAMIC = 5; # pushed and popped without a recorded spot

var type = NONE; # storage type
var assigned = false; # is location valid?
var pos = 0; # position in bytes
var size_bytes = 0; # location is [pos, pos+size_bytes)
var label = null; # for globals, label instead of position
