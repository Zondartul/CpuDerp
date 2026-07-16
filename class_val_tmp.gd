extends IR_Var
class_name IR_Tmp

func _init(IR:IRKind):
	ir_name = IR.make_unique_IR_name("tmp");
	IR.all_syms[ir_name] = self;
	
