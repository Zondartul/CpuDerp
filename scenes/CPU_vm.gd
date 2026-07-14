extends Node
class_name CPU_vm
var Bus:Node;
#var GPU;
#var KB;
var is_setup:bool = false;
var debug_vm:bool = false;
var freq:int = 1;
var errcode:int = 0;
signal cpu_step_done(cpu);
signal mem_accessed(addr, val, is_write);
# for instruction set, preload the language
static var ISA:ISA_ZVM = G.isa_zvm;

# error codes
const ERR_NONE:int = 0;
# input's fault:
const ERR_EXEC_DATA:int = 1;
const ERR_STACK_OVERFLOW:int = 2;
const ERR_STACK_UNDERFLOW:int = 3;
const ERR_BAD_OP:int = 4; # malformed machine code instruction
const ERR_INPUT:int = 5; # generic input wrongness
# cpu's fault:
const ERR_SANITY:int = 6; # sanity check assert, this probably never happens
const ERR_INTERNAL:int = 7; # generic our-fault error


var regs:PackedInt32Array;
# command structure:
# bytes	0		1		2		3	4	5	6	7 
#	  [cmd]	[ flags ][reg1|reg2][immediate u32][pad]
# idea: use pad as checksum. if checksum doesn't match, it's data.
const cmd_size:int = 8;
var no_side_effects:bool = false; #set to true to use utility functions as pure


signal on_cpu_error(new_errcode);

func cpu_error(code:int, msg:String)->void:
	print(msg);
	errcode = code;
	on_cpu_error.emit(code);
	halt();

func cpu_assert(cond, code:int, msg:String)->bool:
	var b:bool = bool(cond);
	if (not b) and not no_side_effects: cpu_error(code, msg);
	return b;

func set_on(on:bool)->void:
	if on:
		regs[ISA.REG_CTRL] |= ISA.BIT_PWR;
		if(debug_vm):print("cpu turned on");
	else:
		regs[ISA.REG_CTRL] &= ~ISA.BIT_PWR;
		if(debug_vm):print("cpu turned off");

func reset()->void:
	regs = PackedInt32Array([
	0, # NONE (not-a-register)
	0, #0:EAX       -\
	0, #1:EBX       -|general purpose registers 
	0, #2:ECX       -|
	0, #3:EDX       -/
	0, #4:IP        # instruction pointer
	65535, #5:ESP   # stack pointer, grows down
	65535, #6:ESZ   # stack zero, underflow if pop
	0,     #7:ESS   # stack size, overflow if push
	0,     #8:EBP   # (stack frame) base pointer
	0,     #9:IVT   # interrupt vector table
	0,     #10:IVS  # interrupct vector size
	0,     #11:IRQ  # interrupt request flag
	0,     #12:CTRL # control register
	]);
	errcode = 0;
	pass;

func setBit(Byte:int, bit:int, val:int=1)->int:
	Byte &= 0b11111111; # mod 255
	if(val):
		Byte |= 0b1 << bit;
	else:
		Byte &= ~(0b1 << bit);
	return Byte;

func getBit(Byte:int, bit:int)->int:
	return (Byte & (0b1 << bit)) >> bit;

func clearBit(Byte, bit)->int: return setBit(Byte, bit, 0);

func fetchByte()->int:
	var byte:int = read8(regs[ISA.REG_IP]); #Bus.readCell(regs[REG_IP]);
	regs[ISA.REG_IP] = to_U32(regs[ISA.REG_IP]+1);
	return byte;

## What does this do?
var bus_setting:Array[bool] = [];
func dbg_push_bus_dbg()->void:
	bus_setting.push_back(Bus.debug_bus_read);
	#bus_setting.push_back(Bus.debug_bus_write);
func dbg_pop_bus_dbg()->void:
	#Bus.debug_bus_write = bus_setting.pop_back()
	Bus.debug_bus_read = bus_setting.pop_back();
func dbg_suppress_bus_dbg()->void:
	Bus.debug_bus_read = false;
	#Bus.debug_bus_write = false;

