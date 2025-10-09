extends RefCounted
class_name Cmd_arg;

var is_present:bool = false; #did we get supplied with this arg in assembly?
var reg_name:String = "";
var reg_idx:int = 0;
var offset:int = 0;
var is_deref:bool = false;
var is_imm:bool = false;
var is_32bit:bool = false; # is this even arg-level?
var is_unresolved:bool = false; #is this a label that needs to be resolved by linker?
