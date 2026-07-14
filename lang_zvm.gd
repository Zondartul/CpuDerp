extends Node
class_name ISA_ZVM;
# constants and definitions for the language: ZonVM assembly
# ----------------- instruction set -----------------
const regnames = [
	"NONE",
	"EAX", "EBX", "ECX", "EDX",
	"IP", 
	"ESP", "ESZ", "ESS", "EBP",
	"IVT", "IVS", "IRQ", 
	"CTRL"
];

const ctrl_flags = [
	"PWR",  #cpu is on
	"STEP", #cpu should stop after 1 step
	"IRS",  #interrupt is being serviced now
	"CMP_L", #compare-less
	"CMP_G", #compare-greater
	"CMP_Z", #compare-zero
	"IE", #interrupts enabled
	#"JUMPED" #just performed a jmp/call/ret/int/intret instruction - do not increment IP
];

const BIT_PWR = (0b1 << 0);
const BIT_STEP = (0b1 << 1);
const BIT_IRS = (0b1 << 2);
const BIT_CMP_L = (0b1 << 3);
const BIT_CMP_G = (0b1 << 4);
const BIT_CMP_Z = (0b1 << 5);
const BIT_IE = (0b1 << 6);

const ctrl_flag_masks = {
	"PWR":BIT_PWR,
	"STEP":BIT_STEP,
	"IRS":BIT_IRS,
	"CMP_L": BIT_CMP_L,
	"CMP_G": BIT_CMP_G,
	"CMP_Z": BIT_CMP_Z,
	"CMP_NZ": BIT_CMP_L | BIT_CMP_G,
	"IE": BIT_IE,
	};
# option flags
#     ---- adr mode ---
# 0 - |  00 reg-reg, 001 reg-*reg, 10 *reg-reg, 11 *reg-*reg 
# 1 - |   + immediate mode is added to src OR dest (before *)
# 2 - 0: src += im; 1: dest += im;
# 3 - 0: 8-bit data, 1: 32-bit data
#     -----command-specific ---
#      ---jmp------|-------shift---------|
# 2 - | if-less    |-| 00 - zero-shift   |
# 3 - | if-zero    |-| 01 - barrel-shift |
# 4 - | if-greater |-| 10 - carry-shift  |
#     -------------
# 5 - | 
# 6 - | 
# 7 - |
const BIT_DEREF1 = (0b1 << 0);
const BIT_DEREF2 = (0b1 << 1);
const BIT_IMDEST = (0b1 << 2);
const BIT_SPEC_IFLESS = (0b1 << 0);
const BIT_SPEC_IFZERO = (0b1 << 1);
const BIT_SPEC_IFGREATER = (0b1 << 2);

const REG_NONE = 0
const REG_EAX = 1;
const REG_EBX = 2;
const REG_ECX = 3;
const REG_EDX = 4;
const REG_IP = 5;
const REG_ESP = 6;
const REG_ESZ = 7;
const REG_ESS = 8;
const REG_EBP = 9;
const REG_IVT = 10;
const REG_IVS = 11;
const REG_IRQ = 12;
const REG_CTRL = 13;
const N_REGS = REG_CTRL;


const opcodes = {
	#---- general ---
	0: "NONE",
	1: "HALT",
	2: "RESET",
	#---- control ---
	3: "JMP", #[op][cond][arg]
	4: "CALL",
	5: "RET",
	6: "CMP",
	#---- interrupt ---
	7: "INT",
	8: "INTRET",
	#---- memory ----
	9: "MOV",
	10: "PUSH",
	11: "POP",
	#---- ALU arithmetic ---
	12: "ADD",
	13: "SUB",
	14: "MUL",
	15: "DIV",
	16: "MOD",
	17: "ABS",
	18: "NEG",
	19: "INC",
	20: "DEC",
	#---- ALU logic
	21: "AND",
	22: "OR",
	23: "XOR",
	24: "NOT",
	#---- ALU bitwise
	25: "BAND",
	26: "BOR",
	27: "BXOR",
	28: "BNOT",  
	29: "SHIFT", #opts: barrel y/n, carry set/get, left/right
	30: "BSET",   # set bit N = 1
	31: "BGET",   # get bit N (to dest and to cmp is-zero)
	32: "BCLEAR", # clear bit N = 0
	#---- generic
	33: "NOP",
	#-: "#DB",     # insert data here
	#-: "#ALLOC",  # insert N empty bytes
	#-: "#WP",     # set write pointer   
};