func fetchCmd()->PackedByteArray:
	dbg_push_bus_dbg();
	dbg_suppress_bus_dbg();
	var cmd:Array[int] = [];
	for i in range(8): cmd.append(fetchByte())
	dbg_pop_bus_dbg();
	return PackedByteArray(cmd);

func disasm_pure(cmd:PackedByteArray)->String:
	no_side_effects = true;
	var decoded:ISA_ZVM.Cmd = decodeCmd(cmd);
	if not decoded: 
		no_side_effects = false;
		return "";
	var text:String = debug_disasm_cmd(decoded);
	no_side_effects = false;
	return text;

func decode_pure(cmd:PackedByteArray)->ISA_ZVM.Cmd:
	no_side_effects = true;
	var decoded:ISA_ZVM.Cmd = decodeCmd(cmd);
	no_side_effects = false;
	return decoded;

## Todo: split into "decodeCmd" and "validateCmd"
func decodeCmd(cmd:PackedByteArray)->ISA_ZVM.Cmd:
	var op:int = cmd[0];
	var flags:int = cmd[1];
	var regsel:int = cmd[2];
	var im:int = cmd.decode_u32(3); #offset = byte 3
	var reg1:int = regsel & 0b1111;
	var reg2:int = (regsel>>4) & 0b1111;
	var deref_reg1:bool = flags & (0b1 << 0);
	var deref_reg2:bool = flags & (0b1 << 1);
	var reg1_im:bool = flags & (0b1 << 2);
	var reg2_im:bool = not reg1_im;
	var is_32bit:bool = flags & (0b1 << 3);
	var spec_flags:int = (flags >> 4) & 0b111;
	
	if not (cpu_assert(op in range(ISA.opcodes.size()), ERR_EXEC_DATA,"trying to execute data")
	and cpu_assert(reg1 in range(ISA.regnames.size()), ERR_BAD_OP, "dest-register index out of bounds ("+str(reg1)+")") 
	and cpu_assert(reg2 in range(ISA.regnames.size()), ERR_BAD_OP, "src-register index out of bounds ("+str(reg2)+")")):
		return null;#false;
	
	var regname1:String = ISA.regnames[reg1];
	var regname2:String = ISA.regnames[reg2];
	var opname:String = ISA.opcodes[op];
	
	#var decoded = {
		#"op_num": op,
		#"op_str": opname,
		#"flags":{"deref1":deref_reg1, "deref2":deref_reg2,"special":spec_flags},
		#"reg1_num": reg1,
		#"reg1_str": regname1,
		#"reg1_im" : reg1_im,
		#"reg2_num": reg2,
		#"reg2_str": regname2,
		#"reg2_im" : reg2_im,
		#"im": im,
		#"is_32bit": is_32bit,
	#};
	var decoded:ISA_ZVM.Cmd = ISA_ZVM.Cmd.new(
		op, #op_num
		opname, #op_str
		ISA_ZVM.CmdFlags.new(
			deref_reg1, #deref1
			deref_reg2, #deref2
			spec_flags), #special
		reg1, #reg1_num
		regname1, #reg1_str
		reg1_im, #reg1_im
		reg2, #reg2_num
		regname2, #reg2_str
		reg2_im, #reg2_im
		im, #im
		is_32bit, #is_32bit
	);
	#print("cmd decode: "+str(decoded));
	if(reg1_im and im):if(debug_vm):print("------------ im @ 1");
	if(reg2_im and im):if(debug_vm):print("------------ im @ 2");
	if(debug_vm):print("Decoded command: [ "+debug_disasm_cmd(decoded)+" ]");
	return decoded;

func decode_op_variant(decoded:ISA_ZVM.Cmd)->String:
	var op_name:String = decoded.op_str;
	if op_name in ISA.spec_ops:
		var spec_op:Dictionary = ISA.spec_ops[op_name];
		var op_code:int = spec_op["op_code"];
		for op2_name in ISA.spec_ops:
			var spec_op2:Dictionary = ISA.spec_ops[op2_name];
			if (spec_op2["op_code"] == op_code) and (spec_op2["flags"] == decoded.flags.special):
				op_name = op2_name; 
				break;
	return op_name;

