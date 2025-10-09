extends RefCounted
class_name Cmd_flags;

var deref_reg1:bool = false;
var deref_reg2:bool = false;
var reg1_im:bool = false;
var reg2_im:bool = false; # not encoded
var is_32bit:bool = false;
var spec_flags:int = 0;

func to_byte()->int:
	return  (int(deref_reg1) << 0) | \
			(int(deref_reg2) << 1) | \
			(int(reg1_im) << 2) | \
			(int(is_32bit) << 3) | \
			((spec_flags & 0b111) << 4);
			
func set_arg1(arg:Cmd_arg)->void:
	reg1_im = arg.is_imm;
	deref_reg1 = arg.is_deref;

func set_arg2(arg:Cmd_arg, erep:ErrorReporter)->void:
	reg2_im = arg.is_imm;
	if reg1_im and reg2_im: 
		erep.error(E.ERR_04);
	deref_reg2 = arg.is_deref;