const spec_ops = {
	"JMP": {"op_code":3, "flags":(BIT_SPEC_IFLESS | BIT_SPEC_IFGREATER | BIT_SPEC_IFZERO)},
	"JG": {"op_code":3, "flags":BIT_SPEC_IFGREATER},
	"JL": {"op_code":3, "flags":BIT_SPEC_IFLESS},
	"JE": {"op_code":3, "flags":BIT_SPEC_IFZERO},
	"JZ": {"op_code":3, "flags":BIT_SPEC_IFZERO},
	"JNZ": {"op_code":3, "flags":(BIT_SPEC_IFLESS | BIT_SPEC_IFGREATER)},
	"JNE": {"op_code":3, "flags":(BIT_SPEC_IFLESS | BIT_SPEC_IFGREATER)},
	"JNG": {"op_code":3, "flags":(BIT_SPEC_IFLESS | BIT_SPEC_IFZERO)},
	"JNL": {"op_code":3, "flags":(BIT_SPEC_IFGREATER | BIT_SPEC_IFZERO)},
};

const SHADOW_UNUSED = 0;
const SHADOW_DATA = 1;
const SHADOW_CMD_HEAD = 2;
const SHADOW_CMD_TAIL = 3;
const SHADOW_CMD_UNRESOLVED = 4;
const SHADOW_CMD_RESOLVED = 5;
const SHADOW_DATA_UNRESOLVED = 6;
const SHADOW_DATA_RESOLVED = 7;
const SHADOW_PADDING = 8;
const SHADOW_FRAME_PREV_EBP = 9;
const SHADOW_FRAME_PREV_IP = 10;
const SHADOW_FRAME_ARGUMENT = 11;
const SHADOW_FRAME_VAR = 12;
const SHADOW_FRAME_TEMP = 13;
const SHADOW_FRAME_PADDING = 14;

const SHADOW_TO_STRING = {
	SHADOW_UNUSED: "UNUSED",
	SHADOW_DATA: "DATA",
	SHADOW_CMD_HEAD: "CMD_HEAD",
	SHADOW_CMD_TAIL: "TAIL",
	SHADOW_CMD_UNRESOLVED: "CMD_UNRESOLVED",
	SHADOW_CMD_RESOLVED: "CMD_RESOLVED",
	SHADOW_DATA_UNRESOLVED: "DATA_UNRESOLVED",
	SHADOW_DATA_RESOLVED: "DATA_RESOLVED",
	SHADOW_PADDING: "PADDING",
	SHADOW_FRAME_PREV_EBP: "FRAME_PREV_EBP",
	SHADOW_FRAME_PREV_IP: "FRAME_PREV_IP",
	SHADOW_FRAME_ARGUMENT: "FRAME_ARGUMENT",
	SHADOW_FRAME_VAR: "FRAME_VAR",
	SHADOW_FRAME_TEMP: "FRAME_TEMP",
	SHADOW_FRAME_PADDING: "FRAME_PADDING",
};

## decoded command "flags" byte
class CmdFlags:
	var deref1:bool; ## should arg1 be dereferenced?
	var deref2:bool; ## should arg2 be dereferenced?
	var special:int; ## command-specific flags (e.g. jump mask)
	func _init(_deref1:bool,_deref2:bool,_special:int):
		deref1=_deref1;deref2=_deref2;special=_special;

## decoded representation of a command (sparse)
class Cmd:
	var op_num:int; ## operation code (command number)
	var op_str:String; ## human-readible representation of the opcode
	var flags:CmdFlags; ## decoded flags byte
	var reg1_num:int; ## register 1 index
	var reg1_str:String; ## reg1 human-readible name
	var reg1_im:bool; ## should the immediate be added to reg1?
	var reg2_num:int; ## register 2 index
	var reg2_str:String; ## reg2 human-readible name
	var reg2_im:bool; ## should the immediate be added to reg2?
	var im:int; ## the immediate value or offset
	var is_32bit:bool; ## should the command use the 32-bit data width?
	func _init( # forego the dictionary for fast assignment
		_op_num:int,_op_str:String,_flags:CmdFlags,
		_reg1_num:int,_reg1_str:String,_reg1_im:bool,
		_reg2_num:int,_reg2_str:String,_reg2_im:bool,
		_im:int,_is_32bit:bool):
		op_num=_op_num;op_str=_op_str;flags=_flags;
		reg1_num=_reg1_num;reg1_str=_reg1_str;reg1_im=_reg1_im;
		reg2_num=_reg2_num;reg2_str=_reg2_str;reg2_im=_reg2_im;
		im=_im;is_32bit=_is_32bit;