func debug_disasm_cmd(decoded:ISA_ZVM.Cmd)->String:
	var S:String = "";
	var op_name:String = decode_op_variant(decoded);
	S += op_name;
	if(decoded.is_32bit): S += ".32";
	
	var has_arg1:bool = (decoded.reg1_num or decoded.reg1_im);
	var has_arg2:bool = (decoded.reg2_num or decoded.reg2_im);
	if(has_arg1 or has_arg2): S += " ";
	if(has_arg1):
		if(decoded.flags.deref1):
			if(decoded.reg1_num):
				if not cpu_assert(decoded.reg1_str != "", ERR_SANITY, ""): return "";
				if(decoded.reg1_im):
					# eax[num] syntax
					S += decoded.reg1_str + "[" + str(decoded.im) + "]";
				else:
					# *eax syntax
					S += "*" + decoded.reg1_str;
			else:
				# *num syntax
				S += "*" + str(decoded.im);
		else:
			if(decoded.reg1_num):
				if not cpu_assert(decoded.reg1_str != "", ERR_SANITY, ""): return "";
				if(decoded.reg1_im and decoded.im):
					# eax+num syntax
					S += decoded.reg1_str + "+" + str(decoded.im);
				else:
					# eax syntax
					S += decoded.reg1_str;
			else:
				# num syntax
				S += str(decoded.im);
				
	if(has_arg2): S += ", ";
	if(has_arg2):
		if(decoded.flags.deref2):
			if(decoded.reg2_num):
				if not cpu_assert(decoded.reg2_str != "", ERR_SANITY, ""): return "";
				if(decoded.reg2_im):
					# eax[num] syntax
					S += decoded.reg2_str + "[" + str(decoded.im) + "]";
				else:
					# *eax syntax
					S += "*" + decoded.reg2_str;
			else:
				# *num syntax
				S += "*" + str(decoded.im);
		else:
			if(decoded.reg2_num):
				if not cpu_assert(decoded.reg2_str != "", ERR_SANITY, ""): return "";
				if(decoded.reg2_im and decoded.im):
					# eax+num syntax
					S += decoded.reg2_str + "+" + str(decoded.im);
				else:
					# eax syntax
					S += decoded.reg2_str;
			else:
				# num syntax
				S += str(decoded.im);
	S += ";"
	return S;

func dummy_func(cmd)->void:
	if(debug_vm):print("CPU cmd not implemented: "+cmd.op_str);
	pass

func check_jmp_cond(cmd)->bool:
	if cmd.flags.special == 0: 
		if(debug_vm):print("(jmp cond 0 - uncoditional)");
		return true;
	var need_l:int = cmd.flags.special & (0b1 << 0);
	var need_e:int = cmd.flags.special & (0b1 << 1);
	var need_g:int = cmd.flags.special & (0b1 << 2);
	var has_l:int = regs[ISA.REG_CTRL] & ISA.BIT_CMP_L;
	var has_e:int = regs[ISA.REG_CTRL] & ISA.BIT_CMP_Z;
	var has_g:int = regs[ISA.REG_CTRL] & ISA.BIT_CMP_G;
	if(debug_vm):print("(jmp cond: need_l "+str(need_l)+", need_e "+str(need_e)+", need_g "+str(need_g)+")");
	if(debug_vm):print("has_l "+str(has_l)+", has_e "+str(has_e)+", has_g "+str(has_g));
	
	if(need_l and has_l): return true; # jump if less
	if(need_e and has_e): return true; # jump if zero (equal)
	if(need_g and has_g): return true; # jump if greater
	return false;


func fetch_src(cmd)->int:
	var src_val:int = 0;
	if(cmd.reg2_num): src_val = to_U32(src_val+regs[cmd.reg2_num]);
	if(cmd.reg2_im): src_val = to_U32(src_val+cmd.im);
	if(cmd.flags.deref2): 
		if(cmd.is_32bit):
			src_val = read32(src_val);
		else:
			src_val = read8(src_val); #Bus.readCell(src_val);
	return src_val;

