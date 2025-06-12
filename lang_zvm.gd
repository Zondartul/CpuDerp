extends Node
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
	"JG": {"op_code":3, "flags":BIT_SPEC_IFGREATER},
	"JL": {"op_code":3, "flags":BIT_SPEC_IFLESS},
	"JE": {"op_code":3, "flags":BIT_SPEC_IFZERO},
	"JZ": {"op_code":3, "flags":BIT_SPEC_IFZERO},
	"JNZ": {"op_code":3, "flags":(BIT_SPEC_IFLESS | BIT_SPEC_IFGREATER)},
	"JNE": {"op_code":3, "flags":(BIT_SPEC_IFLESS | BIT_SPEC_IFGREATER)},
	"JNG": {"op_code":3, "flags":(BIT_SPEC_IFLESS | BIT_SPEC_IFZERO)},
	"JNL": {"op_code":3, "flags":(BIT_SPEC_IFGREATER | BIT_SPEC_IFZERO)},
};
