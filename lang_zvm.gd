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
	0: "HALT",
	1: "RESET",
	#---- control ---
	2: "JMP", #[op][cond][arg]
	3: "CALL",
	4: "RET",
	5: "CMP",
	#---- interrupt ---
	6: "INT",
	7: "INTRET",
	#---- memory ----
	8: "MOV",
	9: "PUSH",
	10: "POP",
	#---- ALU arithmetic ---
	11: "ADD",
	12: "SUB",
	13: "MUL",
	14: "DIV",
	15: "MOD",
	16: "ABS",
	17: "NEG",
	18: "INC",
	19: "DEC",
	#---- ALU logic
	20: "AND",
	21: "OR",
	22: "XOR",
	23: "NOT",
	#---- ALU bitwise
	24: "BAND",
	25: "BOR",
	26: "BXOR",
	27: "BNOT",  
	28: "SHIFT", #opts: barrel y/n, carry set/get, left/right
	29: "BSET",   # set bit N = 1
	30: "BGET",   # get bit N (to dest and to cmp is-zero)
	31: "BCLEAR", # clear bit N = 0
	#---- generic
	32: "NOP",
	#-: "#DB",     # insert data here
	#-: "#ALLOC",  # insert N empty bytes
	#-: "#WP",     # set write pointer   
};