func fetch_dest(cmd)->int:
	var dst_val:int = 0;
	if(cmd.reg1_num): dst_val = to_U32(dst_val+regs[cmd.reg1_num]);
	if(cmd.reg1_im): dst_val = to_U32(dst_val+cmd.im);
	if(cmd.flags.deref1): 
		if(cmd.is_32bit):
			dst_val = read32(dst_val);
		else:
			dst_val = read8(dst_val); #Bus.readCell(dst_val);
	return dst_val; 

func store_dest(cmd, val)->void:
	var dest_adr:int = 0;
	if(cmd.flags.deref1):
		if(cmd.reg1_num): dest_adr = to_U32(dest_adr+regs[cmd.reg1_num]);
		if(cmd.reg1_im): dest_adr = to_U32(dest_adr+cmd.im);
		if(cmd.is_32bit):
			write32(dest_adr, val);
		else:
			write8(dest_adr, val);
		#Bus.writeCell(dest_adr, val);
	else:
		if not cpu_assert(
			not cmd.reg1_im, 
			ERR_BAD_OP,
			"can't store to (reg+im) register, need deref."
			): return;
			
		regs[cmd.reg1_num] = val;
		if(debug_vm):print("reg "+str(cmd.reg1_str)+" is now "+str(regs[cmd.reg1_num]));
	
func error_overflow()->void: if(debug_vm):print("CPU error: Stack Overflow"); halt();
func error_underflow()->void: if(debug_vm):print("CPU error: Stack Underflow"); halt();
func error_interrupt_oor()->void: if(debug_vm):print("CPU error: Interrupt index out of range"); halt();

func push(val)->void: push32(val);
func pop()->int: return pop32();

func push32(val)->void:
	var buff:PackedByteArray = PackedByteArray([0,0,0,0]);
	buff.encode_u32(0,val);
	#for n in buff: push8(n);
	for i in range(4):
		push8(buff[3-i]);

func pop32()->int:
	var buff:PackedByteArray = PackedByteArray([0,0,0,0]);
	for i in range(buff.size()): 
		#buff[buff.size()-1-i] = pop8();
		buff[i] = pop8();
	var n:int = buff.decode_u32(0);
	return n;

func read8(adr)->int: 
	var val:int = Bus.readCell(adr);
	mem_accessed.emit(adr, val, false);
	return val;
func write8(adr, val)->void: 
	if(val > 255):
		if(debug_vm):print("warning: write8("+str(val)+" > 255)");
	mem_accessed.emit(adr, val, true);
	Bus.writeCell(adr, val);
func read32(adr)->int:
	var buff:PackedByteArray = PackedByteArray([0,0,0,0]);
	for i in range(buff.size()):
		buff[i] = read8(adr+i);
	var val:int = buff.decode_u32(0);
	return val;
func write32(adr, val)->void:
	var buff:PackedByteArray = PackedByteArray([0,0,0,0]);
	buff.encode_u32(0, val);
	for i in range(buff.size()):
		write8(adr+i, buff[i]);

func push8(val)->void:
	if(regs[ISA.REG_ESP] <= regs[ISA.REG_ESS]): 
		error_overflow();
	else:
		write8(regs[ISA.REG_ESP], val); #Bus.writeCell(regs[REG_ESP], val);
		regs[ISA.REG_ESP] -= 1;

func pop8()->int:
	if(regs[ISA.REG_ESP] >= regs[ISA.REG_ESZ]):
		error_underflow();
		return 0;
	else:
		regs[ISA.REG_ESP] += 1;
		var val:int = Bus.readCell(regs[ISA.REG_ESP]);
		return val;

func push_all()->void: for i in range(1, regs.size()): push(regs[i]);
func pop_all()->void: for i in range(1, regs.size()): regs[i] = pop();

func _call(new_ip)->void:
	if(debug_vm):print("calling ("+str(new_ip)+")");
	push(regs[ISA.REG_IP]);
	push(regs[ISA.REG_EBP]);
	regs[ISA.REG_EBP] = regs[ISA.REG_ESP];
	regs[ISA.REG_IP] = new_ip;

func _ret()->void: 
	regs[ISA.REG_ESP] = regs[ISA.REG_EBP];
	regs[ISA.REG_EBP] = pop();
	regs[ISA.REG_IP] = pop(); 

