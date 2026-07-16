extends IR_Value
class_name IR_lbl
var label:String;

func _init(IR:IRKind, _label:String=""):
	ir_name = IR.make_unique_IR_name("lbl");
	IR.all_syms[ir_name] = self;
	label=_label;
	storage = Storage.new({"type":Storage.NONE});