func halt()->void: regs[ISA.REG_CTRL] &= ~ISA.BIT_PWR;

func cmd_halt(_cmd)->void: 
	if(debug_vm):print("CPU halted.");
	halt();
func cmd_reset(_cmd)->void: reset();
func cmd_jmp(cmd)->void: 
	var dest:int = fetch_dest(cmd); 
	var cond:int = check_jmp_cond(cmd);
	if(cond): 
		regs[ISA.REG_IP] = dest;
	if(debug_vm):print("[JMP to "+str(dest)+", cond "+str(cond)+"]")
func cmd_call(cmd)->void: 
	var dest:int = fetch_dest(cmd);
	if(check_jmp_cond(cmd)): _call(dest);
func cmd_ret(_cmd)->void: _ret();
func cmd_cmp(cmd)->void:
	var A:int = fetch_dest(cmd);
	var B:int = fetch_src(cmd);
	var is_L:int = int(A < B);
	var is_E:int = int(A == B);
	var is_G:int = int(A > B);
	if(debug_vm):print("cmd cmp("+str(A)+" v "+str(B)+"): l"+str(is_L)+" e"+str(is_E)+" g"+str(is_G));
	
	regs[ISA.REG_CTRL] &= ~(ISA.BIT_CMP_L | ISA.BIT_CMP_Z | ISA.BIT_CMP_G);
	if is_L: regs[ISA.REG_CTRL] |= ISA.BIT_CMP_L;
	if is_E: regs[ISA.REG_CTRL] |= ISA.BIT_CMP_Z;
	if is_G: regs[ISA.REG_CTRL] |= ISA.BIT_CMP_G;
	
func cmd_int(cmd)->void:
	var int_num:int = fetch_src(cmd);
	if( not (regs[ISA.REG_CTRL] & ISA.BIT_IE)): return; #interrupts disabled
	if(regs[ISA.REG_CTRL] & ISA.BIT_IRS): return; # already in interrupt
	regs[ISA.REG_IRQ] = int_num; # interrupt will be serviced next step
func cmd_intret(_cmd)->void:
	regs[ISA.REG_CTRL] &= ~ISA.BIT_IRS;
	_ret();
	pop_all();
func cmd_mov(cmd)->void:
	var src:int = fetch_src(cmd);
	store_dest(cmd, src);
func cmd_push(cmd)->void:
	var dest:int = fetch_dest(cmd);
	if(cmd.is_32bit):
		push32(dest);
	else:
		push8(dest);
func cmd_pop(cmd)->void:
	var val:int = 0;
	if(cmd.is_32bit):
		val = pop32();
	else:
		val = pop8();
	store_dest(cmd, val);

func ALU_op(cmd, op)->void:
	var A:int = fetch_dest(cmd);
	var B:int = fetch_src(cmd);
	var C:int = int(op.call(A,B)) & (2**32-1);
	store_dest(cmd, C);

func op_add(A, B)->int: return A+B;
func op_sub(A, B)->int: return A-B;
func op_mul(A, B)->int: return A*B;
func op_div(A, B)->int: return A/B;
func op_mod(A, B)->int: return A%B;
func op_abs(A, _B)->int: return abs(A);
func op_neg(A, _B)->int: return -A;
func op_inc(A, _B)->int: return A+1;
func op_dec(A, _B)->int: return A-1;
func op_and(A, B)->int: return A and B;
func op_or(A, B)->int: return A or B;
func op_xor(A, B)->int: return (A and not B) or (not A and B);
func op_not(A, _B)->int: return not A;
func op_band(A, B)->int: return A & B;
func op_bor(A, B)->int: return A | B;
func op_bxor(A, B)->int: return A ^ B;
func op_bnot(A, _B)->int: return ~A;
func op_bset(A, B)->int: return setBit(A, B);
func op_bget(A, B)->int: return getBit(A, B);
func op_bclear(A, B)->int: return clearBit(A, B);


func cmd_add(cmd)->void: ALU_op(cmd, op_add);
func cmd_sub(cmd)->void: ALU_op(cmd, op_sub);
func cmd_mul(cmd)->void: ALU_op(cmd, op_mul);
func cmd_div(cmd)->void: ALU_op(cmd, op_div);
func cmd_mod(cmd)->void: ALU_op(cmd, op_mod);
func cmd_abs(cmd)->void: ALU_op(cmd, op_abs);
func cmd_neg(cmd)->void: ALU_op(cmd, op_neg);
func cmd_inc(cmd)->void: ALU_op(cmd, op_inc);
func cmd_dec(cmd)->void: ALU_op(cmd, op_dec);
func cmd_and(cmd)->void: ALU_op(cmd, op_and);
func cmd_or(cmd)->void:  ALU_op(cmd, op_or);
func cmd_xor(cmd)->void: ALU_op(cmd, op_xor);
func cmd_not(cmd)->void: ALU_op(cmd, op_not);
func cmd_band(cmd)->void:ALU_op(cmd, op_band);
func cmd_bor(cmd)->void: ALU_op(cmd, op_bor);
func cmd_bxor(cmd)->void:ALU_op(cmd, op_bxor);
func cmd_bnot(cmd)->void:ALU_op(cmd, op_bnot);

# --------- shift operation helpers --------------
# here n refers to (signed) amount to shift by
# and determines which end of a number, bits disappear from

func basic_shift(val:int, n:int)->int:
	#var val_in = val;
	if n > 0:
		val = val << abs(n);
		#print("basic_shift: "+str(val_in)+" << "+str(n)+" = "+str(val));
	else:
		val = val >> abs(n);
	return val;

func getEndBit(val, n)->int:
	var bit:int = 0;
	if n > 0:
		bit = getBit(val, 31);
	else:
		bit = getBit(val, 0);
	return bit;

func setStartBit(val, n, bit)->int:
	if n > 0:
		val = setBit(val, 0, bit);
	else:
		val = setBit(val, 31, bit);
	return val;

func cmd_shift(cmd)->void:
	var src:int = fetch_src(cmd);
	var dest:int = fetch_dest(cmd);
	var dest_initial:int = dest;
	if src:
		#var end_bit_idx = 0;
		#var start_bit_idx = 31;
		if(cmd.flags.special == 0): #zero-shift (logical shift)
			if(debug_vm):print(".. basic shift (logical)");
			dest = basic_shift(dest, src);
		elif(cmd.flags.special == 1): #barrel-shift
			if(debug_vm):print(".. barrel shift");
			for i in range(abs(src)%32):
				var bit:int = getEndBit(dest, src);
				dest = basic_shift(dest, sign(src));
				dest = setStartBit(dest, src, bit);
		elif(cmd.flags.special == 2): #carry-shift (arithmetic shift)
			if(debug_vm):print(".. carry shift (arithmetic)")
			var sign_bit:int = getBit(dest, 31);
			if src > 0: # shift left, fill bottom with zeroes
				dest = basic_shift(dest, src);
			else: # shift right, fill top with sign bit
				for i in range(abs(src)%32):
					dest = basic_shift(dest, sign(src));
					dest = setBit(dest, 31, sign_bit);
		else:
			if not cpu_assert(
				false, 
				ERR_BAD_OP,
				"can't figure out shift flags"): return;
				
	if(debug_vm):print("cmd shift ("+str(dest_initial)+" << "+str(src)+") = "+str(dest));
	store_dest(cmd, dest);

#----------------------------------------------------------------

func cmd_bset(cmd)->void:ALU_op(cmd, op_bset);
func cmd_bget(cmd)->void:ALU_op(cmd, op_bget);
func cmd_bclear(cmd)->void:ALU_op(cmd, op_bclear);
func cmd_nop(_cmd)->void:pass;

var cmd_handlers:Dictionary[String,Callable] = {
	"HALT":		cmd_halt,  # 0
	"RESET":	cmd_reset, # 1
	#---- control ---
	"JMP":		cmd_jmp,   # 2 [op][cond][arg]
	"CALL":		cmd_call, # 3
	"RET":		cmd_ret, # 4
	"CMP":		cmd_cmp, # 5
	#---- interrupt ---
	"INT":		cmd_int, # 6
	"INTRET":	cmd_intret, # 7
	#---- memory ----
	"MOV":		cmd_mov, # 8
	"PUSH":		cmd_push,# 9
	"POP":		cmd_pop,# 10
	#---- ALU arithmetic ---
	"ADD":		cmd_add,# 11
	"SUB":		cmd_sub,# 12
	"MUL":		cmd_mul,# 13
	"DIV":		cmd_div,# 14
	"MOD":		cmd_mod,# 15
	"ABS":		cmd_abs,# 16
	"NEG":		cmd_neg,# 17
	"INC":		cmd_inc,# 18
	"DEC":		cmd_dec,# 19
	#---- ALU logic
	"AND":		cmd_and,# 20
	"OR":		cmd_or, # 21
	"XOR":		cmd_xor,# 22
	"NOT":		cmd_not,# 23
	#---- ALU bitwise
	"BAND":		cmd_band,# 24
	"BOR":		cmd_bor, # 25
	"BXOR":		cmd_bxor,# 26
	"BNOT":		cmd_bnot, #27
	"SHIFT":	cmd_shift,#28    #opts: barrel y/n, carry set/get, left/right
	"BSET":		cmd_bset, #29    # set bit N = 1
	"BGET":		cmd_bget, #30    # get bit N (to dest and to cmp is-zero)
	"BCLEAR":	cmd_bclear, #31  # clear bit N = 0
	#---- generic
	"NOP":		cmd_nop, #32
};

func run_single_command(cmd:ISA_ZVM.Cmd)->void:
	if not cpu_assert(cmd.op_str in cmd_handlers, ERR_BAD_OP, "unrecognized command"): return;
	#print("cmd ["+cmd.op_str+"]");
	cmd_handlers[cmd.op_str].call(cmd);

const IVT_entry_size:int = 1;
# interrupt vector table entries:
# 0 - interrupt handler IP (address to jump to)
# --- no other params for now


func service_interrupt()->void:
	# flag it that we are currently servicing an interrupt
	# and therefore there is no need to jump into other interrupts
	regs[ISA.REG_CTRL] |= ISA.BIT_IRS;
	var int_num:int = regs[ISA.REG_IRQ];
	#built-in interrupts:
	# int 0 - halt
	# int 1 - reset
	if(int_num == 0): halt(); return;
	if(int_num == 1): reset(); return;
	#user interrupts:
	if(regs[ISA.REG_IRQ] >= regs[ISA.REG_IVS]): error_interrupt_oor(); # interrupt index out of range
	var IV_addr:int = regs[ISA.REG_IVT] + int_num * IVT_entry_size;
	push_all();
	_call(IV_addr);
	
	
func step()->void:
	if(regs[ISA.REG_IRQ] and not (regs[ISA.REG_CTRL] & ISA.BIT_IRS)):
		service_interrupt();
	var cmd:PackedByteArray = fetchCmd();
	var decode:ISA_ZVM.Cmd = decodeCmd(cmd);
	if decode == null: return;
	run_single_command(decode);
	#if(regs[ISA.REG_CTRL] & ISA.BIT_STEP):
	#	regs[ISA.REG_CTRL] &= ~ISA.BIT_PWR;
	cpu_step_done.emit(self);

func setup(dict:Dictionary)->void:
	assert("bus" in dict); # this is an actual assert because it's not related to VM emulation
	Bus = dict.bus;
	is_setup = true;

# Called when the node enters the scene tree for the first time.
func _ready()->void:
	reset();
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.

var tick_debt:float = 0.0;

func _process(delta:float)->void:
	if not (regs[ISA.REG_CTRL] & ISA.BIT_PWR): return;
	tick_debt += freq*delta;
	var lc:LoopCounter = LoopCounter.new(freq+1);
	while tick_debt >= 1.0:
		lc.step();
		if(regs[ISA.REG_CTRL] & ISA.BIT_PWR):
			step();
		tick_debt -= 1.0;

		

const MAX_U8 = 256-1;
const MAX_U32 = 2**32-1;
func to_U8(x)->int: return x & MAX_U8;
func to_U32(x)->int: return x & MAX_U32;
